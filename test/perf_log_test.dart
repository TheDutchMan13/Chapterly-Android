import 'dart:io';

import 'package:chapterly/data/perf_log.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('the performance log notes each step with a time, and no book details',
      () async {
    PerfLog.mark('Chapterly starts');
    await PerfLog.timed('Wi-Fi sync started', () async {});
    final text = PerfLog.text();
    expect(text, startsWith('Chapterly performance log.'));
    expect(text, contains('Chapterly starts'));
    expect(text, contains('Wi-Fi sync started took'));
    expect(RegExp(r'\d+\.\d\d s  Chapterly starts').hasMatch(text), isTrue);
  });

  test('it is written to its file', () async {
    final dir = Directory.systemTemp.createTempSync('perf');
    addTearDown(() => dir.deleteSync(recursive: true));
    final file = File('${dir.path}/performance_log.txt');
    PerfLog.attach(file);
    PerfLog.mark('library loaded (3 books)');
    await Future<void>.delayed(const Duration(milliseconds: 2200));
    expect(file.readAsStringSync(), contains('library loaded (3 books)'));
  });
}
