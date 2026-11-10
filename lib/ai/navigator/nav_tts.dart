/// t352 Navigator voice reply: short spoken confirmations ("वेद खोल रहा हूँ") in an
/// ElevenLabs voice. The app NEVER holds the ElevenLabs key: it asks the AI Worker
/// (`POST {aiEndpoint}/tts`, same base URL + `X-Granth-Client` header as `/ask`), which
/// returns `audio/mpeg`. Playback uses the WebView that already ships with the app
/// (`webview_flutter`), so no new native plugin is needed (Shorebird-patchable).
/// Any failure (offline, 404, timeout, no WebView) → silence; navigation never waits on it.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:webview_flutter/webview_flutter.dart';
import 'package:webview_flutter_android/webview_flutter_android.dart';

import '../../config.dart';
import '../../services/analytics.dart';
import '../../services/firebase_bridge.dart';
import '../../services/remote_config.dart';
import '../../services/storage.dart';

/// Worker routes for speech (relative to the TTS base). Overridable per client.
const String kTtsPath = '/tts';
const String kTtsVoicesPath = '/tts/voices';

/// Worker cap (w13 contract: 300 Unicode chars).
const int kTtsTextMax = 300;
const int kTtsAudioMax = 1024 * 1024;
const String kTtsUserAgent = 'GranthPrabandhan/1.0.0 (Android; Flutter)';

/// One HTTP reply — the transport seam tests replace.
typedef TtsReply = ({int status, String contentType, Uint8List body, Duration? retryAfter});
typedef TtsTransport = Future<TtsReply> Function(String method, Uri url, Map<String, String> headers, List<int>? body, Duration timeout);

/// The JSON body of `POST /tts` (w13). `voice_id` optional: absent → the Worker's default voice.
Map<String, Object?> buildTtsBody(String text, {String lang = 'hi', String? voiceId, String? iid, String? uid}) => {
      'text': text,
      'lang': lang,
      if (voiceId != null && voiceId.isNotEmpty) 'voice_id': voiceId,
      if (iid != null && iid.isNotEmpty) 'iid': iid,
      if (uid != null && uid.isNotEmpty) 'uid': uid,
    };

/// Why a clip did not come back (drives the speaker's back-off).
enum TtsFail { none, offline, notDeployed, unavailable, rateLimited, badVoice, rejected, badReply }

TtsFail ttsFailFor(int? status) => switch (status) {
      null => TtsFail.offline,
      200 => TtsFail.badReply,
      404 || 405 || 501 => TtsFail.notDeployed, // prod without /tts yet
      503 => TtsFail.unavailable, // tts_unavailable: no key / ElevenLabs down
      429 => TtsFail.rateLimited,
      400 => TtsFail.badVoice, // unknown voice_id (or bad text)
      _ => TtsFail.rejected,
    };

class TtsClient {
  TtsClient({String? endpoint, this.path = kTtsPath, this.voicesPath = kTtsVoicesPath, this.header = kAiClientHeader, this.timeout = const Duration(seconds: 8), TtsTransport? transport, String? Function()? iid, String? Function()? uid})
      : _endpoint = endpoint,
        _transport = transport ?? _ioTransport,
        _iid = iid ?? (() => Analytics.I.iid),
        _uid = uid ?? (() => FirebaseBridge.I.uid);

  final String? _endpoint;
  final String path, voicesPath;
  final String header;
  final Duration timeout;
  final TtsTransport _transport;
  final String? Function() _iid, _uid;

  /// `endpoints.tts` (RemoteConfig) → `endpoints.ai` → the built-in prod Worker. The preview
  /// Worker is never the default.
  String get endpoint => (_endpoint ?? RemoteConfig.I.ttsEndpoint ?? RemoteConfig.I.aiEndpoint ?? kAiEndpoint).replaceAll(RegExp(r'/+$'), '');
  Uri _url(String p) => Uri.parse('$endpoint${p.startsWith('/') ? p : '/$p'}');
  Uri get url => _url(path);
  Uri get voicesUrl => _url(voicesPath);

