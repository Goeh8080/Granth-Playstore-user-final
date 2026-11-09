// Backend folder shapes: nested sub-folders (like वेद › ऋग्वेद) and the auto 'general' sub-folder.
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/models/models.dart';
import 'package:granthprabandhan/models/structure.dart';

Granth _g(String id, String title, int pos) => Granth({'id': id, 'title': title, 'position': '$pos'});

void main() {
  Structure s(Map<String, dynamic> group) => Structure.parse('''{"version":1,"religions":[{"id":"hindu","title":"हिन्दू","groups":[${_j(group)}]}]}''');

  test('backend shape: own granths moved to general sub-folder render nested', () {
    final st = s({'id': 'puran', 'title': 'पुराण', 'subgroups': [
      {'id': 'shiv', 'title': 'शिव पुराण', 'granthIds': ['1']},
      {'id': 'general', 'title': 'अन्य पुराण', 'granthIds': ['2', '3']},
    ]});
    final idx = ShelfIndex.build(st, [_g('1', 'a', 1), _g('2', 'b', 2), _g('3', 'c', 3)]);
    expect(idx.placements['2']!.key, 'hindu/puran/general');
    expect(idx.inGroup('hindu', 'puran').length, 3);
    expect(idx.visibleSubgroups('hindu', 'puran').map((e) => e.id), ['shiv', 'general']);
  });

  test('mixed group (own ids + sub-folders) keeps its granths in a synthetic general', () {
    final st = s({'id': 'puran', 'title': 'पुराण', 'granthIds': ['2'], 'subgroups': [
      {'id': 'shiv', 'title': 'शिव पुराण', 'granthIds': ['1']},
    ]});
    final idx = ShelfIndex.build(st, [_g('1', 'a', 1), _g('2', 'b', 2)], overrides: {'1': 'hindu/puran'});
    expect(idx.placements['2']!.key, 'hindu/puran/general');
    expect(idx.placements['1']!.key, 'hindu/puran/general', reason: 'override to the parent group lands in general');
    final gen = idx.visibleSubgroups('hindu', 'puran').firstWhere((e) => e.id == 'general');
    expect(gen.title, 'अन्य पुराण');
  });

  test('flat group (no sub-folders) is unchanged', () {
    final st = s({'id': 'gita', 'title': 'गीता', 'granthIds': ['5']});
    final idx = ShelfIndex.build(st, [_g('5', 'x', 1)]);
    expect(idx.placements['5']!.key, 'hindu/gita');
  });
}

String _j(Object o) {
  if (o is Map) return '{${o.entries.map((e) => '"${e.key}":${_j(e.value!)}').join(',')}}';
  if (o is List) return '[${o.map((e) => _j(e as Object)).join(',')}]';
  return '"$o"';
}
