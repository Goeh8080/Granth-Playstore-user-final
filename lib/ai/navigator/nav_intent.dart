/// t304 Navigator voice — pure text → one allow-listed target (Dart port of Tatv's
/// `navigator.mjs` rules, extended with the app's real routes and catalog names).
///
/// - The wake phrase (Hey Granth / Hey Tatv / हे ग्रंथ / हे तत्व / तत्व) is stripped only as a
///   complete phrase at the very start.
/// - URLs, route strings and unsafe verbs → unknown (never navigates).
/// - Targets are built ONLY from the app's own structure, catalog and page list; every
///   target carries the internal hashes to open STEP BY STEP (folder → sub-folder → granth).
///   Interpreter text is never dispatched as a link.
/// - Hindi / Hinglish names match through a small romanizer + fuzzy (edit-distance) score.
library;

import 'dart:math' as math;

import '../../models/models.dart';
import '../../models/structure.dart';
import '../../state/router.dart';

class NavTarget {
  const NavTarget({required this.id, required this.kind, required this.label, required this.names, required this.steps});
  final String id;

  /// `page` | `religion` | `group` | `sub` | `granth` | `topic`.
  final String kind;
  final String label;
  final List<String> names;

  /// Internal hashes, opened one after another (the last one is the destination).
  final List<String> steps;
}

sealed class NavResult {
  const NavResult();
}

class NavIntent extends NavResult {
  const NavIntent(this.target);
  final NavTarget target;
}

class NavClarify extends NavResult {
  const NavClarify(this.choices);
  final List<NavTarget> choices;
  String get prompt => 'कौन-सा खोलूँ?';
}

class NavUnknown extends NavResult {
  const NavUnknown([this.reason = 'unknown']);
  final String reason;
}

/// Extra spoken names for structure ids (Tatv adapter aliases + common Hinglish).
const Map<String, List<String>> kNavAliases = {
  'hindu': ['hindu', 'हिंदू', 'हिन्दू', 'sanatan', 'सनातन'],
  'ved': ['ved', 'veda', 'vedas', 'वेद', 'ved granth'],
  'puran': ['puran', 'purana', 'puranas', 'पुराण', 'puraan'],
  'rigved': ['rigved', 'rigveda', 'rig ved', 'ऋग्वेद', 'rugved'],
  'yajurved': ['yajurved', 'yajurveda', 'yajur ved', 'यजुर्वेद'],
  'samved': ['samved', 'samveda', 'sam ved', 'सामवेद'],
  'atharvved': ['atharvved', 'atharvaved', 'atharvaveda', 'atharv ved', 'अथर्ववेद'],
  'sukshmved': ['sukshmved', 'sukshma ved', 'sukshm ved', 'सूक्ष्मवेद', 'सूक्ष्म वेद'],
  'gita': ['gita', 'geeta', 'bhagavad gita', 'गीता'],
  'islam': ['islam', 'muslim', 'इस्लाम'],
  'sikh': ['sikh', 'सिख'],
  'isai': ['isai', 'christian', 'ईसाई'],
  'kabir': ['kabir', 'कबीर'],
};

const _wake = r'^(?:(?:hey|hay|hai|he|hi|हे|है|हाय)\s*(?:granth|grant|granth ji|ग्रंथ|ग्रन्थ|tatv|tatva|tattva|tatwa|tatvaa|तत्व|तत्त्व)|तत्व|तत्त्व|tatv|tatva|tattva|tatwa)(?=$|[\s,:!।.?])[\s,:!।.?]*';
final _wakeRe = RegExp(_wake, unicode: true, caseSensitive: false);
final _unsafe = RegExp(r'https?:|www\.|[/#=&<>]|\?\S|javascript:|\b(?:delete|send|pay|install|execute|admin|openlink|ignore|override)\b|हटाओ|भेजो|भुगतान', unicode: true, caseSensitive: false);
final _openWords = RegExp(r'^(?:open|kholo|khol|खोलो|खोल|खोलिए|dikhao|दिखाओ|chalo|चलो|jao|जाओ)\s+|\s+(?:ko\s+|को\s+)?(?:khol|kholo|kholiye|khol do|open|खोल|खोलो|खोलिए|खोल दो|dikhao|दिखाओ|dikha do|par jao|pe jao|पर जाओ|पे जाओ|me jao|में जाओ|chalo|चलो)(?:\s+do|\s+दो)?$', unicode: true, caseSensitive: false);

