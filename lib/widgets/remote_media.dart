import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';
import 'package:path_provider/path_provider.dart';
import 'package:video_player/video_player.dart';

import '../state/ui_prefs.dart';

/// t421 — admin-uploaded folder icons / videos and the bundled brand loops.
///
/// * [MediaCache]: downloads an https file once into the app's support folder
///   (`remote_media/`), so it works offline afterwards. Never throws (null = use the fallback).
/// * [LoopVideo]: a muted, looping, lazily created video that plays only while it is on
///   screen (paused when scrolled away, in another tab, under a page or with the app in the
///   background). Shows [LoopVideo.fallback] while loading, offline or on any error.
/// * [RemoteIcon]: a folder picture — the admin's video, else the admin's image
///   (png/webp/jpg/svg), else the painted v3 icon ([RemoteIcon.fallback]).
///
/// Contract: docs/REMOTE_MEDIA.md.

/// True under `flutter test`: no platform video / disk cache there (the fallback is shown).
final bool _inTest = !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

class MediaCache {
  MediaCache._();
  static final MediaCache I = MediaCache._();

  /// A single file never exceeds this (a folder icon video should be ~0.5 MB).
  static const int maxBytes = 16 * 1024 * 1024;

  final Map<String, Future<File?>> _inflight = {};
  final Map<String, File> _ready = {};
  Directory? _dir;

  /// Stable file name for [url] (FNV-1a 64 of the URL + its extension).
  static String keyFor(String url) {
    var h = 0xcbf29ce484222325;
    for (final b in utf8.encode(url)) {
      h ^= b;
      h = (h * 0x100000001b3) & 0xFFFFFFFFFFFFFFFF;
    }
    final path = Uri.tryParse(url)?.path.toLowerCase() ?? '';
    final dot = path.lastIndexOf('.');
    final ext = dot >= 0 && path.length - dot <= 5 ? path.substring(dot) : '';
    return '${h.toUnsigned(64).toRadixString(16)}$ext';
  }

  /// Tests / local renders: treat [f] as the downloaded copy of [url].
  @visibleForTesting
  void debugPut(String url, File f) => _ready[url] = f;

  /// Already on disk this session (no async gap → no fallback flash on rebuilds).
  File? readySync(String url) => _ready[url];

  Future<File?> get(String url) {
    final f = _ready[url];
    if (f != null) return Future.value(f);
    if (_inTest) return Future.value(null);
    return _inflight.putIfAbsent(url, () => _load(url).whenComplete(() => _inflight.remove(url)));
  }

  Future<File?> _load(String url) async {
    try {
      final dir = _dir ??= Directory('${(await getApplicationSupportDirectory()).path}/remote_media');
      if (!await dir.exists()) await dir.create(recursive: true);
      final f = File('${dir.path}/${keyFor(url)}');
      if (await f.exists() && await f.length() > 0) return _ready[url] = f;
      final r = await Dio(BaseOptions(connectTimeout: const Duration(seconds: 15), receiveTimeout: const Duration(seconds: 60)))
          .get<List<int>>(url, options: Options(responseType: ResponseType.bytes));
      final b = r.data;
      if (b == null || b.isEmpty || b.length > maxBytes) return null;
      final tmp = File('${f.path}.part');
      await tmp.writeAsBytes(b, flush: true);
      await tmp.rename(f.path);
      return _ready[url] = f;
    } catch (_) {
      return null;
    }
  }
}

/// A muted video ([url] wins; if it fails to load / play, the bundled [asset] is tried, then
/// [fallback]) that fills its box ([fit]). [loop] = loop forever; otherwise it plays once and
/// holds the last frame (the manifest default). Reduced motion / animations "कम" = a still frame.
class LoopVideo extends StatefulWidget {
  const LoopVideo({super.key, this.asset, this.url, required this.fallback, this.fit = BoxFit.cover, this.loop = true});
  final String? asset;
  final String? url;
  final Widget fallback;
  final BoxFit fit;
  final bool loop;

  /// At most this many players exist at once (the rest show their fallback).
  static const int maxLive = 6;
  static int _live = 0;

  @override
  State<LoopVideo> createState() => _LoopVideoState();
}

