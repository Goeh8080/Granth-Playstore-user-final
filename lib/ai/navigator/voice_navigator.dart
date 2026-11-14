/// t304 Navigator voice runtime: admin switch (`flags.navigator_enabled`) + user opt-in, mic
/// only while the app is open, one-shot mic button and optional foreground wake phrase
/// ("Hey Granth" / "Hey Tatv" / "तत्व"), then step-by-step navigation with a visible
/// "invisible touch" ripple on each folder / granth as it opens.
library;

import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:speech_to_text/speech_recognition_result.dart';
import 'package:speech_to_text/speech_to_text.dart';

import '../../services/catalog_store.dart';
import '../../services/remote_config.dart';
import '../../services/shelves.dart';
import '../../services/storage.dart';
import '../../state/router.dart';
import '../../state/toast.dart';
import '../../theme/colors.dart';
import '../../widgets/common.dart';
import '../../widgets/overlays.dart';
import 'nav_intent.dart';
import 'nav_phrases.dart';
import 'nav_tts.dart';
import 'nav_voice_sheet.dart';

/// One recognition result: every alternate the recognizer offered (best first), whether it is
/// final, and the top confidence (-1 = the platform gave none).
class NavHeard {
  const NavHeard(this.alternates, {this.isFinal = true, this.confidence = -1});
  final List<String> alternates;
  final bool isFinal;
  final double confidence;
  String get text => alternates.isEmpty ? '' : alternates.first;

  /// Rated and below the bar (Android gives 0..1 on final results).
  bool get lowConfidence => confidence >= 0 && confidence < kNavLowConfidence;
}

const double kNavLowConfidence = 0.35;

/// Recognizer errors worth one more try (noise, a brief network drop, a busy engine).
const Set<String> kNavRetryErrors = {
  'error_no_match', 'error_speech_timeout', 'error_network', 'error_network_timeout', 'error_server', 'error_busy', 'error_server_disconnected', 'error_audio_error', 'error_client',
};

/// How many times one command is re-asked ("फिर से बोलिए") before giving up.
const int kNavRetries = 2;

/// Speech engine seam (tests replace it; the app uses the phone's recognizer).
abstract class NavSpeech {
  Future<bool> init();

  /// [command]: a short command window (vs. the long wake-phrase window). [onDone] gets the
  /// platform error code (`error_no_match` …) or null.
  Future<void> listen({required void Function(NavHeard heard) onHeard, required void Function(String? error) onDone, required Duration listenFor, required Duration pauseFor, bool command = true});
  Future<void> stop();
  bool get listening;
}

class _SttSpeech implements NavSpeech {
  final SpeechToText _stt = SpeechToText();
  void Function(String? error)? _done;
  Timer? _doneLater;
  @override
  bool get listening => _stt.isListening;

