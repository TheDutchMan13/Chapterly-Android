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
    version: '1.46.0',
    date: '2026-11-09',
    changes: [
      'See which devices use your book server: in Book server, the menu '
          'now has Devices on the server, with each app, whose it is and '
          'when it last connected. You can take an old one off the list. It '
          'needs book server 1.9.0 or newer, and shows up once each app is '
          'updated',
      'When the book server cannot be reached, Chapterly now says why: the '
          'PC is there but the server is not running, the address was not '
          'found, or Tailscale or the PC is off',
    ],
  ),
  ChangelogEntry(
    version: '1.45.2',
    date: '2026-11-07',
    changes: [
      'Quicker start and a quicker app while you use it: pages you have not '
          'opened yet are not built until you open them, and pages hidden '
          'behind the one you are on no longer redraw themselves every time '
          'your library changes',
    ],
  ),
  ChangelogEntry(
    version: '1.45.1',
    date: '2026-11-07',
    changes: [
      'Faster Read next page '
          'with a big library: the Read next page worked out its "By authors '
          'you like" list by going through the whole library again for each '
          'author, and did it on every click, even while hidden. It now '
          'takes a few milliseconds and is only worked out again when your '
          'library changes',
    ],
  ),
  ChangelogEntry(
    version: '1.45.0',
    date: '2026-11-07',
    changes: [
      'Faster and lighter with a big library: cover pictures are kept apart '
          'from the books and only read when a cover is shown, so a library '
          'of thousands of books takes far less memory. The first time '
          '1.45.0 opens, it moves your covers over once, which can take a '
          'few seconds',
      'Covers are drawn at the size they are shown, so scrolling a long '
          'list is smoother',
      'Syncing a library with many covers is much quicker: pictures are no '
          'longer checked again on every sync',
      'Possible duplicates are found several times faster, and worked out '
          'again only after your library changes',
    ],
  ),
  ChangelogEntry(
    version: '1.44.0',
    date: '2026-11-07',
    changes: [
      'Reading challenges: set your own challenge between any two dates, '
          'such as 12 books by March, 2,000 pages this summer, 5 books '
          'tagged Horror in October or 10 different authors. Each one '
          'shows a progress bar, days left and whether you are on pace. '
          'Find them on Statistics',
      'Check every series: with a Hardcover token, the Series screen can '
          'ask Hardcover about all your series at once and list the books '
          'you do not have. Ones after the last book you have are ticked, '
          'ready to add to For later',
    ],
  ),
  ChangelogEntry(
    version: '1.43.0',
    date: '2026-11-07',
    changes: [
      'One pairing syncs every profile: pair your phone and PC once, and '
          'each profile syncs with the profile of the same name on the other '
          'device, without switching profiles',
      'A profile missing on one device is added there the next time you '
          'sync. A profile with a PIN is never copied, and syncs only while '
          'it is open',
    ],
  ),
  ChangelogEntry(
    version: '1.42.0',
    date: '2026-11-06',
    changes: [
      'Export for Goodreads or StoryGraph no longer puts a quote mark in '
          'front of notes and titles that start with - or +',
      'Safer reading of book files: an EPUB that unpacks to something huge '
          'is skipped instead of crashing the app',
    ],
  ),
  ChangelogEntry(
    version: '1.41.0',
    date: '2026-11-06',
    changes: [
      'Search settings: a search box at the top of Settings shows only the '
          'sections that have the words you type, in their names or their '
          'descriptions. On Windows it opens the groups that match',
    ],
  ),
  ChangelogEntry(
    version: '1.40.0',
    date: '2026-11-06',
    changes: [
      'Remove a download: on the book server list, the menu on a book you '
          'downloaded has Remove download, which deletes its file but keeps '
          'the book and your place. Downloads has a Remove all button too',
    ],
  ),
  ChangelogEntry(
    version: '1.39.0',
    date: '2026-11-06',
    changes: [
      'Find ISBNs and Fix library also look on Google Books when Open '
          'Library has no ISBN for a book. Find ISBNs has a tick box for it, '
          'like Update covers, and each ISBN says where it came from',
    ],
  ),
  ChangelogEntry(
    version: '1.38.0',
    date: '2026-11-06',
    changes: [
      'Export for Goodreads or StoryGraph: Settings saves your books as a '
          'CSV in Goodreads\' format, with shelves, ratings, dates, series '
          'and ISBNs. Your notes go in Private Notes',
      'Author pages: "About this author" on a book now shows what you have '
          'read by them, all your books by them, and their books you do not '
          'have yet',
      'What should I read next? now also lists the next book in series you '
          'started, books by authors you rated well, and the books that have '
          'waited longest',
    ],
  ),
  ChangelogEntry(
    version: '1.37.0',
    date: '2026-11-05',
    changes: [
      'Fix library: runs the series spellings, your book files, Hardcover, '
          'ISBNs, covers and larger covers one after the other and shows '
          'everything found in one list. You tick what to apply',
      'Your book files: the series, ISBN and cover written inside your EPUB '
          'and M4B files, or known to your book server, fill in what a book '
          'is missing',
      'Hardcover: paste a free Hardcover token in Settings to find series '
          'there, and to see which books of a series you are missing on the '
          'Series screen, with their real titles',
      'Larger covers: covers chosen from Open Library and Google Books now '
          'use their bigger pictures, so they look sharper',
    ],
  ),
  ChangelogEntry(
    version: '1.36.0',
    date: '2026-11-05',
    changes: [
      'Library search: when you type in the search box at the top, buttons '
          'under it search Open Library or Google Books for the same words, '
          'in case the book is not in your library yet',
    ],
  ),
  ChangelogEntry(
    version: '1.35.0',
    date: '2026-11-05',
    changes: [
      'Update covers can also look on Google Books for books Open Library '
          'has no cover for. A tick box turns it off. It stops for the day '
          'when Google has no more searches',
    ],
  ),
  ChangelogEntry(
    version: '1.34.0',
    date: '2026-11-05',
    changes: [
      'Search Google Books yourself: a switch between Open Library and '
          'Google Books in the search screen, in Find match and in Find '
          'cover in the book editor. Without a Google Books key Google '
          'allows only a few searches a day; a free key (Settings) allows '
          'many more',
    ],
  ),
  ChangelogEntry(
    version: '1.33.0',
    date: '2026-11-05',
    changes: [
      'Find ISBNs: looks up books that have no ISBN on Open Library and '
          'shows the ISBN of the book that clearly matches. You choose which '
          'to add. Books that already have one are left alone',
    ],
  ),
  ChangelogEntry(
    version: '1.32.0',
    date: '2026-11-05',
    changes: [
      'Book editor: Find cover shows the covers Open Library has for the '
          'book, from every printing it lists, and you tap the one you want',
      'Update covers: finds books with no cover, or whose Open Library cover '
          'no longer exists, and fetches the cover Open Library has now. You '
          'choose which to use. Covers that still show are never replaced',
    ],
  ),
  ChangelogEntry(
    version: '1.31.0',
    date: '2026-11-05',
    changes: [
      'Import a CSV file: books already in your library can now take the '
          'series name and number from the file. The import window asks '
          'first and shows how many books will change',
    ],
  ),
  ChangelogEntry(
    version: '1.30.0',
    date: '2026-11-05',
    changes: [
      'Series: when one series is spelled two ways, such as "Dexter" and '
          '"Dexter Series" or "The Expanse" and "Expanse", a note at the top '
          'of the Series screen offers to join them. You pick which to join, '
          'and the book numbers stay as they are',
      'Series found in titles now use the spelling of a series you already '
          'have, even when it differs by a word like "Series" or "Saga"',
    ],
  ),
  ChangelogEntry(
    version: '1.29.0',
    date: '2026-11-05',
    changes: [
      'Use Google Books (Settings): fills in a missing cover, page count, '
          'ISBN, first published year and tags, in the background, a few '
          'books at a time and once per book. Nothing a book already has is '
          'changed, and tags are only added to books that have none. It is '
          'off by default because it sends each title and author to Google',
      'It works without a key, but then Google allows only a few books a '
          'day: Chapterly carries on the next day. A free "Google Books key" '
          '(Settings) allows many more',
    ],
  ),
  ChangelogEntry(
    version: '1.28.0',
    date: '2026-11-05',
    changes: [
      'Series are found for you: a book with its series in the title, like '
          '"Mistborn, Book 2" or "(The Expanse, #3)", gets the series and '
          'number by itself, now and as you add books. Series you set are '
          'never changed, and you can turn it off in Settings',
    ],
  ),
  ChangelogEntry(
    version: '1.27.0',
    date: '2026-11-05',
    changes: [
      'Review matches (More, Tidy up): lists the books whose title and '
          'author look very different from their original file name, so a '
          'wrong Open Library match is easy to spot. Tap Find match to fix '
          "one, or It's right to stop it being listed",
      'New on your book server: a banner at the top of your library shows '
          'the books the server found since you last looked, with a Download '
          'button for each. The server checks its folders every hour',
      'Quotes and notes (More): every quote, highlight and note in one '
          'place, with All, Quotes and Notes filters. Type to search them as '
          'before',
      'Series: the next book to read in a series now has its own Open button',
      'Reading stats: Hours listened, the length of the audiobooks you '
          'finished',
      'Audiobooks remember their own speed: set 1.4x for one book and it '
          'stays 1.4x for that book, while others keep theirs',
      'Importing a Goodreads, StoryGraph or other CSV file now shows how '
          'many books are new and how many you already have before anything '
          'is added',
    ],
  ),
  ChangelogEntry(
    version: '1.26.0',
    date: '2026-11-05',
    changes: [
      'Book info: tap the (i) button next to a book in the list, or on the '
          'book page, to see its original name (the file name on your book '
          'server, or the file you added it from), where it came from, and '
          'the title and author it was first matched as',
      'Edit a book: correct the title, author, series, ISBN, pages, year '
          'and cover from the pencil on the book page or "Edit this book" in '
          'Book info. "Find match" searches Open Library again so you can '
          'pick the right book when the match was wrong',
      'A book from your book server can be corrected on the server too, '
          'for everyone using it. The book file itself is never changed',
      '"Reset to the matched info" puts back the details the book was '
          'added with. Your corrections sync to your other devices',
    ],
  ),
  ChangelogEntry(
    version: '1.25.0',
    date: '2026-11-05',
    changes: [
      'A new look, Midnight: deep navy and teal in dark mode, and cool '
          'off-white with deeper teal in light mode. Light, Dark or follow '
          'the phone is still under Settings, Appearance. The older look is '
          'there too, as Classic, with its accent colours and paper option',
      'A new font, Manrope, comes with the app for the Midnight look. You '
          'can still pick another font in Settings',
      'The book you are reading now sits at the top of the library in a '
          '"Continue reading" card with how far along you are. Tap it to open '
          'the book, or turn it off in Settings, Appearance',
      'Rounded covers with a soft shadow, a progress bar under books you '
          'are reading in the grid, and the author under each title',
      'Books without a cover picture show their title on a coloured card '
          'instead of a plain icon',
      'The bar at the bottom floats as a rounded pill, and shelves, buttons, '
          'cards and dialogs are rounder and calmer',
      'The book page has a bigger cover on a teal band',
    ],
  ),
  ChangelogEntry(
    version: '1.24.2',
    date: '2026-11-04',
    changes: [
      'Fixed Chapterly stopping on start in a big library: the books are '
          'now read from and saved to the phone a few at a time, instead of '
          'all at once (the cover pictures are large)',
    ],
  ),
  ChangelogEntry(
    version: '1.24.1',
    date: '2026-11-04',
    changes: [
      'When the book server answers "not found", Chapterly now says why: the '
          'file or its folder was moved, or the server no longer serves that '
          'folder, instead of always saying the book is gone',
    ],
  ),
  ChangelogEntry(
    version: '1.24.0',
    date: '2026-11-04',
    changes: [
      'Connect to your book server with one code: on the Book server screen, '
          'tap "Scan server code" and point the camera at the code the server '
          'shows, or copy the code and tap "Paste server code". The address '
          'and token are filled in for you; then tap Connect. Typing them '
          'still works',
    ],
  ),
  ChangelogEntry(
    version: '1.23.0',
    date: '2026-11-04',
    changes: [
      'Pair with your PC by scanning a code: in Settings, tap "Scan code '
          'from your PC" and point the camera at the code shown by Chapterly '
          'on your PC. It turns on sync if it was off, and your PC finds '
          'the phone by itself. Typing the address and code still works',
    ],
  ),
  ChangelogEntry(
    version: '1.22.0',
    date: '2026-11-04',
    changes: [
      'Sync with a PC is now sealed with your pairing code: the code never '
          'goes over the Wi-Fi, nobody else on the network can read or change '
          'your library on its way, and a sync can\'t be recorded and sent '
          'again. Update Chapterly on your PC too; you don\'t need to pair '
          'again',
      'Sync with a PC: a device with its clock far ahead can no longer win '
          'every change or keep a book deleted',
      'Your highlights, bookmarks and audiobook places are saved more '
          'carefully, so two quick changes can\'t damage the file. If the '
          'file is ever damaged, it is kept aside instead of written over',
      'With the app lock on, automatic backups are kept inside Chapterly, '
          'where other apps and other profiles can\'t open them',
      'Waiting after too many wrong PINs can\'t be skipped by changing the '
          'phone\'s clock, and the PIN asked for in Settings counts the same '
          'tries as the lock screen',
      'Restoring a backup removes the books that are not in it everywhere, '
          'so the next sync doesn\'t bring them back. A backup with the same '
          'book twice restores fine',
      'With the app lock on, the home-screen widget and the audiobook '
          'notification don\'t say which book it is, and messages that name '
          'a book wait until you unlock',
      'A damaged audiobook file can no longer make Chapterly run out of '
          'memory while it looks for chapters',
      'Only the home-screen widget itself can play or pause your audiobook, '
          'not another app',
    ],
  ),
  ChangelogEntry(
    version: '1.21.0',
    date: '2026-11-04',
    changes: [
      'App lock: wrong PINs are counted even if you close Chapterly, and '
          'each round of five makes you wait longer (30 seconds, then a '
          'minute, up to an hour). Deleting a profile counts the same tries',
      'New switch with the app lock: hide Chapterly in the recent apps and '
          'in screenshots',
      'Sync with a PC: the phone only listens while Chapterly is open on '
          'the screen, a wrong code no longer hears which profile is open, '
          'and the code is checked in a way that gives nothing away',
      'Chapterly is left out of Android cloud backups and phone-to-phone '
          'transfers, so your library, pairing code and server token stay '
          'on this phone. Use Settings > Backup to move a library',
      'Removing a book\'s audio no longer takes away access to files that '
          'another book, or another profile, still plays',
      'Undo after a bulk change takes back only what that change did: a '
          'rating, note or tag you added since is kept, and books the change '
          'left alone are not touched',
      'A bulk change that changes nothing on a book leaves it as it was, so '
          'it is not sent again by the next sync',
      'Restoring a backup or importing books now sticks: the next sync no '
          'longer takes the books back to what they were, or removes them '
          'again',
      'Syncing with the book server no longer loses a change you make while '
          'cover pictures are being fetched',
      'Each profile keeps its automatic backups in a folder named after it '
          'and its id, so two profiles with names that look alike never '
          'share one (older backups stay where they were)',
      'Books from the book server are only saved inside Chapterly\'s '
          'folder, under a safe name',
      'CSV export: cells that a spreadsheet would run as a formula are '
          'saved as text',
    ],
  ),
  ChangelogEntry(
    version: '1.20.0',
    date: '2026-11-03',
    changes: [
      'Move books between your own shelves: open one of your shelves, '
          'select books, then More > Move to another shelf of mine. The '
          'books leave that shelf and go to the one you pick (or a new '
          'one), with Undo',
      'Take books off a shelf of your own: select them, then More > Remove '
          'from the shelf. The books stay in your library',
    ],
  ),
  ChangelogEntry(
    version: '1.19.0',
    date: '2026-11-03',
    changes: [
      'Profiles: everyone who reads on this phone can have their own '
          'Chapterly, with their own books, shelves, statistics, goals, '
          'settings, PC sync, book server connection and PIN (Settings, at '
          'the top, or More > Profiles). Your library is the first profile, '
          'called "Me"; rename it any time',
      'Opening another profile restarts Chapterly with it. A profile with a '
          'PIN asks for it when it opens, and the PIN screen can open another '
          'profile',
      'PC sync: each profile pairs with the PC on its own (Chapterly for '
          'Windows 1.15.0 or later), and the PC is told which profile is open',
    ],
  ),
  ChangelogEntry(
    version: '1.18.0',
    date: '2026-11-03',
    changes: [
      'A more colourful Statistics page: coloured tiles with icons, a bar '
          'that shows how your books are spread over the shelves (each shelf '
          'has its own colour), coloured bars for formats and ratings, and '
          'every part in its own rounded block',
    ],
  ),
  ChangelogEntry(
    version: '1.17.1',
    date: '2026-11-03',
    changes: [
      'Wishlist shelf: a fifth shelf for books you want but have not got '
          'yet. They are not counted as For later, in Next up or in your '
          'reading statistics. Open the book file and it moves to In progress',
      'Syncing a big library is fast and no longer fails: cover pictures '
          'travel on their own, and only to a device that does not have them. '
          'Update the phone, the PC and the server together',
    ],
  ),
  ChangelogEntry(
    version: '1.17.0',
    date: '2026-11-03',
    changes: [
      'Book server (More): connect to your own Chapterly book server, then '
          'browse and search your library there and download ebooks and '
          'audiobooks into Chapterly',
      'A book you download goes on For later, or is linked to the same book '
          'when it is already in your library',
      'Your place in those books syncs with your other devices: open a book '
          'and Chapterly carries on from the furthest place you reached',
      'Audiobook bookmarks sync through the book server too',
      'Sync my whole library (on the Book server screen): books, shelves, '
          'ratings, notes, quotes, bookmarks and the wish list sync through '
          'your server, from anywhere Tailscale reaches. A change made on '
          'each device to the same book keeps both',
      'Notes on highlights are kept on the book\'s quote, so they sync too',
      'EPUB places move between the phone and the PC: a place from the '
          'other reader opens at the same point in the book',
      'Send to my other devices: a book from the server downloads there '
          'the next time they open Chapterly',
      'Downloads (Book server): the space downloaded books use, and remove '
          'a file while keeping the book',
      'Audiobooks made of one file per chapter download as one book',
      'Reading reminder (Settings): a daily nudge when you\'re behind this '
          "year's goal, as a notification",
      'Home-screen widget: the book you\'re reading or listening to, with '
          'play and pause',
    ],
  ),
  ChangelogEntry(
    version: '1.16.0',
    date: '2026-11-02',
    changes: [
      'Wish list (More): books you want but do not have yet, with a '
          'priority and where to get each one. Search it, and move a book '
          'into your library (For later) when you get it',
      'The wish list syncs with Chapterly for Windows 1.12.0 or later: added, '
          'edited and deleted on either side (the newer change wins)',
      'Sync with a PC: tap the address or the pairing code to copy it, to '
          'paste into the PC app or keep in a password manager',
    ],
  ),
  ChangelogEntry(
    version: '1.15.0',
    date: '2026-11-01',
    changes: [
      'Audiobook bookmarks: save the place you are at in the player, with a '
          'note, and jump back to it later (Bookmark and Bookmarks)',
      'Bookmarks sync with Chapterly for Windows 1.11.0 and later: added, '
          'edited and deleted on either side',
      'Bookmark notes show up in Search notes and quotes, and in the notes '
          'you share from a book',
      'Book details added by a newer Chapterly on your PC are kept, so a '
          'sync never wipes them',
      'The player buttons wrap onto a second line on a small phone',
    ],
  ),
  ChangelogEntry(
    version: '1.14.0',
    date: '2026-11-01',
    changes: [
      'Search forgives typos ("Brandn Sanderson"), finds words in any order '
          'and names without accents ("Bronte")',
      "This year's reading goal at the top of the Library, with where you "
          'are heading by Dec 31 (hide it with the x, or in Settings)',
      'Finish forecast: a book you are reading shows when you should finish '
          'it at your recent pace (recent days count more)',
      'What should I read next? picks the best match for your taste and '
          'says why; the next book of a series you are reading comes first. '
          'Surprise me still picks at random',
      'Time I have (What should I read next?): only books you could read in '
          '1, 3, 6 or 12 hours',
      'Predicted rating and reading time on the Reading tab of a book',
      'Possible duplicates: Find duplicates also finds books that are nearly '
          'the same (a typo, a subtitle, "Deluxe Edition"), to merge or mark '
          'as not the same',
      'Better matching of book and audiobook files to your books',
      'Rewind a little after a pause (Settings, on by default): playing an '
          'audiobook again goes back 2 to 30 seconds',
      'Series (More): every series with what you have, what you finished, '
          'the missing numbers and what to read next; it can also find series '
          'in titles such as "The Final Empire (Mistborn, #1)"',
      'Tags (More): rename, merge or delete a tag on all books',
      'Saved filters: save the filter chips and search under a name (Saved '
          'filters, at the start of the chips)',
      'Stalled books: a note on the Library when a book on In progress has '
          'not moved for much longer than usual',
      'Quote of the day on the Library (turn it off in Settings)',
      'Library health (More): invalid ISBNs (and ISBN-10s to change to '
          'ISBN-13 in one tap), missing dates, pages, authors and covers, '
          'duplicates and stalled books',
      'Search notes and quotes (More): your notes, quotes, highlights and '
          'notes on highlights, best match first',
      'Share a book\'s notes, quotes and highlights as a Markdown file (the '
          'share button on the Notes tab)',
      'Your taste (Statistics): what you rate higher or lower than usual',
      'Suggested tags (Suggest, next to Tags on a book page)',
      'Similar books in your library, on a book page',
      'Refresh details from Open Library for the books you select: blank '
          'ISBNs, years, covers and pages are filled in',
      'A book with both an audiobook and a book file shows where you are in '
          'each, and carries on in one from where you are in the other',
    ],
  ),
  ChangelogEntry(
    version: '1.13.0',
    date: '2026-10-31',
    changes: [
      'Add a book to read or an audiobook from the + button in the library: '
          'pick an EPUB, PDF or audio file or folder and Chapterly finds its '
          'book in your library from the title and author in the file or its '
          'name',
      'Pick another book if it guessed wrong, or add the file as a new book '
          'with one tap',
    ],
  ),
  ChangelogEntry(
    version: '1.12.0',
    date: '2026-10-31',
    changes: [
      'Highlights in four colours, with your own notes',
      'Read aloud with the phone\'s voice, at the speed you like',
      'Volume buttons turn pages; the screen stays on; brightness for the '
          'reader',
      'Footnotes open over the page; look up a word in the dictionary',
      'PDFs: search and the PDF\'s own contents',
      'Text and theme just for one book, if you like',
      'Opening a book moves it to In progress, and the last page offers to '
          'mark it finished',
      'Statistics: time in the reader, reading speed and the longest streak',
    ],
  ),
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
