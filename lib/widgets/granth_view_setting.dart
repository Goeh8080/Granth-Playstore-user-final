import 'package:flutter/material.dart';

import '../services/remote_config.dart';
import '../services/storage.dart';
import '../theme/colors.dart';
import 'common.dart';
import 'overlays.dart';

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
