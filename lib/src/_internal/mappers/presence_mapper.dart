import '../../models/presence.dart';
import '../dto/presence_dto.dart';

class PresenceMapper {
  static ChatPresence fromDto(PresenceDto dto) => ChatPresence(
        userId: dto.userId,
        status: _parseStatus(dto.status),
        online: dto.online,
        statusText: dto.statusText,
        lastSeen:
            dto.lastSeen != null ? DateTime.tryParse(dto.lastSeen!) : null,
      );

  static ChatPresence fromJson(Map<String, dynamic> json) =>
      fromDto(PresenceDto.fromJson(json));

  static BulkPresenceResponse bulkFromJson(Map<String, dynamic> json) {
    final ownData = json['own'] as Map<String, dynamic>?;
    final own = ownData != null ? fromJson(ownData) : fromJson(json);
    final contactsList = json['contacts'] as List?;
    final contacts = contactsList
            ?.map((e) => fromJson(e as Map<String, dynamic>))
            .toList() ??
        [];
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
