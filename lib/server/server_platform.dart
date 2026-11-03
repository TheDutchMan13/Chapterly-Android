// What differs between the phone and the PC for the book server.

/// How this app's reader writes a place in an EPUB. The phone's reader uses
/// EPUB CFIs, which the PC's reader can't use, so each kind is named and an
/// app only jumps to places it understands. (The PC uses "epub-win".)
const localEpubPositionKind = 'epub-cfi';

/// Where the player finds a downloaded audio file at [path].
String audioLocationFor(String path) => Uri.file(path).toString();
