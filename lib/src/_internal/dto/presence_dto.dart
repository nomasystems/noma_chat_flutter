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
        userId: (json['userId'] ?? '') as String,
        status: (json['status'] ?? 'offline') as String,
        online: (json['online'] ?? false) as bool,
        statusText: json['statusText'] as String?,
        lastSeen: json['lastSeen'] as String?,
      );
}
