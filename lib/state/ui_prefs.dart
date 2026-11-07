import 'package:flutter/foundation.dart';

import '../services/catalog_store.dart';
import '../services/native_bridge.dart';
import '../services/pdf_builder.dart';
import '../services/remote_config.dart';
import '../services/storage.dart';

/// Card looks from the hidden "कार्ड स्टाइल" setting (`granth-look`).
const cardLooks = <(String, String)>[
  ('combo', 'Bento + Clay'),
  ('classic', 'सादा'),
  ('glass', 'Glassmorphism'),
  ('neu', 'Neumorphism'),
  ('clay', 'Claymorphism'),
  ('material', 'Material'),
  ('flat', 'Flat'),
  ('bento', 'Bento'),
];

/// Persisted UI preferences (same localStorage keys as the web app).
///
/// Like the original (`useState` first, then `localStorage.setItem`), a tap changes the
/// value on screen at once: reads come from memory, the file write follows.
class UiPrefs extends ChangeNotifier {
  UiPrefs._() {
    Store.I.adopted.addListener(refresh);
  }
  static final UiPrefs I = UiPrefs._();

  /// The card style; the hidden iOS theme ([theme] == 'ios') brings its own soft cards.
  String get look => theme == 'ios' ? 'ios' : (Store.I.getString(Store.kLook) ?? 'classic');

  /// Hidden app theme (Settings → tap the version 7 times): 'default' | 'ios'. Persisted.
  static const themes = [('default', 'डिफ़ॉल्ट'), ('ios', 'iOS')];
  String get theme => Store.I.getString(Store.kTheme) == 'ios' ? 'ios' : 'default';
  set theme(String v) {
    Store.I.setString(Store.kTheme, v == 'ios' ? 'ios' : 'default');
    notifyListeners();
  }

  set look(String v) {
    Store.I.setString(Store.kLook, v);
    notifyListeners();
  }

  /// Columns of a grid. Priority: admin force › the user's saved choice › admin default › 2.
  /// The result is always one of [allowed], so the grid button and the layout always match
  /// (an admin `3` on a 1|2 page is shown as 2, never as an unlabeled third column).
  int cols(String key, {required List<int> allowed, required int fallback, int? forced}) {
    int fit(int v) => allowed.contains(v) ? v : allowed.reduce((a, b) => (a - v).abs() <= (b - v).abs() ? a : b);
    if (forced != null) return fit(forced);
    final n = Store.I.getInt(key);
    if (n != null && n >= 1) return fit(n); // the user's choice, snapped to this page
    return fallback < 1 ? fallback : fit(fallback);
  }

  void setCols(String key, int v) {
    if (Store.I.getInt(key) == v) return;
    Store.I.setString(key, '$v');
    notifyListeners();
  }

  /// The admin forces this page's grid: the grid button is locked.
  bool gridLocked(String page) => RemoteConfig.I.gridForced(page) != null;

  /// Folder (shelves) and granth grids: force › the user's choice › admin default › 2.
  int get granthCols => cols(Store.kGranthCols, allowed: const [1, 2, 3], fallback: RemoteConfig.I.gridFor('granths') ?? 2, forced: RemoteConfig.I.gridForced('granths'));

  /// Folder (shelves) grid: same user choice as the granth grid; admin `grid_pages.shelves`.
  int get shelfCols => cols(Store.kGranthCols, allowed: const [1, 2, 3], fallback: RemoteConfig.I.gridFor('shelves') ?? 2, forced: RemoteConfig.I.gridForced('shelves'));

  /// Topic / praman / gallery grids (1|2).
  int pageCols(String page, String key) => cols(key, allowed: const [1, 2], fallback: RemoteConfig.I.gridFor(page) ?? 2, forced: RemoteConfig.I.gridForced(page));

  /// The signed config changed `ui.grid`: grids that still follow the default redraw.
  void remoteChanged() => notifyListeners();

  int get uiCols => cols(Store.kUiCols, allowed: const [1, 2], fallback: 2);

  /// `tg()` — the global layout switch in settings.
  void setLayout(int v) {
    for (final k in [Store.kUiCols, Store.kTopicCols, Store.kGranthCols, Store.kPramanCols, Store.kGalleryCols]) {
      Store.I.setString(k, '$v');
    }
    notifyListeners();
  }

  PdfStyle get pdfStyle => pdfStyleFrom(Store.I.getString(Store.kPdfStyle));
  set pdfStyle(PdfStyle s) {
    Store.I.setString(Store.kPdfStyle, pdfStyleId(s));
    notifyListeners();
  }

  // ---- Extra settings (added in round 5; the web app has none of these) ----

