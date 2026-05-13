import 'package:noma_chat/noma_chat.dart';
import 'package:noma_chat/src/_internal/dto/user_dto.dart';
import 'package:noma_chat/src/_internal/mappers/user_mapper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('UserMapper', () {
    test('fromDto maps all fields', () {
      const dto = UserDto(
        id: 'user-1',
        displayName: 'John',
        avatarUrl: 'https://example.com/avatar.png',
        bio: 'Hello',
        email: 'john@example.com',
        role: 'admin',
        active: true,
        custom: {'key': 'value'},
      );
      final user = UserMapper.fromDto(dto);
      expect(user.id, 'user-1');
      expect(user.displayName, 'John');
      expect(user.avatarUrl, 'https://example.com/avatar.png');
      expect(user.bio, 'Hello');
      expect(user.email, 'john@example.com');
      expect(user.role, UserRole.admin);
      expect(user.active, isTrue);
      expect(user.custom, {'key': 'value'});
    });

    test('fromJson handles userId key', () {
      final user = UserMapper.fromJson({'userId': 'u-1'});
      expect(user.id, 'u-1');
    });

    test('owner role maps to UserRole.owner', () {
      final user = UserMapper.fromJson({'id': 'u-1', 'role': 'owner'});
      expect(user.role, UserRole.owner);
    });

    test('unknown role defaults to user', () {
      final user = UserMapper.fromJson({'id': 'u-1', 'role': 'unknown'});
      expect(user.role, UserRole.user);
    });

    test('unknown role logs warning', () {
      final warnings = <String>[];
      UserMapper.logger = (level, msg) {
        if (level == 'warn') warnings.add(msg);
      };
      addTearDown(() => UserMapper.logger = null);

      UserMapper.fromJson({'id': 'u-1', 'role': 'superadmin'});
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('unknown userRole'));
    });

    test('known roles do not log warning', () {
      final warnings = <String>[];
      UserMapper.logger = (level, msg) {
        if (level == 'warn') warnings.add(msg);
      };
      addTearDown(() => UserMapper.logger = null);

      UserMapper.fromJson({'id': 'u-1', 'role': 'owner'});
      UserMapper.fromJson({'id': 'u-2', 'role': 'admin'});
      UserMapper.fromJson({'id': 'u-3', 'role': 'user'});
      expect(warnings, isEmpty);
    });

    test('unknown roomRole logs warning', () {
      final warnings = <String>[];
      UserMapper.logger = (level, msg) {
        if (level == 'warn') warnings.add(msg);
      };
      addTearDown(() => UserMapper.logger = null);

      UserMapper.roomUserFromJson({'userId': 'ru-1', 'role': 'supermod'});
      expect(warnings, hasLength(1));
      expect(warnings.first, contains('unknown roomRole'));
    });

    test('fromJsonList maps list', () {
      final users = UserMapper.fromJsonList([
        {'id': 'u-1'},
        {'id': 'u-2'},
      ]);
      expect(users.length, 2);
      expect(users[0].id, 'u-1');
      expect(users[1].id, 'u-2');
    });

    test('contactFromJson maps contact', () {
      final contact =
          UserMapper.contactFromJson({'userId': 'c-1'});
      expect(contact.userId, 'c-1');
    });

    test('roomUserFromJson maps room user', () {
      final roomUser =
          UserMapper.roomUserFromJson({'userId': 'ru-1', 'role': 'admin'});
      expect(roomUser.userId, 'ru-1');
      expect(roomUser.role, RoomRole.admin);
    });
  });
}
