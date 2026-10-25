// Pure Dart logic (no Flutter imports) so it can be tested on its own.
// QR and pass formats match the HTML version, so both apps understand each other.
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

const int kMask = 0xFFFFFFFF;
const int kPbkdf2Iters = 60000;

const List<int> _k = [
  0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5,
  0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
  0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
  0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
  0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
  0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
  0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
  0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
];

int _rotr(int x, int n) => ((x >> n) | (x << (32 - n))) & kMask;

/// SHA-256 of [msg].
Uint8List sha256(List<int> msg) {
  final h = <int>[0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, 0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19];
  final l = msg.length;
  final n = ((l + 9 + 63) >> 6) << 6; // padded length, a multiple of 64
  final buf = Uint8List(n);
  buf.setRange(0, l, msg);
  buf[l] = 0x80; // the mandatory 1 bit after the message
  final bd = ByteData.view(buf.buffer);
  final bits = l * 8;
  bd.setUint32(n - 8, bits ~/ 4294967296);
  bd.setUint32(n - 4, bits & kMask);
  final w = List<int>.filled(64, 0);
  for (var o = 0; o < n; o += 64) {
    for (var i = 0; i < 16; i++) {
      w[i] = bd.getUint32(o + i * 4);
    }
    for (var i = 16; i < 64; i++) {
      final s0 = _rotr(w[i - 15], 7) ^ _rotr(w[i - 15], 18) ^ (w[i - 15] >> 3);
      final s1 = _rotr(w[i - 2], 17) ^ _rotr(w[i - 2], 19) ^ (w[i - 2] >> 10);
      w[i] = (w[i - 16] + s0 + w[i - 7] + s1) & kMask;
    }
    var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4], f = h[5], g = h[6], hh = h[7];
    for (var i = 0; i < 64; i++) {
      final bigS1 = _rotr(e, 6) ^ _rotr(e, 11) ^ _rotr(e, 25);
      final ch = (e & f) ^ ((~e & kMask) & g);
      final t1 = (hh + bigS1 + ch + _k[i] + w[i]) & kMask;
      final bigS0 = _rotr(a, 2) ^ _rotr(a, 13) ^ _rotr(a, 22);
      final mj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (bigS0 + mj) & kMask;
      hh = g;
      g = f;
      f = e;
      e = (d + t1) & kMask;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & kMask;
    }
    h[0] = (h[0] + a) & kMask;
    h[1] = (h[1] + b) & kMask;
    h[2] = (h[2] + c) & kMask;
    h[3] = (h[3] + d) & kMask;
    h[4] = (h[4] + e) & kMask;
    h[5] = (h[5] + f) & kMask;
    h[6] = (h[6] + g) & kMask;
    h[7] = (h[7] + hh) & kMask;
  }
  final out = Uint8List(32);
  final od = ByteData.view(out.buffer);
  for (var i = 0; i < 8; i++) {
    od.setUint32(i * 4, h[i]);
  }
  return out;
}

/// HMAC-SHA256.
Uint8List hmacSha256(List<int> key, List<int> msg) {
  var k = key;
  if (k.length > 64) k = sha256(k);
  final kk = Uint8List(64)..setRange(0, k.length, k);
  final ip = Uint8List(64), op = Uint8List(64);
  for (var i = 0; i < 64; i++) {
    ip[i] = kk[i] ^ 0x36;
    op[i] = kk[i] ^ 0x5c;
  }
  return sha256([...op, ...sha256([...ip, ...msg])]);
}

