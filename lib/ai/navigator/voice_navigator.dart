/// t304 Navigator voice runtime: admin switch (`flags.navigator_enabled`) + user opt-in, mic
/// only while the app is open, one-shot mic button and optional foreground wake phrase
/// ("Hey Granth" / "Hey Tatv" / "तत्व"), then step-by-step navigation with a visible
/// "invisible touch" ripple on each folder / granth as it opens.
library;

import 'dart:async';

import 'package:flutter/material.dart';
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
import 'nav_intent.dart';

/// Speech engine seam (tests replace it; the app uses the phone's recognizer).
abstract class NavSpeech {
  Future<bool> init();
  Future<void> listen({required void Function(String text, bool isFinal) onText, required void Function() onDone, required Duration listenFor, required Duration pauseFor});
  Future<void> stop();
  bool get listening;
}

class _SttSpeech implements NavSpeech {
  final SpeechToText _stt = SpeechToText();
  void Function()? _done;
  @override
  bool get listening => _stt.isListening;

  @override
  Future<bool> init() async {
    try {
      // Asks for the microphone (RECORD_AUDIO) the first time — only after the user opted in.
      return await _stt.initialize(
        onStatus: (s) {
          if (s == SpeechToText.doneStatus || s == SpeechToText.notListeningStatus) _done?.call();
        },
        onError: (_) => _done?.call(),
      );
    } catch (_) {
      return false;
    }
  }

  @override
  Future<void> listen({required void Function(String text, bool isFinal) onText, required void Function() onDone, required Duration listenFor, required Duration pauseFor}) async {
    var fired = false;
    _done = () {
      if (fired) return;
      fired = true;
      onDone();
    };
    await _stt.listen(
      onResult: (SpeechRecognitionResult r) => onText(r.recognizedWords, r.finalResult),
      listenOptions: SpeechListenOptions(
        localeId: 'hi_IN', // Hindi + Hinglish (English words come through too)
        listenFor: listenFor,
        pauseFor: pauseFor,
        partialResults: true,
        cancelOnError: true,
        listenMode: ListenMode.confirmation,
      ),
    );
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
  NavVoiceState state = NavVoiceState.idle;
  String heard = '';
  bool _ready = false;
  bool _foreground = true;
  bool _observing = false;
  List<String>? _pending;
  Timer? _restart;

  bool get adminOn => RemoteConfig.I.navigatorEnabled;
  bool get optedIn => Store.I.getString(kOptIn) == '1';
  bool get wakeOn => Store.I.getString(kWake) == '1';
  bool get available => adminOn && optedIn;

  void attach() {
    if (_observing) return;
    _observing = true;
    WidgetsBinding.instance.addObserver(this);
    RemoteConfig.I.addListener(_sync);
    _sync();
  }

  void _sync() {
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
    _restart = null;
    if (speech.listening) speech.stop();
    if (state != NavVoiceState.navigating) state = NavVoiceState.idle;
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
    if (!_ready) Toast.show('माइक की अनुमति नहीं मिली');
    _sync();
    return _ready;
  }

  Future<void> setWake(bool on) async {
    await Store.I.setString(kWake, on && available ? '1' : '0');
    if (!wakeOn) _halt();
    _sync();
  }

  Future<bool> _ensure() async => _ready || (_ready = await speech.init());

  /// Mic button: listen once for a command (no wake phrase needed).
  Future<void> listenOnce() async {
    if (!available || !_foreground || state == NavVoiceState.navigating) return;
    if (!await _ensure()) return Toast.show('माइक उपलब्ध नहीं');
    _restart?.cancel();
    if (speech.listening) await speech.stop();
    state = NavVoiceState.listening;
    heard = '';
    notifyListeners();
    await speech.listen(
      listenFor: const Duration(seconds: 8),
      pauseFor: const Duration(seconds: 3),
      onText: (t, done) {
        heard = t;
        notifyListeners();
        if (done) handle(t);
      },
      onDone: () {
        if (state == NavVoiceState.listening) state = NavVoiceState.idle;
        notifyListeners();
        if (wakeOn) _scheduleWake(const Duration(seconds: 2));
      },
    );
  }

  void _scheduleWake(Duration d) {
    _restart?.cancel();
    _restart = Timer(d, _wakeLoop);
  }

  /// Foreground wake phrase: short listening windows with a pause between them (battery).
  Future<void> _wakeLoop() async {
    if (!available || !wakeOn || !_foreground || state == NavVoiceState.navigating || state == NavVoiceState.listening) return;
    if (!await _ensure()) return;
    if (speech.listening) return;
    state = NavVoiceState.wake;
    notifyListeners();
    var armed = false;
    await speech.listen(
      listenFor: const Duration(seconds: 20),
      pauseFor: const Duration(seconds: 4),
      onText: (t, done) {
        if (!done) return;
        if (hasWakePhrase(t)) {
          final rest = stripWake(t);
          if (rest.isEmpty) {
            armed = true; // "Hey Granth" … then the command in the next window
          } else {
            heard = t;
            handle(t);
          }
        } else if (armed) {
          heard = t;
          handle(t);
        }
      },
      onDone: () {
        if (state == NavVoiceState.wake) state = NavVoiceState.idle;
        notifyListeners();
        if (armed && state != NavVoiceState.navigating) {
          listenOnce();
        } else {
          _scheduleWake(const Duration(seconds: 3));
        }
      },
    );
  }

  NavCatalog catalog() {
    final s = CatalogStore.I;
    final idx = Shelves.indexFor(s.granths);
    return NavCatalog.build(structure: Shelves.structure, granths: s.granths, topics: s.topics, placements: idx.placements);
  }

  /// Interprets [text] and opens the result step by step. Returns the result (tests).
  Future<NavResult> handle(String text) async {
    final r = catalog().interpret(text, pending: _pending);
    _pending = null;
    switch (r) {
      case NavIntent(:final target):
        await run(target);
      case NavClarify(:final choices):
        _pending = [for (final c in choices) c.id];
        Toast.show('${r.prompt} ${choices.map((c) => c.label).join(' / ')}');
      case NavUnknown():
        Toast.show(text.trim().isEmpty ? 'कुछ सुनाई नहीं दिया' : 'समझ नहीं आया: ${text.trim()}');
    }
    return r;
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
        child: RepaintBoundary(
          child: AnimatedBuilder(
            animation: _c,
            builder: (context, _) => _at == null || !_c.isAnimating && _c.value == 1 ? const SizedBox.expand() : CustomPaint(size: Size.infinite, painter: _RipplePainter(_at!, _c.value)),
          ),
        ),
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
            onTap: v.listenOnce,
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
