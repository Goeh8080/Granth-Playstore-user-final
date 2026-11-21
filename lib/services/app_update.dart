/// t306: admin-pushed "नया अपडेट आया है" alert. Read from the signed config's optional
/// top-level `appUpdate` object (backend shape; snake_case `app_update` / `latest_version` etc.
/// also accepted). The admin worker serves APKs at `GET /apk/<id>.apk`:
///
/// ```json
/// "appUpdate": {"latestVersion": "1.0.1", "message": "नया अपडेट आया है, डाउनलोड करें",
///               "playUrl": "https://play.google.com/store/apps/details?id=com.granth.app.user",
///               "apkUrl": "https://granth-admin.vedpuran8090.workers.dev/apk/<id>.apk", "force": false}
/// ```
/// t421 (§33 handoff): ALWAYS closable (✕ + "बाद में", barrier-dismissible). Optional
/// `reshow: true` = show on every start until updated; optional `minVersion` (x.y.z): a build
/// below it behaves as `reshow:true` (still closable, never a block). A legacy `force: true`
/// means `reshow: true`.
/// Shown only when it is newer than this build. Older builds ignore the key. Download offers
/// Play Store (market:// → web fallback) or the APK link opened in the BROWSER (no
/// REQUEST_INSTALL_PACKAGES — stays Play-compliant). Also listed in the Dashboard notifications.
library;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../config.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/overlays.dart';
import '../widgets/pdf_sheets.dart' show StyleOption;
import 'api.dart' show kPackageId, kPlayStoreUrl;
import 'notification_log.dart';
import 'remote_config.dart';
import 'storage.dart';

class AppUpdateInfo {
  const AppUpdateInfo({required this.latestVersion, this.latestBuild, this.message = '', this.playUrl, this.apkUrl, this.force = false, this.reshow = false, this.minVersion});
  final String latestVersion;
  final int? latestBuild;
  final String message;
  final String? playUrl;
  final String? apkUrl;
  /// Legacy server flag; t421: only means [reshow] now (the dialog is always closable).
  final bool force;

  /// `reshow: true`: shown on every start until the app is updated.
  final bool reshow;

  /// `minVersion` (plain x.y.z): builds below it get the popup on every start (closable).
  final String? minVersion;

  /// Show on every start (reshow, legacy force, or this build below [minVersion]).
  bool get everyStart => reshow || force || (minVersion != null && compareVersions(kAppVersion, minVersion!) < 0);

  String get key => '$latestVersion+${latestBuild ?? ''}';

  /// Newer than this app ([kAppVersion] / [kBuildNumber])?
  bool get isNewer => compareVersions(latestVersion, kAppVersion) > 0 || (latestBuild != null && latestBuild! > kBuildNumber && compareVersions(latestVersion, kAppVersion) >= 0);

  @override
  bool operator ==(Object other) => other is AppUpdateInfo && other.key == key && other.message == message && other.playUrl == playUrl && other.apkUrl == apkUrl && other.force == force && other.reshow == reshow && other.minVersion == minVersion;
  @override
  int get hashCode => Object.hash(key, message, playUrl, apkUrl, force, reshow, minVersion);
}

/// `1.0.10` > `1.0.9`; non-numbers count as 0.
int compareVersions(String a, String b) {
  List<int> p(String s) => s.split('+').first.split('.').map((x) => int.tryParse(x.trim()) ?? 0).toList();
  final x = p(a), y = p(b);
  for (var i = 0; i < 3; i++) {
    final d = (i < x.length ? x[i] : 0) - (i < y.length ? y[i] : 0);
    if (d != 0) return d.sign;
  }
  return 0;
}

String? _https(Object? v) {
  if (v is! String) return null;
  final u = Uri.tryParse(v.trim());
  return u != null && u.scheme == 'https' && u.host.isNotEmpty && v.length <= 500 ? v.trim() : null;
}

/// Tolerant parser: anything missing / malformed → null (no alert).
AppUpdateInfo? parseAppUpdate(Object? raw) {
  if (raw is! Map) return null;
  final j = raw.cast<String, dynamic>();
  final v = j['latest_version'] ?? j['latestVersion'];
  if (v is! String || !RegExp(r'^\d+(\.\d+){0,2}$').hasMatch(v.trim())) return null;
  final b = j['latest_build'] ?? j['latestBuild'];
  final m = j['message'];
  final mv = j['min_version'] ?? j['minVersion'];
  final minOk = mv is String && RegExp(r'^\d+(\.\d+){0,2}$').hasMatch(mv.trim()) && compareVersions(mv.trim(), v.trim()) <= 0;
  return AppUpdateInfo(
    latestVersion: v.trim(),
    latestBuild: b is num ? b.toInt() : null,
    message: m is String && m.trim().isNotEmpty && m.length <= 300 ? m.trim() : 'नया अपडेट आया है, डाउनलोड करें',
    playUrl: _https(j['play_url'] ?? j['playUrl']),
    apkUrl: _https(j['apk_url'] ?? j['apkUrl']),
    force: (j['force'] ?? false) == true,
    reshow: (j['reshow'] ?? false) == true,
    minVersion: minOk ? (mv as String).trim() : null,
  );
}

