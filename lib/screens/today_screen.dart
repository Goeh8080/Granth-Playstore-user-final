import 'package:flutter/material.dart';

import '../services/catalog_store.dart';
import '../services/remote_config.dart';
import '../state/router.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/overlays.dart';
import '../widgets/today_card.dart';

/// Round-4: आज का प्रमाण — its own page (menu entry below the Photo Highlighter).
/// Shows the daily praman; tapping it opens the praman. Back returns where it was opened.
class TodayPage extends StatelessWidget {
  const TodayPage({super.key, this.now});
  final DateTime Function()? now;

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([RemoteConfig.I, CatalogStore.I]),
    builder: (context, _) {
      final p = RemoteConfig.I.dailyEnabled ? dailyPraman(CatalogStore.I.pramans, RemoteConfig.I.dailyPraman, (now ?? DateTime.now)()) : null;
      return SliverPadding(
        key: const ValueKey('today-page'),
        padding: const EdgeInsets.fromLTRB(2, 4, 2, 24),
        sliver: SliverToBoxAdapter(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SheetHead(title: 'आज का प्रमाण', onBack: AppNav.I.back, direct: true),
              FrostCard(
                child: p == null
                    ? Text(
                        key: const ValueKey('today-empty'),
                        'आज का प्रमाण अभी उपलब्ध नहीं है। प्रमाण सूची से सभी प्रमाण देखें।',
                        style: GText.sans(size: 14, color: GColors.muted, height: 1.45),
                      )
                    : TodayCard(now: now, trending: false),
              ),
              const SizedBox(height: 14),
              SheetButton(
                key: const ValueKey('today-all-pramans'),
                label: 'सभी प्रमाण देखें',
                icon: 'image',
                onTap: () => AppNav.I.go('#/pramans'),
              ),
            ],
          ),
        ),
      );
    },
  );
}
