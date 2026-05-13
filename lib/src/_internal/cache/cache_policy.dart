/// Determines how reads are resolved between network and local cache.
enum CachePolicy {
  /// Fetch from network; fall back to cache on failure.
  networkFirst,
  /// Read from cache; fetch from network only if cache misses.
  cacheFirst,
  /// Always fetch from network; ignore cache entirely.
  networkOnly,
  /// Read from cache only; never make a network request.
  cacheOnly,
}
