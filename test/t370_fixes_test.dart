// t365 tester list: ज्ञान चर्चा repeats, global granth search, last 5 searches.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/ai_client.dart';
import 'package:granthprabandhan/ai/quiz_recent.dart';
import 'package:granthprabandhan/services/search.dart';
import 'package:granthprabandhan/services/search_history.dart';
import 'package:granthprabandhan/widgets/common.dart';

import 'helpers.dart';

void main() {
  setUp(setUpApp);

  test('ज्ञान चर्चा: asked questions are remembered across sessions (id + text) and sent as avoid ids', () async {
    expect(RecentQuiz.I.seen('1e08501d60739092', 'कबीर साहेब कब प्रकट हुए?'), isFalse);
    await RecentQuiz.I.add('1e08501d60739092', 'कबीर साहेब कब प्रकट हुए?');
    expect(RecentQuiz.I.seen('1e08501d60739092', ''), isTrue);
    expect(RecentQuiz.I.seen('ffffffffffffffff', 'कबीर  साहेब कब प्रकट हुए'), isTrue, reason: 'same text, other id');
    expect(RecentQuiz.I.recentIds(), ['1e08501d60739092']);
    final body = buildAskBody('x', const [], const [], mode: 'gyan_charcha', avoid: RecentQuiz.I.recentIds());
    expect(body['avoid_question_ids'], ['1e08501d60739092']);
    expect(buildAskBody('x', const [], const [], avoid: RecentQuiz.I.recentIds()).containsKey('avoid_question_ids'), isFalse, reason: 'only in ज्ञान चर्चा');
  });

  test('search inside a folder covers every granth, the folder\'s own matches first', () {
    final all = ['ऋग्वेद', 'विष्णु पुराण', 'यजुर्वेद', 'वेद पुराण कथा'];
    SearchDoc doc(String s) => makeDoc(s);
    final folder = ['विष्णु पुराण', 'वेद पुराण कथा'];
    final r = globalSearchRows(folder, all, 'वेद', doc);
    expect(r.first, 'वेद पुराण कथा');
    expect(r, containsAll(['ऋग्वेद', 'यजुर्वेद']));
    expect(globalSearchRows(folder, all, '  ', doc), folder);
  });

  testWidgets('last 5 searches under the box: tap reuses, × forgets one, मिटाएँ clears', (t) async {
    for (final q in ['a1', 'a2', 'a3', 'a4', 'a5', 'a6']) {
      await SearchHistory.remember(q);
    }
    expect(SearchHistory.recent, ['a6', 'a5', 'a4', 'a3', 'a2']);
    String? got;
    await t.pumpWidget(MaterialApp(home: Scaffold(body: SearchField(placeholder: 'x', debounce: Duration.zero, onChanged: (v) => got = v))));
    await t.tap(find.byType(TextField));
    await t.pump();
    expect(find.byKey(const ValueKey('search-history')), findsOneWidget);
    await t.tap(find.byKey(const ValueKey('search-history-a4')));
    await t.pump();
    expect(got, 'a4');
    await t.tap(find.byType(TextField));
    await t.pump();
    await t.tap(find.byKey(const ValueKey('search-history-clear')));
    await t.pumpAndSettle();
    expect(SearchHistory.recent, isEmpty);
  });
}
