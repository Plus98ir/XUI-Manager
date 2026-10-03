import 'dart:convert';
import 'dart:math';

final _rnd = Random.secure();

const _lowerAlnum = 'abcdefghijklmnopqrstuvwxyz0123456789';

String randomString(int length, {String chars = _lowerAlnum}) =>
    List.generate(length, (_) => chars[_rnd.nextInt(chars.length)]).join();

String uuidV4() {
  final b = List<int>.generate(16, (_) => _rnd.nextInt(256));
  b[6] = (b[6] & 0x0f) | 0x40;
  b[8] = (b[8] & 0x3f) | 0x80;
  final h = b.map((e) => e.toRadixString(16).padLeft(2, '0')).join();
  return '${h.substring(0, 8)}-${h.substring(8, 12)}-${h.substring(12, 16)}-'
      '${h.substring(16, 20)}-${h.substring(20)}';
}

String randomBase64Key(int bytes) =>
    base64.encode(List<int>.generate(bytes, (_) => _rnd.nextInt(256)));

/// A WireGuard (Curve25519) private key: 32 random bytes, clamped, base64.
String randomWireguardKey() {
  final b = List<int>.generate(32, (_) => _rnd.nextInt(256));
  b[0] &= 248;
  b[31] = (b[31] & 127) | 64;
  return base64.encode(b);
}

String randomUserName() => 'user_${randomString(5)}';
