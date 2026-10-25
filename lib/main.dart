import 'dart:async';
import 'dart:convert';
import 'dart:isolate';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:mobile_scanner/mobile_scanner.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';

import 'core.dart';

void main() => runApp(const QrApp());

// Runs the slow password hashing in the background without capturing any screen objects.
Future<String> hashAsync(String pw, String salt, int iters) =>
    Isolate.run(() => pbkdf2Hex(pw, salt, iters));

// ---------------------------------------------------------------- email to parents
String parentEmailFor(Account me, Student r) {
  for (final x in me.roster) {
    if (x.id == r.id) return x.parentEmail;
  }
  return r.parentEmail;
}

Future<void> sendParentMail(BuildContext context, Account me, Session s, Student r) async {
  final to = parentEmailFor(me, r);
  final p = s.present[r.id];
  final when = fmtDate(s.startedAt);
  final subject = p != null ? '${r.name} came to ${s.name}' : '${r.name} was absent from ${s.name}';
  final line = p != null
      ? '${r.name} came in class "${s.name}" at ${fmtTime(p.t)} on $when.'
      : '${r.name} was absent from class "${s.name}" on $when.';
  final body = 'Hello,\n\n$line\n\nThank you,\n${me.name}';
  final uri = Uri.parse('mailto:$to?subject=${Uri.encodeComponent(subject)}&body=${Uri.encodeComponent(body)}');
  var ok = false;
  try {
    ok = await launchUrl(uri);
  } catch (_) {
    ok = false;
  }
  if (!ok) {
    await Clipboard.setData(ClipboardData(text: 'To: $to\nSubject: $subject\n\n$body'));
    if (context.mounted) snack(context, 'No email app found. The message was copied instead.');
  }
}

void showEmailParents(BuildContext context, Account me, Session s) {
  final rows = s.roster.where((r) => s.present.containsKey(r.id) || s.isDone).toList();
  showModalBottomSheet(
    context: context,
    isScrollControlled: true,
    builder: (ctx) => SafeArea(
      child: ConstrainedBox(
        constraints: BoxConstraints(maxHeight: MediaQuery.of(ctx).size.height * 0.8),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Align(alignment: Alignment.centerLeft, child: Text('Email parents: ${s.name}', style: Theme.of(ctx).textTheme.titleMedium)),
          ),
          const Padding(
            padding: EdgeInsets.symmetric(horizontal: 16),
            child: Text('Tap Email to open your email app with the message ready to send. Add parent emails in the Students tab.', style: TextStyle(fontSize: 12)),
          ),
          if (rows.isEmpty)
            const Padding(padding: EdgeInsets.all(16), child: Text('Nobody to email yet. Students show up here once they are scanned, or when the session closes.'))
          else
            Flexible(
              child: ListView(
                shrinkWrap: true,
                children: rows.map((r) {
                  final p = s.present[r.id];
                  final em = parentEmailFor(me, r);
                  return ListTile(
                    title: Text(r.name),
                    subtitle: Text('${p != null ? 'Came in at ${fmtTime(p.t)}' : 'Absent'}\n${em.isEmpty ? 'No parent email yet' : em}'),
                    isThreeLine: true,
                    trailing: FilledButton.tonal(
                      onPressed: em.isEmpty ? null : () => sendParentMail(ctx, me, s, r),
                      child: const Text('Email'),
                    ),
                  );
                }).toList(),
              ),
            ),
        ]),
      ),
    ),
  );
}

class QrApp extends StatelessWidget {
  const QrApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'QR Attendance',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(colorSchemeSeed: Colors.indigo, useMaterial3: true),
      darkTheme: ThemeData(colorSchemeSeed: Colors.indigo, brightness: Brightness.dark, useMaterial3: true),
      themeMode: ThemeMode.system,
      home: const Root(),
    );
  }
}

// ---------------------------------------------------------------- storage
class Store {
  final SharedPreferences prefs;
  List<Account> accounts = [];
  String remember = '';
  Store(this.prefs);

  static Future<Store> load() async {
    final s = Store(await SharedPreferences.getInstance());
    final raw = s.prefs.getString('qa_state');
    if (raw != null) {
      try {
        final j = jsonDecode(raw) as Map<String, dynamic>;
        s.accounts = (j['accounts'] as List).map((e) => Account.fromJson(e as Map<String, dynamic>)).toList();
        s.remember = (j['remember'] ?? '') as String;
      } catch (_) {}
    }
    return s;
  }

  Future<void> save() => prefs.setString('qa_state', jsonEncode({'accounts': accounts.map((a) => a.toJson()).toList(), 'remember': remember}));
}