  @override
  Future<bool> init() async {
    try {
      // Asks for the microphone (RECORD_AUDIO) the first time — only after the user opted in.
      return await _stt.initialize(
        onStatus: (s) {
          // "done" can arrive just before the error: give the error a moment to win.
          if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) {
            _doneLater?.cancel();
            _doneLater = Timer(const Duration(milliseconds: 180), () => _done?.call(null));
          }
        },
        onError: (e) {
          _doneLater?.cancel();
          _done?.call(e.errorMsg);
        },
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> listen({required void Function(NavHeard heard) onHeard, required void Function(String? error) onDone, required Duration listenFor, required Duration pauseFor, bool command = true}) async {
    var fired = false;
    _doneLater?.cancel();
    _done = (err) {
      if (fired) return;
      fired = true;
      onDone(err);
    };
    try {
      // Android's SpeechRecognizer records from the VOICE_RECOGNITION source (the platform's
      // own noise suppression / AGC) and returns up to 10 alternates; all are matched.
      await _stt.listen(
        onResult: (SpeechRecognitionResult r) => onHeard(NavHeard(
          [for (final a in r.alternates) if (a.recognizedWords.trim().isNotEmpty) a.recognizedWords],
          isFinal: r.finalResult,
          confidence: r.hasConfidenceRating ? r.confidence : -1,
        )),
        listenOptions: SpeechListenOptions(
          localeId: 'hi_IN', // Hindi + Hinglish (English words come through too)
          listenFor: listenFor,
          pauseFor: pauseFor,
          partialResults: true,
          cancelOnError: true,
          // Short command → confirmation; the long wake window → dictation (keeps listening).
          listenMode: command ? ListenMode.confirmation : ListenMode.dictation,
        ),
      );
    } catch (_) {
      _done?.call('error_client');
    }
  }

  @override
  Future<void> stop() async {
    try {
      await _stt.stop();
    } catch (_) {}
  }
}

enum NavVoiceState { off, idle, wake, listening, navigating }

class VoiceNavigator extends ChangeNotifier with WidgetsBindingObserver {
  VoiceNavigator._();
  static VoiceNavigator I = VoiceNavigator._();

  static const kOptIn = 'granth-nav-voice';
  static const kWake = 'granth-nav-wake';

  NavSpeech speech = _SttSpeech();

  /// t352: spoken replies in the ElevenLabs voice (server-side key; silent on failure).
  NavSpeaker speaker = NavSpeaker();
  bool _speaking = false;
  bool get speaking => _speaking;
  DateTime? _pendingAt;

  /// Root navigator (for the voice picker sheet); set by [attach].
  GlobalKey<NavigatorState>? navKey;

  /// Opens the voice picker (tests replace it).
  Future<void> Function()? openVoicePickerOverride;

  NavVoiceState state = NavVoiceState.idle;
  String heard = '';

  /// "फिर से बोलिए" shown while re-listening after noise / no match (UI hint).
  bool retrying = false;
  bool _ready = false;
  bool _foreground = true;
  bool _observing = false;
  List<String>? _pending;
  Timer? _restart;

  /// Who started the current command window: `hold` (Tatv AI button held), `mic`, `wake`.
  String listenSource = 'mic';

  /// t361: hold on the Tatv AI button → listen for a command right away (no wake phrase).
  /// Only with the admin switch on. Not opted in yet → [confirmOptIn] asks kindly first, then
  /// the mic permission; a "no" or a refused mic does nothing more. Returns true if listening.
  Future<bool> holdToListen({Future<bool> Function()? confirmOptIn}) async {
    if (!adminOn || !_foreground || state == NavVoiceState.navigating) return false;
    if (!optedIn) {
      final yes = confirmOptIn == null ? true : await confirmOptIn();
      if (!yes || !await setOptIn(true)) return false;
    }
    if (!available) return false;
    listenSource = 'hold';
    // Fast: the mic starts now; the hidden player warms up meanwhile for the reply.
    unawaited(_warm());
    await listenOnce();
    return state == NavVoiceState.listening;
  }

  /// Pause between retries (tests set zero).
  Duration retryGap = const Duration(milliseconds: 350);

  bool get adminOn => RemoteConfig.I.navigatorEnabled;
  bool get optedIn => Store.I.getString(kOptIn) == '1';
  bool get wakeOn => Store.I.getString(kWake) == '1';
  bool get available => adminOn && optedIn;

  void attach([GlobalKey<NavigatorState>? key]) {
    if (key != null) navKey = key;
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    RemoteConfig.I.addListener(_sync);
    _sync();
  }

  bool _voicesAsked = false;

  /// Player + common replies ready ahead of time (once per run; never blocks listening).
  Future<void>? _warming;
  Future<void> _warm() => _warming ??= () async {
        try {
          final a = speaker.audio;
          if (a is WebViewNavAudio) await a.warm();
          final p = NavPhrases.current();
          await speaker.prefetch([p.again, p.unknown, p.nothing]);
        } catch (_) {}
      }();

  void _sync() {
    if (available && !_voicesAsked) {
      _voicesAsked = true; // once per run: the Worker's voice list for the picker (silent)
      unawaited(refreshNavVoices(speaker.client).catchError((_) => false));
    }
    if (!available) {
      _halt();
    } else if (wakeOn) {
      _scheduleWake(const Duration(milliseconds: 600));
    }
    notifyListeners();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    if (!_foreground) {
      _halt(); // never listens in the background
    } else if (available && wakeOn) {
      _scheduleWake(const Duration(milliseconds: 800));
    }
  }

  void _halt() {
    _restart?.cancel();
    if (_speaking) speaker.stop();
    _restart = null;
    if (speech.listening) speech.stop();
    if (state != NavVoiceState.navigating) state = NavVoiceState.idle;
    retrying = false;
    notifyListeners();
  }

  /// User turns the Navigator on (Settings). Asks for the mic now; reverts if refused.
  Future<bool> setOptIn(bool on) async {
    if (!on) {
      await Store.I.setString(kOptIn, '0');
      await Store.I.setString(kWake, '0');
      _halt();
      return false;
    }
    if (!adminOn) return false;
    _ready = await speech.init();
    await Store.I.setString(kOptIn, _ready ? '1' : '0');
    if (!_ready) Toast.show(NavPhrases.current().micDenied);
    _sync();
    return _ready;
  }

  Future<void> setWake(bool on) async {
    await Store.I.setString(kWake, on && available ? '1' : '0');
    if (!wakeOn) _halt();
    _sync();
  }

  Future<bool> _ensure() async => _ready || (_ready = await speech.init());

  /// Mic button: listen once for a command (no wake phrase needed). On noise, no match, a
  /// network blip or a low-confidence unknown it says "फिर से बोलिए" and listens again
  /// (up to [kNavRetries] times).
  Future<void> listenOnce({int attempt = 0}) async {
    if (!available || !_foreground || state == NavVoiceState.navigating) return;
    if (!await _ensure()) return Toast.show(NavPhrases.current().micUnavailable);
    _restart?.cancel();
    if (_speaking) await _hush(); // tap while it talks: stop the voice, listen
    if (speech.listening) await speech.stop();
    state = NavVoiceState.listening;
    retrying = attempt > 0;
    heard = '';
    notifyListeners();
    var decided = false;
    NavHeard? last;
    await speech.listen(
      listenFor: const Duration(seconds: 12),
      pauseFor: const Duration(seconds: 4),
      onHeard: (h) {
        if (decided) return;
        last = h;
        heard = h.text;
        notifyListeners();
        if (!h.isFinal) return;
        decided = true;
        _decide(h, attempt);
      },
      onDone: (err) {
        if (state == NavVoiceState.listening) state = NavVoiceState.idle;
        notifyListeners();
        if (decided) return;
        decided = true;
        // Some engines end without a final result: use the last partial if it means something.
        final p = last;
        if (p != null && p.text.trim().isNotEmpty && err == null) {
          _decide(NavHeard(p.alternates, confidence: p.confidence), attempt);
          return;
        }
        final retryable = err == null || kNavRetryErrors.contains(err);
        if (retryable && attempt < kNavRetries) {
          unawaited(_again(attempt, busy: err == 'error_busy'));
        } else {
          retrying = false;
          if (err != null && !retryable) Toast.show(NavPhrases.current().micFailed);
          if (wakeOn) _scheduleWake(const Duration(seconds: 2));
        }
      },
    );
  }

  /// Final words of a command window → act, or ask again when nothing matched.
  Future<void> _decide(NavHeard h, int attempt) async {
    final r = interpretHeard(h.alternates);
    if (r is NavUnknown && attempt < kNavRetries && r.reason != 'unsafe' && r.reason != 'too_long') {
      // Noise or a low-confidence guess: one more try instead of "समझ नहीं आया".
      if (h.text.trim().isEmpty || h.lowConfidence || r.reason == 'unknown' || r.reason == 'empty') {
        await _again(attempt);
        return;
      }
    }
    retrying = false;
    await handle(h.text, alternates: h.alternates, result: r);
  }

  Future<void> _again(int attempt, {bool busy = false}) async {
    retrying = true;
    notifyListeners();
    final p = NavPhrases.current();
    Toast.show(p.again);
    await _say(p.again, rearm: false);
    await Future<void>.delayed(busy ? retryGap * 2 : retryGap);
    if (available && _foreground && state != NavVoiceState.navigating) await listenOnce(attempt: attempt + 1);
  }

  void _scheduleWake(Duration d) {
    _restart?.cancel();
    _restart = Timer(d, _wakeLoop);
  }

  int _wakeErrors = 0;

  /// Foreground wake phrase: short listening windows with a pause between them (battery).
  Future<void> _wakeLoop() async {
    // Never listens while its own voice plays (it would hear itself); [_say] re-arms after.
    if (!available || !wakeOn || !_foreground || _speaking || state == NavVoiceState.navigating || state == NavVoiceState.listening) return;
    if (!await _ensure()) return;
    if (speech.listening) return;
    state = NavVoiceState.wake;
    notifyListeners();
    // After "कौन-सा खोलूँ?" the answer ("वेद") needs no wake phrase.
    var armed = false;
    final answer = _pendingFresh;
    var acted = false;
    await speech.listen(
      command: false,
      listenFor: const Duration(seconds: 30),
      pauseFor: const Duration(seconds: 5),
      onHeard: (h) {
        if (!h.isFinal || acted) return;
        final w = wakeAcross(h.alternates);
        if (w != null) {
          if (w.rest.isEmpty) {
            armed = true; // "Hey Granth" … then the command in the next window
          } else {
            acted = true;
            heard = h.text;
            handle(w.rest.first, alternates: w.rest);
          }
        } else if (armed || answer) {
          acted = true;
          heard = h.text;
          handle(h.text, alternates: h.alternates);
        }
      },
      onDone: (err) {
        if (state == NavVoiceState.wake) state = NavVoiceState.idle;
        notifyListeners();
        // Silence / noise is normal here: no prompt. Repeated hard errors back off a little.
        _wakeErrors = err == null || err == 'error_no_match' || err == 'error_speech_timeout' ? 0 : _wakeErrors + 1;
        if (armed && !acted && state != NavVoiceState.navigating) {
          listenSource = 'wake';
          listenOnce();
        } else if (!acted) {
          _scheduleWake(Duration(seconds: 3 + 3 * _wakeErrors.clamp(0, 5)));
        }
      },
    );
  }

  NavCatalog catalog() {
    final s = CatalogStore.I;
    final idx = Shelves.indexFor(s.granths);
    return NavCatalog.build(structure: Shelves.structure, granths: s.granths, topics: s.topics, placements: idx.placements);
  }

  bool get _pendingFresh => _pending != null && _pendingAt != null && DateTime.now().difference(_pendingAt!) < const Duration(seconds: 45);

  /// Best meaning across all recognizer alternates (pending clarification first, then all).
  NavResult interpretHeard(List<String> alternates) {
    final cat = catalog();
    final pending = _pendingFresh ? _pending : null;
    var r = cat.interpretAll(alternates, pending: pending);
    // A new command after a clarification must not be limited to the old choices.
    if (pending != null && r is NavUnknown) r = cat.interpretAll(alternates);
    return r;
  }

  /// Interprets [text] (plus any recognizer [alternates]) and opens the result step by step,
  /// speaking a short confirmation in parallel. Returns the result (tests).
  Future<NavResult> handle(String text, {List<String> alternates = const [], NavResult? result}) async {
    final r = result ?? interpretHeard([text, ...alternates.where((a) => a != text)]);
    _pending = null;
    _pendingAt = null;
    switch (r) {
      case NavIntent(:final target) when target.kind == 'action':
        if (target.id == kNavActionVoice) {
          await _say(NavPhrases.current().chooseVoice);
          await openVoicePicker();
        }
      case NavIntent(:final target):
        final voice = _say(NavPhrases.current().opening(target.label));
        await run(target);
        await voice;
      case NavClarify(:final choices):
        _pending = [for (final c in choices) c.id];
        _pendingAt = DateTime.now();
        Toast.show('${r.prompt} ${choices.map((c) => c.label).join(' / ')}');
        await _say(NavPhrases.current().clarify([for (final c in choices) c.label]), shown: true);
        // Listen for the answer right away (one-shot); wake mode also accepts it unprefixed.
        if (available && _foreground && !wakeOn && state == NavVoiceState.idle) unawaited(listenOnce());
      case NavUnknown():
        final empty = text.trim().isEmpty;
        final p = NavPhrases.current();
        Toast.show(empty ? p.nothing : p.unknownToast(text));
        await _say(empty ? p.nothing : p.unknown, shown: true);
    }
    return r;
  }

  /// The voice picker sheet ("awaaz badlo" or Settings).
  Future<void> openVoicePicker() async {
    if (navVoiceLocked()) return; // the admin's voice only
    final o = openVoicePickerOverride;
    if (o != null) return o();
    final ctx = navKey?.currentContext;
    if (ctx == null || !ctx.mounted) return;
    await showNavVoiceSheet(ctx, speaker: speaker);
  }

  /// Speaks [text] with the mic off; re-arms the wake phrase afterwards. No server voice
  /// (offline, /tts off …) → the text is shown instead ([shown]: already on screen).
  Future<void> _say(String text, {bool rearm = true, bool shown = false}) async {
    _speaking = true;
    _restart?.cancel();
    try {
      if (speech.listening) await speech.stop();
      await speaker.say(text);
      if (speaker.lastSilent && !shown) Toast.show(text);
    } catch (_) {
    } finally {
      _speaking = false;
      notifyListeners();
      if (rearm && available && wakeOn && _foreground) _scheduleWake(const Duration(milliseconds: 1200));
    }
  }

  Future<void> _hush() async {
    await speaker.stop();
    _speaking = false;
  }

  /// Opens [t] one step at a time: ripple on the item, then the page, then the next item.
  Future<void> run(NavTarget t, {Duration tap = const Duration(milliseconds: 380), Duration settle = const Duration(milliseconds: 560)}) async {
    if (state == NavVoiceState.navigating) return;
    if (speech.listening) await speech.stop();
    state = NavVoiceState.navigating;
    notifyListeners();
    try {
      for (final h in t.steps) {
        if (AppNav.I.hash == h) continue;
        await NavTouch.I.touch(h);
        await Future<void>.delayed(tap);
        AppNav.I.go(h);
        await Future<void>.delayed(settle);
      }
    } finally {
      state = NavVoiceState.idle;
      notifyListeners();
      if (wakeOn) _scheduleWake(const Duration(seconds: 2));
    }
  }

  @visibleForTesting
  static void debugReset() => I = VoiceNavigator._();
}

/// Where the on-screen item for a destination hash is (registered by [NavTouchTarget]).
class NavTouch {
  NavTouch._();
  static final NavTouch I = NavTouch._();
  final Map<String, BuildContext> _targets = {};

  /// Latest ripple: global position + a counter so the same spot replays.
  final ValueNotifier<(Offset, int)?> ripple = ValueNotifier(null);
  int _n = 0;

  void _add(String hash, BuildContext c) => _targets[hash] = c;
  void _remove(String hash, BuildContext c) {
    if (identical(_targets[hash], c)) _targets.remove(hash);
  }

  /// Scrolls the item for [hash] into view (when it is on this screen) and shows the ripple
  /// on it; otherwise a ripple in the middle of the screen.
  Future<void> touch(String hash) async {
    final c = _targets[hash];
    Offset? at;
    if (c != null && c.mounted) {
      try {
        await Scrollable.ensureVisible(c, duration: const Duration(milliseconds: 240), curve: Curves.easeOutCubic, alignment: 0.4);
      } catch (_) {}
      if (c.mounted) {
        final box = c.findRenderObject();
        if (box is RenderBox && box.hasSize && box.attached) at = box.localToGlobal(box.size.center(Offset.zero));
      }
    }
    if (at == null) {
      final v = WidgetsBinding.instance.platformDispatcher.views.firstOrNull;
      if (v != null) at = Offset(v.physicalSize.width / v.devicePixelRatio / 2, v.physicalSize.height / v.devicePixelRatio / 2);
    }
    if (at != null) ripple.value = (at, ++_n);
  }

  bool has(String hash) => _targets.containsKey(hash);
}

/// Marks a tappable item as "the thing that opens [hash]" for the Navigator's touch.
class NavTouchTarget extends StatefulWidget {
  const NavTouchTarget({super.key, required this.hash, required this.child});
  final String hash;
  final Widget child;
  @override
  State<NavTouchTarget> createState() => _NavTouchTargetState();
}

class _NavTouchTargetState extends State<NavTouchTarget> {
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    NavTouch.I._add(widget.hash, context);
  }

  @override
  void didUpdateWidget(NavTouchTarget old) {
    super.didUpdateWidget(old);
    if (old.hash != widget.hash) {
      NavTouch.I._remove(old.hash, context);
      NavTouch.I._add(widget.hash, context);
    }
  }

  @override
  void dispose() {
    NavTouch.I._remove(widget.hash, context);
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => widget.child;
}

/// Full-screen, touch-through layer that draws the Navigator's tap ripple.
class NavTouchLayer extends StatefulWidget {
  const NavTouchLayer({super.key});
  @override
  State<NavTouchLayer> createState() => _NavTouchLayerState();
}

class _NavTouchLayerState extends State<NavTouchLayer> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 520));
  Offset? _at;

  @override
  void initState() {
    super.initState();
    NavTouch.I.ripple.addListener(_on);
  }

  void _on() {
    final v = NavTouch.I.ripple.value;
    final box = context.findRenderObject();
    if (v == null || box is! RenderBox || !box.hasSize) return;
    setState(() => _at = box.globalToLocal(v.$1));
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    NavTouch.I.ripple.removeListener(_on);
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => IgnorePointer(
        child: Stack(fit: StackFit.expand, children: [
          // t352: hidden 1×1 player for the Navigator's spoken replies (only after the first one).
          const Positioned(left: 0, top: 0, child: NavAudioHost()),
          RepaintBoundary(
            child: AnimatedBuilder(
              animation: _c,
              builder: (context, _) => _at == null || !_c.isAnimating && _c.value == 1 ? const SizedBox.expand() : CustomPaint(size: Size.infinite, painter: _RipplePainter(_at!, _c.value)),
            ),
          ),
        ]),
      );
}

