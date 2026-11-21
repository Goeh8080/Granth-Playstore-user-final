/// t421 (§33 handoff) — admin-managed icons + videos from the PUBLIC media manifest:
/// `GET https://granth-admin.vedpuran8090.workers.dev/media/manifest.json` (schema 1, ETag / 304,
/// max-age 300). t430 additive contract: `active_pack` + `packs: [{id, name, builtin}]`; icons and
/// videos carry `pack` (only the active pack's are used; an item without `pack` is always used);
/// targets `folder:<path>`, `key:<icon_key>`, `slot:<name>` and `slot:page:<route>`; video
/// placement `icon`. `p_builtin` with no overrides = empty lists = the bundled 56 vectors. Optional and decorative: any failure keeps the built-in v3 icons and
/// the bundled videos. The last good manifest is kept (offline starts use it). Contract:
/// docs/REMOTE_MEDIA.md.
library;

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dio/dio.dart';
import 'package:flutter/foundation.dart';

import 'storage.dart';

const String kMediaManifestUrl = String.fromEnvironment('MEDIA_MANIFEST_URL', defaultValue: 'https://granth-admin.vedpuran8090.workers.dev/media/manifest.json');

/// Placements the app knows (others are kept but unused).
const Set<String> kMediaPlacements = {'home', 'granths', 'settings', 'login', 'splash', 'dashboard', 'folder', 'icon', 'chooser_folders', 'chooser_list'};

/// Pages a `slot:page:<route>` target can name.
const Set<String> kPageSlots = {'home', 'granths', 'settings', 'login', 'splash', 'dashboard'};

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

  /// `folder` / `icon` placements loop unless the server sends `loop: false`; the others
  /// (chooser, page backgrounds) play once (muted) and hold the last frame unless `loop: true`.
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

final _target = RegExp(r'^(folder|slot|key):[a-z0-9][a-z0-9_/-]{0,80}$');
final _pageSlot = RegExp(r'^slot:page:([a-z]+)$');

/// A target the app understands, or null (`''` / unknown = library only, ignored).
String? parseMediaTarget(Object? t) {
  if (t is! String) return null;
  final v = t.trim();
  final page = _pageSlot.firstMatch(v);
  if (page != null) return kPageSlots.contains(page.group(1)) ? v : null;
  return _target.hasMatch(v) ? v : null;
}

class MediaPack {
  const MediaPack({required this.id, required this.name, this.builtin = false});
  final String id;
  final String name;
  final bool builtin;
}

/// Parsed manifest: icons by target (newest `updated_at` wins), videos sorted by `position`.
class ParsedManifest {
  const ParsedManifest({this.revision = 0, this.icons = const {}, this.videos = const [], this.activePack, this.packs = const []});
  final int revision;
  final String? activePack;
  final List<MediaPack> packs;
  final Map<String, ManifestIcon> icons;
  final List<ManifestVideo> videos;
  static const empty = ParsedManifest();
}

/// Tolerant: anything malformed is skipped; a non-map → null (keep the last good one).
ParsedManifest? parseMediaManifest(Object? raw) {
  if (raw is! Map) return null;
  final ap = raw['active_pack'];
  final active = ap is String && ap.trim().isNotEmpty ? ap.trim() : null;
  final packs = <MediaPack>[
    for (final p in raw['packs'] is List ? raw['packs'] as List : const [])
      if (p is Map && p['id'] is String && (p['id'] as String).isNotEmpty) MediaPack(id: p['id'] as String, name: '${p['name'] ?? p['id']}', builtin: p['builtin'] == true),
  ];
  // The server already filters to the active pack; this is a second guard. No `pack` on an
  // item (older manifests) or no `active_pack` = always used.
  bool inPack(Map e) {
    final p = e['pack'];
    return active == null || p is! String || p.isEmpty || p == active;
  }

  final icons = <String, ManifestIcon>{};
  for (final e in raw['icons'] is List ? raw['icons'] as List : const []) {
    if (e is! Map || e['active'] == false || !inPack(e)) continue;
    final t = parseMediaTarget(e['target']);
    if (t == null) continue; // '' = library only (ignored)
    final mime = '${e['mime'] ?? ''}';
    final url = _https(e['url'], exts: const {'png', 'webp', 'jpg', 'jpeg'});
    if (url == null || (mime.isNotEmpty && !const {'image/png', 'image/webp', 'image/jpeg'}.contains(mime))) continue;
    final at = '${e['updated_at'] ?? ''}';
    final old = icons[t];
    if (old == null || at.compareTo(old.updatedAt) >= 0) icons[t] = ManifestIcon(target: t, url: url, updatedAt: at);
  }
  final videos = <ManifestVideo>[];
  for (final e in raw['videos'] is List ? raw['videos'] as List : const []) {
    if (e is! Map || e['active'] == false || !inPack(e)) continue;
    final placement = '${e['placement'] ?? ''}';
    final url = _https(e['url']);
    if (url == null || !kMediaPlacements.contains(placement)) continue;
    final t = parseMediaTarget(e['target']);
    final tile = placement == 'folder' || placement == 'icon';
    videos.add(ManifestVideo(
      url: url,
      provider: '${e['provider'] ?? 'direct'}',
      placement: placement,
      target: t,
      posterUrl: _https(e['poster_url'], exts: const {'png', 'webp', 'jpg', 'jpeg'}),
      loop: tile ? e['loop'] != false : e['loop'] == true,
      position: e['position'] is num ? (e['position'] as num).toInt() : 0,
    ));
  }
  videos.sort((a, b) => a.position.compareTo(b.position));
  final rev = raw['revision'];
  return ParsedManifest(revision: rev is num ? rev.toInt() : 0, icons: icons, videos: videos, activePack: active, packs: packs);
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

  /// Tile video (`folder` / `icon` placement) for exactly [target].
  ManifestVideo? _tileVideo(String target) {
    for (final v in current.videos) {
      if ((v.placement == 'folder' || v.placement == 'icon') && v.target == target && v.playable) return v;
    }
    return null;
  }

  /// Folder logo resolution (contract): `folder:<path>` wins, else `key:<that folder's icon
  /// key>`, else null (= the bundled vector). Video before image for the same target; the image
  /// of the same target is the video's poster when the server sends no `poster_url`.
  ({String? image, ManifestVideo? video, String? poster}) logoFor({String? folderPath, String? iconKey}) {
    for (final t in [if (folderPath != null && folderPath.isNotEmpty) 'folder:$folderPath', if (iconKey != null && iconKey.isNotEmpty) 'key:$iconKey']) {
      final v = _tileVideo(t);
      final img = iconFor(t);
      if (v != null) return (image: img, video: v, poster: v.posterUrl ?? img);
      if (img != null) return (image: img, video: null, poster: null);
    }
    return (image: null, video: null, poster: null);
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
