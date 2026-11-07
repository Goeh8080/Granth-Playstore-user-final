import 'package:flutter/foundation.dart';

/// App logger: prints in debug/profile builds, does nothing in release (no log spam, nothing
/// sensitive in logcat). Use instead of `print` / `debugPrint`.
void log(Object? message) {
  if (kReleaseMode) return;
  debugPrint('$message');
}
