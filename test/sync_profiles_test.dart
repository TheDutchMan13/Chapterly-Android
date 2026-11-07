import 'package:chapterly/data/sync_profiles.dart';
import 'package:flutter_test/flutter_test.dart';

SyncProfileInfo _info(String id, String name, {bool locked = false}) =>
    SyncProfileInfo(id: id, name: name, color: 0, locked: locked);

void main() {
  group('pairing up profiles', () {
    test('same names pair up, and the first profiles pair with each other',
        () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Hans'), _info('a1', 'Anna')],
        phone: [_info('main', 'Me'), _info('b1', 'anna ')],
      );
      expect(plan.links.links, {'a1': 'b1', 'main': 'main'});
      expect(plan.createOnPhone, isEmpty);
      expect(plan.createOnPc, isEmpty);
    });

    test('a name beats the first profile', () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Hans')],
        phone: [_info('main', 'Me'), _info('b1', 'Hans')],
      );
      expect(plan.links.links, {'main': 'b1'});
      expect([for (final p in plan.createOnPc) p.name], ['Me']);
    });

    test('profiles left over are added on the other side, but not with a PIN',
        () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Me'), _info('a1', 'Anna'), _info('s1', 'Secret', locked: true)],
        phone: [_info('main', 'Me'), _info('b1', 'Bob'), _info('k1', 'Kid', locked: true)],
      );
      expect([for (final p in plan.createOnPhone) p.name], ['Anna']);
      expect([for (final p in plan.createOnPc) p.name], ['Bob']);
    });

    test('a profile removed on one side is not added back', () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Me'), _info('a1', 'Anna')],
        phone: [_info('main', 'Me'), _info('b1', 'Bob')],
        saved: const ProfileLinks(
          links: {'main': 'main', 'a1': 'gone', 'gone2': 'b1'},
        ),
      );
      expect(plan.links.links, {'main': 'main'});
      expect(plan.createOnPhone, isEmpty);
      expect(plan.createOnPc, isEmpty);
      expect(plan.links.leftOnPc, {'a1'});
      expect(plan.links.leftOnPhone, {'b1'});
    });

    test('pairs from last time are kept after a rename', () {
      final plan = planProfileLinks(
        pc: [_info('main', 'Me'), _info('a1', 'Annie')],
        phone: [_info('main', 'Me'), _info('b1', 'Anna')],
        saved: const ProfileLinks(links: {'main': 'main', 'a1': 'b1'}),
      );
      expect(plan.links.links, {'main': 'main', 'a1': 'b1'});
    });

    test('the pairs are saved and read back', () {
      const links = ProfileLinks(
        links: {'main': 'main'},
        leftOnPc: {'a1'},
        leftOnPhone: {'b1'},
      );
      final back = ProfileLinks.fromJson(links.toJson());
      expect(back.links, links.links);
      expect(back.leftOnPc, links.leftOnPc);
      expect(back.leftOnPhone, links.leftOnPhone);
      expect(ProfileLinks.fromJson('not json').isEmpty, isTrue);
    });

    test('profile paths', () {
      expect(profileSyncPath(null, '/sync'), '/v2/sync');
      expect(profileSyncPath('main', '/covers/x'), '/v2/p/main/covers/x');
      final split = splitProfilePath('/v2/p/k3x9q2ab/covers/missing');
      expect(split?.id, 'k3x9q2ab');
      expect(split?.path, '/v2/covers/missing');
      expect(splitProfilePath('/v2/p/../sync'), isNull);
      expect(splitProfilePath('/v2/p/main'), isNull);
    });
  });
}