class _RipplePainter extends CustomPainter {
  _RipplePainter(this.at, this.t);
  final Offset at;
  final double t;
  @override
  void paint(Canvas canvas, Size size) {
    final e = Curves.easeOutCubic.transform(t);
    final fade = (1 - t).clamp(0.0, 1.0);
    canvas.drawCircle(at, 14 + 46 * e, Paint()..color = GColors.saffron.withValues(alpha: 0.28 * fade));
    canvas.drawCircle(
      at,
      10 + 30 * e,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 3
        ..color = GColors.maroon.withValues(alpha: 0.7 * fade),
    );
    canvas.drawCircle(at, 9 * (1 - e * 0.4), Paint()..color = GColors.maroon.withValues(alpha: 0.55 * fade));
  }

  @override
  bool shouldRepaint(_RipplePainter old) => old.t != t || old.at != at;
}

/// Small mic button (only when the admin turned the Navigator on and the user opted in).
class NavMicButton extends StatelessWidget {
  const NavMicButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([VoiceNavigator.I, RemoteConfig.I]),
        builder: (context, _) {
          final v = VoiceNavigator.I;
          if (!v.available) return const SizedBox.shrink();
          final active = v.state == NavVoiceState.listening || v.state == NavVoiceState.navigating;
          return Pressable(
            key: const ValueKey('nav-mic'),
            onTap: () {
              v.listenSource = 'mic';
              v.listenOnce();
            },
            child: AnimatedContainer(
              duration: const Duration(milliseconds: 220),
              width: 48,
              height: 48,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active ? GColors.maroon : GColors.paper,
                shape: BoxShape.circle,
                border: Border.all(color: v.state == NavVoiceState.wake ? GColors.saffron : GColors.creamDark, width: 2),
                boxShadow: [BoxShadow(color: GColors.shadow(0.2), blurRadius: 12, offset: const Offset(0, 4))],
              ),
              child: Icon(active ? Icons.graphic_eq : Icons.mic_none_rounded, size: 24, color: active ? GColors.paper : GColors.maroon, semanticLabel: 'आवाज़ से खोलें (Hey Granth)'),
            ),
          );
        },
      );
}

