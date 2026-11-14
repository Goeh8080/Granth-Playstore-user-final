import 'dart:math' as math;

import 'package:flutter/material.dart';
import '../ai/navigator/voice_navigator.dart' show NavTouchTarget;

import '../models/models.dart';
import '../models/structure.dart';
import '../services/catalog_store.dart';
import '../services/storage.dart';
import '../services/remote_config.dart';
import '../services/order.dart' show numericCompare;
import '../services/search.dart';
import '../state/ui_prefs.dart';
import '../state/motion.dart';
import '../services/shelves.dart';
import '../state/places.dart';
import '../state/router.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/group_icon.dart';
import '../widgets/religion_symbol.dart';
import '../widgets/live_panel.dart';
import '../widgets/panel.dart';
import '../widgets/pop.dart';
import '../widgets/overlays.dart';
import '../widgets/granth_view_setting.dart';
import 'granths_screen.dart';

export '../widgets/granth_view_setting.dart' show granthViewKey, granthViewMode, granthViewChanged, setGranthView;

/// Round 10 — the folder levels of the Granth tab (omma-style structure, built natively):
///
///   religions  `#/granths`                       → [GranthsPanel] with the religion folders
///   religion   `#/granths?r=hindu`               → its groups (वेद, गीता, पुराण …)
///   group      `#/granths?r=hindu&g=puran`       → the granths in it ([GranthCard]s)
///   sub-group  `#/granths?r=hindu&g=ved&s=rigved`
///   अन्य       `#/granths?r=other`               → granths the structure file does not place
///   all        `#/granths?all=1`                 → the old flat list of every granth
///
/// A group that holds no granth is hidden. Every level keeps its own scroll place
/// (`Places.keyFor`) and the leaf lists are the normal granth list, so a card opens the
/// normal granth screen with its PDF buttons.
class ShelvesPanel extends StatelessWidget {
  const ShelvesPanel({super.key, required this.route});
  final GRoute route;

  @override
  Widget build(BuildContext context) {
    final r = route;
    if (r.flat) return const GranthsPanel();
    if (r.religionId == null) {
      return const _RootGranths();
    }
    if (r.religionId == kOtherId) {
      return GranthsPanel(
        placeKey: Places.keyFor(r)!,
        scope: const ShelfScope.other(),
        title: Shelves.structure.other.title,
        subtitle: 'बाकी सभी ग्रंथ',
        emptyNote: Shelves.structure.other.comingSoon,
        leading: const GroupIcon('misc', size: 44),
      );
    }
    final religion = Shelves.structure.religion(r.religionId!);
    if (religion == null) return const _Missing();
    if (r.groupId == null) return _FolderScreen(key: ValueKey('religion-${religion.id}'), religion: religion);
    final group = religion.groups.where((g) => g.id == r.groupId).firstOrNull;
    if (group == null) return const _Missing();
    if (group.hasSubgroups && r.subId == null) return _FolderScreen(key: ValueKey('group-${religion.id}-${group.id}'), religion: religion, group: group);
    final leaf = group.hasSubgroups ? group.subgroups.where((s) => s.id == r.subId).firstOrNull : group;
    if (leaf == null) return const _Missing();
    return GranthsPanel(
      placeKey: Places.keyFor(r)!,
      scope: ShelfScope(religion.id, group.id, group.hasSubgroups ? leaf.id : null),
      title: leaf.title,
      subtitle: group.hasSubgroups ? '${religion.title} • ${group.title}' : religion.title,
      leading: GroupIcon(leaf.icon, size: 44),
      emptyNote: leaf.comingSoon,
    );
  }
}

/// A link to a folder that does not exist (old bookmark, edited structure): say so, with a way back.
class _Missing extends StatelessWidget {
  const _Missing();
  @override
  Widget build(BuildContext context) => SliverToBoxAdapter(
        child: EmptyState(title: 'यह फ़ोल्डर नहीं मिला', actionLabel: 'सभी फ़ोल्डर', onAction: () => AppNav.I.go('#/granths')),
      );
}

