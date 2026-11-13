import 'dart:convert';
import 'dart:io';

import 'package:chapterly/data/app_settings.dart';
import 'package:chapterly/data/book_repository.dart';
import 'package:chapterly/data/book_store.dart';
import 'package:chapterly/data/phone_sync.dart';
import 'package:chapterly/data/sync_covers.dart';
import 'package:chapterly/data/sync_crypto.dart';
import 'package:chapterly/data/sync_protocol.dart';
import 'package:chapterly/data/sync_server.dart';
import 'package:chapterly/models/book.dart';
import 'package:chapterly/models/shelf.dart';
import 'package:flutter_test/flutter_test.dart';

const _code = 'K7QX2M9PZR4TB6WN';

class _Covers implements SyncCovers {
  final pictures = <String, String>{};

  @override
  Future<String?> get(String hash) async => pictures[hash];

  @override
  Future<List<String>> missing(List<String> hashes) async =>
      [for (final hash in hashes) if (!pictures.containsKey(hash)) hash];

  @override
  Future<void> put(String hash, String dataUrl) async {
    if (coverHash(dataUrl) != hash) {
      throw const FormatException('Not that cover.');
    }
    pictures[hash] = dataUrl;
  }
}

class _Answer {
  const _Answer(this.status, this.bytes);

  final int status;
  final List<int> bytes;

  String get text => utf8.decode(bytes);
}

