// t306: admin-pushed update alert (optional `app_update` config key).
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/services/app_update.dart';
import 'package:granthprabandhan/services/notification_log.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'helpers.dart';

void main() {
  setUp(() async {
    await setUpApp();
    NotificationLog.I.debugReset();
    RemoteConfig.I.appUpdate = null;
  });
  tearDown(() => RemoteConfig.I.appUpdate = null);

  test('parser is tolerant: snake + camel case, bad input → null, https only', () {
    expect(parseAppUpdate(null), isNull);
    expect(parseAppUpdate('x'), isNull);
    expect(parseAppUpdate({'message': 'no version'}), isNull);
    expect(parseAppUpdate({'latest_version': 'v2'}), isNull);
    final a = parseAppUpdate({'latestVersion': '1.0.1', 'message': 'नया अपडेट', 'playUrl': 'https://play.google.com/x', 'apkUrl': 'http://evil/x.apk', 'force': 'yes'})!;
    expect(a.latestVersion, '1.0.1');
    expect(a.apkUrl, isNull, reason: 'non-https APK links are dropped');
    expect(a.playUrl, 'https://play.google.com/x');
    expect(a.force, isFalse, reason: 'force only when exactly true');
    final b = parseAppUpdate({'latest_version': '1.0.0', 'latest_build': 2, 'apk_url': 'https://x.dev/a.apk', 'force': true})!;
    expect(b.isNewer, isTrue, reason: 'same name, higher build');
    expect(b.message, isNotEmpty);
    expect(parseAppUpdate({'latest_version': '1.0.0'})!.isNewer, isFalse);
    expect(parseAppUpdate({'latest_version': '0.9.9', 'latest_build': 5})!.isNewer, isFalse);
  });

  test('backend config shapes: snake first then camel alias; defaults when omitted', () {
    expect(parseGranthViewMode({'granthViewMode': 'list'}), 'list');
    expect(parseGranthViewMode({'granth_view_mode': 'folders', 'granthViewMode': 'list'}), 'folders');
    expect(parseGranthViewMode({'granth_view_mode': 'user_choice'}), isNull);
    expect(parseGranthViewMode({}), isNull);
    expect(parseNavigatorEnabled({'navigator_enabled': true}, null), isTrue);
    expect(parseNavigatorEnabled({'navigatorEnabled': true}, null), isTrue);
    expect(parseNavigatorEnabled({'navigator_enabled': false, 'navigatorEnabled': true}, null), isFalse);
    expect(parseNavigatorEnabled(null, {'navigator_enabled': true}), isTrue, reason: 'legacy flags location');
    expect(parseNavigatorEnabled({}, {}), isFalse);
    final u = parseAppUpdate({'latestVersion': '1.0.1', 'message': 'm', 'playUrl': 'https://play.google.com/store/apps/details?id=com.granth.app.user', 'apkUrl': 'https://granth-admin.vedpuran8090.workers.dev/apk/abc.apk', 'force': false})!;
    expect(u.apkUrl, endsWith('/apk/abc.apk'));
    expect(u.isNewer, isTrue);
  });

  test('version compare', () {
    expect(compareVersions('1.0.10', '1.0.9'), 1);
    expect(compareVersions('1.0', '1.0.0'), 0);
    expect(compareVersions('1.0.0+3', '1.0.1'), -1);
  });

  test('config without the key (old admin) keeps working → no alert', () {
    expect(RemoteConfig.I.appUpdate, isNull);
    expect(AppUpdate.I.pending, isNull);
  });

  Future<GlobalKey<NavigatorState>> boot(WidgetTester t) async {
    final key = GlobalKey<NavigatorState>();
    await t.pumpWidget(MaterialApp(navigatorKey: key, home: const Scaffold(body: SizedBox())));
    AppUpdate.I.navigatorKey = key;
    return key;
  }

  testWidgets('newer version: dialog once, notification logged, download offers Play + APK', (t) async {
    await boot(t);
    RemoteConfig.I.appUpdate = parseAppUpdate({'latest_version': '1.0.1', 'message': 'नया अपडेट आया है', 'apk_url': 'https://x.dev/g.apk'});
    AppUpdate.I.check();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-sheet')), findsOneWidget);
    expect(find.text('नया अपडेट आया है'), findsOneWidget);
    expect(NotificationLog.I.entries.single.kind, 'app_update');
    await t.tap(find.byKey(const ValueKey('app-update-download')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-play')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-apk')), findsOneWidget);
    Navigator.of(t.element(find.byKey(const ValueKey('app-update-how'))), rootNavigator: true).pop();
    await t.pumpAndSettle();
    // Not shown again for the same version…
    AppUpdate.I.check();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-sheet')), findsNothing);
    expect(Store.I.getString(AppUpdate.kShown), '1.0.1+');
    // …but the notification entry reopens it.
    await NotificationLog.I.open(NotificationLog.I.entries.single);
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-sheet')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('app-update-later')));
    await t.pumpAndSettle();
    expect(t.takeException(), isNull);
  });

  testWidgets('force hides "later" and shows every time; no APK link → Play only', (t) async {
    await boot(t);
    RemoteConfig.I.appUpdate = parseAppUpdate({'latest_version': '2.0.0', 'force': true});
    Store.I.setString(AppUpdate.kShown, '2.0.0+');
    AppUpdate.I.check();
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-sheet')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-later')), findsNothing);
    await t.tap(find.byKey(const ValueKey('app-update-download')));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('app-update-play')), findsOneWidget);
    expect(find.byKey(const ValueKey('app-update-apk')), findsNothing);
    expect(t.takeException(), isNull);
  });
}