// ---------------------------------------------------------------- small helpers
void snack(BuildContext c, String m) => ScaffoldMessenger.of(c).showSnackBar(SnackBar(content: Text(m)));

Future<bool> confirmDlg(BuildContext c, String msg, {String yes = 'OK'}) async {
  final r = await showDialog<bool>(
    context: c,
    builder: (ctx) => AlertDialog(
      content: Text(msg),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(onPressed: () => Navigator.pop(ctx, true), child: Text(yes)),
      ],
    ),
  );
  return r ?? false;
}

class Pill extends StatelessWidget {
  final String text;
  final Color color;
  const Pill(this.text, this.color, {super.key});
  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
        decoration: BoxDecoration(border: Border.all(color: color), borderRadius: BorderRadius.circular(99)),
        child: Text(text, style: TextStyle(color: color, fontSize: 11, fontWeight: FontWeight.w600)),
      );
}

Widget stat(String v, String l) => Expanded(
      child: Container(
        margin: const EdgeInsets.symmetric(horizontal: 3),
        padding: const EdgeInsets.symmetric(vertical: 8),
        decoration: BoxDecoration(border: Border.all(color: Colors.grey.withAlpha(90)), borderRadius: BorderRadius.circular(10)),
        child: Column(children: [
          Text(v, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold)),
          Text(l, style: const TextStyle(fontSize: 12)),
        ]),
      ),
    );

Widget page(Widget child) => Align(
      alignment: Alignment.topCenter,
      child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 560), child: child),
    );

const Color kOk = Color(0xFF16A34A);
const Color kWarn = Color(0xFFD97706);
const Color kBad = Color(0xFFDC2626);

// ---------------------------------------------------------------- root + auth
class Root extends StatefulWidget {
  const Root({super.key});
  @override
  State<Root> createState() => _RootState();
}

class _RootState extends State<Root> {
  Store? store;
  Account? me;

  @override
  void initState() {
    super.initState();
    Store.load().then((s) {
      final r = s.accounts.where((a) => '${a.id}:${a.hash.substring(0, 16)}' == s.remember).toList();
      setState(() {
        store = s;
        me = r.isEmpty ? null : r.first;
      });
    });
  }

  void _logout() {
    store!.remember = '';
    store!.save();
    setState(() => me = null);
  }

  @override
  Widget build(BuildContext context) {
    if (store == null) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    if (me == null) {
      return AuthScreen(
        store: store!,
        onDone: (a, keep) {
          store!.remember = keep ? '${a.id}:${a.hash.substring(0, 16)}' : '';
          store!.save();
          setState(() => me = a);
        },
      );
    }
    return me!.isTeacher
        ? TeacherHome(store: store!, me: me!, onLogout: _logout)
        : StudentHome(store: store!, me: me!, onLogout: _logout);
  }
}

class AuthScreen extends StatefulWidget {
  final Store store;
  final void Function(Account, bool) onDone;
  const AuthScreen({super.key, required this.store, required this.onDone});
  @override
  State<AuthScreen> createState() => _AuthScreenState();
}

class _AuthScreenState extends State<AuthScreen> {
  late bool registering = widget.store.accounts.isEmpty;
  String role = 'teacher';
  bool keep = false, busy = false;
  String err = '';
  int fails = 0, lockUntil = 0;
  final nameC = TextEditingController(), userC = TextEditingController(), passC = TextEditingController(), pass2C = TextEditingController();

  Future<void> _register() async {
    final name = nameC.text.trim(), un = userC.text.trim().toLowerCase(), pw = passC.text;
    if (name.length < 2) return setState(() => err = 'Enter your full name.');
    if (!RegExp(r'^[a-z0-9_.]{3,20}$').hasMatch(un)) return setState(() => err = 'Username: 3 to 20 letters, numbers, dot or underscore.');
    if (widget.store.accounts.any((a) => a.username == un)) return setState(() => err = 'That username is taken on this device.');
    if (pw.length < 6) return setState(() => err = 'Password must be at least 6 characters.');
    if (pw != pass2C.text) return setState(() => err = 'Passwords do not match.');
    setState(() {
      busy = true;
      err = '';
    });
    final salt = randHex(16);
    final h = await hashAsync(pw, salt, kPbkdf2Iters);
    if (!mounted) return;
    final a = Account(id: randHex(6), role: role, name: name, username: un, salt: salt, hash: h, iters: kPbkdf2Iters);
    widget.store.accounts.add(a);
    await widget.store.save();
    widget.onDone(a, false);
  }

