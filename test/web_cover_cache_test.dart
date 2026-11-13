import 'dart:io';
import 'dart:typed_data';

import 'package:chapterly/data/web_cover_cache.dart';
import 'package:chapterly/widgets/book_cover.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

/// The smallest PNG: one transparent pixel.
final _png = Uint8List.fromList([
  0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0x00, 0x00, 0x00, 0x0D,
  0x49, 0x48, 0x44, 0x52, 0x00, 0x00, 0x00, 0x01, 0x00, 0x00, 0x00, 0x01,
  0x08, 0x06, 0x00, 0x00, 0x00, 0x1F, 0x15, 0xC4, 0x89, 0x00, 0x00, 0x00,
  0x0A, 0x49, 0x44, 0x41, 0x54, 0x78, 0x9C, 0x63, 0x00, 0x01, 0x00, 0x00,
  0x05, 0x00, 0x01, 0x0D, 0x0A, 0x2D, 0xB4, 0x00, 0x00, 0x00, 0x00, 0x49,
  0x45, 0x4E, 0x44, 0xAE, 0x42, 0x60, 0x82,
]);

const _url = 'https://covers.example.org/b/id/1-M.jpg';

void main() {
  late Directory dir;
  var fetches = 0;
  var online = true;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('web_covers');
    WebCoverCache.folder = dir;
    WebCoverCache.clearMemory();
    fetches = 0;
    online = true;
    WebCoverCache.client = () => MockClient((request) async {
          fetches++;
          if (!online) throw const SocketException('offline');
          if (request.url.path.endsWith('error.jpg')) {
            return http.Response('<html>Not found</html>', 200);
          }
          return http.Response.bytes(_png, 200);
        });
  });

  tearDown(() {
    WebCoverCache.folder = null;
    dir.deleteSync(recursive: true);
  });

  test('a web cover is fetched once and then shows offline', () async {
    expect(await WebCoverCache.load(_url), _png);
    expect(fetches, 1);
    expect(dir.listSync().whereType<File>(), hasLength(1));

    // The app is opened again, with no connection.
    WebCoverCache.clearMemory();
    online = false;
    expect(await WebCoverCache.load(_url), _png);
    expect(fetches, 1, reason: 'read from the phone, not the web');
  });

  test('a cover asked for by many rows at once is fetched once', () async {
    final all = await Future.wait([
      for (var i = 0; i < 5; i++) WebCoverCache.load(_url),
    ]);
    expect(all.every((b) => b != null), isTrue);
    expect(fetches, 1);
  });

  test('an error page is never kept as a cover, and offline is not kept',
      () async {
    expect(await WebCoverCache.load('https://x.org/error.jpg'), isNull);
    online = false;
    expect(await WebCoverCache.load('https://x.org/other.jpg'), isNull);
    expect(dir.listSync(), isEmpty);
    // Once back online, it is fetched.
    online = true;
    expect(await WebCoverCache.load('https://x.org/other.jpg'), _png);
  });

  test('only web addresses are fetched', () async {
    expect(await WebCoverCache.load('file:///etc/passwd'), isNull);
    expect(fetches, 0);
  });

  testWidgets('the cover shows the kept picture', (tester) async {
    await tester.runAsync(() => WebCoverCache.load(_url));
    await tester.pumpWidget(const MaterialApp(
      home: BookCover(coverUrl: _url, title: 'Dune', width: 44, height: 64),
    ));
    expect(find.byType(Image), findsOneWidget);
    expect(find.text('Dune'), findsNothing, reason: 'not the placeholder');
  });
}
