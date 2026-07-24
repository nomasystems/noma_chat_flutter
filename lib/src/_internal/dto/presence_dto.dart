import '../ui_debug_log.dart';
import '../util/json_safe.dart';

class PresenceDto {
  final String userId;
  final String status;
  final bool online;
  final String? statusText;
  final String? lastSeen;

  const PresenceDto({
    required this.userId,
    required this.status,
    required this.online,
    this.statusText,
    this.lastSeen,
  });

  factory PresenceDto.fromJson(Map<String, dynamic> json) => PresenceDto(
    userId: jsonIdOr(
      json['userId'],
      '',
      onEmptyFromPresent: () => uiDebugLog(
        'PresenceDto',
        'fromJson: userId present but coerced to empty (raw: '
            '${json['userId']})',
      ),
    ),
    status: jsonStringOr(json['status'], 'offline'),
    online: jsonBoolOr(json['online'], false),
    statusText: jsonStringOrNull(json['statusText']),
    lastSeen: jsonStringOrNull(json['lastSeen']),
  );
}
