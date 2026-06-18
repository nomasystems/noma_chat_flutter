import 'dart:async' show TimeoutException;
import 'dart:collection';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:html/dom.dart' show Document, Element;
import 'package:html/parser.dart' show parse;

import '../models/link_preview_metadata.dart';

/// Fetches Open Graph metadata for URLs typed in the chat composer.
///
/// Results are cached in-memory (LRU) so re-typing the same URL within a
/// session is instant. Failures are also cached as `null` to avoid retrying
/// pages that don't expose previewable metadata.
class LinkPreviewFetcher {
  LinkPreviewFetcher({
    Dio? dio,
    // Bumped from 5s to 15s. The previous default tripped Dio's own
    // `connectTimeout` / `receiveTimeout` long before the outer wrapper
    // in `_doFetch` had a chance — the spinner stopped, the null result
    // landed in cache, and the next 5 minutes of paste-the-same-URL
    // returned null instantly even when the underlying page was just
    // slow. 15s matches the outer Future.timeout and gives slow CDNs
    // / heavy OG-tag pages room to respond.
    Duration timeout = const Duration(seconds: 15),
    int cacheSize = 64,
    Duration failureTtl = const Duration(minutes: 5),
    @visibleForTesting DateTime Function()? clock,
  }) : _dio = dio ?? _defaultDio(timeout),
       _cacheSize = cacheSize,
       _failureTtl = failureTtl,
       _clock = clock ?? DateTime.now;

  static Dio _defaultDio(Duration timeout) => Dio(
    BaseOptions(
      connectTimeout: timeout,
      receiveTimeout: timeout,
      followRedirects: true,
      // Accept any status so we can attempt to parse 4xx pages too instead
      // of throwing and leaving the spinner running.
      validateStatus: (status) => status != null && status < 500,
      headers: const {
        // Use a browser-looking User-Agent. Many CDNs (Cloudflare, etc.)
        // return 403 for unknown crawlers, leaving the spinner stuck.
        'User-Agent':
            'Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) '
            'AppleWebKit/537.36 (KHTML, like Gecko) '
            'Chrome/120.0.0.0 Safari/537.36',
        'Accept':
            'text/html,application/xhtml+xml,application/xml;q=0.9,*/*;q=0.8',
        'Accept-Language': 'en-US,en;q=0.9,es;q=0.8',
      },
    ),
  );

  final Dio _dio;
  final int _cacheSize;
  final Duration _failureTtl;
  final DateTime Function() _clock;
  final LinkedHashMap<String, LinkPreviewMetadata?> _cache =
      LinkedHashMap<String, LinkPreviewMetadata?>();
  // Wall-clock at which a `null` cache entry was stored. Successful previews
  // never expire (they would only become stale if the page itself changes);
  // failures retry after `_failureTtl` so a transient network glitch does
  // not poison the cache for the rest of the session.
  final Map<String, DateTime> _failureStoredAt = {};
  final Map<String, Future<LinkPreviewMetadata?>> _inFlight = {};

  // === Observability counters ===
  int _hits = 0;
  int _misses = 0;
  int _failureRetries = 0;
  int _evictions = 0;

  /// Lightweight snapshot of the in-memory LRU + failure TTL caches.
  /// Useful for telemetry / debug overlays. Cheap to call — just reads
  /// the underlying maps and counters, no I/O.
  LinkPreviewCacheStats get cacheStats => LinkPreviewCacheStats(
    entries: _cache.length,
    capacity: _cacheSize,
    failures: _failureStoredAt.length,
    inFlight: _inFlight.length,
    hits: _hits,
    misses: _misses,
    failureRetries: _failureRetries,
    evictions: _evictions,
  );

  Future<LinkPreviewMetadata?> fetch(String url) {
    if (_cache.containsKey(url)) {
      final cached = _cache[url];
      if (cached == null) {
        final storedAt = _failureStoredAt[url];
        if (storedAt != null && _clock().difference(storedAt) >= _failureTtl) {
          // ChatFailureResult expired — evict and refetch.
          _cache.remove(url);
          _failureStoredAt.remove(url);
          _failureRetries++;
        } else {
          // Refresh LRU position even on cached failures.
          _cache.remove(url);
          _cache[url] = null;
          _hits++;
          return Future.value(null);
        }
      } else {
        _cache.remove(url);
        _cache[url] = cached;
        _hits++;
        return Future.value(cached);
      }
    } else {
      _misses++;
    }
    final pending = _inFlight[url];
    if (pending != null) return pending;

    final future = _doFetch(url).whenComplete(() => _inFlight.remove(url));
    _inFlight[url] = future;
    return future;
  }