void main() {
  group('the phone server (sealed sync)', () {
    late SyncServer server;
    late HttpClient client;
    late SyncKey key;
    late _Covers covers;
    late DateTime now;

    setUp(() async {
      now = DateTime(2026, 11, 4, 12);
      covers = _Covers();
      server = SyncServer(
        token: _code,
        handleSync: (body) async => '{"echo":${jsonEncode(body)}}',
        covers: covers,
        clock: () => now,
      );
      await server.start(port: 0);
      client = HttpClient();
      key = await SyncKey.fromCode(_code);
    });

    tearDown(() async {
      client.close(force: true);
      await server.stop();
    });

    Uri url(String path) =>
        Uri.parse('http://127.0.0.1:${server.boundPort}$path');

    Future<_Answer> send(
      String method,
      String path, {
      List<int>? body,
      String? challenge,
    }) async {
      final request = await client.openUrl(method, url(path));
      if (challenge != null) {
        request.headers.set('X-Chapterly-Challenge', challenge);
      }
      if (body != null) {
        request.contentLength = body.length;
        request.add(body);
      }
      final response = await request.close();
      final bytes = <int>[];
      await for (final chunk in response) {
        bytes.addAll(chunk);
      }
      return _Answer(response.statusCode, bytes);
    }

    Future<String> hello() async {
      final answer = await send('GET', '/v2/hello');
      expect(answer.status, 200);
      return (jsonDecode(answer.text) as Map)['challenge'] as String;
    }

    Future<List<int>> seal(
      String method,
      String path,
      String challenge,
      String plain, {
      SyncKey? withKey,
    }) =>
        (withKey ?? key).seal(
          utf8.encode(plain),
          requestContext(method, path, challenge),
        );

    Future<String> open(
      String method,
      String path,
      String challenge,
      _Answer answer,
    ) async =>
        utf8.decode(
          await key.open(
            answer.bytes,
            responseContext(method, path, challenge),
          ),
        );

    test('ping says it speaks the sealed sync and needs no code', () async {
      final answer = await send('GET', '/v1/ping');
      expect(answer.status, 200);
      final data = jsonDecode(answer.text) as Map;
      expect(data['app'], 'chapterly');
      expect(data['sync'], 2);
    });

    test('hello, sealed sync, sealed answer', () async {
      final challenge = await hello();
      final answer = await send(
        'POST',
        '/v2/sync',
        challenge: challenge,
        body: await seal('POST', '/v2/sync', challenge, 'hello'),
      );
      expect(answer.status, 200);
      // The answer is not readable on the way...
      expect(
        utf8.decode(answer.bytes, allowMalformed: true).contains('echo'),
        isFalse,
      );
      // ...and opens only with the code, for this request.
      expect(
        await open('POST', '/v2/sync', challenge, answer),
        '{"echo":"hello"}',
      );
      await expectLater(
        key.open(answer.bytes, requestContext('POST', '/v2/sync', challenge)),
        throwsA(isA<SyncAuthException>()),
      );
    });

    test('one challenge serves a whole sync run', () async {
      final challenge = await hello();
      for (final text in ['one', 'two']) {
        final answer = await send(
          'POST',
          '/v2/sync',
          challenge: challenge,
          body: await seal('POST', '/v2/sync', challenge, text),
        );
        expect(answer.status, 200);
      }
    });

    test('a wrong code is refused and hears nothing', () async {
      final challenge = await hello();
      final other = await SyncKey.fromCode('AAAAAAAAAAAAAAAA');
      final answer = await send(
        'POST',
        '/v2/sync',
        challenge: challenge,
        body: await seal(
          'POST',
          '/v2/sync',
          challenge,
          'hello',
          withKey: other,
        ),
      );
      expect(answer.status, 401);
      expect(jsonDecode(answer.text), {'error': 'code'});
    });

    test('a request sealed for another path is refused', () async {
      final challenge = await hello();
      final answer = await send(
        'POST',
        '/v2/sync',
        challenge: challenge,
        body: await seal('POST', '/v2/covers/missing', challenge, '{}'),
      );
      expect(answer.status, 401);
      expect(jsonDecode(answer.text), {'error': 'code'});
    });

    test('the same request sent twice is refused the second time', () async {
      final challenge = await hello();
      final body = await seal('POST', '/v2/sync', challenge, 'hello');
      final first = await send(
        'POST',
        '/v2/sync',
        challenge: challenge,
        body: body,
      );
      expect(first.status, 200);
      final again = await send(
        'POST',
        '/v2/sync',
        challenge: challenge,
        body: body,
      );
      expect(again.status, 401);
      expect(jsonDecode(again.text), {'error': 'replay'});
    });

    test('an expired or unknown challenge is refused', () async {
      final challenge = await hello();
      now = now.add(const Duration(minutes: 6));
      final stale = await send(
        'POST',
        '/v2/sync',
        challenge: challenge,
        body: await seal('POST', '/v2/sync', challenge, 'hello'),
      );
      expect(stale.status, 401);
      expect(jsonDecode(stale.text), {'error': 'challenge'});

      final unknown = await send(
        'POST',
        '/v2/sync',
        challenge: 'made-up',
        body: await seal('POST', '/v2/sync', 'made-up', 'hello'),
      );
      expect(unknown.status, 401);
      expect(jsonDecode(unknown.text), {'error': 'challenge'});

      final none = await send('POST', '/v2/sync', body: [1, 2, 3]);
      expect(none.status, 401);
    });

    test('many wrong codes make the phone wait a minute', () async {
      final challenge = await hello();
      for (var i = 0; i < 20; i++) {
        final answer = await send(
          'POST',
          '/v2/sync',
          challenge: challenge,
          body: List.filled(40, i),
        );
        expect(answer.status, 401);
      }
      final right = await seal('POST', '/v2/sync', challenge, 'hello');
      final blocked = await send(
        'POST',
        '/v2/sync',
        challenge: challenge,
        body: right,
      );
      expect(blocked.status, 429);
      now = now.add(const Duration(minutes: 1, seconds: 1));
      final fresh = await hello();
      final after = await send(
        'POST',
        '/v2/sync',
        challenge: fresh,
        body: await seal('POST', '/v2/sync', fresh, 'hello'),
      );
      expect(after.status, 200);
    });

    test('the old unsealed sync asks for the PC app to be updated', () async {
      final request = await client.openUrl('POST', url('/v1/sync'));
      request.headers.set('authorization', 'Bearer $_code');
      request.write('{}');
      final response = await request.close();
      final text = await utf8.decoder.bind(response).join();
      expect(response.statusCode, 426);
      expect(text, contains('Update Chapterly on your PC'));
      expect((await send('GET', '/v1/covers/missing')).status, 426);
    });

    test('covers move sealed', () async {
      const picture = 'data:image/jpeg;base64,AAAA';
      final hash = coverHash(picture);
      final challenge = await hello();

      const missingPath = '/v2/covers/missing';
      final missing = await send(
        'POST',
        missingPath,
        challenge: challenge,
        body: await seal(
          'POST',
          missingPath,
          challenge,
          jsonEncode({
            'hashes': [hash],
          }),
        ),
      );
      expect(missing.status, 200);
      expect(
        jsonDecode(await open('POST', missingPath, challenge, missing)),
        {
          'missing': [hash],
        },
      );

      final path = '/v2/covers/$hash';
      final put = await send(
        'PUT',
        path,
        challenge: challenge,
        body: await seal('PUT', path, challenge, picture),
      );
      expect(put.status, 200);
      expect(await open('PUT', path, challenge, put), '');
      expect(covers.pictures[hash], picture);

      final get = await send(
        'GET',
        path,
        challenge: challenge,
        body: await seal('GET', path, challenge, ''),
      );
      expect(get.status, 200);
      expect(await open('GET', path, challenge, get), picture);

      // A GET without its sealed empty body is refused.
      final bare = await send('GET', path, challenge: challenge);
      expect(bare.status, 401);
    });

    test('an error after a good request is sealed too', () async {
      final challenge = await hello();
      final path = '/v2/covers/${'0' * 32}';
      final answer = await send(
        'GET',
        path,
        challenge: challenge,
        body: await seal('GET', path, challenge, ''),
      );
      expect(answer.status, 404);
      expect(
        jsonDecode(await open('GET', path, challenge, answer)),
        {'error': 'No such cover.'},
      );
    });
  });

  group('dates from a device with its clock ahead', () {
    final now = DateTime(2026, 11, 4, 12);

    Book book(String id, DateTime updated) => Book(
          id: id,
          title: 'Book $id',
          author: 'A',
          shelf: Shelf.forLater,
          addedAt: DateTime(2026),
          updatedAt: updated,
        );

    test('are read as now when more than a day ahead', () {
      final text = encodeSyncPayload(
        [
          book('far', DateTime(2030)),
          book('soon', now.add(const Duration(hours: 20))),
        ],
        {
          'gone': DateTime(2031),
          'ok': now.subtract(const Duration(days: 3)),
        },
      );
      final payload = decodeSyncPayload(text, now: now);
      final byId = {for (final b in payload.books) b.id: b};
      expect(byId['far']!.updatedAt, now);
      expect(byId['far']!.title, 'Book far');
      expect(
        byId['soon']!.updatedAt,
        now.add(const Duration(hours: 20)),
      );
      expect(payload.tombstones['gone'], now);
      expect(
        payload.tombstones['ok'],
        now.subtract(const Duration(days: 3)),
      );
    });
  });

  group('the sync switch', () {
    test('two starts at once (the app coming back while sync starts) leave '
        'sync running', () async {
      final repository = BookRepository(InMemoryBookStore());
      await repository.load();
      final settings = AppSettings()..setSyncEnabled(true);
      // A fixed free port, so the two starts would fight over it.
      final probe = await ServerSocket.bind(InternetAddress.anyIPv4, 0);
      final port = probe.port;
      await probe.close();
      final sync = PhoneSync(repository: repository, settings: settings)
        ..portOverride = port;
      await Future.wait([sync.refresh(), sync.appResumed(), sync.refresh()]);
      expect(sync.running, isTrue);
      expect(sync.error, isNull);
      sync.dispose();
    });

    test('a stop while the port is opening leaves nothing listening',
        () async {
      final repository = BookRepository(InMemoryBookStore());
      await repository.load();
      final settings = AppSettings()..setSyncEnabled(true);
      final sync = PhoneSync(repository: repository, settings: settings)
        ..portOverride = 0;
      final starting = sync.refresh();
      final pausing = sync.appPaused();
      await Future.wait([starting, pausing]);
      expect(sync.running, isFalse);

      await sync.appResumed();
      expect(sync.running, isTrue);
      settings.setSyncEnabled(false);
      final again = sync.refresh();
      await again;
      expect(sync.running, isFalse);
      sync.dispose();
    });
  });
}
