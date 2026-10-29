/// What changed in each version, newest first. Add a new entry for each release.
class ChangelogEntry {
  const ChangelogEntry({
    required this.version,
    required this.date,
    required this.changes,
  });

  final String version;
  final String date;
  final List<String> changes;
}

const changelog = [
  ChangelogEntry(
    version: '1.7.0',
    date: '2026-10-29',
    changes: [
      'Defaults for new books: choose the shelf, format and tags they start with',
      'Choose the exact edition when adding a book from search',
      'Search by Open Library ID (such as OL45804W)',
      'Sort by publication year or date modified',
      'Filter by the year you finished a book',
      'Tags: match all or any, and hide books with a tag (tap a tag twice)',
      'Change the format or author of several books at once',
      'Show ratings as numbers instead of stars',
      'Quick rating dialog on the book screen (number mode)',
      'Choose whether book cards show the format and tags',
      'Reorder the shelf tabs',
      'Yearly pages goal, plus pages finished per month and per year',
    ],
  ),
  ChangelogEntry(
    version: '1.6.0',
    date: '2026-10-29',
    changes: [
      'Shelves of your own: make shelves such as Beach reads or Gifts, shown as extra tabs',
      'Quotes: save favourite passages from a book, with the page number',
      'Reading challenge: the yearly goal is a ring showing books to go and your pace',
      'Year in review: a shareable picture of your year',
      'What should I read next? picks a random book from For later',
      'Find duplicates: merge books that look the same, with Undo',
      'More by this author: other books by the author from Open Library',
      'App lock: protect Chapterly with a PIN',
      'Sync status: Settings shows when the last PC sync happened',
      'About section with the version, this changelog and the licence',
      'Custom cover photos removed: covers now come from Open Library',
    ],
  ),
];