class _LoopVideoState extends State<LoopVideo> with WidgetsBindingObserver {
  VideoPlayerController? _c;
  bool _ready = false, _failed = false, _visible = false, _foreground = true, _tickers = true, _calm = false;
  bool _counted = false, _checkQueued = false, _urlFailed = false, _ended = false;
  ScrollPosition? _pos;

  String? get _src => (widget.url?.isNotEmpty ?? false) && !_urlFailed ? widget.url : widget.asset;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickers = TickerMode.valuesOf(context).enabled;
    _calm = !UiPrefs.I.animations || MediaQuery.disableAnimationsOf(context);
    final pos = Scrollable.maybeOf(context)?.position;
    if (!identical(pos, _pos)) {
      _pos?.removeListener(_queueCheck);
      _pos = pos?..addListener(_queueCheck);
    }
    _queueCheck();
  }

  @override
  void didUpdateWidget(LoopVideo old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url || old.asset != widget.asset) {
      _drop();
      _failed = false;
      _urlFailed = false;
      _ended = false;
      _queueCheck();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _foreground = state == AppLifecycleState.resumed;
    _apply();
  }

  void _queueCheck() {
    if (_checkQueued || !mounted) return;
    _checkQueued = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _checkQueued = false;
      _check();
    });
  }

  void _check() {
    if (!mounted) return;
    var vis = false;
    final ro = context.findRenderObject();
    if (_tickers && ro is RenderBox && ro.attached && ro.hasSize) {
      final r = ro.localToGlobal(Offset.zero) & ro.size;
      vis = r.overlaps(Offset.zero & MediaQuery.sizeOf(context));
    }
    _visible = vis;
    // t430: a looping tile that scrolled off screen gives its decoder back (at most
    // [maxLive] at once); it starts again from the cached file when it comes back.
    if (!vis && widget.loop && _c != null && _ready) {
      _drop();
      if (mounted) setState(() {});
      return;
    }
    if (vis && _c == null && !_failed) _init();
    _apply();
  }

  Future<void> _init() async {
    final src = _src;
    if (src == null || _inTest || LoopVideo._live >= LoopVideo.maxLive) return;
    LoopVideo._live++;
    _counted = true;
    final opts = VideoPlayerOptions(mixWithOthers: true);
    VideoPlayerController c;
    if (src.startsWith('http')) {
      final f = await MediaCache.I.get(src);
      if (!mounted || _src != src) {
        _release();
        return;
      }
      c = f != null ? VideoPlayerController.file(f, videoPlayerOptions: opts) : VideoPlayerController.networkUrl(Uri.parse(src), videoPlayerOptions: opts);
    } else {
      c = VideoPlayerController.asset(src, videoPlayerOptions: opts);
    }
    _c = c;
    try {
      await c.initialize();
      await c.setVolume(0);
      await c.setLooping(widget.loop);
      c.addListener(() => _watch(c, src));
      if (!mounted || !identical(_c, c)) return;
      // still frame: the last frame for play-once clips, a late frame for loops
      if (_calm) await c.seekTo(widget.loop ? c.value.duration * 0.75 : c.value.duration - const Duration(milliseconds: 100));
      setState(() => _ready = true);
      _apply();
    } catch (_) {
      if (identical(_c, c)) {
        _drop();
        if (!mounted) return;
        if (src.startsWith('http') && (widget.asset?.isNotEmpty ?? false)) {
          // the admin's file failed: the bundled clip instead
          _urlFailed = true;
          setState(() {});
          _queueCheck();
        } else {
          setState(() => _failed = true);
        }
      }
    }
  }

  /// Play-once: remember the end (the last frame stays on screen; never restarted). A play
  /// error = the same fallback as a load error (bundled clip, then the still / painted one).
  void _watch(VideoPlayerController c, String src) {
    if (!identical(_c, c)) return;
    final v = c.value;
    if (v.hasError) {
      scheduleMicrotask(() {
        if (!identical(_c, c)) return;
        _drop();
        if (!mounted) return;
        if (src.startsWith('http') && (widget.asset?.isNotEmpty ?? false)) {
          _urlFailed = true;
          setState(() {});
          _queueCheck();
        } else {
          setState(() => _failed = true);
        }
      });
      return;
    }
    if (!widget.loop && !_ended && v.isInitialized && v.duration > Duration.zero && v.position >= v.duration - const Duration(milliseconds: 80) && !v.isPlaying) _ended = true;
  }

  void _apply() {
    final c = _c;
    if (c == null || !_ready) return;
    final play = _visible && _foreground && _tickers && !_calm && !_ended;
    if (play && !c.value.isPlaying) {
      c.play();
    } else if (!play && c.value.isPlaying) {
      c.pause();
    }
  }

  void _release() {
    if (_counted) {
      _counted = false;
      LoopVideo._live--;
    }
  }

  void _drop() {
    final c = _c;
    _c = null;
    _ready = false;
    c?.dispose();
    _release();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pos?.removeListener(_queueCheck);
    _drop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final c = _c;
    final on = _ready && c != null && !_failed && c.value.isInitialized;
    final size = on ? c.value.size : Size.zero;
    return AnimatedSwitcher(
      duration: const Duration(milliseconds: 260),
      layoutBuilder: (cur, prev) => Stack(fit: StackFit.passthrough, alignment: Alignment.center, children: [...prev, ?cur]),
      child: on && size.width > 0 && size.height > 0
          ? ClipRect(
              key: const ValueKey('loop-video-on'),
              child: FittedBox(fit: widget.fit, child: SizedBox(width: size.width, height: size.height, child: VideoPlayer(c))),
            )
          : KeyedSubtree(key: const ValueKey('loop-video-fallback'), child: widget.fallback),
    );
  }
}

