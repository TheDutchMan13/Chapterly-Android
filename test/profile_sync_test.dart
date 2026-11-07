import 'dart:math';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/phone_sync_core.dart';
import 'package:chapterly/data/phone_sync_profiles.dart';
import 'package:chapterly/data/pin_lock.dart';
import 'package:chapterly/data/profiles.dart';
import 'package:chapterly/data/sync_profiles.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late ProfileStore store;
  late PhoneSyncCore openCore;
  late PhoneProfileHost host;
  var opened = <String>[];

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    store = await ProfileStore.load();
    final repository = BookRepository(InMemoryBookStore());
    await repository.load();
    openCore = PhoneSyncCore(repository: repository, settings: AppSettings());
    opened = [];
    host = PhoneProfileHost(
      store: store,
      openCore: openCore,
      open: (id) async {
        opened.add(id);
        final other = BookRepository(InMemoryBookStore());
        await other.load();
        return (repository: other, settings: AppSettings());
      },
    );
  });

  test('the phone lists its profiles and adds the ones the PC asks for',
      () async {
    final list = decodeProfileList(
      await host.profiles(
        encodeProfileRequest([
          (name: 'Anna', color: profileColors[3]),
          (name: 'me', color: 0),
          (name: 'Anna', color: 0),
        ]),
      ),
    );
    expect([for (final p in list) p.name], ['Me', 'Anna']);
    expect(store.profiles, hasLength(2));
    expect(store.profiles.last.color, profileColors[3]);
    expect(list.every((p) => !p.locked), isTrue);
  });

  test('the open profile syncs with the library on the screen', () async {
    expect(await host.endpoint(mainProfileId), same(openCore));
    expect(opened, isEmpty);
  });

  test('another profile is opened once, and a missing one is not there',
      () async {
    final anna = await store.add('Anna', random: Random(1));
    final first = await host.endpoint(anna.id);
    final again = await host.endpoint(anna.id);
    expect(first, isNotNull);
    expect(again, same(first));
    expect(opened, [anna.id]);
    expect(await host.endpoint('nobody1'), isNull);
  });

  test('a profile with a PIN syncs only while it is open', () async {
    final kid = await store.add('Kid', random: Random(2));
    final salt = newPinSalt(Random(3));
    await store.scope(kid.id).setString('pinSalt', salt);
    await store.scope(kid.id).setString('pinHash', hashPin('1234', salt));

    final list = decodeProfileList(await host.profiles('{}'));
    expect(list.firstWhere((p) => p.id == kid.id).locked, isTrue);
    await expectLater(host.endpoint(kid.id), throwsA(isA<ProfileLocked>()));
    expect(opened, isEmpty);
  });

  test('one pairing code and switch for every profile', () async {
    SharedPreferences.setMockInitialValues({
      'syncCode': 'FIRSTPROFILECODE',
      'syncEnabled': true,
    });
    final profiles = await ProfileStore.load();
    final anna = await profiles.add('Anna', random: Random(1));
    final annas = await AppSettings.load(profiles.scope(anna.id));
    expect(annas.syncCode, 'FIRSTPROFILECODE');
    expect(annas.syncEnabled, isTrue);
    annas.setSyncCode('NEWCODEFORPHONE2');
    final mine = await AppSettings.load(profiles.scope(mainProfileId));
    expect(mine.syncCode, 'NEWCODEFORPHONE2');
    // Removing the first profile's settings keeps the pairing.
    await profiles.scope(mainProfileId).clear();
    final again = await AppSettings.load(profiles.scope(anna.id));
    expect(again.syncCode, 'NEWCODEFORPHONE2');
  });
}