/// t361: hold (long-press) on a Tatv AI button → the Navigator listens for a command right
/// away. A normal tap still reaches [child] (opens Tatv AI) exactly as before. Off (no
/// gesture at all) unless the admin switched the Navigator on.
class NavHoldTrigger extends StatelessWidget {
  const NavHoldTrigger({super.key, required this.id, required this.child, this.confirmOptIn});
  final String id;
  final Widget child;

  /// Asks before turning the Navigator on (tests replace it). Default: a small sheet.
  final Future<bool> Function(BuildContext context)? confirmOptIn;

  Future<void> _hold(BuildContext context) async {
    HapticFeedback.lightImpact();
    await VoiceNavigator.I.holdToListen(confirmOptIn: () => (confirmOptIn ?? _askOptIn)(context));
  }

  static Future<bool> _askOptIn(BuildContext context) async {
    if (!context.mounted) return false;
    final r = await showPop<bool>(
      context,
      (ctx) => SheetCard(
        maxWidth: 400,
        children: [
          Text('आवाज़ से खोलें?', style: GText.display(size: 22, color: GColors.maroon, height: 1.3)),
          const SizedBox(height: 6),
          Text('Tatv AI बटन दबाकर रखें और बोलें, जैसे "वेद खोलो"। इसके लिए माइक की अनुमति चाहिए — माइक सिर्फ़ तभी सुनता है जब आप बटन दबाकर रखें या चालू करें।', style: GText.sans(size: 14.5, color: GColors.brown, height: 1.5)),
          const SizedBox(height: 14),
          SheetButton(key: const ValueKey('nav-hold-yes'), label: 'हाँ, चालू करें', primary: true, onTap: () => Navigator.pop(ctx, true)),
          const SizedBox(height: 8),
          SheetButton(key: const ValueKey('nav-hold-no'), label: 'अभी नहीं', onTap: () => Navigator.pop(ctx, false)),
        ],
      ),
    );
    return r == true;
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: Listenable.merge([RemoteConfig.I, VoiceNavigator.I]),
        builder: (context, _) {
          final v = VoiceNavigator.I;
          final on = v.adminOn;
          final listening = on && v.state == NavVoiceState.listening && v.listenSource == 'hold';
          return GestureDetector(
            key: ValueKey('nav-hold-$id'),
            behavior: HitTestBehavior.deferToChild,
            onLongPress: on ? () => _hold(context) : null,
            child: Stack(clipBehavior: Clip.none, alignment: Alignment.center, children: [
              child,
              if (listening) const Positioned.fill(child: IgnorePointer(child: _ListeningRing())),
              if (listening)
                Positioned(
                  bottom: 0,
                  child: IgnorePointer(
                    child: FractionalTranslation(
                      translation: const Offset(0, -1.6),
                      child: Container(
                        key: const ValueKey('nav-hold-listening'),
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                        decoration: BoxDecoration(color: GColors.maroon, borderRadius: BorderRadius.circular(14), boxShadow: [BoxShadow(color: GColors.shadow(0.2), blurRadius: 8, offset: const Offset(0, 3))]),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [
                          const Icon(Icons.graphic_eq, size: 16, color: GColors.paper),
                          const SizedBox(width: 4),
                          Text(v.retrying ? NavPhrases.current().again : NavPhrases.current().listening, style: GText.sans(size: 12.5, weight: FontWeight.w700, color: GColors.paper)),
                        ]),
                      ),
                    ),
                  ),
                ),
            ]),
          );
        },
      );
}

class _ListeningRing extends StatefulWidget {
  const _ListeningRing();
  @override
  State<_ListeningRing> createState() => _ListeningRingState();
}

class _ListeningRingState extends State<_ListeningRing> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 900))..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedBuilder(
        animation: _c,
        builder: (context, _) => DecoratedBox(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(40),
            border: Border.all(color: GColors.saffron.withValues(alpha: 0.5 + 0.5 * _c.value), width: 2 + 2 * _c.value),
          ),
        ),
      );
}