  Future<void> _login() async {
    if (nowMs() < lockUntil) return setState(() => err = 'Too many tries. Wait ${((lockUntil - nowMs()) / 1000).ceil()}s.');
    final un = userC.text.trim().toLowerCase(), pw = passC.text;
    if (un.isEmpty || pw.isEmpty) return setState(() => err = 'Enter your username and password.');
    final found = widget.store.accounts.where((a) => a.username == un).toList();
    if (found.isEmpty) return setState(() => err = 'Wrong username or password.');
    final a = found.first;
    final salt = a.salt, iters = a.iters;
    setState(() {
      busy = true;
      err = '';
    });
    final h = await hashAsync(pw, salt, iters);
    if (!mounted) return;
    if (h == a.hash) {
      widget.onDone(a, keep);
      return;
    }
    fails++;
    setState(() {
      busy = false;
      if (fails >= 5) {
        lockUntil = nowMs() + 30000;
        fails = 0;
        err = 'Too many tries. Locked for 30s.';
      } else {
        err = 'Wrong username or password.';
      }
    });
  }

  Future<void> _forgot() async {
    final un = userC.text.trim().toLowerCase();
    final found = widget.store.accounts.where((a) => a.username == un).toList();
    if (found.isEmpty) return setState(() => err = 'Type your username above first.');
    final ok = await confirmDlg(context, 'Delete the account "$un" and everything saved in it (students, history, pass)? This cannot be undone.', yes: 'Delete');
    if (!ok) return;
    widget.store.accounts.remove(found.first);
    await widget.store.save();
    setState(() {
      registering = widget.store.accounts.isEmpty;
      err = '';
    });
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(16),
          child: page(Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            const SizedBox(height: 24),
            const Text('📋 QR Attendance', style: TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            Card(
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  Text(registering ? 'Create account' : 'Log in', style: Theme.of(context).textTheme.titleLarge),
                  const SizedBox(height: 12),
                  if (registering) ...[
                    SegmentedButton<String>(
                      segments: const [
                        ButtonSegment(value: 'teacher', label: Text('Teacher')),
                        ButtonSegment(value: 'student', label: Text('Student')),
                      ],
                      selected: {role},
                      onSelectionChanged: (s) => setState(() => role = s.first),
                    ),
                    const SizedBox(height: 12),
                    TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Full name', border: OutlineInputBorder())),
                    const SizedBox(height: 10),
                  ],
                  TextField(controller: userC, autocorrect: false, decoration: InputDecoration(labelText: registering ? 'Username (letters, numbers, . _)' : 'Username', border: const OutlineInputBorder())),
                  const SizedBox(height: 10),
                  TextField(controller: passC, obscureText: true, decoration: InputDecoration(labelText: registering ? 'Password (6+ characters)' : 'Password', border: const OutlineInputBorder())),
                  if (registering) ...[
                    const SizedBox(height: 10),
                    TextField(controller: pass2C, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm password', border: OutlineInputBorder())),
                  ],
                  if (!registering) CheckboxListTile(contentPadding: EdgeInsets.zero, value: keep, onChanged: (v) => setState(() => keep = v ?? false), title: const Text('Keep me logged in on this device', style: TextStyle(fontSize: 13))),
                  const SizedBox(height: 8),
                  FilledButton(onPressed: busy ? null : (registering ? _register : _login), child: Text(busy ? 'Please wait…' : (registering ? 'Register' : 'Log in'))),
                  if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: kBad))),
                  Row(children: [
                    TextButton(onPressed: () => setState(() => registering = !registering), child: Text(registering ? (widget.store.accounts.isEmpty ? '' : 'I already have an account') : 'Create a new account')),
                    if (!registering) TextButton(onPressed: _forgot, child: const Text('Forgot password?')),
                  ]),
                ]),
              ),
            ),
          ])),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- teacher
class TeacherHome extends StatefulWidget {
  final Store store;
  final Account me;
  final VoidCallback onLogout;
  const TeacherHome({super.key, required this.store, required this.me, required this.onLogout});
  @override
  State<TeacherHome> createState() => _TeacherHomeState();
}

class _TeacherHomeState extends State<TeacherHome> {
  int tab = 0;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (closeExpired(widget.me)) widget.store.save();
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    timer?.cancel();
    super.dispose();
  }

  Future<void> save() => widget.store.save();
  void changed() => setState(() {});

  @override
  Widget build(BuildContext context) {
    final tabs = <Widget>[
      ClassTab(me: widget.me, save: save, onChanged: changed),
      ScanTab(me: widget.me, save: save, onChanged: changed),
      StudentsTab(me: widget.me, save: save, onChanged: changed),
      HistoryTab(me: widget.me),
    ];
    return Scaffold(
      appBar: AppBar(
        title: Text('Teacher · ${widget.me.name}', style: const TextStyle(fontSize: 16)),
        actions: [TextButton(onPressed: widget.onLogout, child: const Text('Log out'))],
      ),
      body: SafeArea(child: page(tabs[tab])),
      bottomNavigationBar: NavigationBar(
        selectedIndex: tab,
        onDestinationSelected: (i) => setState(() => tab = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.play_circle_outline), label: 'Class'),
          NavigationDestination(icon: Icon(Icons.qr_code_scanner), label: 'Scan'),
          NavigationDestination(icon: Icon(Icons.groups_outlined), label: 'Students'),
          NavigationDestination(icon: Icon(Icons.history), label: 'History'),
        ],
      ),
    );
  }
}

