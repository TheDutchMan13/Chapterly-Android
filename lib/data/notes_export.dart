import '../ebook/ebook_library.dart';
import '../models/quote.dart';

/// One audiobook bookmark, ready to print: where it is and its note.
class ExportedMark {
  const ExportedMark({required this.place, this.note = ''});

  /// Such as "1:02:15 · Chapter 4".
  final String place;
  final String note;
}

/// Everything you wrote about one book: your notes, quotes, highlights from
/// the reader and audiobook bookmarks.
class BookNotesExport {
  const BookNotesExport({
    required this.title,
    required this.author,
    this.notes,
    this.quotes = const [],
    this.highlights = const [],
    this.marks = const [],
  });

  final String title;
  final String author;
  final String? notes;
  final List<Quote> quotes;
  final List<EbookHighlight> highlights;
  final List<ExportedMark> marks;

  bool get isEmpty =>
      (notes ?? '').trim().isEmpty &&
      quotes.isEmpty &&
      highlights.isEmpty &&
      marks.isEmpty;

  /// A file name such as "Dune - notes".
  String get fileStem {
    final clean = title.replaceAll(RegExp(r'[\\/:*?"<>|]+'), ' ').trim();
    return '${clean.isEmpty ? 'Book' : clean} - notes';
  }
}

/// The notes as Markdown, for Obsidian, a notes app or a text editor.
String notesMarkdown(BookNotesExport e) {
  final out = StringBuffer()..writeln('# ${e.title}');
  if (e.author.trim().isNotEmpty) out.writeln('*${e.author.trim()}*');
  final notes = e.notes?.trim() ?? '';
  if (notes.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Notes')
      ..writeln()
      ..writeln(notes);
  }
  if (e.quotes.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Quotes');
    for (final quote in e.quotes) {
      out
        ..writeln()
        ..writeln(_blockquote(quote.text));
      if (quote.page != null) out.writeln('— page ${quote.page}');
    }
  }
  if (e.highlights.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Highlights');
    for (final highlight in e.highlights) {
      out
        ..writeln()
        ..writeln(_blockquote(highlight.text));
      final note = highlight.note?.trim() ?? '';
      if (note.isNotEmpty) {
        out
          ..writeln()
          ..writeln(note);
      }
    }
  }
  if (e.marks.isNotEmpty) {
    out
      ..writeln()
      ..writeln('## Audiobook bookmarks')
      ..writeln();
    for (final mark in e.marks) {
      final note = mark.note.trim();
      out.writeln('- **${mark.place}**${note.isEmpty ? '' : ': $note'}');
    }
  }
  return out.toString();
}

String _blockquote(String text) => [
      for (final line in text.trim().split('\n')) '> ${line.trimRight()}',
    ].join('\n');
