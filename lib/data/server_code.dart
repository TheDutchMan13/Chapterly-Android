final _host = RegExp(r'^[A-Za-z0-9]([A-Za-z0-9.-]*[A-Za-z0-9])?$');
final _port = RegExp(r'^[0-9]{1,5}$');
final _token = RegExp(r'^[A-Za-z0-9_.~-]+$');

/// The address and token inside a server code, or null if [text] is not one.
/// A server code is `chapterly-server:1|<host>:<port>|<token>`; spaces around
/// it are ignored.
({String address, String token})? parseServerCode(String text) {
  final parts = text.trim().split('|');
  if (parts.length != 3 || parts[0] != 'chapterly-server:1') return null;
  final address = parts[1];
  final token = parts[2];
  final colon = address.lastIndexOf(':');
  if (colon <= 0) return null;
  final host = address.substring(0, colon);
  final port = address.substring(colon + 1);
  if (!_host.hasMatch(host) || !_port.hasMatch(port)) return null;
  final number = int.parse(port);
  if (number < 1 || number > 65535) return null;
  if (!_token.hasMatch(token)) return null;
  return (address: address, token: token);
}