class ClassTab extends StatefulWidget {
  final Account me;
  final Future<void> Function() save;
  final VoidCallback onChanged;
  const ClassTab({super.key, required this.me, required this.save, required this.onChanged});
  @override
  State<ClassTab> createState() => _ClassTabState();
}

class _ClassTabState extends State<ClassTab> {
  final nameC = TextEditingController();
  final minC = TextEditingController(text: '10');
  final Set<String> off = {};

  @override
  void dispose() {
    nameC.dispose();
    minC.dispose();
    super.dispose();
  }

  Future<void> _start() async {
    final me = widget.me;
    if (me.roster.isEmpty) return snack(context, 'Add your students first (Students tab).');
    final chosen = me.roster.where((s) => !off.contains(s.id)).toList();
    if (chosen.isEmpty) return snack(context, 'Pick at least one student for this session.');
    final min = (int.tryParse(minC.text.trim()) ?? 10).clamp(1, 600).toInt();
    var code = newSessionCode();
    while (me.sessions.any((s) => s.code == code)) {
      code = newSessionCode();
    }
    final now = nowMs();
    me.sessions.insert(
      0,
      Session(
        id: now.toRadixString(36) + randHex(2),
        code: code,
        name: nameC.text.trim().isEmpty ? 'Class ${fmtDate(now)}' : nameC.text.trim(),
        minutes: min,
        startedAt: now,
        deadlineAt: now + min * 60000,
        roster: chosen.map((s) => Student(s.id, s.name, '', s.parentEmail)).toList(),
      ),
    );
    nameC.clear();
    await widget.save();
    widget.onChanged();
  }

  Widget _sessionCard(Session s, bool solo) {
    final open = s.isOpen;
    final cs = Theme.of(context).colorScheme;
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Expanded(child: Text(s.name, style: Theme.of(context).textTheme.titleMedium)),
            Pill(open ? 'OPEN' : 'CLOSED', open ? kWarn : Colors.grey),
          ]),
          if (open) ...[
            const SizedBox(height: 8),
            const Text('Session code. Tell students to enter it.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12)),
            Text(s.code, textAlign: TextAlign.center, style: TextStyle(fontSize: 34, fontWeight: FontWeight.w800, letterSpacing: 6, color: cs.primary)),
          ],
          Text(open ? mmss(s.deadlineAt - nowMs()) : '0:00', textAlign: TextAlign.center, style: const TextStyle(fontSize: 34, fontWeight: FontWeight.w800)),
          Text(open ? 'left to get scanned' : 'time is up', textAlign: TextAlign.center, style: const TextStyle(fontSize: 12)),
          const SizedBox(height: 10),
          Row(children: [stat('${s.presentCount}', 'Present'), stat('${s.restCount}', open ? 'Waiting' : 'Absent'), stat('${s.roster.length}', 'Total')]),
          Padding(
            padding: const EdgeInsets.only(top: 8),
            child: OutlinedButton.icon(
              onPressed: () => showEmailParents(context, widget.me, s),
              icon: const Icon(Icons.email_outlined),
              label: const Text('Email parents'),
            ),
          ),
          if (open)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: OutlinedButton(
                style: OutlinedButton.styleFrom(foregroundColor: kBad),
                onPressed: () async {
                  if (await confirmDlg(context, 'Close "${s.name}" now? Everyone not scanned becomes absent.', yes: 'Close')) {
                    s.status = 'closed';
                    s.closedAt = nowMs();
                    await widget.save();
                    widget.onChanged();
                  }
                },
                child: const Text('Close now (mark the rest absent)'),
              ),
            ),
          ExpansionTile(
            initiallyExpanded: solo,
            tilePadding: EdgeInsets.zero,
            title: Text('Students (${s.roster.length})', style: const TextStyle(fontSize: 14)),
            children: s.roster.map((r) {
              final p = s.present[r.id];
              return ListTile(
                dense: true,
                contentPadding: EdgeInsets.zero,
                title: Text(r.name),
                trailing: p != null
                    ? Pill('present ${fmtTime(p.t)}${p.m == 'manual' ? ' (manual)' : ''}', kOk)
                    : (open
                        ? Row(mainAxisSize: MainAxisSize.min, children: [
                            const Pill('waiting', kWarn),
                            TextButton(
                              onPressed: () async {
                                s.present[r.id] = Present(nowMs(), 'manual');
                                await widget.save();
                                widget.onChanged();
                              },
                              child: const Text('Mark ✓'),
                            ),
                          ])
                        : const Pill('absent', kBad)),
              );
            }).toList(),
          ),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    var list = me.openSessions;
    if (list.isEmpty && me.sessions.isNotEmpty) list = [me.sessions.first];
    final n = me.roster.where((s) => !off.contains(s.id)).length;
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Start a class', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(controller: nameC, decoration: const InputDecoration(labelText: 'Class / session name', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            Row(children: [
              Expanded(child: TextField(controller: minC, keyboardType: TextInputType.number, decoration: const InputDecoration(labelText: 'Minutes to get scanned', border: OutlineInputBorder()))),
              const SizedBox(width: 10),
              FilledButton(onPressed: _start, child: const Text('Start')),
            ]),
            ExpansionTile(
              tilePadding: EdgeInsets.zero,
              title: Text('Students in this session: ${n == me.roster.length ? 'all ($n)' : '$n of ${me.roster.length}'}', style: const TextStyle(fontSize: 14)),
              children: [
                Row(children: [
                  TextButton(onPressed: () => setState(off.clear), child: const Text('Select all')),
                  TextButton(onPressed: () => setState(() => off.addAll(me.roster.map((s) => s.id))), child: const Text('Select none')),
                ]),
                ...me.roster.map((s) => CheckboxListTile(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(s.name),
                      value: !off.contains(s.id),
                      onChanged: (v) => setState(() => v == true ? off.remove(s.id) : off.add(s.id)),
                    )),
              ],
            ),
            const Text('Run as many sessions as you like, even at the same time. Each gets its own code. Anyone not scanned when time runs out is marked absent.', style: TextStyle(fontSize: 12)),
          ]),
        ),
      ),
      ...list.map((s) => _sessionCard(s, list.length == 1)),
    ]);
  }
}

