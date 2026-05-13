/// Configuration for automatic HTTP request retries with exponential backoff.
class RetryConfig {
  final int maxRetries;
  final Duration baseDelay;
  final Duration maxDelay;
  final Set<int> retryableStatusCodes;
  final bool enabled;

  const RetryConfig({
    this.maxRetries = 3,
    this.baseDelay = const Duration(milliseconds: 500),
    this.maxDelay = const Duration(seconds: 16),
    this.retryableStatusCodes = const {429, 502, 503, 504},
    this.enabled = true,
  });

  /// Disables retries entirely.
  const RetryConfig.disabled()
    : maxRetries = 0,
      baseDelay = Duration.zero,
      maxDelay = Duration.zero,
      retryableStatusCodes = const {},
      enabled = false;
}