Tone _tone(String t) => switch (t) {
      'saffron' => Tone.saffron,
      'gold' => Tone.gold,
      _ => Tone.maroon,
    };

String _count(int granths, int pramans) => pramans > 0 ? '$granths ग्रंथ • $pramans प्रमाण' : '$granths ग्रंथ';

/// The folder grid uses the same persisted 1×1 / 2×2 / 3×3 choice as the granth cards
/// (`Store.kGranthCols`; until the user chooses: the admin's `ui.grid`, else 2×2), so one switch
/// lays out the whole Granth tab.
int folderCols() => UiPrefs.I.shelfCols;

/// The size of a folder's picture for a column count: big and clear in 2×2.
/// v2 (Goutam: "bade bade nahi"): compact like ref2/ref3 — the 1×1 row is a slim list row,
/// 3×3 shows three small square-ish logo tiles per row.
double folderPicSize(int cols) => switch (cols) {
      1 => 52,
      2 => 64,
      _ => 44,
    };

/// One folder card: the normal card (so every card style / theme applies) with a picture,
/// the folder name and its real counts. 1×1 is the wide row (picture, text, ›); 2×2 and 3×3
/// are tiles (picture on top, name and counts centred under it). Names wrap to two lines and
/// then end in "…", so a long Hindi name never overflows at any width or text size.
class FolderRow extends StatelessWidget {
  const FolderRow({super.key, required this.leading, required this.title, required this.subtitle, required this.onTap, this.dim = false, this.cols = 1, this.navHash});

  /// t304: the hash this folder opens (the voice Navigator shows its touch here).
  final String? navHash;

  /// Builds the picture for the size this layout wants ([folderPicSize]).
  final Widget Function(double size) leading;
  final String title;
  final String subtitle;
  final VoidCallback onTap;

  /// "जल्द आ रहा है" folders are a little paler.
  final bool dim;
  final int cols;

  @override
  Widget build(BuildContext context) {
    final w = _build(context);
    return navHash == null ? w : NavTouchTarget(hash: navHash!, child: w);
  }

  Widget _build(BuildContext context) {
    final pic = leading(folderPicSize(cols));
    final titleColor = dim ? GColors.muted : GColors.maroon;
    final subColor = dim ? GColors.muted : GColors.brown;
    if (cols == 1) {
      return GCard(
        decorate: premiumFolderCard,
        clip: true,
        padding: EdgeInsets.zero,
        onTap: onTap,
        child: Stack(children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
            child: Row(children: [
              pic,
              const SizedBox(width: 14),
              Expanded(
                child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                  Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: GText.script(size: 17.5, color: titleColor, height: 1.25).copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 1),
                  Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis, style: GText.sans(size: 12.5, weight: FontWeight.w600, color: subColor)),
                ]),
              ),
              const SizedBox(width: 8),
              const ChevronCircle(size: 28),
            ]),
          ),
        ]),
      );
    }
    final small = cols >= 3;
    // t408: the old grid arrangement, each tile a compact iOS-style squircle (continuous
    // corners, 1:1) in the old flat card colours — no gloss, no gradient.
    final look = cardDecoration(UiPrefs.I.look);
    final shape = ContinuousRectangleBorder(
      borderRadius: BorderRadius.circular(small ? 30 : 40),
      side: BorderSide(color: (look.border as Border?)?.top.color ?? GColors.creamDark),
    );
    return AspectRatio(
      aspectRatio: 1,
      child: Pressable(
        onTap: onTap,
        scale: 0.985,
        child: DecoratedBox(
          decoration: ShapeDecoration(color: look.color ?? GColors.paper, shape: shape, shadows: [BoxShadow(color: GColors.shadow(0.08), blurRadius: 8, offset: const Offset(0, 2))]),
          child: ClipPath(
            clipper: ShapeBorderClipper(shape: shape),
            child: Padding(
              padding: EdgeInsets.symmetric(horizontal: small ? 4 : 8, vertical: small ? 6 : 10),
              child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
                pic,
                SizedBox(height: small ? 4 : 7),
                Text(title,
                    textAlign: TextAlign.center,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: GText.script(size: small ? 12.5 : 15.5, color: titleColor, height: 1.2).copyWith(fontWeight: FontWeight.w700)),
                FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(subtitle, maxLines: 1, style: GText.sans(size: small ? 10 : 11.5, weight: FontWeight.w600, color: subColor, height: 1.25)),
                ),
              ]),
            ),
          ),
        ),
      ),
    );
  }

}

