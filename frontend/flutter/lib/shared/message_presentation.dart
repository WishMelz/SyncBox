import 'package:flutter/services.dart';

class TextRangeMatch {
  const TextRangeMatch(this.start, this.end);
  final int start, end;
}

List<TextRangeMatch> highlightRanges(String text, String query) {
  final needle = query.trim().toLowerCase().replaceAll('ς', 'σ');
  if (needle.isEmpty) return [];
  final folded = StringBuffer();
  final starts = <int>[], ends = <int>[];
  var offset = 0;
  for (final rune in text.runes) {
    final original = String.fromCharCode(rune);
    final lower = original.toLowerCase().replaceAll('ς', 'σ');
    folded.write(lower);
    for (var i = 0; i < lower.length; i++) {
      starts.add(offset);
      ends.add(offset + original.length);
    }
    offset += original.length;
  }
  final source = folded.toString(), ranges = <TextRangeMatch>[];
  var cursor = 0;
  while (cursor < source.length) {
    final at = source.indexOf(needle, cursor);
    if (at < 0) break;
    ranges.add(TextRangeMatch(starts[at], ends[at + needle.length - 1]));
    cursor = at + needle.length;
  }
  return ranges;
}

class MessageLink {
  const MessageLink(this.start, this.end, this.url);
  final int start, end;
  final Uri url;
}

List<MessageLink> messageLinks(String text) {
  final pattern = RegExp(r'''https?://[^\s<>"'　]+''', caseSensitive: false);
  return pattern
      .allMatches(text)
      .map((m) {
        var candidate = m
            .group(0)!
            .replaceFirst(RegExp(r'[.,!?;:，。！？；：、）】》」』]+$'), '');
        for (final pair in [
          ['(', ')'],
          ['[', ']'],
        ]) {
          while (candidate.endsWith(pair[1]) &&
              candidate.split(pair[1]).length >
                  candidate.split(pair[0]).length) {
            candidate = candidate.substring(0, candidate.length - 1);
          }
        }
        final url = Uri.tryParse(candidate);
        if (url == null ||
            !['http', 'https'].contains(url.scheme.toLowerCase()) ||
            url.host.isEmpty) {
          return null;
        }
        return MessageLink(m.start, m.start + candidate.length, url);
      })
      .whereType<MessageLink>()
      .toList();
}

bool sameMessageDay(DateTime a, DateTime b) =>
    a.year == b.year && a.month == b.month && a.day == b.day;
String messageDayLabel(DateTime date, {DateTime? now}) {
  final today = now ?? DateTime.now();
  if (sameMessageDay(date, today)) return '今天';
  if (sameMessageDay(date, DateTime(today.year, today.month, today.day - 1))) {
    return '昨天';
  }
  return '${date.year == today.year ? '' : '${date.year}年'}${date.month}月${date.day}日';
}

Future<void> openMessageLink(Uri url) async {
  if (!['http', 'https'].contains(url.scheme.toLowerCase()) || url.host.isEmpty) {
    throw const FormatException('无效链接');
  }
  final opened = await const MethodChannel('syncbox/links')
      .invokeMethod<bool>('open', url.toString());
  if (opened != true) throw const FormatException('无法打开链接');
}