class ScanTab extends StatefulWidget {
  final Account me;
  final Future<void> Function() save;
  final VoidCallback onChanged;
  const ScanTab({super.key, required this.me, required this.save, required this.onChanged});
  @override
  State<ScanTab> createState() => _ScanTabState();
}

class _ScanTabState extends State<ScanTab> {
  MobileScannerController? ctrl;
  bool camOn = false;
  String lastCode = '';
  int lastAt = 0;
  ScanResult? res;
  final manual = TextEditingController();

  @override
  void dispose() {
    ctrl?.dispose();
    manual.dispose();
    super.dispose();
  }

  Future<void> _apply(String raw) async {
    final r = handleScan(widget.me, raw);
    if (r.kind == 'ok') {
      HapticFeedback.mediumImpact();
      await widget.save();
      widget.onChanged();
    } else {
      HapticFeedback.heavyImpact();
    }
    if (mounted) setState(() => res = r);
  }

  void _onDetect(BarcodeCapture cap) {
    for (final b in cap.barcodes) {
      final v = b.rawValue;
      if (v == null) continue;
      final now = nowMs();
      if (v != lastCode || now - lastAt > 2500) {
        lastCode = v;
        lastAt = now;
        _apply(v);
      }
    }
  }

  void _toggle() {
    if (camOn) {
      final old = ctrl;
      setState(() {
        camOn = false;
        ctrl = null;
      });
      WidgetsBinding.instance.addPostFrameCallback((_) => old?.dispose());
    } else {
      ctrl = MobileScannerController(facing: CameraFacing.back, formats: const [BarcodeFormat.qrCode]);
      setState(() => camOn = true);
    }
  }

