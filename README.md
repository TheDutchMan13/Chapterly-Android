# Chapterly

A private, offline-first book tracker for Android. Built with Flutter.
Inspired by the feature set of openreads (GPL-2.0), with its own code.

## What works now
- Four shelves (with book counts): Finished, In progress, For later, Unfinished
- Books are saved on the phone (SQLite) and survive restarts
- Add books by searching Open Library (with covers and page counts), by
  scanning a barcode (ISBN), or manually
- Book screen: shelf, format (paperback, hardcover, e-book, audiobook),
  1-5 star rating, start and finish dates, page count, tags, notes/review,
  favorite heart, and your own cover from a phone photo. Moving a book to
  In progress or Finished stamps today's date
- Reading log: write down pages read per day; shown in the statistics
- Re-reads: "Read again" saves the finished reading (dates, rating, log) under
  Earlier readings and starts a new one. Every finished reading counts in the
  statistics
- Series: set a series name and number on a book, see the whole series in
  order, and jump to the next book
- Reading time: add minutes to the reading log by hand or with a built-in
  timer; hours, a reading streak and today's pages show in the statistics
- Share a book card: a picture with the cover, rating and a quote from your
  notes
- Similar books: tap the author or a tag on the book screen to see the others
- Search the library (title, author, ISBN or tag), and filter by favorites,
  format and tags
- Select several books (long press) to move them to a shelf, add a tag or
  trash them (with Undo)
- Trash: deleted books can be restored, or deleted for good
- Sort by date added, title, author, rating, pages, date finished, format or
  favorites first
  (tap the same option again to flip the direction), and switch between list
  and grid. These choices are remembered
- Reading pace: pages a day and an estimated finish date for books in progress
- Statistics: ratings breakdown, most read authors and tags, books finished, pages read, pages and time logged, streak,
  averages, longest book, formats, books per month or per year, and a yearly
  and a monthly reading goal
- Backup and restore: export your whole library as a JSON file and restore it
  (custom covers are files on the phone and are not part of the backup)
- CSV export, and CSV import from Goodreads or a Chapterly CSV
- Choose your accent colour and font (Settings > Appearance)
- Light, dark or phone-following theme, with an optional pure black dark mode
- Backup reminder: a banner asks for a new backup after 2 weeks to 3 months
  (your choice, or switch it off)
- Sync with a PC on your home Wi-Fi (Settings > Sync with a PC). Off by
  default. Works while Chapterly is open. Settings shows when the last sync
  happened and what it did. The protocol is in `docs/SYNC.md`
- Shelves of your own (Beach reads, Gifts...): extra tabs next to the four
  main shelves; manage them from the menu, or add selected books to one
- Quotes: save favourite passages from a book, with the page
- Reading challenge: the yearly goal is a ring with books to go and whether
  you are ahead of or behind pace
- Year in review: a shareable picture of your year (Statistics > pick a year)
- What should I read next?: a random pick from For later, optionally by tag
  or format
- Find duplicates: books that look the same are merged into one (with Undo)
- More by this author: other books by the author from Open Library, leaving
  out the ones you have
- App lock: protect Chapterly with a PIN (Settings > Privacy). A forgotten PIN
  can only be cleared by erasing the app data, so keep a backup

## Ideas for later
- Windows app to sync with (the phone side is ready; see docs/SYNC.md)

## Data and privacy
No account, no ads, no tracking. The only network traffic is Open Library
search requests and cover image downloads. Your library stays on the phone.

## Run it

    C:\dev\flutter\bin\flutter.bat pub get
    C:\dev\flutter\bin\flutter.bat run

Every push to `main` builds an APK with GitHub Actions (Actions tab,
download the `chapterly-apk` artifact).

## License

Chapterly is free software under the GNU General Public License v3.0.
See the `LICENSE` file. Copyright (C) 2026 Hans De Kryger.
