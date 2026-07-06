import 'dart:async';
import 'dart:typed_data';

import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:noma_chat/src/ui/services/link_preview_fetcher.dart';

class _HangingAdapter implements HttpClientAdapter {
  int fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) {
    fetchCount++;
    return Completer<ResponseBody>().future;
  }

  @override
  void close({bool force = false}) {}
}

class _HtmlAdapter implements HttpClientAdapter {
  _HtmlAdapter(this.html);

  final String html;
  int fetchCount = 0;

  @override
  Future<ResponseBody> fetch(
    RequestOptions options,
    Stream<Uint8List>? requestStream,
    Future<void>? cancelFuture,
  ) async {
    fetchCount++;
    return ResponseBody.fromString(
      html,
      200,
      headers: {
        Headers.contentTypeHeader: ['text/html'],
      },
    );
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  group('LinkPreviewCacheStats.hitRate', () {
    test('is 0.0 before any fetch has happened', () {
      const stats = LinkPreviewCacheStats(
        entries: 0,
        capacity: 64,
        failures: 0,
        inFlight: 0,
        hits: 0,
        misses: 0,
        failureRetries: 0,
        evictions: 0,
      );

      expect(stats.hitRate, 0.0);
    });

    test('rounds hits / (hits + misses) to two decimals', () {
      const stats = LinkPreviewCacheStats(
        entries: 2,
        capacity: 64,
        failures: 0,
        inFlight: 0,
        hits: 1,
        misses: 2,
        failureRetries: 0,
        evictions: 0,
      );

      expect(stats.hitRate, 0.33);
    });

    test('is 1.0 when every lookup was a hit', () {
      const stats = LinkPreviewCacheStats(
        entries: 3,
        capacity: 64,
        failures: 0,
        inFlight: 0,
        hits: 4,
        misses: 0,
        failureRetries: 0,
        evictions: 0,
      );

      expect(stats.hitRate, 1.0);
    });
  });

  group('LinkPreviewCacheStats.toString', () {
    test('renders every counter and the derived hit rate', () {
      const stats = LinkPreviewCacheStats(
        entries: 5,
        capacity: 64,
        failures: 2,
        inFlight: 1,
        hits: 3,
        misses: 1,
        failureRetries: 1,
        evictions: 4,
      );

      final text = stats.toString();
      expect(text, contains('entries: 5/64'));
      expect(text, contains('failures: 2'));
      expect(text, contains('inFlight: 1'));
      expect(text, contains('hits: 3'));
      expect(text, contains('misses: 1'));
      expect(text, contains('failureRetries: 1'));
      expect(text, contains('evictions: 4'));
      expect(text, contains('hitRate: 0.75'));
    });
  });

  group('LinkPreviewFetcher cancellation', () {
    test('cancel aborts the in-flight request and resolves to null', () async {
      final adapter = _HangingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final fetcher = LinkPreviewFetcher(dio: dio);

      final future = fetcher.fetch('https://example.com/a');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.fetchCount, 1);
      expect(fetcher.cacheStats.inFlight, 1);

      fetcher.cancel('https://example.com/a');

      expect(await future, isNull);
      expect(fetcher.cacheStats.inFlight, 0);
    });

    test('a cancelled fetch is not cached, so a retype fetches fresh', () async {
      final adapter = _HangingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final fetcher = LinkPreviewFetcher(dio: dio);

      final first = fetcher.fetch('https://example.com/b');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      fetcher.cancel('https://example.com/b');
      await first;

      expect(fetcher.cacheStats.entries, 0);
      expect(fetcher.cacheStats.failures, 0);

      fetcher.fetch('https://example.com/b');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(adapter.fetchCount, 2);
    });

    test('cancelAll aborts every in-flight request', () async {
      final adapter = _HangingAdapter();
      final dio = Dio()..httpClientAdapter = adapter;
      final fetcher = LinkPreviewFetcher(dio: dio);

      final a = fetcher.fetch('https://example.com/1');
      final b = fetcher.fetch('https://example.com/2');
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(fetcher.cacheStats.inFlight, 2);

      fetcher.cancelAll();

      expect(await a, isNull);
      expect(await b, isNull);
      expect(fetcher.cacheStats.inFlight, 0);
    });

    test('cancel on an unknown url is a no-op', () {
      final fetcher = LinkPreviewFetcher(dio: Dio());
      expect(() => fetcher.cancel('https://nope.example'), returnsNormally);
    });

    test('a non-cancelled fetch still completes normally', () async {
      const html =
          '<html><head><meta property="og:title" content="Hi"></head></html>';
      final adapter = _HtmlAdapter(html);
      final dio = Dio()..httpClientAdapter = adapter;
      final fetcher = LinkPreviewFetcher(dio: dio);

      final result = await fetcher.fetch('https://example.com/ok');

      expect(result, isNotNull);
      expect(result!.title, 'Hi');
      expect(fetcher.cacheStats.inFlight, 0);
    });
  });
}