  @override
  Widget build(BuildContext context) {
    final open = widget.me.openSessions;
    final status = open.isEmpty
        ? 'No class is open. Start one in the Class tab.'
        : 'Listening for ${open.length} open session${open.length > 1 ? 's' : ''}: ${open.map((s) => '${s.name} (${mmss(s.deadlineAt - nowMs())})').join(' · ')}';
    final r = res;
    final rc = r == null ? Colors.grey : (r.kind == 'ok' ? kOk : (r.kind == 'warn' ? kWarn : kBad));
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text(status, style: const TextStyle(fontSize: 13)),
            const SizedBox(height: 10),
            ClipRRect(
              borderRadius: BorderRadius.circular(12),
              child: SizedBox(
                height: 300,
                child: camOn && ctrl != null
                    ? MobileScanner(
                        controller: ctrl!,
                        onDetect: _onDetect,
                        errorBuilder: (context, error, child) => const Center(child: Text('Camera error. Check camera permission.', style: TextStyle(color: Colors.white))),
                      )
                    : Container(color: Colors.black, alignment: Alignment.center, child: const Text('Camera is off', style: TextStyle(color: Colors.grey))),
              ),
            ),
            const SizedBox(height: 10),
            FilledButton(onPressed: _toggle, child: Text(camOn ? 'Stop camera' : 'Start camera')),
            if (r != null)
              Container(
                margin: const EdgeInsets.only(top: 10),
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(color: rc.withAlpha(40), borderRadius: BorderRadius.circular(10)),
                child: Text('${r.kind == 'ok' ? '✔' : (r.kind == 'warn' ? '⚠' : '✖')} ${r.msg}', style: TextStyle(color: rc, fontWeight: FontWeight.w600)),
              ),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Row(children: [
            Expanded(child: TextField(controller: manual, decoration: const InputDecoration(labelText: "Camera blocked? Paste the student's QR text", border: OutlineInputBorder()))),
            const SizedBox(width: 8),
            FilledButton(
              onPressed: () {
                _apply(manual.text);
                manual.clear();
              },
              child: const Text('Check in'),
            ),
          ]),
        ),
      ),
    ]);
  }
}

class StudentsTab extends StatefulWidget {
  final Account me;
  final Future<void> Function() save;
  final VoidCallback onChanged;
  const StudentsTab({super.key, required this.me, required this.save, required this.onChanged});
  @override
  State<StudentsTab> createState() => _StudentsTabState();
}

class _StudentsTabState extends State<StudentsTab> {
  final countC = TextEditingController();
  late List<TextEditingController> names;
  late List<TextEditingController> emails;
  String msg = '';

  @override
  void initState() {
    super.initState();
    names = widget.me.roster.map((s) => TextEditingController(text: s.name)).toList();
    emails = widget.me.roster.map((s) => TextEditingController(text: s.parentEmail)).toList();
    countC.text = names.isEmpty ? '' : '${names.length}';
  }

  @override
  void dispose() {
    countC.dispose();
    for (final c in names) {
      c.dispose();
    }
    for (final c in emails) {
      c.dispose();
    }
    super.dispose();
  }

  void _resize(String v) {
    final n = (int.tryParse(v) ?? 0).clamp(0, 200).toInt();
    setState(() {
      while (names.length < n) {
        names.add(TextEditingController());
        emails.add(TextEditingController());
      }
      while (names.length > n) {
        names.removeLast().dispose();
        emails.removeLast().dispose();
      }
    });
  }

  Future<void> _saveRoster() async {
    if (names.isEmpty) return setState(() => msg = 'Enter how many students first.');
    final list = <Student>[];
    for (var i = 0; i < names.length; i++) {
      final nm = names[i].text.trim();
      if (nm.isEmpty) return setState(() => msg = 'Student ${i + 1} has no name.');
      final em = emails[i].text.trim();
      if (em.isNotEmpty && !looksLikeEmail(em)) return setState(() => msg = 'Student ${i + 1}: that parent email does not look right.');
      final old = i < widget.me.roster.length ? widget.me.roster[i] : null;
      list.add(Student(old?.id ?? 's${randHex(3)}', nm, old?.secret ?? randHex(16), em));
    }
    widget.me.roster = list;
    await widget.save();
    widget.onChanged();
    setState(() => msg = 'Saved ${list.length} students.');
  }