  String? _safe(String? Function() f) {
    try {
      return f();
    } catch (_) {
      return null;
    }
  }

  Map<String, String> _headers({bool json = false, String accept = 'application/json'}) => {
        if (json) 'Content-Type': 'application/json; charset=utf-8',
        'X-Granth-Client': header,
        'Accept': accept,
        'User-Agent': kTtsUserAgent,
      };

  /// Status / failure / Retry-After of the latest call.
  int? lastStatus;
  TtsFail lastFail = TtsFail.none;
  Duration? lastRetryAfter;

  void _note(int? status, Duration? retryAfter) {
    lastStatus = status;
    lastFail = status == 200 ? TtsFail.none : ttsFailFor(status);
    lastRetryAfter = retryAfter;
  }

  /// MP3 bytes for [text], or null on any failure (see [lastFail]). Never throws.
  Future<({Uint8List bytes, String mime})?> synth(String text, {String lang = 'hi', String? voiceId}) async {
    final t = text.trim();
    if (t.isEmpty) return null;
    final cut = t.runes.length > kTtsTextMax ? String.fromCharCodes(t.runes.take(kTtsTextMax)) : t;
    try {
      final r = await _transport('POST', url, _headers(json: true, accept: 'audio/mpeg'), utf8.encode(jsonEncode(buildTtsBody(cut, lang: lang, voiceId: voiceId, iid: _safe(_iid), uid: _safe(_uid)))), timeout)
          .timeout(timeout + const Duration(seconds: 1));
      _note(r.status, r.retryAfter);
      final mime = r.contentType.split(';').first.trim().toLowerCase();
      if (r.status != 200) return null;
      if (r.body.isEmpty || r.body.length > kTtsAudioMax || !(mime.startsWith('audio/') || mime == 'application/octet-stream')) {
        lastFail = TtsFail.badReply;
        return null;
      }
      return (bytes: r.body, mime: mime.startsWith('audio/') ? mime : 'audio/mpeg');
    } catch (_) {
      _note(null, null);
      return null;
    }
  }

  /// `GET /tts/voices` → the Worker's allow-list and default id, or null. Never throws.
  Future<({List<NavVoiceOption> voices, String? defaultId})?> voices() async {
    try {
      final r = await _transport('GET', voicesUrl, _headers(), null, timeout).timeout(timeout + const Duration(seconds: 1));
      _note(r.status, r.retryAfter);
      if (r.status != 200) return null;
      final j = jsonDecode(utf8.decode(r.body, allowMalformed: true));
      if (j is! Map) return null;
      final list = parseVoiceList(j['voices']);
      if (list == null) return null;
      final d = j['default_voice_id'];
      return (voices: list, defaultId: d is String && list.any((v) => v.id == d) ? d : null);
    } catch (_) {
      _note(null, null);
      return null;
    }
  }

  static Future<TtsReply> _ioTransport(String method, Uri url, Map<String, String> headers, List<int>? body, Duration timeout) async {
    final client = HttpClient()
      ..connectionTimeout = timeout
      ..userAgent = kTtsUserAgent;
    try {
      final req = await client.openUrl(method, url);
      headers.forEach(req.headers.set);
      if (body != null) {
        req.contentLength = body.length;
        req.add(body);
      }
      final res = await req.close().timeout(timeout);
      final b = BytesBuilder(copy: false);
      var n = 0;
      await for (final chunk in res.timeout(timeout)) {
        n += chunk.length;
        if (n > kTtsAudioMax) break;
        b.add(chunk);
      }
      final ra = int.tryParse(res.headers.value('retry-after') ?? '');
      return (
        status: n > kTtsAudioMax ? 413 : res.statusCode,
        contentType: res.headers.contentType?.mimeType ?? '',
        body: b.takeBytes(),
        retryAfter: ra == null || ra < 0 ? null : Duration(seconds: ra),
      );
    } finally {
      client.close(force: true);
    }
  }
}

/// Plays one clip and completes when it ended (true) or failed (false).
abstract class NavAudio {
  Future<bool> play(Uint8List bytes, String mime);
  Future<void> stop();

