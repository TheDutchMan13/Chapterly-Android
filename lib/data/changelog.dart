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
    version: '1.11.0',
    date: '2026-10-31',
    changes: [
      'Reader: add the EPUB or PDF file of a book and read it in Chapterly '
          '(Book file, on the Reading tab of the book page)',
      'Tap the middle of the page for the tools, or the sides to turn the '
          'page',
      'Text size, typeface, line spacing, margins, and paper, white, dark or '
          'black pages',
      'Chapters, search, bookmarks, and turning pages or scrolling',
      'Highlight a passage to save it to the book\'s quotes',
      'The reader keeps the current page up to date and adds reading time to '
          'the reading log',
      'Chapterly keeps its own copy of the file on this phone; it is not '
          'synced or backed up',
    ],
  ),
  ChangelogEntry(
    version: '1.10.0',
    date: '2026-10-30',
    changes: [
      'Audiobooks: add the audio for a book (one file, or a folder of files) '
          'and listen to it in Chapterly',
      'Keeps playing with the screen off, with controls in the notification, '
          'on the lock screen and on headphones',
      'Chapters from .m4b files, or one chapter per file in a folder',
      'Skip 30 seconds, speed from 0.5x to 3x, and a sleep timer (or stop at '
          'the end of the chapter)',
      'Where you are in an audiobook syncs between the phone and the PC',
      'Time spent listening is added to the reading log and statistics',
      'Offers to move a book to Finished when you reach the end',
      'A fuller player: a big cover, larger buttons, the chapter and how '
          'much of the book is left',
      'The book page is split into Overview, Reading and Notes, with the '
          'cover, shelf and progress always at the top',
      'A More tab in the bottom bar for Next up, Read next, your shelves, '
          'duplicates, trash and settings, and how syncing with the PC is going',
      'Choose the cover size for the grid view (View, then Cover size)',
    ],
  ),
  ChangelogEntry(
    version: '1.9.0',
    date: '2026-10-30',
    changes: [
      'Wishlist: set a priority and where to get each For later book',
      'Next up: put your For later books in the order you will read them',
      'Sort by priority or by Next up, and set the priority of several books',
      'Pick any accent colour you like, not just the ready-made ones',
      'Paper look: a warm, cream page colour for light mode',
      'A bar along the bottom to switch between your library and Statistics',
      'Covers added on the PC show on the phone too',
    ],
  ),
  ChangelogEntry(
    version: '1.8.0',
    date: '2026-10-29',
    changes: [
      'Automatic backups to Documents/Chapterly, keeping the last five',
      'Import Kindle highlights (My Clippings.txt) as quotes',
      'Current page: progress bar and pace for books you are reading',
      'Tag goals, such as 10 sci-fi books this year',
      'Rating details: rate the plot, characters, writing and pacing',
      'Books like this online: suggestions by subject from Open Library',
      'Import from StoryGraph and Libib CSV exports',
    ],
  ),
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
      'New app icon',
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
