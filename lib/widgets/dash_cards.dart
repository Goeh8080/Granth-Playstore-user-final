/// t303: the two Dashboard cards further down the page — "अपने-आप सिंक / डाउनलोड" (live sync
/// state, page progress, the auto-download switch, last sync time; same store and settings
/// the सिंक strip and Settings use) and "सूचनाएँ" (the phone's recent notifications; a tap
/// opens exactly that admin reply / ticket thread / praman). Both follow the card style.
library;

import 'package:flutter/material.dart';

import '../screens/home_shell.dart' show SyncStrip, hiDate;
import '../services/catalog_store.dart';
import '../services/notification_log.dart';
import '../state/ui_prefs.dart';
import '../theme/colors.dart';
import 'common.dart';

BoxDecoration _surface() => themedSurface(BoxDecoration(color: GColors.paper, border: Border.all(color: GColors.creamDark), borderRadius: BorderRadius.circular(14)));

Widget _head(String icon, String title, {Widget? trailing}) => Row(children: [
      GIcon(icon, size: 20, color: GColors.maroon),
      const SizedBox(width: 10),
      Expanded(child: Text(title, style: GText.display(size: 20, color: GColors.maroon, height: 1.2))),
      ?trailing,
    ]);

class SyncDashCard extends StatelessWidget {
  const SyncDashCard({super.key});

  @override
  Widget build(BuildContext context) {
    final s = CatalogStore.I;
    return RepaintBoundary(
      child: ListenableBuilder(
        listenable: Listenable.merge([s, s.progress, s.lastSync, UiPrefs.I]),
        builder: (context, _) {
          final u = s.progress.value;
          final syncing = s.status == SyncStatus.syncing;
          final running = u.running || syncing;
          final status = syncing
              ? 'सिंक हो रहा है…'
              : (s.error ?? (s.online ? (u.running ? 'पेज सेव हो रहे हैं' : 'ऑफलाइन तैयार') : 'इंटरनेट नहीं · सेव किया डेटा चल रहा है'));
          final auto = UiPrefs.I.autoDownload;
          return Container(
            key: const ValueKey('dash-sync-card'),
            margin: const EdgeInsets.only(top: 18),
            padding: const EdgeInsets.all(18),
            decoration: _surface(),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              _head('refresh-cw', 'अपने-आप सिंक / डाउनलोड',
                  trailing: Pill(key: const ValueKey('dash-sync-now'), direct: true, icon: 'refresh-cw', label: running ? 'चल रहा है' : 'सिंक', onTap: running ? null : SyncStrip.tapSync)),
              const SizedBox(height: 10),
              Row(children: [
                AnimatedContainer(
                  duration: const Duration(milliseconds: 300),
                  width: 8,
                  height: 8,
                  decoration: BoxDecoration(color: s.online ? GColors.online : GColors.maroon, shape: BoxShape.circle),
                ),
                const SizedBox(width: 8),
                Expanded(child: Text(status, key: const ValueKey('dash-sync-status'), style: GText.sans(size: 14, color: GColors.text, height: 1.4))),
              ]),
              const SizedBox(height: 10),
              Text(
                u.total > 0 ? '${u.total} में से ${u.done} पेज सेव' : 'पेज की सूची अभी नहीं आई',
                key: const ValueKey('dash-sync-count'),
                style: GText.sans(size: 15, weight: FontWeight.w700, color: GColors.maroon),
              ),
              const SizedBox(height: 6),
              ClipRRect(
                borderRadius: BorderRadius.circular(99),
                child: LinearProgressIndicator(
                  value: syncing && u.total == 0 ? null : (u.total == 0 ? 0 : (u.done / u.total).clamp(0.0, 1.0)),
                  minHeight: 6,
                  backgroundColor: GColors.creamDark,
                  valueColor: const AlwaysStoppedAnimation(GColors.saffron),
                ),
              ),
              const SizedBox(height: 10),
              Wrap(spacing: 8, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                Text('अपने-आप डाउनलोड', style: GText.sans(size: 14, weight: FontWeight.w600, color: GColors.text)),
                Pill(key: const ValueKey('dash-auto-download-on'), direct: true, label: 'चालू', tone: auto ? PillTone.maroon : PillTone.plain, onTap: () => UiPrefs.I.autoDownload = true),
                Pill(key: const ValueKey('dash-auto-download-off'), direct: true, label: 'बंद', tone: auto ? PillTone.plain : PillTone.maroon, onTap: () => UiPrefs.I.autoDownload = false),
              ]),
              const SizedBox(height: 8),
              Text(
                s.syncedAt != null ? 'आख़िरी सिंक: ${hiDate(s.syncedAt)}' : 'अभी सिंक नहीं हुआ',
                key: const ValueKey('dash-sync-last'),
                style: GText.sans(size: 13, color: GColors.muted),
              ),
            ]),
          );
        },
      ),
    );
  }
}