String hexOf(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

Uint8List unhex(String h) {
  final out = Uint8List(h.length ~/ 2);
  for (var i = 0; i < out.length; i++) {
    out[i] = int.parse(h.substring(i * 2, i * 2 + 2), radix: 16);
  }
  return out;
}

/// PBKDF2-HMAC-SHA256, one 32-byte block. Used to hash passwords.
String pbkdf2Hex(String password, String saltHex, int iterations) {
  final pw = utf8.encode(password);
  var u = hmacSha256(pw, [...unhex(saltHex), 0, 0, 0, 1]);
  final t = Uint8List.fromList(u);
  for (var i = 1; i < iterations; i++) {
    u = hmacSha256(pw, u);
    for (var j = 0; j < 32; j++) {
      t[j] ^= u[j];
    }
  }
  return hexOf(t);
}

final Random _rng = Random.secure();
String randHex(int n) => hexOf(List<int>.generate(n, (_) => _rng.nextInt(256)));

const String _codeChars = 'ABCDEFGHJKLMNPQRSTUVWXYZ23456789';
String newSessionCode() => List.generate(6, (_) => _codeChars[_rng.nextInt(_codeChars.length)]).join();
String cleanCode(String c) => c.toUpperCase().replaceAll(RegExp(r'[^A-Z0-9]'), '');

String sigOf(String secret, String text) =>
    hexOf(hmacSha256(utf8.encode(secret), utf8.encode(text))).substring(0, 16);

/// What goes inside a student's QR: session code + student id + signature.
String qrText(String rid, String secret, String code) => 'QA4|$code|$rid|${sigOf(secret, '$code|$rid')}';

String makePass(String id, String name, String secret) =>
    'QAP2.${base64.encode(utf8.encode(jsonEncode({'r': id, 'n': name, 's': secret})))}';

/// Returns {r, n, s} or null when the pass is invalid.
Map<String, dynamic>? parsePass(String text) {
  try {
    final t = text.trim();
    if (!t.startsWith('QAP2.')) return null;
    final o = jsonDecode(utf8.decode(base64.decode(t.substring(5)))) as Map<String, dynamic>;
    if (o['r'] == null || o['s'] == null) return null;
    return o;
  } catch (_) {
    return null;
  }
}

// ---------------- time helpers ----------------
int nowMs() => DateTime.now().millisecondsSinceEpoch;

String mmss(int ms) {
  final s = (ms <= 0 ? 0 : (ms / 1000).ceil());
  return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
}

String fmtTime(int ms) {
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  return '$h:${d.minute.toString().padLeft(2, '0')} ${d.hour < 12 ? 'AM' : 'PM'}';
}

String fmtDate(int ms) {
  const m = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  return '${m[d.month - 1]} ${d.day}, ${d.year}';
}

// ---------------- models ----------------
class Student {
  String id, name, secret, parentEmail;
  Student(this.id, this.name, this.secret, [this.parentEmail = '']);
  Map<String, dynamic> toJson() => {'id': id, 'name': name, 'secret': secret, 'parentEmail': parentEmail};
  factory Student.fromJson(Map<String, dynamic> j) =>
      Student(j['id'] as String, j['name'] as String, (j['secret'] ?? '') as String, (j['parentEmail'] ?? '') as String);
}

bool looksLikeEmail(String e) => RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(e);

class Present {
  int t;
  String m; // 'qr' or 'manual'
  Present(this.t, this.m);
  Map<String, dynamic> toJson() => {'t': t, 'm': m};
  factory Present.fromJson(Map<String, dynamic> j) => Present(j['t'] as int, j['m'] as String);
}

class Session {
  String id, code, name, status;
  int minutes, startedAt, deadlineAt;
  int? closedAt;
  List<Student> roster; // snapshot of who is in this session (secret left empty)
  Map<String, Present> present;
  Session({
    required this.id,
    required this.code,
    required this.name,
    required this.minutes,
    required this.startedAt,
    required this.deadlineAt,
    required this.roster,
    this.status = 'open',
    this.closedAt,
    Map<String, Present>? present,
  }) : present = present ?? {};

  bool get isOpen => status == 'open' && nowMs() < deadlineAt;
  bool get isDone => !isOpen;
  int get presentCount => roster.where((r) => present.containsKey(r.id)).length;
  int get restCount => roster.length - presentCount;

  Map<String, dynamic> toJson() => {
        'id': id,
        'code': code,
        'name': name,
        'status': status,
        'minutes': minutes,
        'startedAt': startedAt,
        'deadlineAt': deadlineAt,
        'closedAt': closedAt,
        'roster': roster.map((r) => r.toJson()).toList(),
        'present': present.map((k, v) => MapEntry(k, v.toJson())),
      };

  factory Session.fromJson(Map<String, dynamic> j) => Session(
        id: j['id'] as String,
        code: j['code'] as String,
        name: j['name'] as String,
        status: j['status'] as String,
        minutes: j['minutes'] as int,
        startedAt: j['startedAt'] as int,
        deadlineAt: j['deadlineAt'] as int,
        closedAt: j['closedAt'] as int?,
        roster: (j['roster'] as List).map((e) => Student.fromJson(e as Map<String, dynamic>)).toList(),
        present: (j['present'] as Map<String, dynamic>).map((k, v) => MapEntry(k, Present.fromJson(v as Map<String, dynamic>))),
      );
}

class Account {
  String id, role, name, username, salt, hash;
  int iters;
  List<Student> roster; // teacher only
  List<Session> sessions; // teacher only
  String? passR, passN, passS; // student only: the pass from the teacher
  String? code; // student only: current session code

  Account({
    required this.id,
    required this.role,
    required this.name,
    required this.username,
    required this.salt,
    required this.hash,
    required this.iters,
    List<Student>? roster,
    List<Session>? sessions,
    this.passR,
    this.passN,
    this.passS,
    this.code,
  })  : roster = roster ?? [],
        sessions = sessions ?? [];

  bool get isTeacher => role == 'teacher';
  List<Session> get openSessions => sessions.where((s) => s.isOpen).toList();

  Map<String, dynamic> toJson() => {
        'id': id,
        'role': role,
        'name': name,
        'username': username,
        'salt': salt,
        'hash': hash,
        'iters': iters,
        'roster': roster.map((r) => r.toJson()).toList(),
        'sessions': sessions.map((s) => s.toJson()).toList(),
        'passR': passR,
        'passN': passN,
        'passS': passS,
        'code': code,
      };

  factory Account.fromJson(Map<String, dynamic> j) => Account(
        id: j['id'] as String,
        role: j['role'] as String,
        name: j['name'] as String,
        username: j['username'] as String,
        salt: j['salt'] as String,
        hash: j['hash'] as String,
        iters: j['iters'] as int,
        roster: (j['roster'] as List).map((e) => Student.fromJson(e as Map<String, dynamic>)).toList(),
        sessions: (j['sessions'] as List).map((e) => Session.fromJson(e as Map<String, dynamic>)).toList(),
        passR: j['passR'] as String?,
        passN: j['passN'] as String?,
        passS: j['passS'] as String?,
        code: j['code'] as String?,
      );
}

// ---------------- scanning ----------------
class ScanResult {
  final String kind; // 'ok', 'warn' or 'bad'
  final String msg;
  const ScanResult(this.kind, this.msg);
}

/// Checks a scanned QR against the teacher's open sessions and marks the student present.
/// The caller saves the account afterwards when result.kind == 'ok'.
ScanResult handleScan(Account teacher, String raw) {
  final p = raw.trim().split('|');
  if (p.length != 4 || p[0] != 'QA4') return const ScanResult('bad', 'Not an attendance QR (old format? ask the student to refresh)');
  final open = teacher.openSessions;
  final matches = open.where((s) => s.code == p[1]).toList();
  if (matches.isEmpty) {
    return ScanResult('bad', open.isNotEmpty ? 'This QR is from a different or finished session' : 'No class is open. Time is up, so this student is absent.');
  }
  final s = matches.first;
  final rid = p[2];
  final full = teacher.roster.where((r) => r.id == rid).toList();
  if (full.isEmpty) return const ScanResult('bad', 'Student not on your list');
  final inSession = s.roster.where((r) => r.id == rid).toList();
  if (inSession.isEmpty) return ScanResult('bad', '${full.first.name} is not in "${s.name}"');
  if (sigOf(full.first.secret, '${s.code}|$rid') != p[3]) return const ScanResult('bad', 'Invalid or forged QR');
  if (s.present.containsKey(rid)) return ScanResult('warn', '${full.first.name} is already marked present in ${s.name}');
  s.present[rid] = Present(nowMs(), 'qr');
  return ScanResult('ok', '${full.first.name} is present · ${s.name}');
}

/// Closes any session whose time ran out. Returns true when something changed.
bool closeExpired(Account teacher) {
  var changed = false;
  final now = nowMs();
  for (final s in teacher.sessions) {
    if (s.status == 'open' && now >= s.deadlineAt) {
      s.status = 'closed';
      s.closedAt = now;
      changed = true;
    }
  }
  return changed;
}
