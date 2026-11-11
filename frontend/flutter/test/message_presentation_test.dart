import 'package:flutter_test/flutter_test.dart';
import 'package:syncbox/shared/message_presentation.dart';

void main() {
  test('highlights use original UTF16 offsets and literal case-insensitive matching', () {
    const text = '😀中文 SyncBOX syncbox [a+b]';
    final matches = highlightRanges(text, ' syncbox ');
    expect(matches.map((r) => text.substring(r.start, r.end)), [
      'SyncBOX',
      'syncbox',
    ]);
    expect(highlightRanges(text, '[a+b]'), hasLength(1));
    final emoji = highlightRanges(text, '😀').single;
    expect([emoji.start, emoji.end], [0, 2]);
    expect(highlightRanges('中文中文', '中文'), hasLength(2));
    expect(highlightRanges(text, ' '), isEmpty);
    expect(highlightRanges('İx', 'x').single.start, 1);
  });

  test('only HTTP(S) links are recognized with punctuation trimmed', () {
    const text =
        'https://example.com/a_(b)， HTTPS://example.com/x?q=SyncBOX。 javascript:alert(1) ftp://example.com';
    final links = messageLinks(text);
    expect(links.map((r) => text.substring(r.start, r.end)), [
      'https://example.com/a_(b)',
      'HTTPS://example.com/x?q=SyncBOX',
    ]);
    expect(links[1].url.query, 'q=SyncBOX');
    expect(messageLinks('https://'), isEmpty);
    expect(messageLinks('(https://example.com/a)').single.url.path, '/a');
  });

  test('date labels handle today, yesterday, and year boundaries', () {
    final today = DateTime(2026, 1, 1, 10);
    expect(sameMessageDay(today, DateTime(2026, 1, 1, 23)), isTrue);
    expect(sameMessageDay(today, DateTime(2025, 12, 31)), isFalse);
    expect(messageDayLabel(today, now: today), '今天');
    expect(messageDayLabel(DateTime(2025, 12, 31), now: today), '昨天');
    expect(messageDayLabel(DateTime(2025, 12, 30), now: today), '2025年12月30日');
  });
}