// ---- Fuzzy wake phrase (noisy rooms, accents, recognizer slips) -----------------------------

/// Greeting part of a wake phrase, as [navKey] keys ("hey" → hei, "हे" → he, "hai", "ae" …).
const _wakeGreet = {'he', 'hei', 'hai', 'hi', 'hae', 'ae', 'ai', 'e', 'a', 'hallo', 'halo', 'helo', 'ok', 'okei'};

/// Name part, as keys ("granth"/"ग्रंथ"/"ग्रन्थ" → grant, "tatv"/"tatva"/"तत्व" → tatv).
const _wakeName = ['grant', 'tatv'];

bool _nameLike(String k) => k.length >= 3 && _wakeName.any((n) => k == n || NavCatalog._lev(k, n) <= 1);

/// What follows a wake phrase in [text]: null = no wake phrase; '' = the wake phrase alone.
/// Exact phrases first ([hasWakePhrase]); then a fuzzy match on the first words, e.g.
/// "hey grand", "he granth", "हे ग्रन्थ", "a granth", "hey tatwa", "heygranth", "ok tatv".
/// "granth kholo" (no greeting) is a command, never a wake phrase.
String? matchWake(String text) {
  final t = text.trim().toLowerCase();
  if (t.isEmpty) return null;
  if (hasWakePhrase(t)) return stripWake(t).replaceFirst(RegExp(r'^(?:ji|जी)(?:\s+|$)', unicode: true), '').trim();
  final words = t.split(RegExp(r'[\s,:!।.?]+')).where((w) => w.isNotEmpty).toList();
  if (words.isEmpty) return null;
  String rest(int n) => words.skip(n).join(' ');
  final k0 = navKey(words[0]);
  if (words.length >= 2 && _wakeGreet.contains(k0) && _nameLike(navKey(words[1]))) {
    // "hey granth ji …"
    final n = words.length >= 3 && (words[2] == 'ji' || words[2] == 'जी') ? 3 : 2;
    return rest(n);
  }
  // Run together: "heygranth", "हेग्रंथ".
  for (final g in _wakeGreet) {
    if (g.length >= 2 && k0.startsWith(g) && _nameLike(k0.substring(g.length))) return rest(1);
  }
  return null;
}

/// The first recognizer alternate that carries a wake phrase, and every alternate's command
/// part (wake phrase removed, empty ones dropped). Null when none has a wake phrase.
({List<String> rest})? wakeAcross(List<String> alternates) {
  var found = false;
  final rest = <String>[];
  for (final a in alternates.take(10)) {
    final r = matchWake(a);
    if (r == null) continue;
    found = true;
    if (r.isNotEmpty && !rest.contains(r)) rest.add(r);
  }
  return found ? (rest: rest) : null;
}

/// Target id of the "change the voice" command.
const String kNavActionVoice = 'action:voice';

/// True when [text] begins with a complete wake phrase.
bool hasWakePhrase(String text) => _wakeRe.hasMatch(text.trim().toLowerCase());

/// [text] without the wake phrase at the start (unchanged otherwise; never inside a word).
String stripWake(String text) => text.trim().toLowerCase().replaceFirst(_wakeRe, '').trim();

class NavCatalog {
  NavCatalog(this.targets);
  final List<NavTarget> targets;

