import '../../models/presence.dart';
import '../dto/presence_dto.dart';
import '../util/json_safe.dart';

class PresenceMapper {
  static ChatPresence fromDto(PresenceDto dto) => ChatPresence(
    userId: dto.userId,
    status: _parseStatus(dto.status),
    online: dto.online,
    statusText: dto.statusText,
    lastSeen: dto.lastSeen != null ? DateTime.tryParse(dto.lastSeen!) : null,
  );

  static ChatPresence fromJson(Map<String, dynamic> json) =>
      fromDto(PresenceDto.fromJson(json));

  static BulkPresenceResponse bulkFromJson(Map<String, dynamic> json) {
    final ownData = jsonMapOrNull(json['own']);
    final own = ownData != null ? fromJson(ownData) : fromJson(json);
    final contactsList = json['contacts'];
    final contacts = contactsList is List
        ? [
            for (final e in contactsList)
              if (e is Map<String, dynamic>) fromJson(e),
          ]
        : <ChatPresence>[];
    return BulkPresenceResponse(own: own, contacts: contacts);
  }

  static PresenceStatus _parseStatus(String status) => switch (status) {
    'available' => PresenceStatus.available,
    'away' => PresenceStatus.away,
    'busy' => PresenceStatus.busy,
    'dnd' => PresenceStatus.dnd,
    _ => PresenceStatus.offline,
  };
}
