# Chapterly

A private, offline-first book tracker for Android. Built with Flutter.
Inspired by the feature set of openreads (GPL-2.0), with its own code.

## What works now
- Four shelves: Finished, In progress, For later, Unfinished
- Books are saved on the phone (SQLite) and survive restarts
- Add books by searching Open Library (with covers and page counts), by
  scanning a barcode (ISBN), or manually
- Book screen: shelf, 1-5 star rating, start and finish dates, page count,
  tags, delete. Moving a book to In progress or Finished stamps today's date
- Tags, with filter chips on the library screen (a book must have all selected tags)
- Sort by date added, title, author, rating, pages or date finished
  (tap the same option again to flip the direction), and switch between list
  and grid. These choices are remembered
- Statistics: books finished, pages read, averages, longest book, books per
  month or per year, and a yearly reading goal
- Backup and restore: export your whole library as a JSON file and restore it
- CSV export, and CSV import from Goodreads or a Chapterly CSV
- Light and dark theme (follows the phone)

## Ideas for later
- Custom reading time
- Re-reads (more than one reading of a book)
- Choose the app colour

## Data and privacy
No account, no ads, no tracking. The only network traffic is Open Library
search requests and cover image downloads. Your library stays on the phone.

## Run it

    C:\dev\flutter\bin\flutter.bat pub get
    C:\dev\flutter\bin\flutter.bat run

Every push to `main` builds an APK with GitHub Actions (Actions tab,
download the `chapterly-apk` artifact).