/// t368: the default (सादा) card of the Granth tab folders — warm cream, soft gold rim, gold
/// glow shadow. Every other card style keeps its own look.
/// t368's warm gradient card is retired (t408: old flat card colours, no gloss); kept as a hook.
BoxDecoration? premiumFolderCard(String look) => null;

/// The "›" in a small cream circle with a gold rim.
class ChevronCircle extends StatelessWidget {
  const ChevronCircle({super.key, this.size = 34});
  final double size;
  @override
  Widget build(BuildContext context) => Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          color: GColors.paper,
          border: Border.all(color: GColors.goldLight, width: 1.3),
          boxShadow: [BoxShadow(color: GColors.gold.withValues(alpha: 0.18), blurRadius: 6, offset: const Offset(0, 2))],
        ),
        child: GIcon('chevron-right', size: size * 0.55, color: GColors.maroon),
      );
}

/// A faint lotus watermark (and in 1×1 a maroon swoosh in the bottom-right corner).
class FolderCardBackdrop extends CustomPainter {
  const FolderCardBackdrop({required this.wide});
  final bool wide;

  @override
  void paint(Canvas canvas, Size size) {
    final w = size.width, h = size.height;
    final petal = Paint()..color = GColors.gold.withValues(alpha: 0.10);
    final c = wide ? Offset(w - 70, h * 0.55) : Offset(w / 2, h * 0.36);
    final r = wide ? h * 0.42 : math.min(w, h) * 0.32;
    for (var i = -2; i <= 2; i++) {
      canvas.save();
      canvas.translate(c.dx, c.dy + r * 0.5);
      canvas.rotate(i * 0.42);
      canvas.drawPath(
        Path()
          ..moveTo(0, 0)
          ..quadraticBezierTo(-r * 0.32, -r * 0.55, 0, -r)
          ..quadraticBezierTo(r * 0.32, -r * 0.55, 0, 0)
          ..close(),
        petal,
      );
      canvas.restore();
    }
    if (!wide) return;
    final sw = Path()
      ..moveTo(w, h * 0.45)
      ..quadraticBezierTo(w * 0.93, h * 0.92, w * 0.70, h)
      ..lineTo(w, h)
      ..close();
    canvas.drawPath(sw, Paint()..shader = const LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFA31C34), Color(0xFF6E0F20)]).createShader(Rect.fromLTWH(w * 0.7, h * 0.45, w * 0.3, h * 0.55)));
    canvas.drawPath(
      Path()
        ..moveTo(w, h * 0.40)
        ..quadraticBezierTo(w * 0.92, h * 0.90, w * 0.66, h),
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1.3
        ..color = GColors.gold.withValues(alpha: 0.7),
    );
  }

  @override
  bool shouldRepaint(FolderCardBackdrop old) => old.wide != wide;
}

/// The [FolderRow]s as the app's grid (1/2/3 columns, [gridSliver]) with the staggered entry
/// + scale-pop. Keyed by the column count so switching replays the entry like the granth cards.
Widget folderSliver({required List<Widget> rows, required List<String> ids, required int cols, required double dx, required PopLedger ledger}) {
  return KeyedSubtree(
    key: ValueKey('folders-$cols'),
    child: gridSliver(
      count: rows.length,
      cols: cols,
      gap: cols == 1 ? 12 : (cols == 2 ? 10 : 8),
      item: (context, i) {
        final id = 'f$cols:${ids[i]}';
        return Entry(
          index: i + 1,
          dx: dx,
          ledger: ledger,
          id: id,
          child: CardPop(ledger: ledger, id: id, group: 'folders-$cols', index: i + 1, child: rows[i]),
        );
      },
    ),
  );
}

