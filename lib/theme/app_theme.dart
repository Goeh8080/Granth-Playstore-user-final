/// t430 — admin theme override: optional top-level `theme` key of /config.json:
///
/// ```json
/// "theme": {"primary": "#RRGGBB", "secondary": "#RRGGBB", "background": "#RRGGBB",
///           "surface": "#RRGGBB", "login_gradient": ["#RRGGBB", "#RRGGBB"]}
/// ```
///
/// Every field is optional; an invalid field is ignored on its own; no key = the bundled
/// defaults (the app's own saffron / maroon / peach accents on pure white). Applied on the next
/// config sync without a restart. The splash never uses it.
library;

import 'package:flutter/material.dart';

import 'colors.dart';

/// `#RRGGBB` / `#rrggbb` → opaque colour; anything else → null.
Color? parseHexColor(Object? v) {
  if (v is! String) return null;
  final m = RegExp(r'^#([0-9a-fA-F]{6})$').firstMatch(v.trim());
  if (m == null) return null;
  return Color(0xFF000000 | int.parse(m.group(1)!, radix: 16));
}

class ThemeOverride {
  const ThemeOverride({this.primary, this.secondary, this.background, this.surface, this.loginGradient});
  final Color? primary, secondary, background, surface;

  /// 2–4 colours, else null.
  final List<Color>? loginGradient;
  static const none = ThemeOverride();

  static ThemeOverride parse(Object? raw) {
    if (raw is! Map) return none;
    List<Color>? grad;
    final g = raw['login_gradient'];
    if (g is List && g.length >= 2 && g.length <= 4) {
      final c = [for (final e in g) parseHexColor(e)];
      if (c.every((e) => e != null)) grad = c.cast<Color>();
    }
    return ThemeOverride(
      primary: parseHexColor(raw['primary']),
      secondary: parseHexColor(raw['secondary']),
      background: parseHexColor(raw['background']),
      surface: parseHexColor(raw['surface']),
      loginGradient: grad,
    );
  }

  @override
  bool operator ==(Object other) =>
      other is ThemeOverride && other.primary == primary && other.secondary == secondary && other.background == background && other.surface == surface && '${other.loginGradient}' == '$loginGradient';
  @override
  int get hashCode => Object.hash(primary, secondary, background, surface, '$loginGradient');
}

/// The live palette (bundled defaults + the admin's override).
class AppTheme extends ChangeNotifier {
  AppTheme._();
  static final AppTheme I = AppTheme._();

  /// Bundled login background: the app's peach / saffron / cream, slowly moving.
  static const defaultLoginGradient = [Color(0xFFFFFFFF), Color(0xFFFCE3C6), Color(0xFFF8C99A), Color(0xFFFDF0E2)];

  ThemeOverride _o = ThemeOverride.none;
  ThemeOverride get override => _o;

  Color get primary => _o.primary ?? GColors.maroon;
  Color get secondary => _o.secondary ?? GColors.saffron;
  Color get background => _o.background ?? GColors.cream;
  Color get surface => _o.surface ?? GColors.paper;
  List<Color> get loginGradient => _o.loginGradient ?? defaultLoginGradient;

  void apply(Object? raw) {
    final n = ThemeOverride.parse(raw);
    if (n == _o) return;
    _o = n;
    notifyListeners();
  }
}
