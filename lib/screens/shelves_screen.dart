import 'package:flutter/material.dart';
import '../ai/navigator/voice_navigator.dart' show NavTouchTarget;

import '../models/models.dart';
import '../models/structure.dart';
import '../services/catalog_store.dart';
import '../services/storage.dart';
import '../services/remote_config.dart';
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
import 'granths_screen.dart';

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
double folderPicSize(int cols) => switch (cols) {
      1 => 60,
      2 => 84,
      _ => 58,
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
    final subColor = dim ? GColors.muted : GColors.saffronDark;
    if (cols == 1) {
      return GCard(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        onTap: onTap,
        child: Row(children: [
          pic,
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text(title, maxLines: 2, overflow: TextOverflow.ellipsis, style: GText.script(size: 19, color: titleColor)),
              const SizedBox(height: 3),
              Text(subtitle, maxLines: 2, overflow: TextOverflow.ellipsis, style: GText.sans(size: 13, weight: FontWeight.w600, color: subColor)),
            ]),
          ),
          const SizedBox(width: 8),
          const GIcon('chevron-right', size: 20, color: GColors.muted),
        ]),
      );
    }
    final small = cols >= 3;
    return GCard(
      padding: EdgeInsets.symmetric(horizontal: small ? 6 : 10, vertical: small ? 10 : 14),
      onTap: onTap,
      child: SizedBox(
        width: double.infinity,
        child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
          pic,
          SizedBox(height: small ? 8 : 10),
          Text(title,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GText.script(size: small ? 14.5 : 18, color: titleColor, height: 1.3)),
          const SizedBox(height: 2),
          // 3×3 is narrow: "37 ग्रंथ • 551 प्रमाण" becomes two short lines
          Text(small ? subtitle.replaceAll(' • ', '\n') : subtitle,
              textAlign: TextAlign.center,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: GText.sans(size: small ? 11 : 12.5, weight: FontWeight.w600, color: subColor, height: 1.3)),
        ]),
      ),
    );
  }
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


const granthViewKey = Store.kGranthView;

/// Real bundled previews (2× captures, 780 px wide): the COMPLETE folder screen and the 3×3 list.
const double _kFoldersAspect = 780 / 1880;
const double _kListAspect = 780 / 1146;

/// Effective root Granth view: admin `ui.granth_view_mode` (folders/list) wins, else the
/// user's saved once-only choice, else folders. Old saved values are read unchanged.
String granthViewMode() => RemoteConfig.I.uiGranthViewMode ?? (Store.I.getString(granthViewKey) == 'list' ? 'list' : 'folders');