  /// The phone's own offline voice (Web Speech in the WebView), when the device has one.
  Future<bool> hasLocalVoice();
  Future<bool> speakLocal(String text, {String lang = 'hi-IN'});
}

/// Plays audio through a tiny hidden WebView (`<audio>` with a data: URL).
class WebViewNavAudio implements NavAudio {
  WebViewNavAudio._();
  static final WebViewNavAudio I = WebViewNavAudio._();

  /// The host widget mounts a 1×1 view for this controller once it exists.
  final ValueNotifier<WebViewController?> controller = ValueNotifier(null);
  Completer<void>? _ready;
  Completer<bool>? _clip;

  static const _html = '<!doctype html><html><head><meta name="viewport" content="width=device-width"></head>'
      '<body style="margin:0;background:transparent"><audio id="a" preload="auto"></audio><script>'
      'var a=document.getElementById("a");'
      'function say(m){try{GranthTts.postMessage(m)}catch(e){}}'
      'a.onended=function(){say("end")};a.onerror=function(){say("err")};'
      'function gPlay(src){try{a.pause();a.src=src;var p=a.play();if(p&&p.catch)p.catch(function(){say("err")})}catch(e){say("err")}}'
      'function gStop(){try{a.pause();a.removeAttribute("src");a.load()}catch(e){}try{speechSynthesis.cancel()}catch(e){}}'
      'function gVoices(){try{return window.speechSynthesis?speechSynthesis.getVoices().length:0}catch(e){return 0}}'
      'function gSpeak(t,l){try{var u=new SpeechSynthesisUtterance(t);u.lang=l;var vs=speechSynthesis.getVoices();'
      'for(var i=0;i<vs.length;i++){if((vs[i].lang||"").toLowerCase().indexOf(l.slice(0,2))==0){u.voice=vs[i];break}}'
      'u.onend=function(){say("end")};u.onerror=function(){say("err")};speechSynthesis.cancel();speechSynthesis.speak(u)}catch(e){say("err")}}'
      'try{if(window.speechSynthesis){speechSynthesis.getVoices();speechSynthesis.onvoiceschanged=function(){}}}catch(e){}'
      'say("ready");</script></body></html>';

  Future<WebViewController?> _ensure() async {
    if (controller.value != null && _ready != null) {
      await _ready!.future.timeout(const Duration(seconds: 4), onTimeout: () {});
      return _ready!.isCompleted ? controller.value : null;
    }
    if (WebViewPlatform.instance == null) return null; // tests / unsupported platform
    final ready = _ready = Completer<void>();
    final c = WebViewController();
    await c.setJavaScriptMode(JavaScriptMode.unrestricted);
    await c.setBackgroundColor(const Color(0x00000000));
    await c.addJavaScriptChannel('GranthTts', onMessageReceived: (m) {
      switch (m.message) {
        case 'ready':
          if (!ready.isCompleted) ready.complete();
        case 'end':
          _finish(true);
        case 'err':
          _finish(false);
      }
    });
    final p = c.platform;
    if (p is AndroidWebViewController) await p.setMediaPlaybackRequiresUserGesture(false);
    controller.value = c;
    await c.loadHtmlString(_html, baseUrl: 'https://granthprabandhan.pages.dev/');
    await ready.future.timeout(const Duration(seconds: 4), onTimeout: () {});
    return ready.isCompleted ? c : null;
  }

  void _finish(bool ok) {
    final c = _clip;
    _clip = null;
    if (c != null && !c.isCompleted) c.complete(ok);
  }

  @override
  Future<bool> play(Uint8List bytes, String mime) async {
    try {
      final c = await _ensure();
      if (c == null) return false;
      _finish(false);
      final done = _clip = Completer<bool>();
      final src = 'data:$mime;base64,${base64Encode(bytes)}';
      await c.runJavaScript('gPlay(${jsonEncode(src)})');
      // ~128 kbps MP3 ≈ 16 KB/s: generous upper bound so the mic never stays muted forever.
      final limit = Duration(milliseconds: 2500 + bytes.length ~/ 8);
      return await done.future.timeout(limit > const Duration(seconds: 25) ? const Duration(seconds: 25) : limit, onTimeout: () {
        _finish(false);
        return false;
      });
    } catch (_) {
      _finish(false);
      return false;
    }
  }