  void _showPass(Student s) {
    final pass = makePass(s.id, s.name, s.secret);
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(s.name),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Send this to the student privately. They paste it in their Student account.', style: TextStyle(fontSize: 13)),
          const SizedBox(height: 8),
          SelectableText(pass, style: const TextStyle(fontFamily: 'monospace', fontSize: 11)),
        ]),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: pass));
              snack(context, 'Copied');
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  void _testQr(Student s) {
    final cands = widget.me.openSessions.where((x) => x.roster.any((r) => r.id == s.id)).toList();
    if (cands.isEmpty) return snack(context, 'Start a session that includes ${s.name} first. Each session has its own QR.');
    var pick = cands.first;
    showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text('${s.name} (test view)'),
          content: Column(mainAxisSize: MainAxisSize.min, children: [
            if (cands.length > 1)
              DropdownButton<Session>(
                value: pick,
                isExpanded: true,
                items: cands.map((c) => DropdownMenuItem(value: c, child: Text('${c.name} (${c.code})'))).toList(),
                onChanged: (v) => setD(() => pick = v ?? pick),
              ),
            QrImageView(data: qrText(s.id, s.secret, pick.code), size: 240, backgroundColor: Colors.white, padding: const EdgeInsets.all(12)),
            Text('Same QR the student gets for session ${pick.code}.', style: const TextStyle(fontSize: 12)),
          ]),
          actions: [TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close'))],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return ListView(padding: const EdgeInsets.all(12), children: [
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Student list', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(controller: countC, keyboardType: TextInputType.number, onChanged: _resize, decoration: const InputDecoration(labelText: 'How many students?', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            for (var i = 0; i < names.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: Column(children: [
                  TextField(controller: names[i], decoration: InputDecoration(labelText: 'Student ${i + 1} name', border: const OutlineInputBorder())),
                  const SizedBox(height: 6),
                  TextField(controller: emails[i], keyboardType: TextInputType.emailAddress, autocorrect: false, decoration: const InputDecoration(labelText: 'Parent email (optional)', border: OutlineInputBorder())),
                ]),
              ),
            FilledButton(onPressed: _saveRoster, child: const Text('Save student list')),
            if (msg.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(msg)),
          ]),
        ),
      ),
      Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('QR passes', style: Theme.of(context).textTheme.titleMedium),
            const Text('Each student gets a personal pass. They paste it once in their Student account to unlock their QR.', style: TextStyle(fontSize: 12)),
            if (widget.me.roster.isEmpty) const Padding(padding: EdgeInsets.only(top: 8), child: Text('Add your students above first.')),
            ...widget.me.roster.map((s) => ListTile(
                  contentPadding: EdgeInsets.zero,
                  title: Text(s.name),
                  trailing: Row(mainAxisSize: MainAxisSize.min, children: [
                    TextButton(onPressed: () => _showPass(s), child: const Text('Get pass')),
                    TextButton(onPressed: () => _testQr(s), child: const Text('Test QR')),
                  ]),
                )),
          ]),
        ),
      ),
    ]);
  }
}

class HistoryTab extends StatelessWidget {
  final Account me;
  const HistoryTab({super.key, required this.me});

  void _csv(BuildContext context, Session s) {
    final done = s.isDone;
    final rows = <String>['Name,Status,Time'];
    for (final r in s.roster) {
      final p = s.present[r.id];
      rows.add('"${r.name.replaceAll('"', '""')}",${p != null ? 'present' : (done ? 'absent' : 'waiting')},${p != null ? fmtTime(p.t) : ''}');
    }
    final text = '${s.name} - ${fmtDate(s.startedAt)}\n${rows.join('\n')}';
    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('CSV'),
        content: SingleChildScrollView(child: SelectableText(text, style: const TextStyle(fontFamily: 'monospace', fontSize: 12))),
        actions: [
          TextButton(
            onPressed: () {
              Clipboard.setData(ClipboardData(text: text));
              snack(context, 'Copied');
            },
            child: const Text('Copy'),
          ),
          TextButton(onPressed: () => Navigator.pop(ctx), child: const Text('Close')),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (me.sessions.isEmpty) return const Padding(padding: EdgeInsets.all(16), child: Text('No classes yet.'));
    return ListView(
      padding: const EdgeInsets.all(12),
      children: me.sessions.map((s) {
        final done = s.isDone;
        return Card(
          child: Column(children: [
            ListTile(
              title: Text(s.name),
              subtitle: Text('${fmtDate(s.startedAt)} · ${fmtTime(s.startedAt)} · ${s.minutes} min\n${s.presentCount} present · ${s.restCount} ${done ? 'absent' : 'waiting'}'),
              isThreeLine: true,
            ),
            Padding(
              padding: const EdgeInsets.only(right: 12, bottom: 8),
              child: Row(mainAxisAlignment: MainAxisAlignment.end, children: [
                OutlinedButton.icon(onPressed: () => showEmailParents(context, me, s), icon: const Icon(Icons.email_outlined), label: const Text('Email parents')),
                const SizedBox(width: 8),
                OutlinedButton(onPressed: () => _csv(context, s), child: const Text('CSV')),
              ]),
            ),
          ]),
        );
      }).toList(),
    );
  }
}

// ---------------------------------------------------------------- student
class StudentHome extends StatefulWidget {
  final Store store;
  final Account me;
  final VoidCallback onLogout;
  const StudentHome({super.key, required this.store, required this.me, required this.onLogout});
  @override
  State<StudentHome> createState() => _StudentHomeState();
}

class _StudentHomeState extends State<StudentHome> with WidgetsBindingObserver {
  final passC = TextEditingController(), codeC = TextEditingController();
  String err = '';
  bool reveal = false;
  Timer? timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    timer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    timer?.cancel();
    passC.dispose();
    codeC.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed && reveal) setState(() => reveal = false);
  }

  Future<void> _savePass() async {
    final o = parsePass(passC.text);
    if (o == null) return setState(() => err = 'That pass looks invalid. Copy the whole thing from your teacher.');
    widget.me.passR = o['r'] as String;
    widget.me.passN = (o['n'] ?? '') as String;
    widget.me.passS = o['s'] as String;
    await widget.store.save();
    passC.clear();
    setState(() => err = '');
  }