/// Only the root Granth section asks this, never dashboard or a deep link.
/// Choice is once-only and final: there is no user-facing "दृश्य बदलें" control.
/// When the admin forces a view, the chooser is skipped entirely.
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

  @override
  void dispose() {
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
    await Store.I.setString(granthViewKey, mode);
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

/// Genuine deterministic GranthApp screenshots with a light looping scroll preview.
/// See assets/previews/PROVENANCE.md. Shown once on first root Granth entry.
/// All text follows the app theme (Theme text styles + colour scheme), no fixed colours.
class GranthViewChoice extends StatelessWidget {
  const GranthViewChoice({super.key});

  double _previewHeight(BuildContext context, {required bool large}) {
    final scale = MediaQuery.textScalerOf(context).scale(16) / 16;
    final h = MediaQuery.sizeOf(context).height;
    if (large) return (h * .12).clamp(48.0, 80.0);
    // Tall enough at 320dp to read both full-width previews; still fits without dialog scroll.
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
        padding: EdgeInsets.all(large ? 6 : 8),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            _PreviewStrip(
              key: ValueKey('granth-view-preview-$mode'),
              asset: folders ? 'assets/previews/granth-folders-example.png' : 'assets/previews/granth-list-example.png',
              aspect: folders ? _kFoldersAspect : _kListAspect,
              semanticLabel: folders ? 'उदाहरण: असली ऐप का पूरा फ़ोल्डर दृश्य' : 'उदाहरण: सभी ग्रंथ का असली 3×3 ग्रिड',
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
      Row(children: [
        Expanded(
          child: Text(
            large ? 'ग्रंथ का दृश्य' : 'आप ग्रंथ कैसे देखना चाहेंगे',
            key: const ValueKey('granth-view-heading'),
            softWrap: true,
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
        ),
        IconButton(tooltip: 'पीछे', onPressed: () => Navigator.pop(context), icon: GIcon('x', size: 18, color: tt.bodyMedium?.color ?? cs.onSurface)),
      ]),
      SizedBox(height: large ? 6 : 12),
      LayoutBuilder(builder: (context, box) {
        // Never taller than the full 3×3 list example at this width (no empty band under it);
        // the taller complete folder screen scrolls inside the same height.
        final optW = (box.maxWidth - 8) / 2 - (large ? 12 : 16) - 2;
        final h = optW > 0 ? imageHeight.clamp(0.0, optW / _kListAspect) : imageHeight;
        return Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Expanded(child: _option(context, 'folders', 'फ़ोल्डर', 'श्रेणियों में', large, h)),
          const SizedBox(width: 8),
          Expanded(child: _option(context, 'list', 'सभी ग्रंथ', 'एक सूची में', large, h)),
        ]);
      }),
      SizedBox(height: large ? 4 : 10),
      Text(
        large ? 'एक बार · अंतिम' : 'एक बार चुनें · बाद में नहीं बदलेगा',
        key: const ValueKey('granth-view-note'),
        textAlign: TextAlign.center,
        maxLines: 2,
        overflow: TextOverflow.ellipsis,
        style: tt.bodySmall?.copyWith(color: tt.bodySmall?.color?.withValues(alpha: 0.72), height: 1.2),
      ),
    ]);
  }
}

/// Lightweight looping scroll over a real full-width screenshot (no video dependency).
/// The whole width is always visible (every folder column / all 3 list columns); the
/// strip scrolls top → bottom → top with a short pause at each end so the COMPLETE
/// screen is shown every loop. Stops on dispose; respects reduce-motion / एनिमेशन कम.
class _PreviewStrip extends StatefulWidget {
  const _PreviewStrip({
    super.key,
    required this.asset,
    required this.aspect,
    required this.semanticLabel,
    required this.height,
    required this.duration,
  });
  final String asset;
  final double aspect;
  final String semanticLabel;
  final double height;
  final Duration duration;

  @override
  State<_PreviewStrip> createState() => _PreviewStripState();
}

class _PreviewStripState extends State<_PreviewStrip> with SingleTickerProviderStateMixin {
  late final AnimationController _c;
  bool _motion = true;

  /// Pause ~18% at top and bottom, ease in between.
  static const _curve = Interval(0.18, 0.82, curve: Curves.easeInOutCubic);

  @override
  void initState() {
    super.initState();
    _c = AnimationController(vsync: this, duration: widget.duration);
  }

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

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: widget.height,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(8),
        child: LayoutBuilder(builder: (context, box) {
          final w = box.maxWidth;
          final stripH = w / widget.aspect;
          final maxY = (stripH - widget.height).clamp(0.0, double.infinity);
          final dpr = MediaQuery.devicePixelRatioOf(context);
          final image = Image.asset(
            widget.asset,
            semanticLabel: widget.semanticLabel,
            width: w,
            height: stripH,
            fit: BoxFit.fill,
            // Decode once at the on-screen size (sharp, light on memory).
            cacheWidth: (w * dpr).ceil().clamp(64, 780),
            filterQuality: FilterQuality.high,
          );
          return AnimatedBuilder(
            animation: _c,
            child: image,
            builder: (context, child) {
              final t = _motion ? _curve.transform(_c.value) : 0.0;
              return Stack(clipBehavior: Clip.hardEdge, children: [
                Positioned(top: -maxY * t, left: 0, width: w, height: stripH, child: child!),
              ]);
            },
          );
        }),
      ),
    );
  }
}