  /// Builds every target from trusted runtime state only.
  factory NavCatalog.build({required Structure structure, required List<Granth> granths, required List<Topic> topics, Map<String, Placement> placements = const {}}) {
    final out = <NavTarget>[];
    void page(String id, String label, List<String> names, String hash) => out.add(NavTarget(id: 'page:$id', kind: 'page', label: label, names: names, steps: [hash]));
    page('dashboard', 'डैशबोर्ड', ['dashboard', 'home', 'डैशबोर्ड', 'होम', 'मुख्य पेज'], '#/dashboard');
    page('folders', 'ग्रंथ (फ़ोल्डर)', ['granth', 'granths', 'ग्रंथ', 'ग्रन्थ', 'folder', 'folders', 'फ़ोल्डर', 'kitab', 'किताब'], '#/granths');
    page('all', 'सभी ग्रंथ', ['sabhi granth', 'sare granth', 'saare granth', 'all granth', 'सभी ग्रंथ', 'सारे ग्रंथ', 'granth list', 'ek suchi'], '#/granths?all=1');
    page('topics', 'विषय', ['topics', 'topic', 'vishay', 'विषय'], '#/topics');
    page('pramans', 'प्रमाण', ['praman', 'pramaan', 'pramans', 'प्रमाण'], '#/pramans');
    page('search', 'खोज', ['search', 'khoj', 'खोज', 'सर्च', 'dhundo', 'ढूंढो'], '#/pramans');
    page('today', 'आज का प्रमाण', ['aaj ka praman', 'aaj ka pramaan', 'aj ka praman', 'today', 'daily praman', 'आज का प्रमाण'], '#/today');
    page('gallery', 'गैलरी', ['gallery', 'गैलरी', 'downloads', 'डाउनलोड'], '#/gallery');
    page('ai', 'तत्त्व AI', ['ai', 'tatv ai', 'chat', 'चैट', 'tatv se pucho', 'gyan charcha', 'ज्ञान चर्चा'], '#/ai');
    page('settings', 'सेटिंग', ['settings', 'setting', 'सेटिंग', 'सेटिंग्स', 'सेटिंग्ज़'], '#/settings');
    page('account', 'अकाउंट', ['account', 'profile', 'अकाउंट', 'प्रोफाइल'], '#/account');
    // t352: "awaaz badlo" / "voice change" / "kaunsi awaaz" → the voice picker (no route).
    out.add(const NavTarget(id: kNavActionVoice, kind: 'action', label: 'आवाज़', steps: [], names: [
      'awaaz badlo', 'awaz badlo', 'aawaz badlo', 'awaaz badal do', 'awaz badal do', 'awaaz change', 'awaz change', 'voice change', 'change voice', 'change the voice',
      'voice badlo', 'kaunsi awaaz', 'konsi awaz', 'kaun si awaaz', 'kon si awaz', 'awaaz chuno', 'voice', 'awaaz', 'आवाज़ बदलो', 'आवाज बदलो', 'आवाज़ बदल दो', 'आवाज़ बदलें',
      'कौनसी आवाज़', 'कौन सी आवाज़', 'कौन-सी आवाज़', 'आवाज़ चुनो', 'आवाज़', 'आवाज', 'वॉइस चेंज',
    ]));
    page('support', 'सहायता', ['support', 'help', 'sahayata', 'सहायता', 'मदद', 'ticket', 'टिकट'], '#/support');
    for (final r in structure.religions) {
      if (!r.visible) continue;
      final rh = GRoute.folderHash(religion: r.id);
      out.add(NavTarget(id: 'r:${r.id}', kind: 'religion', label: r.title, names: [r.title, r.id, ...?kNavAliases[r.id]], steps: ['#/granths', rh]));
      for (final g in r.groups) {
        if (!g.visible) continue;
        final gh = GRoute.folderHash(religion: r.id, group: g.id);
        out.add(NavTarget(id: 'g:${r.id}/${g.id}', kind: 'group', label: g.title, names: [g.title, g.id, ...?kNavAliases[g.id]], steps: ['#/granths', rh, gh]));
        for (final s in g.subgroups) {
          if (!s.visible) continue;
          final sh = GRoute.folderHash(religion: r.id, group: g.id, sub: s.id);
          out.add(NavTarget(id: 's:${r.id}/${g.id}/${s.id}', kind: 'sub', label: s.title, names: [s.title, s.id, ...?kNavAliases[s.id]], steps: ['#/granths', rh, gh, sh]));
        }
      }
    }
    for (final g in granths) {
      if (g.id.isEmpty || g.title.trim().isEmpty) continue;
      final steps = <String>['#/granths'];
      final key = placements[g.id]?.key;
      if (key != null && key.isNotEmpty) {
        final p = key.split('/');
        steps.add(GRoute.folderHash(religion: p[0]));
        if (p.length > 1) steps.add(GRoute.folderHash(religion: p[0], group: p[1]));
        if (p.length > 2) steps.add(GRoute.folderHash(religion: p[0], group: p[1], sub: p[2]));
      }
      steps.add('#/pramans?granth=${g.id}'); // same hash the granth card opens
      out.add(NavTarget(id: 'granth:${g.id}', kind: 'granth', label: g.title, names: [g.title], steps: steps));
    }
    for (final t in topics) {
      if (t.id.isEmpty || t.title.trim().isEmpty) continue;
      out.add(NavTarget(id: 'topic:${t.id}', kind: 'topic', label: t.title, names: [t.title], steps: ['#/topics', '#/pramans?topic=${t.id}']));
    }
    return NavCatalog(out);
  }

  static const _kindRank = {'action': 0, 'page': 0, 'religion': 1, 'group': 1, 'sub': 1, 'topic': 2, 'granth': 3};

