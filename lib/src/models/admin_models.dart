import 'package:freezed_annotation/freezed_annotation.dart';

part 'admin_models.freezed.dart';

/// Raw system metrics payload exposed by the admin endpoint. Kept opaque
/// because the backend evolves the shape; consumers read [raw] directly.
@freezed
abstract class SystemStats with _$SystemStats {
  const factory SystemStats({required Map<String, dynamic> raw}) = _SystemStats;
}

/// Raw admin session metadata. Kept opaque (see [SystemStats]).
@freezed
abstract class AdminSession with _$AdminSession {
  const factory AdminSession({required Map<String, dynamic> raw}) =
      _AdminSession;
}

/// Server-side content filter rule (regex/keyword) applied to messages.
@freezed
abstract class ContentFilter with _$ContentFilter {
  const factory ContentFilter({
    required String id,
    required String pattern,
    String? createdAt,
  }) = _ContentFilter;
}

/// Privilege level of a user as seen by the admin API.
enum AdminUserRole { user, admin }