  Future<LinkPreviewMetadata?> _doFetch(String url) async {
    // Defensive outer timeout: Dio's `connectTimeout` and `receiveTimeout`
    // are honoured by the Dart HTTP client on desktop but can be ignored on
    // iOS Simulator when the socket gets stuck in CONNECTING (observed
    // multiple times — preview spinner runs forever despite the settings
    // above). A single attempt then rides the 15s wrapper, throws, and
    // returns an UNCACHED transient null — the typing-time banner shows
    // nothing while a later Send re-fetch on a fresh socket succeeds. Give
    // the FIRST fetch the same second chance: one bounded retry on transient
    // failure so typing-time and send-time agree. A hard `Future.timeout`
    // guarantees each attempt resolves, the spinner stops, and the
    // `_inFlight` entry is removed via the `whenComplete` upstream — no leaks
    // even if the underlying request keeps running in the background.
    Object? lastError;
    for (var attempt = 0; attempt < 2; attempt++) {
      LinkPreviewMetadata? result;
      try {
        final response = await _dio
            .get<dynamic>(
              url,
              options: Options(responseType: ResponseType.plain),
            )
            .timeout(
              const Duration(seconds: 15),
              onTimeout: () {
                throw TimeoutException('link_preview fetch timeout: $url');
              },
            );
        final raw = response.data;
        final body = raw is String ? raw : raw?.toString();
        if (body != null && body.isNotEmpty) {
          result = _parse(url, body);
        }
      } catch (e) {
        // Transient failure (timeout / socket error / DNS / Dio exception):
        // retry once on a fresh socket before giving up. Do NOT cache a null
        // here — caching would blank the preview for the whole `_failureTtl`
        // window after a single network hiccup.
        lastError = e;
        continue;
      }
      // We got a response. `result == null` here means the page legitimately
      // exposes no previewable OG/Twitter/title tags — cache that null so we
      // don't keep re-fetching a page we know has nothing to show (until the
      // failure TTL expires).
      _store(url, result);
      return result;
    }
    // Both attempts hit transient errors: return uncached null so a later
    // retype / Send retries from scratch.
    assert(lastError != null);
    return null;
  }

  void _store(String url, LinkPreviewMetadata? value) {
    if (_cache.length >= _cacheSize) {
      final oldest = _cache.keys.first;
      _cache.remove(oldest);
      _failureStoredAt.remove(oldest);
      _evictions++;
    }
    _cache[url] = value;
    if (value == null) {
      _failureStoredAt[url] = _clock();
    } else {
      _failureStoredAt.remove(url);
    }
  }

  LinkPreviewMetadata? _parse(String url, String html) {
    final Document document = parse(html);
    String? meta(String property, {String attr = 'property'}) {
      final selector = 'meta[$attr="$property"]';
      final Element? el = document.querySelector(selector);
      final value = el?.attributes['content']?.trim();
      return (value == null || value.isEmpty) ? null : value;
    }

    final title =
        meta('og:title') ??
        meta('twitter:title', attr: 'name') ??
        document.querySelector('title')?.text.trim();
    final description =
        meta('og:description') ??
        meta('twitter:description', attr: 'name') ??
        meta('description', attr: 'name');
    final image =
        meta('og:image') ??
        meta('twitter:image', attr: 'name') ??
        meta('twitter:image:src', attr: 'name');

    final preview = LinkPreviewMetadata(
      url: url,
      title: title,
      description: description,
      imageUrl: image != null ? _absoluteUrl(url, image) : null,
    );
    return preview.hasContent ? preview : null;
  }

  String _absoluteUrl(String pageUrl, String maybeRelative) {
    try {
      final base = Uri.parse(pageUrl);
      final resolved = base.resolve(maybeRelative);
      return resolved.toString();
    } on FormatException catch (_) {
      return maybeRelative;
    }
  }
}

/// Snapshot of [LinkPreviewFetcher]'s in-memory LRU + failure-TTL caches,
/// plus running counters of how the cache has been used since process
/// start.
///
/// Read from [LinkPreviewFetcher.cacheStats]. Useful when wiring a debug
/// overlay or sending telemetry — for example, a low [hitRate] over a
/// long session may indicate that the LRU [capacity] is too small for the
/// host app's typical conversation length.
class LinkPreviewCacheStats {
  const LinkPreviewCacheStats({
    required this.entries,
    required this.capacity,
    required this.failures,
    required this.inFlight,
    required this.hits,
    required this.misses,
    required this.failureRetries,
    required this.evictions,
  });

  /// Total entries currently stored in the LRU (successes + failures).
  final int entries;

  /// Maximum [entries] before the oldest one is evicted.
  final int capacity;

  /// Subset of [entries] that are cached `null` results (failed fetches
  /// awaiting their TTL).
  final int failures;

  /// Number of in-flight fetches that have been deduplicated against
  /// concurrent callers.
  final int inFlight;

  /// Cumulative cache hits since this fetcher was constructed (successful
  /// previews + cached failures within their TTL).
  final int hits;

  /// Cumulative cache misses since this fetcher was constructed
  /// (URLs whose preview had to be fetched from the network).
  final int misses;

  /// Cumulative failure entries whose TTL expired and were re-fetched.
  /// Counted separately from [misses] so callers can distinguish "first
  /// time we see this URL" from "we already tried, time to retry".
  final int failureRetries;

  /// Cumulative number of LRU evictions (oldest entry dropped because
  /// the cache reached [capacity]).
  final int evictions;

  /// `hits / (hits + misses)` rounded to two decimals; `0.0` until the
  /// first fetch happens. Treats failure retries as misses.
  double get hitRate {
    final total = hits + misses;
    if (total == 0) return 0.0;
    return (hits * 100 / total).round() / 100;
  }

  @override
  String toString() =>
      'LinkPreviewCacheStats(entries: $entries/$capacity, '
      'failures: $failures, inFlight: $inFlight, '
      'hits: $hits, misses: $misses, failureRetries: $failureRetries, '
      'evictions: $evictions, hitRate: $hitRate)';
}