/// The religion folders (+ अन्य, + "सभी ग्रंथ") under the Granth tab's search box.
class _ReligionFolders extends StatelessWidget {
  const _ReligionFolders({required this.dx, required this.ledger});
  final double dx;
  final PopLedger ledger;

  @override
  Widget build(BuildContext context) {
    final all = CatalogStore.I.granths;
    // Nothing synced yet: say so once, instead of six empty folders.
    if (all.isEmpty) return const SliverToBoxAdapter(child: EmptyState(title: 'कोई ग्रंथ नहीं', body: 'सिंक के बाद पवित्र ग्रंथ यहाँ खुलेंगे।'));
    final index = Shelves.indexFor(all);
    final cols = folderCols();
    final rows = <Widget>[];
    final ids = <String>[];
    for (final r in index.structure.religions) {
      if (!r.visible) continue; // the admin hid the tile (its granths stay reachable elsewhere)
      final list = index.inReligion(r.id);
      ids.add(r.id);
      rows.add(FolderRow(
        cols: cols,
        leading: (size) => ReligionSymbol(r.icon, tone: _tone(r.tone), size: size),
        title: r.title,
        subtitle: list.isEmpty ? (r.comingSoon.isNotEmpty ? r.comingSoon : 'जल्द आ रहा है') : _count(list.length, ShelfIndex.pramans(list)),
        dim: list.isEmpty,
        navHash: GRoute.folderHash(religion: r.id),
        onTap: () => AppNav.I.go(GRoute.folderHash(religion: r.id)),
      ));
    }
    final other = index.other;
    if (other.isNotEmpty || index.structure.other.comingSoon.isNotEmpty) {
      ids.add(kOtherId);
      rows.add(FolderRow(
        cols: cols,
        leading: (size) => ReligionSymbol(index.structure.other.icon, tone: _tone(index.structure.other.tone), size: size),
        title: index.structure.other.title,
        subtitle: other.isEmpty ? index.structure.other.comingSoon : _count(other.length, ShelfIndex.pramans(other)),
        dim: other.isEmpty,
        navHash: GRoute.folderHash(religion: kOtherId),
        onTap: () => AppNav.I.go(GRoute.folderHash(religion: kOtherId)),
      ));
    }
    if (all.isNotEmpty) {
      ids.add('all');
      rows.add(FolderRow(
        cols: cols,
        leading: (size) => IconBox(tone: Tone.saffron, icon: 'library', size: size, radius: size * 0.26, iconSize: size * 0.5),
        title: 'सभी ग्रंथ',
        subtitle: '${all.length} ग्रंथ • एक सूची में',
        navHash: '#/granths?all=1',
        onTap: () => AppNav.I.go('#/granths?all=1'),
      ));
    }
    return SliverMainAxisGroup(slivers: [
      folderSliver(rows: rows, ids: ids, cols: cols, dx: dx, ledger: ledger),
    ]);
  }
}

/// A religion (its groups) or a group with sub-groups (वेद, 6 शास्त्र): folders only.
class _FolderScreen extends StatefulWidget {
  const _FolderScreen({super.key, required this.religion, this.group});
  final ShelfReligion religion;
  final ShelfGroup? group;
  @override
  State<_FolderScreen> createState() => _FolderScreenState();
}

class _FolderScreenState extends State<_FolderScreen> with LivePanel {
  final _ledger = PopLedger();
  late final String _place = 'folder-search-${widget.religion.id}-${widget.group?.id ?? ""}';
  late String _query = Places.query(_place);

