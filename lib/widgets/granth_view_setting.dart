import 'package:flutter/material.dart';

import '../services/remote_config.dart';
import '../services/storage.dart';
import '../theme/colors.dart';
import 'common.dart';
import 'overlays.dart';
import 'remote_media.dart';
import '../services/media_manifest.dart';

/// The user's once-only folders/list choice (t368: kept across logout, changeable in Settings).
const granthViewKey = Store.kGranthView;

/// Effective root Granth view: admin `ui.granth_view_mode` (folders/list) wins, else the
/// user's saved choice, else folders. Old saved values are read unchanged.
String granthViewMode() => RemoteConfig.I.uiGranthViewMode ?? (Store.I.getString(granthViewKey) == 'list' ? 'list' : 'folders');

/// Bumped whenever the user changes the view in Settings / the filter sheet (the root rebuilds).
final ValueNotifier<int> granthViewChanged = ValueNotifier(0);

/// Saves the user's view (`folders` / `list`).
Future<void> setGranthView(String mode) async {
  await Store.I.setString(granthViewKey, mode == 'list' ? 'list' : 'folders');
  granthViewChanged.value++;
}

/// The admin forces the view (no chooser, no setting).
bool granthViewForced() => RemoteConfig.I.uiGranthViewMode != null;

/// The two pills "फ़ोल्डर" / "एक सूची" (Settings → ग्रंथ दृश्य, and the search bar's filter sheet).
List<Widget> granthViewPills({VoidCallback? after}) {
  final mode = granthViewMode();
  final locked = granthViewForced();
  return [
    for (final (id, label, icon) in const [('folders', 'फ़ोल्डर (श्रेणियाँ)', 'folder-open'), ('list', 'एक सूची (सभी ग्रंथ)', 'library')])
      Pill(
        key: ValueKey('set-granth-view-$id'),
        direct: true,
        icon: icon,
        label: label,
        enabled: !locked,
        tone: mode == id ? PillTone.maroon : PillTone.plain,
        onTap: locked
            ? null
            : () async {
                await setGranthView(id);
                after?.call();
              },
      ),
  ];
}

/// t421: the chooser / Settings loops — lotus for फ़ोल्डर, book for एक सूची (bundled, muted,
/// ~300 KB each). The admin may replace them with media-manifest videos of placement
/// `chooser_folders` / `chooser_list` (a failing URL falls back to the bundled clip). Placement
/// `settings` is a general Settings background and is NOT used here.
const Map<String, String> kGranthViewVideoAsset = {
  'folders': 'assets/brand/video/lotus_folders.mp4',
  'list': 'assets/brand/video/book_list.mp4',
};

ManifestVideo? granthViewVideoOverride(String mode) => MediaManifest.I.videoFor(mode == 'list' ? 'chooser_list' : 'chooser_folders');

/// The looping video of a view option, with [fallback] (live miniature / icon) while it loads
/// or if the phone cannot play it.
class GranthViewVideo extends StatelessWidget {
  const GranthViewVideo({super.key, required this.mode, required this.fallback, this.radius = 10});
  final String mode;
  final Widget fallback;
  final double radius;
  @override
  Widget build(BuildContext context) {
    final o = granthViewVideoOverride(mode);
    return ClipRRect(
      borderRadius: BorderRadius.circular(radius),
      child: ColoredBox(
        color: GColors.cream,
        child: LoopVideo(
          key: ValueKey('granth-view-video-$mode'),
          asset: kGranthViewVideoAsset[mode == 'list' ? 'list' : 'folders'],
          url: o?.url,
          // bundled previews loop; an admin clip follows its own `loop` (default: once + hold)
          loop: o?.loop ?? true,
          fallback: fallback,
        ),
      ),
    );
  }
}

/// Settings → ग्रंथ दृश्य (t421: "setting me bhi video chale"): the two options as the same
/// looping videos as the chooser, each tappable, with its pill under it. Locked (greyed, no tap)
/// while the admin forces the view.
Widget granthViewVideoChoices({VoidCallback? after}) {
  final mode = granthViewMode();
  final locked = granthViewForced();
  final pills = granthViewPills(after: after);
  const ids = ['folders', 'list'];
  const icons = ['folder-open', 'library'];
  return SizedBox(
    key: const ValueKey('set-granth-view-videos'),
    width: double.infinity,
    child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
      for (var i = 0; i < 2; i++) ...[
        if (i > 0) const SizedBox(width: 10),
        Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
            Opacity(
              opacity: locked ? 0.6 : 1,
              child: Pressable(
                key: ValueKey('set-granth-view-video-${ids[i]}'),
                scale: kGrowScale,
                glow: BorderRadius.circular(14),
                onTap: locked
                    ? null
                    : () async {
                        await setGranthView(ids[i]);
                        after?.call();
                      },
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 180),
                  curve: Curves.easeOutCubic,
                  padding: const EdgeInsets.all(3),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(color: mode == ids[i] ? GColors.maroon : GColors.creamDark, width: mode == ids[i] ? 2 : 1),
                  ),
                  child: AspectRatio(
                    aspectRatio: 1.3,
                    child: GranthViewVideo(
                      mode: ids[i],
                      radius: 11,
                      fallback: Center(child: IconBox(tone: Tone.maroon, icon: icons[i], size: 52, radius: 14, iconSize: 26)),
                    ),
                  ),
                ),
              ),
            ),
            const SizedBox(height: 8),
            Align(alignment: Alignment.center, child: pills[i]),
          ]),
        ),
      ],
    ]),
  );
}

/// Settings heading of the block.
String granthViewTitle() => granthViewForced() ? 'ग्रंथ दृश्य · एडमिन द्वारा नियंत्रित (Managed by admin)' : 'ग्रंथ दृश्य (Granth टैब)';

/// The search bar's filter button: change the view right there.
Future<void> showGranthViewSheet(BuildContext context) => showPop<void>(
      context,
      (ctx) => StatefulBuilder(
        builder: (ctx, set) => SheetCard(key: const ValueKey('granth-view-sheet'), children: [
          Text(granthViewTitle(), style: GText.sans(size: 17, weight: FontWeight.w700, color: GColors.maroon)),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: granthViewPills(after: () {
            set(() {});
            Navigator.of(ctx).pop();
          })),
          const SizedBox(height: 10),
          Text('यह सेटिंग्स में भी बदल सकते हैं।', style: GText.sans(size: 12.5, color: GColors.muted)),
        ]),
      ),
    );