  @override
  Future<bool> hasLocalVoice() async {
    try {
      final c = await _ensure();
      if (c == null) return false;
      final n = await c.runJavaScriptReturningResult('gVoices()');
      return (num.tryParse('$n') ?? 0) > 0;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<bool> speakLocal(String text, {String lang = 'hi-IN'}) async {
    try {
      final c = await _ensure();
      if (c == null || !await hasLocalVoice()) return false;
      _finish(false);
      final done = _clip = Completer<bool>();
      await c.runJavaScript('gSpeak(${jsonEncode(text)},${jsonEncode(lang)})');
      return await done.future.timeout(Duration(milliseconds: 3000 + text.length * 120), onTimeout: () {
        _finish(false);
        return false;
      });
    } catch (_) {
      _finish(false);
      return false;
    }
  }

  @override
  Future<void> stop() async {
    _finish(false);
    try {
      await controller.value?.runJavaScript('gStop()');
    } catch (_) {}
  }
}

/// Mounts the hidden 1×1 audio WebView (nothing until the first spoken reply).
class NavAudioHost extends StatelessWidget {
  const NavAudioHost({super.key});
  @override
  Widget build(BuildContext context) => ValueListenableBuilder<WebViewController?>(
        valueListenable: WebViewNavAudio.I.controller,
        builder: (context, c, _) => c == null
            ? const SizedBox.shrink()
            : IgnorePointer(child: ExcludeSemantics(child: SizedBox(width: 1, height: 1, child: WebViewWidget(controller: c)))),
      );
}

/// Text → server voice → speaker, with a small cache (the same few phrases repeat) and a
/// back-off when the Worker has no `/tts` yet (404/405) so the app does not keep asking.
class NavSpeaker {
  NavSpeaker({TtsClient? client, NavAudio? audio, this.backoff = const Duration(minutes: 10), DateTime Function()? now, String? Function()? voice})
      : _client = client,
        _audio = audio,
        _now = now ?? DateTime.now,
        _voice = voice ?? navSavedVoice;
  final String? Function() _voice;

  TtsClient? _client;
  NavAudio? _audio;
  TtsClient get client => _client ??= TtsClient();
  NavAudio get audio => _audio ??= WebViewNavAudio.I;
  final Duration backoff;
  final DateTime Function() _now;
  DateTime? _offUntil;
  final Map<String, ({Uint8List bytes, String mime})> _cache = {};
  int _seq = 0;

  /// Texts asked for (tests / debugging).
  final List<String> said = [];

  bool get speaking => _speaking;
  bool _speaking = false;

  /// Speaks [text] in [voiceId] (default: the user's saved choice; [kPhoneVoice] = the
  /// phone's offline voice). Any server failure (offline, 404 before prod has /tts, 503
  /// tts_unavailable, 429) → the phone voice if it has one, else silence; never an error.
  Future<bool> say(String text, {String lang = 'hi', String? voiceId}) async {
    final t = text.trim();
    if (t.isEmpty) return false;
    final voice = voiceId ?? _voice();
    final my = ++_seq;
    said.add(t);
    voices.add(voice);
    _speaking = true;
    try {
      if (voice == kPhoneVoice) return await audio.speakLocal(t);
      if (_offUntil != null && _now().isBefore(_offUntil!)) return await _local(t, my);
      var v = voice;
      var key = '$lang|${v ?? ''}|$t';
      var clip = _cache[key];
      if (clip == null) {
        clip = await client.synth(t, lang: lang, voiceId: v);
        if (clip == null && client.lastFail == TtsFail.badVoice && v != null) {
          v = null; // the Worker no longer allows this voice: its default instead
          key = '$lang||$t';
          clip = await client.synth(t, lang: lang);
        }
        if (clip == null) {
          final wait = switch (client.lastFail) {
            TtsFail.notDeployed => backoff,
            TtsFail.unavailable => const Duration(minutes: 2),
            TtsFail.rateLimited => _cap(client.lastRetryAfter ?? const Duration(seconds: 60)),
            _ => null,
          };
          if (wait != null) _offUntil = _now().add(wait);
          return await _local(t, my);
        }
        if (_cache.length >= 24) _cache.remove(_cache.keys.first);
        _cache[key] = clip;
      }
      if (my != _seq) return false; // a newer reply replaced this one
      return await audio.play(clip.bytes, clip.mime);
    } catch (_) {
      return false;
    } finally {
      if (my == _seq) _speaking = false;
    }
  }

  static Duration _cap(Duration d) => d > const Duration(hours: 1) ? const Duration(hours: 1) : d;

  /// Server speech paused until (back-off after 404 / 503 / 429); null = allowed.
  DateTime? get offUntil => _offUntil;

  Future<bool> _local(String t, int my) async => my == _seq && await audio.speakLocal(t);

  /// Voice ids asked for, parallel to [said] (tests).
  final List<String?> voices = [];

  Future<void> stop() async {
    _seq++;
    _speaking = false;
    try {
      await _audio?.stop();
    } catch (_) {}
  }
}

/// Short spoken line for an opened target: "वेद खोल रहा हूँ".
String navSayOpening(String label) {
  var l = label.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
  if (l.runes.length > 60) l = String.fromCharCodes(l.runes.take(60));
  return l.isEmpty ? 'खोल रहा हूँ' : '$l खोल रहा हूँ';
}

/// "कौन-सा खोलूँ? वेद या वेद ग्रंथ"
String navSayClarify(List<String> labels) => 'कौन-सा खोलूँ? ${labels.take(3).map((l) => l.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim()).join(' या ')}';

const String kNavSayUnknown = 'समझ नहीं आया';
const String kNavSayNothing = 'कुछ सुनाई नहीं दिया';

/// Saved voice choice (Store key); [kPhoneVoice] = the phone's offline voice.
const String kNavVoiceKey = 'granth-nav-voice-id';
const String kPhoneVoice = 'phone';

const String kNavVoicesCacheKey = 'granth-nav-voices';

/// Voices for the picker: the Worker's last `/tts/voices` answer (saved), else the admin's
/// `ui.navigator_voices`, else the bundled allow-list.
List<NavVoiceOption> navServerVoices() {
  try {
    final raw = Store.I.getString(kNavVoicesCacheKey);
    if (raw != null && raw.isNotEmpty) {
      final j = jsonDecode(raw);
      final l = j is Map ? parseVoiceList(j['voices']) : null;
      if (l != null) return l;
    }
  } catch (_) {}
  return RemoteConfig.I.navigatorVoices;
}

/// The Worker's default voice id from the saved `/tts/voices` answer (null = unknown).
String? navDefaultVoice() {
  try {
    final raw = Store.I.getString(kNavVoicesCacheKey);
    final j = raw == null ? null : jsonDecode(raw);
    final d = j is Map ? j['default_voice_id'] : null;
    return d is String && d.isNotEmpty ? d : null;
  } catch (_) {
    return null;
  }
}

/// Asks the Worker for its voice list and saves it; false (list unchanged) on any failure.
Future<bool> refreshNavVoices(TtsClient client) async {
  final r = await client.voices();
  if (r == null) return false;
  try {
    await Store.I.setString(kNavVoicesCacheKey, jsonEncode({
      'voices': [for (final v in r.voices) {'id': v.id, 'name': v.name, 'gender': v.gender}],
      if (r.defaultId != null) 'default_voice_id': r.defaultId,
    }));
  } catch (_) {}
  return true;
}

/// The saved voice id when it is still valid (phone, or still in the admin's list); else null.
String? navSavedVoice() {
  try {
    final v = Store.I.getString(kNavVoiceKey);
    if (v == null || v.isEmpty) return null;
    return v == kPhoneVoice || navServerVoices().any((o) => o.id == v) ? v : null;
  } catch (_) {
    return null;
  }
}