  @override
  Widget build(BuildContext context) {
    final religion = widget.religion;
    final group = widget.group;
    final index = Shelves.indexFor(CatalogStore.I.granths);
    final dx = panelDx();
    final List<Granth> inside = group == null ? index.inReligion(religion.id) : index.inGroup(religion.id, group.id);
    final children = group == null ? index.visibleGroups(religion.id) : index.visibleSubgroups(religion.id, group.id);
    final searching = _query.trim().isNotEmpty;
    final cols = searching ? UiPrefs.I.granthCols : folderCols();
    // Tester t365: inside any dharm / folder the search box finds EVERY granth (inside पुराण,
    // "ved" shows the वेद granths too), this folder's own matches first.
    final matches = searching ? globalSearchRows(inside, CatalogStore.I.granths, _query, CatalogStore.I.granthDoc) : const <Granth>[];
    final rows = <Widget>[];
    final ids = <String>[];
    for (final c in children) {
      if (searching && searchFields([c], _query, (folder) => [folder.title]).isEmpty) continue;
      final list = group == null ? index.inGroup(religion.id, c.id) : index.inLeaf(leafKey(religion.id, group.id, c.id));
      ids.add(c.id);
      rows.add(FolderRow(
        cols: cols,
        leading: (size) => GroupIcon(c.icon, size: size),
        title: c.title,
        subtitle: _count(list.length, ShelfIndex.pramans(list)),
        navHash: GRoute.folderHash(religion: religion.id, group: group?.id ?? c.id, sub: group == null ? null : c.id),
        onTap: () => AppNav.I.go(GRoute.folderHash(religion: religion.id, group: group?.id ?? c.id, sub: group == null ? null : c.id)),
      ));
    }
    return SliverMainAxisGroup(slivers: [
      StickyHeader(
        child: Entry(
          index: 0,
          dx: dx,
          child: PageHeader(
            tone: _tone(religion.tone),
            icon: religion.icon,
            leading: group == null ? ReligionSymbol(religion.icon, tone: _tone(religion.tone), size: 44) : GroupIcon(group.icon, size: 44),
            tools: Tools(
              grid: GridSwitch(locked: UiPrefs.I.gridLocked(searching ? 'granths' : 'shelves'), options: const [1, 2, 3], value: cols, onChanged: (v) => UiPrefs.I.setCols(Store.kGranthCols, v)),
              search: SearchField(placeholder: 'सभी ग्रंथों में खोजें', initial: _query, onChanged: (q) {
                Places.setQuery(_place, q);
                setState(() => _query = q);
              }),
            ),
            title: group?.title ?? religion.title,
            subtitle: group == null ? _count(inside.length, ShelfIndex.pramans(inside)) : '${religion.title} • ${_count(inside.length, ShelfIndex.pramans(inside))}',
          ),
        ),
      ),
      const SliverToBoxAdapter(child: SizedBox(height: 18)),
      if (searching && rows.isNotEmpty) folderSliver(rows: rows, ids: ids, cols: cols, dx: dx, ledger: _ledger),
      if (searching)
        KeyedSubtree(key: ValueKey('folder-search-$cols'), child: gridSliver(count: matches.length, cols: cols, gap: 10,
          item: (_, i) => GranthCard(granth: matches[i], index: i + 1, total: matches.length, cols: cols))),
      if (searching && matches.isEmpty && rows.isEmpty)
        const SliverToBoxAdapter(child: EmptyState(title: 'कोई ग्रंथ नहीं', body: 'दूसरा शब्द खोजें।')),
      if (!searching) folderSliver(rows: rows, ids: ids, cols: cols, dx: dx, ledger: _ledger),
      if (!searching && rows.isEmpty)
        SliverToBoxAdapter(
          child: EmptyState(
            title: 'जल्द आ रहा है',
            body: (group?.comingSoon.isNotEmpty ?? false)
                ? group!.comingSoon
                : (group == null && religion.comingSoon.isNotEmpty ? religion.comingSoon : '${group?.title ?? religion.title} के ग्रंथ अभी उपलब्ध नहीं हैं।'),
          ),
        ),
    ]);
  }
}


/// Only the root Granth section asks this, never dashboard or a deep link.
/// t368: asked once ever (kept after logout); changed later in Settings → ग्रंथ दृश्य or with
/// the search bar's filter button. When the admin forces a view, the chooser is skipped entirely.
class _RootGranths extends StatefulWidget {
  const _RootGranths();
  @override
  State<_RootGranths> createState() => _RootGranthsState();
}

