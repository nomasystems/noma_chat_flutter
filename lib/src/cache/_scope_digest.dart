import 'dart:convert';

/// Number of hex characters kept from the digest — 128 bits.
const int _digestHexLength = 32;

/// A fixed-length, collision-free namespace key for [value].
///
/// Box names are the constraint this exists for: Hive asserts they are
/// ASCII and at most 255 characters, and lower-cases them before naming a
/// file, so a raw identifier cannot be carried into one. Anything that
/// folds an id into that alphabet — replacing the characters outside it,
/// truncating, lower-casing — maps different ids onto the same name, and
/// on a per-user cache that means one user reading another's store.
///
/// A SHA-256 digest of the raw bytes, truncated to 128 bits and rendered
/// in lowercase hex, is injective for every practical purpose, is already
/// in the surviving alphabet, and is 32 characters wide whatever the id
/// is — which is also what keeps a per-room box name inside Hive's limit
/// regardless of how long the host's ids are.
String scopeDigest(String value) =>
    _sha256Hex(utf8.encode(value)).substring(0, _digestHexLength);

/// SHA-256 (FIPS 180-4) over [bytes], as 64 lowercase hex characters.
///
/// Hand-rolled rather than taken from `package:crypto`: that package is
/// not a dependency of `noma_chat`, and a cache namespace key does not
/// justify adding one to every consumer of the SDK. Every intermediate is
/// masked back to 32 bits, so the result is identical on the Dart VM and
/// on the web, where `int` is a double and unmasked 64-bit arithmetic
/// would silently lose precision.
String _sha256Hex(List<int> bytes) {
  final h = <int>[
    0x6a09e667,
    0xbb67ae85,
    0x3c6ef372,
    0xa54ff53a,
    0x510e527f,
    0x9b05688c,
    0x1f83d9ab,
    0x5be0cd19,
  ];

  final block = List<int>.filled(64, 0);
  final w = List<int>.filled(64, 0);
  final padded = _padded(bytes);

  for (var offset = 0; offset < padded.length; offset += 64) {
    block.setRange(0, 64, padded, offset);
    for (var t = 0; t < 16; t++) {
      final i = t * 4;
      w[t] =
          ((block[i] << 24) |
              (block[i + 1] << 16) |
              (block[i + 2] << 8) |
              block[i + 3]) &
          0xFFFFFFFF;
    }
    for (var t = 16; t < 64; t++) {
      final s0 = _rotr(w[t - 15], 7) ^ _rotr(w[t - 15], 18) ^ (w[t - 15] >>> 3);
      final s1 = _rotr(w[t - 2], 17) ^ _rotr(w[t - 2], 19) ^ (w[t - 2] >>> 10);
      w[t] = (w[t - 16] + s0 + w[t - 7] + s1) & 0xFFFFFFFF;
    }

    var a = h[0];
    var b = h[1];
    var c = h[2];
    var d = h[3];
    var e = h[4];
    var f = h[5];
    var g = h[6];
    var hh = h[7];

    for (var t = 0; t < 64; t++) {
      final s1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ (~e & 0xFFFFFFFF & g);
      final temp1 = (hh + s1 + ch + _k[t] + w[t]) & 0xFFFFFFFF;
      final s0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final temp2 = (s0 + maj) & 0xFFFFFFFF;
      hh = g;
      g = f;
      f = e;
      e = (d + temp1) & 0xFFFFFFFF;
      d = c;
      c = b;
      b = a;
      a = (temp1 + temp2) & 0xFFFFFFFF;
    }

    h[0] = (h[0] + a) & 0xFFFFFFFF;
    h[1] = (h[1] + b) & 0xFFFFFFFF;
    h[2] = (h[2] + c) & 0xFFFFFFFF;
    h[3] = (h[3] + d) & 0xFFFFFFFF;
    h[4] = (h[4] + e) & 0xFFFFFFFF;
    h[5] = (h[5] + f) & 0xFFFFFFFF;
    h[6] = (h[6] + g) & 0xFFFFFFFF;
    h[7] = (h[7] + hh) & 0xFFFFFFFF;
  }

  return h.map((word) => word.toRadixString(16).padLeft(8, '0')).join();
}

/// [bytes] followed by `0x80`, zeroes up to a 56-byte remainder, and the
/// original length in bits as a 64-bit big-endian integer.
List<int> _padded(List<int> bytes) {
  final padded = <int>[...bytes, 0x80];
  while (padded.length % 64 != 56) {
    padded.add(0);
  }
  final bitLength = bytes.length * 8;
  final high = bitLength ~/ 0x100000000;
  final low = bitLength & 0xFFFFFFFF;
  for (final word in [high, low]) {
    padded.add((word >>> 24) & 0xFF);
    padded.add((word >>> 16) & 0xFF);
    padded.add((word >>> 8) & 0xFF);
    padded.add(word & 0xFF);
  }
  return padded;
}

int _rotr(int x, int n) => ((x >>> n) | (x << (32 - n))) & 0xFFFFFFFF;

const List<int> _k = <int>[
  0x428a2f98,
  0x71374491,
  0xb5c0fbcf,
  0xe9b5dba5,
  0x3956c25b,
  0x59f111f1,
  0x923f82a4,
  0xab1c5ed5,
  0xd807aa98,
  0x12835b01,
  0x243185be,
  0x550c7dc3,
  0x72be5d74,
  0x80deb1fe,
  0x9bdc06a7,
  0xc19bf174,
  0xe49b69c1,
  0xefbe4786,
  0x0fc19dc6,
  0x240ca1cc,
  0x2de92c6f,
  0x4a7484aa,
  0x5cb0a9dc,
  0x76f988da,
  0x983e5152,
  0xa831c66d,
  0xb00327c8,
  0xbf597fc7,
  0xc6e00bf3,
  0xd5a79147,
  0x06ca6351,
  0x14292967,
  0x27b70a85,
  0x2e1b2138,
  0x4d2c6dfc,
  0x53380d13,
  0x650a7354,
  0x766a0abb,
  0x81c2c92e,
  0x92722c85,
  0xa2bfe8a1,
  0xa81a664b,
  0xc24b8b70,
  0xc76c51a3,
  0xd192e819,
  0xd6990624,
  0xf40e3585,
  0x106aa070,
  0x19a4c116,
  0x1e376c08,
  0x2748774c,
  0x34b0bcb5,
  0x391c0cb3,
  0x4ed8aa4a,
  0x5b9cca4f,
  0x682e6ff3,
  0x748f82ee,
  0x78a5636f,
  0x84c87814,
  0x8cc70208,
  0x90befffa,
  0xa4506ceb,
  0xbef9a3f7,
  0xc67178f2,
];