class NotificationsDashCard extends StatelessWidget {
  const NotificationsDashCard({super.key});

  static const shown = 6;

  static String _icon(String kind) => switch (kind) {
        'admin_reply' || 'support_reply' => 'message-circle',
        'new_praman' || 'daily' => 'image',
        'trending' => 'clipboard-list',
        _ => 'bell',
      };

  @override
  Widget build(BuildContext context) => RepaintBoundary(
        child: ListenableBuilder(
          listenable: Listenable.merge([NotificationLog.I, UiPrefs.I]),
          builder: (context, _) {
            final all = NotificationLog.I.entries;
            final list = all.take(shown).toList();
            final unseen = NotificationLog.I.unseen;
            return Container(
              key: const ValueKey('dash-notif-card'),
              margin: const EdgeInsets.only(top: 18),
              padding: const EdgeInsets.all(18),
              decoration: _surface(),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                _head('bell', 'सूचनाएँ',
                    trailing: unseen > 0
                        ? Pill(key: const ValueKey('dash-notif-unseen'), label: '$unseen नई', tone: PillTone.maroon)
                        : null),
                const SizedBox(height: 8),
                if (list.isEmpty)
                  Padding(
                    key: const ValueKey('dash-notif-empty'),
                    padding: const EdgeInsets.symmetric(vertical: 8),
                    child: Text('अभी कोई सूचना नहीं। admin के जवाब, नए प्रमाण, चर्चित विषय और आज का प्रमाण यहाँ दिखेंगे।',
                        style: GText.sans(size: 14, color: GColors.muted, height: 1.5)),
                  )
                else
                  for (final e in list)
                    Pressable(
                      key: ValueKey('dash-notif-${e.id}'),
                      onTap: () => NotificationLog.I.open(e),
                      scale: 0.98,
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 8),
                        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                          Padding(padding: const EdgeInsets.only(top: 2), child: GIcon(_icon(e.kind), size: 18, color: e.seen ? GColors.muted : GColors.saffronDark)),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                              Text(e.title, style: GText.sans(size: 14.5, weight: e.seen ? FontWeight.w600 : FontWeight.w700, color: GColors.maroon, height: 1.35)),
                              if (e.body.isNotEmpty)
                                Text(e.body, maxLines: 2, overflow: TextOverflow.ellipsis, style: GText.sans(size: 13, color: GColors.text, height: 1.4)),
                              Text(hiDate(e.at), style: GText.sans(size: 11.5, color: GColors.muted, height: 1.4)),
                            ]),
                          ),
                          if (!e.seen)
                            Container(
                              margin: const EdgeInsets.only(top: 6, left: 6),
                              width: 8,
                              height: 8,
                              decoration: const BoxDecoration(color: GColors.saffron, shape: BoxShape.circle),
                            ),
                        ]),
                      ),
                    ),
              ]),
            );
          },
        ),
      );
}