class _RootGranthsState extends State<_RootGranths> {
  String get _mode => granthViewMode();
  bool _asking = false;

  @override
  void initState() {
    super.initState();
    RemoteConfig.I.addListener(_cfg);
    granthViewChanged.addListener(_changed);
    // A slow phone may open the saved settings a moment late: decide only once they are
    // there, so a choice made earlier is never asked again.
    if (Store.I.persistent) {
      _schedule();
    } else {
      Store.I.adopted.addListener(_prefsReady);
    }
  }

  void _prefsReady() {
    Store.I.adopted.removeListener(_prefsReady);
    if (mounted) setState(_schedule);
  }

  void _schedule() {
    if (!_needsChoice) return;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _needsChoice && !_asking) _choose();
    });
  }

  bool get _needsChoice => RemoteConfig.I.uiGranthViewMode == null && Store.I.getString(granthViewKey) == null;

  void _cfg() {
    if (!mounted) return;
    // Admin forced a view while the chooser is open: close it, the forced view applies.
    if (_asking && RemoteConfig.I.uiGranthViewMode != null) Navigator.of(context, rootNavigator: true).pop();
    setState(() {});
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    granthViewChanged.removeListener(_changed);
    RemoteConfig.I.removeListener(_cfg);
    Store.I.adopted.removeListener(_prefsReady);
    super.dispose();
  }

  Future<void> _choose() async {
    _asking = true;
    // Must pick one (no Back / outside tap), so the question is asked only once.
    final mode = await showPop<String>(context, (_) => const PopScope(canPop: false, child: GranthViewChoice()), dismissible: false, barrierOpacity: 0.55);
    _asking = false;
    if (mode == null || !mounted) return;
    await setGranthView(mode);
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) => SliverMainAxisGroup(slivers: [
        GranthsPanel(
          key: ValueKey('root-$_mode'),
          placeKey: _mode == 'folders' ? 'religions-place' : 'granth-list-place',
          idle: _mode == 'folders' ? (context, dx, ledger) => _ReligionFolders(dx: dx, ledger: ledger) : null,
        ),
      ]);
}

/// t368 — "आप ग्रंथ कैसे देखना चाहेंगे": asked once ever, cannot be dismissed without a
/// choice. Each option is a LIVE miniature of the real screen (not a video or picture) that
/// keeps scrolling: the religion folders in 1×1 and the single list in 3×3, in the app theme
/// with real names and counts. All text follows the app theme (Theme text styles).
class GranthViewChoice extends StatelessWidget {
  const GranthViewChoice({super.key});

