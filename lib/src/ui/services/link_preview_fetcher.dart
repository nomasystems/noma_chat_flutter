import 'dart:collection';

import 'package:dio/dio.dart';
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
    Duration timeout = const Duration(seconds: 5),
    int cacheSize = 64,
  }) : _dio = dio ?? _defaultDio(timeout),
       _cacheSize = cacheSize;

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
  final LinkedHashMap<String, LinkPreviewMetadata?> _cache =
      LinkedHashMap<String, LinkPreviewMetadata?>();
  final Map<String, Future<LinkPreviewMetadata?>> _inFlight = {};

  Future<LinkPreviewMetadata?> fetch(String url) {
    if (_cache.containsKey(url)) {
      final cached = _cache.remove(url);
      _cache[url] = cached;
      return Future.value(cached);
    }
    final pending = _inFlight[url];
    if (pending != null) return pending;

    final future = _doFetch(url).whenComplete(() => _inFlight.remove(url));
    _inFlight[url] = future;
    return future;
  }

  Future<LinkPreviewMetadata?> _doFetch(String url) async {
    LinkPreviewMetadata? result;
    try {
      final response = await _dio.get<dynamic>(
        url,
        options: Options(responseType: ResponseType.plain),
      );
      final raw = response.data;
      final body = raw is String ? raw : raw?.toString();
      if (body != null && body.isNotEmpty) {
        result = _parse(url, body);
      }
    } catch (_) {
      result = null;
    }
    _store(url, result);
    return result;
  }

  void _store(String url, LinkPreviewMetadata? value) {
    if (_cache.length >= _cacheSize) {
      _cache.remove(_cache.keys.first);
    }
    _cache[url] = value;
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
