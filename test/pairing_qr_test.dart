import 'package:chapterly/data/pairing_qr.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a valid payload', () {
    expect(
      parsePairingQr('chapterly-pair:1:ABCDEFGH23456789'),
      'ABCDEFGH23456789',
    );
    expect(
      parsePairingQr('chapterly-pair:1:0123456789ABCDEF'),
      '0123456789ABCDEF',
    );
  });

  test('trims whitespace', () {
    expect(
      parsePairingQr('  chapterly-pair:1:ABCDEFGH23456789\r\n'),
      'ABCDEFGH23456789',
    );
  });

  test('rejects lowercase', () {
    expect(parsePairingQr('chapterly-pair:1:abcdefgh23456789'), isNull);
    expect(parsePairingQr('Chapterly-Pair:1:ABCDEFGH23456789'), isNull);
  });

  test('rejects a wrong prefix or version', () {
    expect(parsePairingQr('chapterly:1:ABCDEFGH23456789'), isNull);
    expect(parsePairingQr('chapterly-pair:2:ABCDEFGH23456789'), isNull);
    expect(parsePairingQr('chapterly-pair:ABCDEFGH23456789'), isNull);
    expect(parsePairingQr('xchapterly-pair:1:ABCDEFGH23456789'), isNull);
  });

  test('rejects a wrong length', () {
    expect(parsePairingQr('chapterly-pair:1:ABCDEFGH2345678'), isNull);
    expect(parsePairingQr('chapterly-pair:1:ABCDEFGH234567890'), isNull);
    expect(parsePairingQr('chapterly-pair:1:'), isNull);
  });

  test('rejects other characters and extra text', () {
    expect(parsePairingQr('chapterly-pair:1:ABCDEFGH2345678-'), isNull);
    expect(parsePairingQr('chapterly-pair:1:ABCD-EFGH-2345-6789'), isNull);
    expect(parsePairingQr('chapterly-pair:1:ABCDEFGH23456789 x'), isNull);
    expect(parsePairingQr('chapterly-pair:1:ABCDEFGH23456789\nmore'), isNull);
    expect(parsePairingQr('9780140328721'), isNull);
    expect(parsePairingQr(''), isNull);
  });
}