  double _previewHeight(BuildContext context, {required bool large}) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final h = MediaQuery.sizeOf(context).height;
    if (large) return (h * .12).clamp(48.0, 80.0);
    return (h * .34 / (scale > 1.3 ? scale / 1.3 : 1)).clamp(96.0, 260.0);
  }

  Widget _option(BuildContext context, String mode, String title, String hint, bool large, double imageHeight) {
    final folders = mode == 'folders';
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final cs = theme.colorScheme;
    return Pressable(
      key: ValueKey('granth-view-$mode'),
      onTap: () => Navigator.pop(context, mode),
      child: GCard(
        decorate: premiumFolderCard,
        padding: EdgeInsets.all(large ? 6 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            GranthViewLivePreview(
              key: ValueKey('granth-view-preview-$mode'),
              mode: mode,
              height: imageHeight,
              duration: folders ? const Duration(seconds: 9) : const Duration(seconds: 7),
            ),
            SizedBox(height: large ? 4 : 8),
            Text(
              title,
              key: ValueKey('granth-view-title-$mode'),
              textAlign: TextAlign.center,
              maxLines: large ? 1 : 2,
              overflow: TextOverflow.ellipsis,
              style: (large ? tt.titleSmall : tt.titleMedium)?.copyWith(fontWeight: FontWeight.w600, color: cs.primary, height: 1.2),
            ),
            if (!large)
              Text(hint,
                  key: ValueKey('granth-view-hint-$mode'),
                  textAlign: TextAlign.center,
                  style: tt.bodySmall?.copyWith(color: tt.bodySmall?.color?.withValues(alpha: 0.72), height: 1.3)),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final large = MediaQuery.textScalerOf(context).scale(16) > 24;
    final imageHeight = _previewHeight(context, large: large);
    final theme = Theme.of(context);
    final tt = theme.textTheme;
    final cs = theme.colorScheme;
    return SheetCard(key: const ValueKey('granth-view-picker'), scroll: false, opaque: true, children: [
      // No close button: a choice is required (asked only once ever).
      Text(
        large ? 'ग्रंथ का दृश्य' : 'आप ग्रंथ कैसे देखना चाहेंगे',
        key: const ValueKey('granth-view-heading'),
        softWrap: true,
        textAlign: TextAlign.center,
        maxLines: large ? 1 : 2,
        overflow: TextOverflow.ellipsis,
        style: (large ? tt.titleMedium : tt.titleLarge)?.copyWith(
          fontFamily: GFonts.display,
          fontFamilyFallback: GFonts.displayFallback,
          fontWeight: FontWeight.w400,
          color: cs.primary,
          height: 1.25,
        ),
      ),
      SizedBox(height: large ? 6 : 12),
      LayoutBuilder(builder: (context, box) {
        // A phone-shaped window (≤ 1.45 × its width), so both options fit without scrolling.
        final optW = (box.maxWidth - 8) / 2 - (large ? 12 : 16) - 2;
        final h = optW > 0 ? imageHeight.clamp(0.0, optW * 1.45) : imageHeight;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _option(context, 'folders', 'फ़ोल्डर', 'श्रेणियों में · 1×1', large, h)),
          const SizedBox(width: 8),
          Expanded(child: _option(context, 'list', 'सभी ग्रंथ', 'एक सूची में · 3×3', large, h)),
        ]);
      }),
      SizedBox(height: large ? 4 : 10),
      Text(
        large ? 'एक बार · सेटिंग्स में बदलें' : 'एक बार चुनें · बाद में सेटिंग्स में बदल सकते हैं',
        key: const ValueKey('granth-view-note'),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: tt.bodySmall?.copyWith(color: tt.bodySmall?.color?.withValues(alpha: 0.72), height: 1.2),
      ),
    ]);
  }
}

/// A live, looping, auto-scrolling miniature of the root Granth screen in [mode]: built from
/// the real widgets ([FolderRow] + [ReligionSymbol] tiles, granth tiles) at a 320 dp virtual
/// width and scaled into the option. Scrolls top → bottom → top with a pause at each end;
/// still (top) when animations are off / reduced motion. Not interactive.
class GranthViewLivePreview extends StatefulWidget {
  const GranthViewLivePreview({super.key, required this.mode, required this.height, this.duration = const Duration(seconds: 8)});
  final String mode;
  final double height;
  final Duration duration;

  static const double virtualWidth = 320;

  @override
  State<GranthViewLivePreview> createState() => _GranthViewLivePreviewState();
}

