// t362: icon pack v2 — keep all 26 old icons, add 20 folder + 10 religion keys.
// Each new key keeps its id and paints a distinct (non-fallback) symbol;
// an unknown key still maps to and paints as `misc`.
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/widgets/group_icon.dart';
import 'package:granthprabandhan/widgets/religion_symbol.dart';

const _oldFolders = [
  'scroll', 'book-red', 'book-green', 'book-blue', 'book-orange', 'swords', 'books', 'quran', 'hadees',
  'granth-sahib', 'dasam', 'bible', 'tripitak', 'dhammapad', 'kabir-sagar', 'bijak', 'shabdavali', 'misc',
];
const _oldReligions = ['om', 'crescent', 'khanda', 'cross', 'dharma', 'jain', 'kabir', 'misc'];

Future<List<int>> _pixels(void Function(Canvas, Size) paint) async {
  final rec = ui.PictureRecorder();
  paint(Canvas(rec), const Size(48, 48));
  final pic = rec.endRecording();
  final img = await pic.toImage(48, 48);
  final data = await img.toByteData(format: ui.ImageByteFormat.rawRgba);
  img.dispose();
  pic.dispose();
  return data!.buffer.asUint8List();
}

Future<List<int>> _group(String name) => _pixels(GroupIconPainter(name).paint);
Future<List<int>> _religion(String name) => _pixels((c, s) => ReligionSymbolPainter(name, const Color(0xFF5A3A1A)).paint(c, s));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('icon pack v2 keys: all 26 old kept, 30 new resolve, unknown → misc', () {
    expect(_oldFolders, groupIconNames);
    expect(_oldReligions, religionSymbolNames);
    expect(newGroupIconNames, [
      'gita', 'ved', 'ramayan', 'mahabharat', 'puran', 'upanishad', 'bhagwat', 'shiv', 'devi', 'hanuman',
      'satsang', 'bhajan', 'aarti', 'mala', 'kalash', 'mandir', 'sant-vani', 'gyan', 'amritvani', 'sakhi',
    ]);
    expect(newReligionSymbolNames, ['swastik', 'trishul', 'kamal', 'deepak', 'shikhar', 'mangal-kalash', 'surya', 'vriksh', 'bahai', 'atash']);
    for (final k in _oldFolders) {
      expect(groupIconKey(k), k, reason: 'old folder $k kept');
    }
    for (final k in _oldReligions) {
      expect(religionIconKey(k), k, reason: 'old religion $k kept');
    }
    expect(religionIconKey('ektara'), 'kabir');
    for (final k in newGroupIconNames) {
      expect(groupIconKey(k), k, reason: k);
    }
    for (final k in newReligionSymbolNames) {
      expect(religionIconKey(k), k, reason: k);
    }
    expect(groupIconKey('no-such-icon'), 'misc');
    expect(religionIconKey('no-such-icon'), 'misc');
    expect(religionIconKey(null), 'misc');
  });

  testWidgets('new keys paint a non-fallback symbol; unknown still paints misc', (t) async {
    final got = await t.runAsync(() async {
      final folderMisc = await _group('misc');
      final folderUnknown = await _group('no-such-icon');
      final folderNew = <String, List<int>>{for (final k in newGroupIconNames) k: await _group(k)};
      final religionMisc = await _religion('misc');
      final religionUnknown = await _religion('no-such-icon');
      final religionNew = <String, List<int>>{for (final k in newReligionSymbolNames) k: await _religion(k)};
      return (folderMisc, folderUnknown, folderNew, religionMisc, religionUnknown, religionNew);
    });
    expect(got, isNotNull);
    final (folderMisc, folderUnknown, folderNew, religionMisc, religionUnknown, religionNew) = got!;
    expect(folderUnknown, folderMisc, reason: 'unknown folder key falls back to misc');
    expect(religionUnknown, religionMisc, reason: 'unknown religion key falls back to misc');
    for (final e in folderNew.entries) {
      expect(e.value, isNot(equals(folderMisc)), reason: 'folder ${e.key} is not the misc fallback');
    }
    for (final e in religionNew.entries) {
      expect(e.value, isNot(equals(religionMisc)), reason: 'religion ${e.key} is not the misc fallback');
    }
  });
}
