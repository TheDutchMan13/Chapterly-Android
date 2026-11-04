# Chapterly sync protocol (version 1)

The phone runs a small server while sync is switched on in Settings and the
app is open. A PC app on the same home Wi-Fi sends its library to the phone,
and gets back the merged library. Both sides end up with the same books.

## Sealed transport ("sync": 2, Chapterly 1.22.0 and later)

The messages below no longer travel as plain text, and the code is never
sent. Both apps derive an AES-256-GCM key from the pairing code
(`lib/data/sync_crypto.dart`, the same file in both apps):

- `GET /v1/ping` (plain, no code) also answers `"sync": 2`.
- `GET /v2/hello` (plain, no code) answers `{"challenge": "..."}`; valid for
  5 minutes, usable for every request of one sync.
- `POST /v2/sync`, `POST /v2/covers/missing`, `GET` and `PUT
  /v2/covers/<name>` carry `X-Chapterly-Challenge` and a body sealed for
  `"<METHOD> <path> <challenge>"` (a GET sends a sealed empty body). The
  answer is sealed for `"response <METHOD> <path> <challenge>"`, also for
  JSON errors. A cover PUT answers `200` with a sealed empty body.
- Refused before opening (plain JSON): `401 {"error":"challenge"}` (get a new
  challenge and retry once), `401 {"error":"code"}`, `401
  {"error":"replay"}`, `413` too large, `429` after 20 wrong codes in a
  minute (for a minute).
- The old `/v1/sync` and `/v1/covers` routes answer `426`: update the PC app.

What follows describes the content of the messages, which is unchanged.

## Connecting

1. On the phone: Settings > Sync with a PC > switch on "Allow sync from my PC".
   The phone shows its address (for example `192.168.1.20:8765`) and a
   16-character pairing code.
2. On the PC: enter the address and the code once. Remove the dashes from the
   code (`ABCD-EFGH-...` becomes `ABCDEFGH...`).

### Pairing with a QR code (Chapterly 1.23.0 and later)

Instead of typing, the PC can show a QR code and the phone scans it:

1. The PC shows a QR code whose text is exactly `chapterly-pair:1:<CODE>`,
   where `<CODE>` is 16 characters A-Z and 0-9 (the pairing code without
   dashes, uppercase). Nothing else is in it.
2. On the phone: Settings > Sync with a PC > "Scan code from your PC". Only
   text matching `^chapterly-pair:1:[A-Z0-9]{16}$` (spaces around it are
   ignored) is accepted; other codes are ignored.
3. The phone turns sync on if it was off, stores `<CODE>` as its pairing code
   and restarts its sync server, so the key derived from the code
   (`sync_crypto.dart`) is the new one at once. It then says "Code set".
4. The PC finds the phone on the home Wi-Fi by itself (for example by trying
   `/v1/ping` on the local network) and checks the code with `/v2/hello` and
   a sealed request. The phone only listens while Chapterly is open on the
   screen, so it must stay open until the PC has paired.

The old code is replaced, as with "New code". The manual address and code
still work.

Port: 8765. The code is sent in the `Authorization` header, so only use this
on your own home network. Anyone on the same Wi-Fi with the code can read and
change your library. Press "New code" on the phone to revoke access.

## Requests

### `GET /v1/ping` (no code needed)

Reply `200`:

    {"app": "chapterly", "protocol": 1}

Use it to check that an address is a Chapterly phone before pairing.

When the phone has more than one profile, the reply also has `"profile"`, the
name of the profile open on the phone. Only the open profile answers, with its
own pairing code; a code of another profile gets a `401` whose `error` names
the open profile.

### `POST /v1/sync`

Header: `Authorization: Bearer <code>`, `Content-Type: application/json`.

Body: the PC's whole library, including books in the trash, and the list of
books it has permanently deleted:

    {
      "app": "chapterly",
      "protocol": 1,
      "features": ["audioBookmarks", "wishes"],
      "books": [ { ...book... } ],
      "wishes": [ { ...wish... } ],
      "tombstones": { "<book id>": "2026-03-01T12:00:00.000" }
    }

`wishes` is the wish list (books you want but do not own yet), deleted ones
included. `features` lists what this app can carry; "wishes" means it keeps
and returns the wish list. An app without a wish list ignores `wishes` and
sends none, which leaves the other device's list as it is.

`features` lists what this app's book data can carry. Apps before Android
1.15.0 and Windows 1.11.0 send none and ignore the list. `audioBookmarks`
means the app keeps a book's audiobook bookmarks and sends them back; the PC
does not trust the bookmarks in a reply without it and keeps its own.

Reply `200`: the merged library in the same shape. The PC should replace its
library with it.

Errors: `401` wrong or missing code, `400` the message is not valid or needs a
newer protocol (reply has `{"error": "..."}` text), `500` the phone could not
finish.

Looking without changing anything: a body with no books and no tombstones
merges nothing into the phone's library, so the phone's library stays as it
is and the reply is simply the phone's library. The PC uses this for "Show
changes before syncing": it works out what a real sync would change on each
side, shows it, and only then sends its real library.

## A book

Fields (all optional except `id`, `title`, `shelf`, `addedAt`, `updatedAt`):

    id, title, author, shelf ("finished" | "inProgress" | "forLater" | "unfinished"),
    addedAt, updatedAt, deletedAt, tags (list), isbn, coverUrl,
    firstPublishYear, pages, rating (1-5), startedAt, finishedAt,
    format ("paperback" | "hardcover" | "ebook" | "audiobook"),
    favorite (bool), notes, series, seriesNumber,
    collections (list of shelf names),
    quotes (list of {text, page, addedAt}),
    currentPage, aspectRatings ({"plot" | "characters" | "writing" | "pacing": 1-5}),
    priority ("low" | "medium" | "high"), buyAt (shop, library or link),
    queuePosition (place in the Next up order, 0 is first),
    audio ({positionMs, lengthMs, track, trackMs, trackCount}: where you are
      in the audiobook; the audio files themselves never sync),
    audioBookmarks (list of {track, trackMs, positionMs, addedAt, note}:
      places saved in the audiobook; `addedAt` tells two apart. Left out
      when a book has none),
    readingLog (list of {date, pages, minutes}),
    previousReadings (list of {startedAt, finishedAt, rating, log})

Dates are ISO 8601 text.

A field an app does not know (sent by a newer Chapterly) is kept with the
book and sent back unchanged, so a sync with an older app never wipes it.

`coverUrl` is usually a web address. A cover added on the PC from a picture is
stored in the book itself as a small JPEG data address
(`data:image/jpeg;base64,...`, about 400 pixels wide), so it syncs like any
other field. Both apps show either kind.

## A wish

    id, title, author, isbn, priority ("low" | "medium" | "high"),
    where (shop, library or link), note, addedAt, updatedAt, deletedAt

Wishes are merged by `id`: the copy with the newer `updatedAt` wins (on a tie
the device that is merging wins). A deleted wish keeps its `deletedAt` and is
kept for 180 days so the delete reaches the other device; an edit made after
a delete brings the wish back.

## Merging rules

Use the same rules on both sides:

1. For each book id, the copy with the newer `updatedAt` wins. On a tie the
   copy on the device that is merging wins.
2. A book whose tombstone time is the same as or later than its `updatedAt` is
   removed. A book changed after its tombstone is kept, and the tombstone is
   dropped.
3. Keep the newest tombstone time when both sides have one for the same id.

The phone's own code for these rules is in `lib/data/sync_merge.dart`, and its
tests are in `test/sync_test.dart`.