  /// Reading text size: small / normal / large.
  String get textSize => switch (Store.I.getString(Store.kTextSize)) {
    'small' => 'small',
    'large' => 'large',
    'xlarge' => 'xlarge',
    _ => 'normal',
  };
  set textSize(String v) {
    Store.I.setString(Store.kTextSize, v);
    textFactor.value = _factor(v);
    notifyListeners();
  }

  static double _factor(String v) => switch (v) {
    'small' => 0.9,
    'large' => 1.15,
    'xlarge' => 1.3,
    _ => 1.0,
  };

  /// Multiplier on the phone's own text size; only the app's text scaler listens to it.
  late final ValueNotifier<double> textFactor = ValueNotifier(_factor(textSize));

  /// Re-read the stored values (app start, reset). [start]: send keep-screen-on to
  /// the window (at start only when it is on — the window starts without it).
  void refresh({bool start = false}) {
    textFactor.value = _factor(textSize);
    if (!start || keepAwake) NativeBridge.keepScreenOn(keepAwake);
    notifyListeners();
  }

  bool _flag(String k, bool def) => switch (Store.I.getString(k)) {
    '1' || 'true' => true,
    '0' || 'false' => false,
    _ => def,
  };

  /// Picture download for offline use only on WiFi (default off: download on any network).
  bool get wifiOnly => _flag(Store.kWifiOnly, false);
  set wifiOnly(bool v) {
    Store.I.setString(Store.kWifiOnly, v ? '1' : '0');
    notifyListeners();
    // Turned off while on mobile data: the waiting download can go now.
    final s = CatalogStore.I;
    if (!v && s.hasData && s.savedPages < s.allPages) s.savePages();
  }

  /// Background downloads (pages for offline use, PDFs re-made by themselves when the net is
  /// back). Default on. Off: pages and PDFs download only when the user taps.
  bool get autoDownload => _flag(Store.kAutoDownload, true);
  set autoDownload(bool v) {
    Store.I.setString(Store.kAutoDownload, v ? '1' : '0');
    notifyListeners();
    final s = CatalogStore.I;
    if (v && s.hasData && s.savedPages < s.allPages) s.savePages();
  }

  /// The 2-minute / on-resume refresh (default on).
  /// Round-3: the user's own taskbar choice; null = never chosen.
  bool? get taskbarLocal => switch (Store.I.getString(Store.kTaskbar)) {
    '1' => true,
    '0' => false,
    _ => null,
  };
  set taskbar(bool v) {
    Store.I.setString(Store.kTaskbar, v ? '1' : '0');
    notifyListeners();
  }

  /// Whether the bottom tab bar is on: the admin's `ui.taskbar.force` wins, then the user's own
  /// choice, then the admin's default, then off (fresh install).
  bool get taskbar => resolveTaskbar(RemoteConfig.I.uiTaskbar, taskbarLocal);

  /// The admin forces the bar on/off (the Settings toggle is then locked).
  bool get taskbarForced => RemoteConfig.I.uiTaskbar.force != null;

  bool get autoSync => _flag(Store.kAutoSync, true);
  set autoSync(bool v) {
    Store.I.setString(Store.kAutoSync, v ? '1' : '0');
    notifyListeners();
  }

  /// Keep the screen on while the app is open (default off).
  bool get keepAwake => _flag(Store.kKeepAwake, false);
  set keepAwake(bool v) {
    Store.I.setString(Store.kKeepAwake, v ? '1' : '0');
    NativeBridge.keepScreenOn(v);
    notifyListeners();
  }

  /// Settings → "एनिमेशन" चालू / कम (default चालू). "कम" switches off the decorative entrance
  /// animations added in round 8 (card scale-pop, blur-focus, inner stagger); the dashboard
  /// count-up, the menu, the tilt on opening a granth and the splash are not touched.
  bool get animations => _flag(Store.kAnimations, true);
  set animations(bool v) {
    Store.I.setString(Store.kAnimations, v ? '1' : '0');
    notifyListeners();
  }

  /// Settings → "सेटिंग रीसेट करें": every setting back to its default. Downloaded granths,
  /// pages, gallery and PDFs are never touched.
  static const settingKeys = [
    Store.kLook, Store.kTheme, Store.kUiCols, Store.kTopicCols, Store.kGranthCols, Store.kPramanCols, Store.kGalleryCols, //
    Store.kPdfStyle, Store.kTextSize, Store.kWifiOnly, Store.kAutoDownload, Store.kAutoSync, Store.kKeepAwake, Store.kAnimations, Store.kTaskbar,
  ];
  Future<void> resetAll() async {
    for (final k in settingKeys) {
      await Store.I.remove(k);
    }
    refresh();
  }
}