  /// Best meaning over several recognizer alternates (best first): the first clear intent wins,
  /// else the first clarification, else the first alternate's unknown. An unsafe reading met before any intent stops the
  /// search (it never navigates).
  NavResult interpretAll(List<String> alternates, {List<String>? pending}) {
    final alts = [for (final a in alternates.take(10)) if (a.trim().isNotEmpty) a];
    if (alts.isEmpty) return const NavUnknown('empty');
    NavResult? first, clarify;
    for (final a in alts) {
      final r = interpret(a, pending: pending);
      first ??= r;
      if (r is NavUnknown && r.reason == 'unsafe') return r;
      if (r is NavIntent) return r;
      if (r is NavClarify) clarify ??= r;
    }
    return clarify ?? first!;
  }

  /// One step of meaning for [text]: an intent, a short clarification, or unknown.
  NavResult interpret(String text, {List<String>? pending}) {
    if (text.length > 180) return const NavUnknown('too_long');
    var s = matchWake(text) ?? text.trim().toLowerCase();
    if (_unsafe.hasMatch(s)) return const NavUnknown('unsafe');
    s = s.replaceAll(RegExp(r'[,!।.?]+'), ' ').replaceAll(RegExp(r'\s+'), ' ').trim();
    for (var i = 0; i < 2; i++) {
      s = s.replaceFirst(_openWords, '').trim();
    }
    if (s.isEmpty) return const NavUnknown('empty');
    final pool = pending == null ? targets : targets.where((t) => pending.contains(t.id)).toList();
    final q = navKey(s);
    if (q.isEmpty) return const NavUnknown('empty');
    final scored = <(NavTarget, double)>[];
    for (final t in pool) {
      var best = 0.0;
      for (final n in t.names) {
        final k = navKey(n);
        if (k.isEmpty) continue;
        best = math.max(best, _score(q, k));
        if (best >= 1) break;
      }
      if (best >= 0.72) scored.add((t, best));
    }
    if (scored.isEmpty) return const NavUnknown();
    scored.sort((a, b) {
      final c = b.$2.compareTo(a.$2);
      return c != 0 ? c : (_kindRank[a.$1.kind] ?? 9).compareTo(_kindRank[b.$1.kind] ?? 9);
    });
    final top = scored.first;
    final close = scored.where((e) => e.$2 >= top.$2 - 0.04).toList();
    if (close.length == 1 || top.$2 >= 1 && scored.where((e) => e.$2 >= 1).length == 1) return NavIntent(top.$1);
    // Several equally good: a structure folder beats a same-named granth/topic (वेद folder).
    final ranks = close.map((e) => _kindRank[e.$1.kind] ?? 9).toList();
    final minRank = ranks.reduce(math.min);
    final atMin = close.where((e) => (_kindRank[e.$1.kind] ?? 9) == minRank).toList();
    if (atMin.length == 1 && minRank <= 1) return NavIntent(atMin.first.$1);
    return NavClarify(close.take(4).map((e) => e.$1).toList());
  }

  static double _score(String q, String k) {
    if (q == k) return 1;
    final qs = q.split(' '), ks = k.split(' ');
    // Whole-word containment ("gita" in "shrimad bhagvad gita").
    if (q.length >= 3 && (ks.contains(q) || (k.length >= 3 && qs.contains(k)))) return 0.9;
    if (q.length >= 5 && k.startsWith(q)) return 0.86;
    // One-word Devanagari titles ("श्रीमद्भगवद्गीता") vs spoken words ("bhagavad gita").
    final qj = q.replaceAll(' ', ''), kj = k.replaceAll(' ', '');
    if (qj.length >= 6 && kj.contains(qj)) return 0.85;
    final d = _lev(q, k);
    final sim = 1 - d / math.max(q.length, k.length);
    // Short words need to be nearly exact ("ved" vs "veda"). A one-letter slip is accepted
    // only when both are 4 letters: 3-letter keys are too close to each other
    // ("shiv"→siv ≠ sikh→sik, "anya"→ani ≠ ai).
    if (math.max(q.length, k.length) <= 4) return d <= 1 && q.length >= 4 && k.length >= 4 ? 0.8 : 0;
    return sim;
  }

