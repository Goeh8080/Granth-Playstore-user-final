// t303: Dashboard auto-sync/download card + notifications card.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/screens/dashboard_screen.dart';
import 'package:granthprabandhan/services/notification_log.dart';
import 'package:granthprabandhan/services/storage.dart';
import 'package:granthprabandhan/state/router.dart';
import 'package:granthprabandhan/state/ui_prefs.dart';
import 'helpers.dart';

void main() {
  setUp(() async {
    await setUpApp();
    NotificationLog.I.debugReset();
    UiPrefs.I.animations = false;
  });

  Future<void> boot(WidgetTester t) async {
    await t.binding.setSurfaceSize(const Size(320, 3000));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(const MaterialApp(home: Scaffold(body: CustomScrollView(slivers: [DashboardPanel()]))));
    await t.pump(const Duration(seconds: 2));
  }

  testWidgets('sync card shows status, progress, last sync and toggles auto download', (t) async {
    await boot(t);
    expect(find.byKey(const ValueKey('dash-sync-card')), findsOneWidget);
    expect(find.byKey(const ValueKey('dash-sync-last')), findsOneWidget);
    expect(find.textContaining('आख़िरी सिंक'), findsOneWidget);
    expect(UiPrefs.I.autoDownload, isTrue);
    await t.tap(find.byKey(const ValueKey('dash-auto-download-off')));
    await t.pump();
    expect(UiPrefs.I.autoDownload, isFalse);
    expect(Store.I.getString(Store.kAutoDownload), '0', reason: 'same setting Settings uses');
    await t.tap(find.byKey(const ValueKey('dash-auto-download-on')));
    await t.pump();
    expect(UiPrefs.I.autoDownload, isTrue);
    expect(t.takeException(), isNull);
  });

  testWidgets('notifications card: empty state, then entries; tap opens the exact thread', (t) async {
    await boot(t);
    expect(find.byKey(const ValueKey('dash-notif-empty')), findsOneWidget);
    NotificationLog.I.record(id: 'support:7:x', kind: 'support_reply', title: 'सहायता: admin का जवाब', body: 'टिकट', link: '#/support?t=7');
    NotificationLog.I.record(id: 'daily:100:', kind: 'daily', title: 'आज का प्रमाण', link: '#/pramans?id=100');
    NotificationLog.I.record(id: 'daily:100:', kind: 'daily', title: 'आज का प्रमाण', link: '#/pramans?id=100'); // deduped
    await t.pump();
    expect(NotificationLog.I.entries.length, 2);
    expect(find.byKey(const ValueKey('dash-notif-unseen')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('dash-notif-support:7:x')));
    await t.pump();
    expect(AppNav.I.hash, '#/support?t=7');
    expect(NotificationLog.I.entries.firstWhere((e) => e.id == 'support:7:x').seen, isTrue);
    expect(t.takeException(), isNull);
  });

  test('log survives restart and tolerates old/garbage data', () async {
    NotificationLog.I.record(id: 'a', kind: 'new_praman', title: 'नया प्रमाण', link: '#/pramans');
    NotificationLog.I.debugReset();
    expect(NotificationLog.I.entries.single.id, 'a');
    await Store.I.setString(NotificationLog.kKey, 'not json');
    NotificationLog.I.debugReset();
    expect(NotificationLog.I.entries, isEmpty);
    await Store.I.setString(NotificationLog.kKey, '[{"id":"x"},{"id":"b","kind":"daily","title":"t","at":1,"extra":1}]');
    NotificationLog.I.debugReset();
    expect(NotificationLog.I.entries.single.id, 'b');
  });
}