  Future<void> _saveCode() async {
    final c = cleanCode(codeC.text);
    if (c.length != 6) return setState(() => err = 'The code is 6 characters.');
    widget.me.code = c;
    await widget.store.save();
    codeC.clear();
    setState(() => err = '');
  }

  @override
  Widget build(BuildContext context) {
    final me = widget.me;
    final hasPass = me.passR != null && me.passS != null;
    final children = <Widget>[];
    if (!hasPass) {
      children.add(Card(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Unlock your QR', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 10),
            TextField(controller: passC, maxLines: 4, decoration: const InputDecoration(labelText: 'Paste the pass your teacher sent you', border: OutlineInputBorder())),
            const SizedBox(height: 10),
            FilledButton(onPressed: _savePass, child: const Text('Save pass')),
            if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: kBad))),
            const Padding(padding: EdgeInsets.only(top: 8), child: Text('Treat your pass like a password. Sharing it lets someone else check in as you.', style: TextStyle(fontSize: 12))),
          ]),
        ),
      ));
    } else {
      children.add(Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(children: [const Text('Signed in as', style: TextStyle(fontSize: 12)), Text(me.passN ?? '', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.bold))]))));
      if (me.code == null) {
        children.add(Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Text('Enter the session code', style: Theme.of(context).textTheme.titleMedium),
              const Text('Your teacher shows a 6-character code at the start of every class.', style: TextStyle(fontSize: 12)),
              const SizedBox(height: 10),
              TextField(controller: codeC, textCapitalization: TextCapitalization.characters, maxLength: 6, textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, letterSpacing: 4), decoration: const InputDecoration(hintText: 'K7M2XP', border: OutlineInputBorder())),
              FilledButton(onPressed: _saveCode, child: const Text('Show my QR')),
              if (err.isNotEmpty) Padding(padding: const EdgeInsets.only(top: 8), child: Text(err, style: const TextStyle(color: kBad))),
            ]),
          ),
        ));
      } else {
        final qr = QrImageView(data: qrText(me.passR!, me.passS!, me.code!), size: 260, backgroundColor: Colors.white, padding: const EdgeInsets.all(12));
        children.add(Card(
          child: Padding(
            padding: const EdgeInsets.all(14),
            child: Column(children: [
              Text('Session ${me.code}', style: const TextStyle(fontWeight: FontWeight.bold, letterSpacing: 3)),
              const SizedBox(height: 10),
              // Hold your finger on the code to show it. Let go (or leave the app) and it blurs again.
              Listener(
                onPointerDown: (_) => setState(() => reveal = true),
                onPointerUp: (_) => setState(() => reveal = false),
                onPointerCancel: (_) => setState(() => reveal = false),
                child: Stack(alignment: Alignment.center, children: [
                  reveal ? qr : ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 18, sigmaY: 18), child: qr),
                  if (!reveal) const Padding(padding: EdgeInsets.all(24), child: Text('Press and hold here to show your QR', textAlign: TextAlign.center, style: TextStyle(fontWeight: FontWeight.bold, color: Colors.black))),
                ]),
              ),
              const SizedBox(height: 8),
              Text('${me.passN ?? ''} · ${DateTime.now().toString().substring(11, 19)}', style: const TextStyle(fontWeight: FontWeight.w600)),
              const Padding(padding: EdgeInsets.only(top: 6), child: Text('Hold your finger on the code while your teacher scans it. It hides itself when you let go or leave this screen. It only works for this session.', textAlign: TextAlign.center, style: TextStyle(fontSize: 12))),
              TextButton(
                onPressed: () async {
                  me.code = null;
                  await widget.store.save();
                  setState(() {});
                },
                child: const Text('New class? Enter a new code'),
              ),
            ]),
          ),
        ));
      }
      children.add(Center(
        child: TextButton(
          style: TextButton.styleFrom(foregroundColor: kBad),
          onPressed: () async {
            if (await confirmDlg(context, 'Remove your pass from this device?', yes: 'Remove')) {
              me.passR = null;
              me.passN = null;
              me.passS = null;
              me.code = null;
              await widget.store.save();
              setState(() {});
            }
          },
          child: const Text('Remove my pass'),
        ),
      ));
    }
    return Scaffold(
      appBar: AppBar(
        title: Text('Student · ${me.name}', style: const TextStyle(fontSize: 16)),
        actions: [TextButton(onPressed: widget.onLogout, child: const Text('Log out'))],
      ),
      body: SafeArea(child: page(ListView(padding: const EdgeInsets.all(12), children: children))),
    );
  }
}