  static int _lev(String a, String b) {
    if (a.isEmpty) return b.length;
    if (b.isEmpty) return a.length;
    var prev = List<int>.generate(b.length + 1, (i) => i);
    for (var i = 1; i <= a.length; i++) {
      final cur = List<int>.filled(b.length + 1, 0)..[0] = i;
      for (var j = 1; j <= b.length; j++) {
        final cost = a.codeUnitAt(i - 1) == b.codeUnitAt(j - 1) ? 0 : 1;
        cur[j] = math.min(math.min(cur[j - 1] + 1, prev[j] + 1), prev[j - 1] + cost);
      }
      prev = cur;
    }
    return prev[b.length];
  }
}

// ---- Hindi / Hinglish key -------------------------------------------------------------------

const _cons = {
  'क': 'k', 'ख': 'k', 'ग': 'g', 'घ': 'g', 'ङ': 'n', 'च': 'ch', 'छ': 'ch', 'ज': 'j', 'झ': 'j', 'ञ': 'n',
  'ट': 't', 'ठ': 't', 'ड': 'd', 'ढ': 'd', 'ण': 'n', 'त': 't', 'थ': 't', 'द': 'd', 'ध': 'd', 'न': 'n',
  'प': 'p', 'फ': 'f', 'ब': 'b', 'भ': 'b', 'म': 'm', 'य': 'y', 'र': 'r', 'ल': 'l', 'व': 'v', 'श': 's',
  'ष': 's', 'स': 's', 'ह': 'h', 'ळ': 'l', 'क़': 'k', 'ख़': 'k', 'ग़': 'g', 'ज़': 'j', 'ड़': 'r', 'ढ़': 'r', 'फ़': 'f',
};
const _vowels = {'अ': 'a', 'आ': 'a', 'इ': 'i', 'ई': 'i', 'उ': 'u', 'ऊ': 'u', 'ऋ': 'ri', 'ए': 'e', 'ऐ': 'e', 'ओ': 'o', 'औ': 'o'};
const _matras = {'ा': 'a', 'ि': 'i', 'ी': 'i', 'ु': 'u', 'ू': 'u', 'ृ': 'ri', 'े': 'e', 'ै': 'e', 'ो': 'o', 'ौ': 'o'};

/// Devanagari → rough Latin (inherent "a" dropped at word end, as people type Hinglish).
String romanize(String s) {
  final b = StringBuffer();
  final chars = s.replaceAll('\u093C', '').runes.map(String.fromCharCode).toList();
  for (var i = 0; i < chars.length; i++) {
    final c = chars[i];
    final next = i + 1 < chars.length ? chars[i + 1] : '';
    if (_cons.containsKey(c)) {
      b.write(_cons[c]);
      final endOfWord = next.isEmpty || next == ' ';
      if (!_matras.containsKey(next) && next != '्' && !endOfWord) b.write('a');
    } else if (_matras.containsKey(c)) {
      b.write(_matras[c]);
    } else if (_vowels.containsKey(c)) {
      b.write(_vowels[c]);
    } else if (c == 'ं' || c == 'ँ') {
      b.write('n');
    } else if (c == '्' || c == 'ः') {
      // virama / visarga: nothing
    } else {
      b.write(c);
    }
  }
  return b.toString();
}

/// Comparable key for a spoken or written name: romanized, lower-case, Hinglish spellings
/// folded (aa→a, ee→i, sh→s, th→t, w→v …), punctuation removed.
String navKey(String s) {
  var t = romanize(s.toLowerCase());
  t = t.replaceAll(RegExp(r'[^a-z0-9 ]'), ' ');
  const folds = [
    ('aa', 'a'), ('ee', 'i'), ('ii', 'i'), ('oo', 'u'), ('uu', 'u'), ('sh', 's'), ('kh', 'k'), ('gh', 'g'),
    ('chh', 'ch'), ('th', 't'), ('dh', 'd'), ('ph', 'f'), ('bh', 'b'), ('jh', 'j'), ('w', 'v'), ('z', 'j'),
    ('q', 'k'), ('x', 'ks'), ('y', 'i'), ('ri', 'r'), ('ru', 'r'),
  ];
  for (final (a, b) in folds) {
    t = t.replaceAll(a, b);
  }
  t = t.replaceAllMapped(RegExp(r'(.)\1+'), (m) => m[1]!);
  // Word-final short "a" is usually silent in speech ("veda" ≈ "ved", "gita" stays via exact name).
  t = t.split(RegExp(r'\s+')).where((w) => w.isNotEmpty).map((w) => w.length > 3 && w.endsWith('a') ? w.substring(0, w.length - 1) : w).join(' ');
  return t.trim();
}
