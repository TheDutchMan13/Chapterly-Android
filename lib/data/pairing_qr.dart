final _pairingQr = RegExp(r'^chapterly-pair:1:([A-Z0-9]{16})$');

/// The pairing code inside a QR code shown by the PC app, or null if [text] is
/// not one. The text is `chapterly-pair:1:` followed by 16 capital letters or
/// digits, and nothing else (spaces around it are ignored).
String? parsePairingQr(String text) {
  final match = _pairingQr.firstMatch(text.trim());
  return match?.group(1);
}