/// A folder picture: admin [videoUrl] (muted, play once + hold last frame unless [loop]) ›
/// admin [imageUrl] (PNG/WebP) › [fallback] (the painted v3 icon, also shown while loading /
/// offline / on error). [posterUrl] is shown while the video loads.
class RemoteIcon extends StatelessWidget {
  const RemoteIcon({super.key, this.imageUrl, this.videoUrl, this.posterUrl, this.loop = false, required this.size, required this.fallback});
  final String? imageUrl;
  final String? videoUrl;
  final String? posterUrl;
  final bool loop;
  final double size;
  final Widget fallback;

  @override
  Widget build(BuildContext context) {
    final img = imageUrl;
    final vid = videoUrl;
    if ((img == null || img.isEmpty) && (vid == null || vid.isEmpty)) return fallback;
    final pic = img != null && img.isNotEmpty ? img : posterUrl;
    final still = pic != null && pic.isNotEmpty ? _NetImage(url: pic, size: size, fallback: fallback) : fallback;
    if (vid == null || vid.isEmpty) return still;
    // reduced motion: the still only (no video download) when there is one
    if (pic != null && pic.isNotEmpty && (!UiPrefs.I.animations || MediaQuery.disableAnimationsOf(context))) return still;
    return SizedBox.square(
      dimension: size,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(size * 0.24),
        child: LoopVideo(url: vid, loop: loop, fallback: still),
      ),
    );
  }
}

class _NetImage extends StatefulWidget {
  const _NetImage({required this.url, required this.size, required this.fallback});
  final String url;
  final double size;
  final Widget fallback;
  @override
  State<_NetImage> createState() => _NetImageState();
}

class _NetImageState extends State<_NetImage> {
  File? _f;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_NetImage old) {
    super.didUpdateWidget(old);
    if (old.url != widget.url) {
      _f = null;
      _load();
    }
  }

  void _load() {
    final url = widget.url;
    _f = MediaCache.I.readySync(url);
    if (_f != null) return;
    MediaCache.I.get(url).then((f) {
      if (mounted && f != null && widget.url == url) setState(() => _f = f);
    });
  }

  @override
  Widget build(BuildContext context) {
    final f = _f;
    if (f == null) return widget.fallback;
    final s = widget.size;
    final Widget pic = f.path.endsWith('.svg')
        ? SvgPicture.file(f, width: s, height: s, fit: BoxFit.contain, placeholderBuilder: (_) => widget.fallback)
        : Image.file(
            f,
            width: s,
            height: s,
            fit: BoxFit.contain,
            cacheWidth: (s * MediaQuery.devicePixelRatioOf(context)).round().clamp(32, 1024).toInt(),
            gaplessPlayback: true,
            errorBuilder: (_, _, _) => widget.fallback,
          );
    return SizedBox.square(dimension: s, child: ClipRRect(borderRadius: BorderRadius.circular(s * 0.22), child: pic));
  }
}