class AppUpdate {
  AppUpdate._();
  static final AppUpdate I = AppUpdate._();
  static const kShown = 'granth-update-shown';

  GlobalKey<NavigatorState>? navigatorKey;
  bool _open = false;
  bool _attached = false;

  void attach(GlobalKey<NavigatorState> key) {
    navigatorKey = key;
    if (_attached) return;
    _attached = true;
    RemoteConfig.I.addListener(check);
    WidgetsBinding.instance.addPostFrameCallback((_) => check());
  }

  AppUpdateInfo? get pending {
    final u = RemoteConfig.I.appUpdate;
    return u != null && u.isNewer ? u : null;
  }

  /// Logs the notification and shows the alert once per version (every start with reshow /
  /// below minVersion / legacy force).
  void check() {
    final u = pending;
    if (u == null) return;
    NotificationLog.I.record(id: 'update:${u.key}', kind: 'app_update', title: 'नया अपडेट (${u.latestVersion})', body: u.message);
    if (!u.everyStart && Store.I.getString(kShown) == u.key) return;
    Store.I.setString(kShown, u.key);
    prompt();
  }

  Future<void> prompt() async {
    final u = pending;
    final ctx = navigatorKey?.currentContext;
    if (u == null || ctx == null || _open) return;
    _open = true;
    try {
      // t421: always closable (Goutam's rule) — never a blocking dialog.
      final go = await showPop<bool>(ctx, (c) => _UpdateSheet(info: u), dismissible: true);
      if (go != true) return;
      final ctx2 = navigatorKey?.currentContext;
      if (ctx2 == null || !ctx2.mounted) return;
      final how = await showPop<String>(ctx2, (c) => _HowSheet(info: u));
      if (how == 'play') await openPlay(u);
      if (how == 'apk' && u.apkUrl != null) await launchUrl(Uri.parse(u.apkUrl!), mode: LaunchMode.externalApplication);
    } finally {
      _open = false;
    }
  }

  static Future<void> openPlay(AppUpdateInfo u) async {
    try {
      if (await launchUrl(Uri.parse('market://details?id=$kPackageId'), mode: LaunchMode.externalApplication)) return;
    } catch (_) {}
    await launchUrl(Uri.parse(u.playUrl ?? kPlayStoreUrl), mode: LaunchMode.externalApplication);
  }
}

class _UpdateSheet extends StatelessWidget {
  const _UpdateSheet({required this.info});
  final AppUpdateInfo info;
  @override
  Widget build(BuildContext context) => SheetCard(key: const ValueKey('app-update-sheet'), children: [
        Row(children: [
          Expanded(child: Text('नया अपडेट', style: GText.display(size: 24, color: GColors.maroon))),
          IconButton(
            key: const ValueKey('app-update-close'),
            tooltip: 'बंद करें',
            icon: const Icon(Icons.close_rounded, color: GColors.maroon),
            onPressed: () => Navigator.pop(context, false),
          ),
        ]),
        const SizedBox(height: 8),
        Text(info.message, style: GText.sans(size: 15.5, color: GColors.text, height: 1.5)),
        const SizedBox(height: 4),
        Text('संस्करण ${info.latestVersion} · अभी $kAppVersion', style: GText.sans(size: 12.5, color: GColors.muted)),
        const SizedBox(height: 14),
        Row(children: [
          Expanded(child: SheetButton(key: const ValueKey('app-update-later'), label: 'बाद में', onTap: () => Navigator.pop(context, false))),
          const SizedBox(width: 10),
          Expanded(child: SheetButton(key: const ValueKey('app-update-download'), label: 'डाउनलोड', primary: true, onTap: () => Navigator.pop(context, true))),
        ]),
      ]);
}

class _HowSheet extends StatelessWidget {
  const _HowSheet({required this.info});
  final AppUpdateInfo info;
  @override
  Widget build(BuildContext context) => SheetCard(key: const ValueKey('app-update-how'), children: [
        SheetHead(title: 'कहाँ से डाउनलोड करें', onBack: () => Navigator.pop(context)),
        StyleOption(key: const ValueKey('app-update-play'), title: 'Play Store', hint: 'सबसे सुरक्षित — Play Store में ऐप का पेज खुलेगा', on: false, onTap: () => Navigator.pop(context, 'play')),
        if (info.apkUrl != null) ...[
          const SizedBox(height: 8),
          StyleOption(key: const ValueKey('app-update-apk'), title: 'APK', hint: 'ब्राउज़र में APK डाउनलोड होगा, फिर उसे खोलकर इंस्टॉल करें', on: false, onTap: () => Navigator.pop(context, 'apk')),
        ],
      ]);
}
