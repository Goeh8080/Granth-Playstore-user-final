import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/main.dart';

/// Production hardening: friendly release error widget, no raw print/debugPrint in app code,
/// and the release build settings stay on.
void main() {
  testWidgets('release error widget is a calm Hindi note, never the error text', (t) async {
    await t.pumpWidget(releaseErrorWidget(FlutterErrorDetails(exception: Exception('secret stack'))));
    expect(find.byKey(const ValueKey('release-error-widget')), findsOneWidget);
    expect(find.textContaining('secret'), findsNothing);
  });

  test('app code logs only through util/log.dart (no-op in release)', () {
    final bad = <String>[];
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart') || f.path.contains('highlighter') || f.path.endsWith('util/log.dart')) continue;
      final s = f.readAsStringSync();
      if (RegExp(r'(?<![\w.])(print|debugPrint)\(').hasMatch(s)) bad.add(f.path);
    }
    expect(bad, isEmpty);
  });

  test('release build: R8 + resource shrinking on, not debuggable, targetSdk ≥ 35, no cleartext', () {
    final g = File('android/app/build.gradle.kts').readAsStringSync();
    expect(g, contains('isMinifyEnabled = true'));
    expect(g, contains('isShrinkResources = true'));
    expect(g, contains('isDebuggable = false'));
    expect(g, contains('targetSdk = maxOf(flutter.targetSdkVersion, 36)'));
    final m = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
    expect(m, contains('android:usesCleartextTraffic="false"'));
    expect(m, isNot(contains('android:debuggable')));
    expect(File('pubspec.yaml').readAsStringSync(), contains('version: 1.0.0+1'));
  });
}