class _GranthViewLivePreviewState extends State<GranthViewLivePreview> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(vsync: this, duration: widget.duration);
  bool _motion = true;
  static const _curve = Interval(0.18, 0.82, curve: Curves.easeInOutCubic);

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final on = Motion.on(context);
    if (on == _motion && (_c.isAnimating || !on)) return;
    _motion = on;
    if (on) {
      if (!_c.isAnimating) _c.repeat(reverse: true);
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  /// (content, estimated virtual height — the scroll range; the content sizes itself)
  (Widget, double) _content() {
    final all = CatalogStore.I.granths;
    if (widget.mode == 'folders') {
      const rowH = 98.0, gap = 10.0;
      final index = Shelves.indexFor(all);
      final rows = <Widget>[];
      for (final r in index.structure.religions) {
        if (!r.visible) continue;
        final list = index.inReligion(r.id);
        rows.add(FolderRow(
          cols: 1,
          leading: (size) => ReligionSymbol(r.icon, tone: _tone(r.tone), size: size),
          title: r.title,
          subtitle: list.isEmpty ? (r.comingSoon.isNotEmpty ? r.comingSoon : 'जल्द आ रहा है') : _count(list.length, ShelfIndex.pramans(list)),
          dim: list.isEmpty,
          onTap: () {},
        ));
      }
      final h = rows.length * (rowH + gap) + 8;
      return (
        Padding(
          padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
          child: Column(mainAxisSize: MainAxisSize.min, children: [for (final r in rows) Padding(padding: const EdgeInsets.only(bottom: gap), child: r)]),
        ),
        h,
      );
    }
    final list = [...all]..sort((a, b) => numericCompare(a.position, b.position));
    final items = list.take(24).toList();
    const tileH = 118.0, gap = 8.0;
    final n = (items.length / 3).ceil();
    return (
      Padding(
        padding: const EdgeInsets.fromLTRB(8, 8, 8, 0),
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          for (var r = 0; r < n; r++)
            Padding(
              padding: const EdgeInsets.only(bottom: gap),
              child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                for (var c = 0; c < 3; c++) ...[
                  if (c > 0) const SizedBox(width: gap),
                  Expanded(child: r * 3 + c < items.length ? _MiniGranthTile(granth: items[r * 3 + c]) : const SizedBox()),
                ],
              ]),
            ),
        ]),
      ),
      n * (tileH + gap) + 8,
    );
  }

  @override
  Widget build(BuildContext context) {
    final (content, contentH) = _content();
    return Semantics(
      label: widget.mode == 'folders' ? 'उदाहरण: फ़ोल्डर दृश्य (1×1), अपने आप स्क्रॉल होता हुआ' : 'उदाहरण: सभी ग्रंथ एक सूची में (3×3), अपने आप स्क्रॉल होता हुआ',
      child: ExcludeSemantics(
        child: IgnorePointer(
          child: SizedBox(
            height: widget.height,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(10),
              child: ColoredBox(
                color: GColors.cream,
                child: LayoutBuilder(builder: (context, box) {
                  final k = box.maxWidth / GranthViewLivePreview.virtualWidth;
                  final maxY = (contentH - widget.height / k).clamp(0.0, double.infinity);
                  final page = OverflowBox(
                    alignment: Alignment.topLeft,
                    minWidth: GranthViewLivePreview.virtualWidth,
                    maxWidth: GranthViewLivePreview.virtualWidth,
                    minHeight: 0,
                    maxHeight: double.infinity,
                    child: MediaQuery(data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling), child: content),
                  );
                  return AnimatedBuilder(
                    animation: _c,
                    child: RepaintBoundary(child: page),
                    builder: (context, child) {
                      final t = _motion ? _curve.transform(_c.value) : 0.0;
                      return Transform(
                        key: const ValueKey('granth-view-preview-page'),
                        alignment: Alignment.topLeft,
                        transform: Matrix4.diagonal3Values(k, k, 1)..translateByDouble(0, -maxY * t, 0, 1),
                        child: child,
                      );
                    },
                  );
                }),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// One granth in the 3×3 list miniature: a glossy book tile, the name and its praman count.
class _MiniGranthTile extends StatelessWidget {
  const _MiniGranthTile({required this.granth});
  final Granth granth;
  @override
  Widget build(BuildContext context) => DecoratedBox(
        decoration: premiumFolderCard('classic')!,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(6, 8, 6, 6),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            const GroupIcon('book-blue', size: 50),
            const SizedBox(height: 6),
            Text(granth.title, maxLines: 2, overflow: TextOverflow.ellipsis, textAlign: TextAlign.center, style: GText.script(size: 12.5, color: GColors.maroon, height: 1.25).copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 4),
            Text('${granth.pramanCount} प्रमाण', maxLines: 1, style: GText.sans(size: 10.5, weight: FontWeight.w600, color: GColors.brown)),
          ]),
        ),
      );
}
