/// t421 (§33 handoff) — admin-managed icons + videos from the PUBLIC media manifest:
/// `GET https://granth.wnmsolutions.com/media/manifest.json` (ETag / 304; empty lists until the
/// server is deployed). Optional and decorative: any failure keeps the built-in v3 icons and
/// the bundled videos. The last good manifest is kept (offline starts use it). Contract:
/// docs/REMOTE_MEDIA.md.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'storage.dart';

const String kMediaManifestUrl = String.fromEnvironment('MEDIA_MANIFEST_URL', defaultValue: 'https://granth.wnmsolutions.com/media/manifest.json');

/// Placements the app knows (others are kept but unused).
const Set<String> kMediaPlacements = {'home', 'granths', 'settings', 'login', 'splash', 'dashboard', 'folder', 'chooser_folders', 'chooser_list'};

/// Providers `video_player` can play directly (youtube / google_drive are skipped for tile /
/// background use: poster or nothing).
const Set<String> kPlayableProviders = {'direct', 'firebase_storage', 'r2'};

class ManifestIcon {
  const ManifestIcon({required this.target, required this.url, this.updatedAt = ''});
  final String target;
  final String url;
  final String updatedAt;
}

class ManifestVideo {
  const ManifestVideo({required this.url, required this.provider, required this.placement, this.target, this.posterUrl, this.loop = false, this.position = 0});
  final String url;
  final String provider;
  final String placement;
  final String? target;
  final String? posterUrl;

  /// Default: play once (muted) and hold the last frame; loop only when true.
  final bool loop;
  final int position;
  bool get playable => kPlayableProviders.contains(provider);
}

String? _https(Object? v, {Set<String>? exts}) {
  if (v is! String) return null;
  final s = v.trim();
  if (s.isEmpty || s.length > 1000) return null;
  final u = Uri.tryParse(s);
  if (u == null || u.scheme != 'https' || u.host.isEmpty) return null;
  if (exts != null) {
    final p = u.path.toLowerCase();
    final dot = p.lastIndexOf('.');
    if (dot < 0 || !exts.contains(p.substring(dot + 1))) return null;
  }
  return s;
}

final _target = RegExp(r'^(folder|slot):[a-z0-9][a-z0-9_/-]{0,80}$');

/// Parsed manifest: icons by target (newest `updated_at` wins), videos sorted by `position`.
class ParsedManifest {
  const ParsedManifest({this.revision = 0, this.icons = const {}, this.videos = const []});
  final int revision;
  final Map<String, ManifestIcon> icons;
  final List<ManifestVideo> videos;
  static const empty = ParsedManifest();
}

/// Tolerant: anything malformed is skipped; a non-map → null (keep the last good one).
ParsedManifest? parseMediaManifest(Object? raw) {
  if (raw is! Map) return null;
  final icons = <String, ManifestIcon>{};
  for (final e in raw['icons'] is List ? raw['icons'] as List : const []) {
    if (e is! Map || e['active'] == false) continue;
    final t = e['target'];
    if (t is! String || !_target.hasMatch(t)) continue; // '' = library only (ignored)
    final mime = '${e['mime'] ?? ''}';
    final url = _https(e['url'], exts: const {'png', 'webp', 'jpg', 'jpeg'});
    if (url == null || (mime.isNotEmpty && !const {'image/png', 'image/webp', 'image/jpeg'}.contains(mime))) continue;
    final at = '${e['updated_at'] ?? ''}';
    final old = icons[t];
    if (old == null || at.compareTo(old.updatedAt) >= 0) icons[t] = ManifestIcon(target: t, url: url, updatedAt: at);
  }
  final videos = <ManifestVideo>[];
  for (final e in raw['videos'] is List ? raw['videos'] as List : const []) {
    if (e is! Map || e['active'] == false) continue;
    final placement = '${e['placement'] ?? ''}';
    final url = _https(e['url']);
    if (url == null || !kMediaPlacements.contains(placement)) continue;
    final t = e['target'];
    videos.add(ManifestVideo(
      url: url,
      provider: '${e['provider'] ?? 'direct'}',
      placement: placement,
      target: t is String && _target.hasMatch(t) ? t : null,
      posterUrl: _https(e['poster_url'], exts: const {'png', 'webp', 'jpg', 'jpeg'}),
      loop: e['loop'] == true,
      position: e['position'] is num ? (e['position'] as num).toInt() : 0,
    ));
  }
  videos.sort((a, b) => a.position.compareTo(b.position));
  final rev = raw['revision'];
  return ParsedManifest(revision: rev is num ? rev.toInt() : 0, icons: icons, videos: videos);
}

class MediaManifest extends ChangeNotifier {
  MediaManifest({Dio? dio, this.url = kMediaManifestUrl}) : _dio = dio;
  static MediaManifest I = MediaManifest();

  static const kBody = 'granth-media-manifest';
  static const kEtag = 'granth-media-manifest-etag';

  final String url;
  Dio? _dio;
  ParsedManifest _m = ParsedManifest.empty;
  bool _loaded = false;
  Future<void>? _busy;
  DateTime? _last;

  ParsedManifest get current {
    if (!_loaded) _loadSaved();
    return _m;
  }

  void _loadSaved() {
    _loaded = true;
    try {
      final raw = Store.I.getString(kBody);
      if (raw != null && raw.isNotEmpty) _m = parseMediaManifest(jsonDecode(raw)) ?? ParsedManifest.empty;
    } catch (_) {}
  }

  /// Admin icon for `folder:<id>` / `folder:<group>/<sub>` / `slot:<name>`; null = built-in.
  String? iconFor(String target) => current.icons[target]?.url;

  /// First playable video for [placement] (and [target] when given; null target = general).
  ManifestVideo? videoFor(String placement, {String? target}) {
    for (final v in current.videos) {
      if (v.placement == placement && v.target == target && v.playable) return v;
    }
    return null;
  }

  /// Fetches with If-None-Match (at most every 5 minutes). Never throws.
  Future<void> refresh({bool force = false}) => _busy ??= _refresh(force).whenComplete(() => _busy = null);

  Future<void> _refresh(bool force) async {
    if (!_loaded) _loadSaved();
    if (_dio == null && !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST')) return; // no network in tests
    final now = DateTime.now();
    if (!force && _last != null && now.difference(_last!) < const Duration(minutes: 5)) return;
    _last = now;
    try {
      final dio = _dio ??= Dio(BaseOptions(connectTimeout: const Duration(seconds: 8), receiveTimeout: const Duration(seconds: 10)));
      final etag = Store.I.getString(kEtag);
      final r = await dio.get<String>(url,
          options: Options(
            responseType: ResponseType.plain,
            headers: {if (etag != null && etag.isNotEmpty) 'If-None-Match': etag},
            validateStatus: (s) => s == 200 || s == 304,
          ));
      if (r.statusCode == 304) return;
      final text = r.data ?? '';
      final p = parseMediaManifest(jsonDecode(text));
      if (p == null) return;
      _m = p;
      await Store.I.setString(kBody, text);
      final e = r.headers.value('etag');
      if (e != null) await Store.I.setString(kEtag, e);
      notifyListeners();
    } catch (_) {}
  }

  @visibleForTesting
  void debugSet(ParsedManifest m) {
    _loaded = true;
    _m = m;
    notifyListeners();
  }
}
