import 'package:chapterly/data/server_code.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('accepts a valid code', () {
    final code = parseServerCode('chapterly-server:1|100.72.125.106:8780|aB3_-.~x');
    expect(code, isNotNull);
    expect(code!.address, '100.72.125.106:8780');
    expect(code.token, 'aB3_-.~x');
  });

  test('accepts a hostname', () {
    final code = parseServerCode('chapterly-server:1|my-pc.tail1234.ts.net:80|tok');
    expect(code?.address, 'my-pc.tail1234.ts.net:80');
  });

  test('trims whitespace', () {
    final code = parseServerCode('  chapterly-server:1|10.0.0.1:8780|tok\r\n');
    expect(code?.address, '10.0.0.1:8780');
    expect(code?.token, 'tok');
  });

  test('rejects a wrong prefix or version', () {
    expect(parseServerCode('chapterly-server:2|10.0.0.1:8780|tok'), isNull);
    expect(parseServerCode('chapterly-pair:1|10.0.0.1:8780|tok'), isNull);
    expect(parseServerCode('Chapterly-Server:1|10.0.0.1:8780|tok'), isNull);
    expect(parseServerCode('xchapterly-server:1|10.0.0.1:8780|tok'), isNull);
    expect(parseServerCode('10.0.0.1:8780|tok'), isNull);
  });

  test('rejects a missing part', () {
    expect(parseServerCode(''), isNull);
    expect(parseServerCode('chapterly-server:1'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:8780'), isNull);
    expect(parseServerCode('chapterly-server:1||tok'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1|tok'), isNull);
    expect(parseServerCode('chapterly-server:1|:8780|tok'), isNull);
  });

  test('rejects a bad port', () {
    expect(parseServerCode('chapterly-server:1|10.0.0.1:0|tok'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:65536|tok'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:99999999|tok'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:abc|tok'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:-1|tok'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:65535|tok'), isNotNull);
  });

  test('rejects a bad host', () {
    expect(parseServerCode('chapterly-server:1|http://10.0.0.1:8780|tok'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1/x:8780|tok'), isNull);
    expect(parseServerCode('chapterly-server:1|my pc:8780|tok'), isNull);
  });

  test('rejects an empty or odd token', () {
    expect(parseServerCode('chapterly-server:1|10.0.0.1:8780|'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:8780|to/k'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:8780|to=k'), isNull);
  });

  test('rejects extra pipes and spaces', () {
    expect(parseServerCode('chapterly-server:1|10.0.0.1:8780|tok|more'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:8780|to k'), isNull);
    expect(parseServerCode('chapterly-server:1| 10.0.0.1:8780|tok'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:8780 |tok'), isNull);
    expect(parseServerCode('chapterly-server:1|10.0.0.1:8780|tok\nmore'), isNull);
  });
}
