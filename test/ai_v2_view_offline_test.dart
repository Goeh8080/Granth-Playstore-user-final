// OFFLINE UI projections only; backend §25 not reviewed/deployed, no real HTTP/device proof.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/quiz_v2.dart';
import 'package:granthprabandhan/widgets/quiz_v2_view.dart';
import 'package:granthprabandhan/theme/colors.dart';
import 'ai_v2_offline_test.dart' show publicQuestion, publicGrade;

void main() {
  Future<void> show(WidgetTester t, Widget w) async {
    await t.binding.setSurfaceSize(const Size(320, 640));
    addTearDown(() => t.binding.setSurfaceSize(null));
    await t.pumpWidget(
      MaterialApp(
        theme: buildTheme(),
        home: Scaffold(
          body: MediaQuery(
            data: const MediaQueryData(
              size: Size(320, 640),
              textScaler: TextScaler.linear(1.3),
            ),
            child: SingleChildScrollView(
              child: Padding(padding: const EdgeInsets.all(16), child: w),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  testWidgets(
    'OFFLINE 320dp: exact source choices, question/options only, colors only after submit',
    (t) async {
      final sources = <String>[];
      await show(t, QuizV2View(state: 'choose_source', onSource: sources.add));
      for (final label in ['वेद से', 'पुराण से', 'सारे ग्रंथ']) {
        expect(find.text(label), findsOneWidget);
      }
      await t.tap(find.text('वेद से'));
      expect(sources, ['ved']);
      final q = QuizV2Question.parse(publicQuestion())!;
      await show(t, QuizV2View(state: 'question', question: q));
      expect(find.text(q.text), findsOneWidget);
      expect(find.byType(Image), findsNothing);
      for (final id in ['a', 'b', 'c', 'd']) {
        final c = t.widget<AnimatedContainer>(
          find.byKey(ValueKey('quiz-v2-option-$id')),
        );
        expect(
          ((c.decoration as BoxDecoration).border as Border).top.color,
          isNot(Colors.green),
        );
        expect(
          ((c.decoration as BoxDecoration).border as Border).top.color,
          isNot(Colors.red),
        );
      }
      final grade = QuizV2Grade.parse(publicGrade(), q, 'a')!;
      await show(t, QuizV2View(state: 'graded', question: q, grade: grade));
      for (final id in ['a', 'b', 'c', 'd']) {
        final c = t.widget<AnimatedContainer>(
          find.byKey(ValueKey('quiz-v2-option-$id')),
        );
        expect(
          ((c.decoration as BoxDecoration).border as Border).top.color,
          id == 'b' ? Colors.green : Colors.red,
        );
      }
      expect(
        find.text('जमा करने के बाद जानकारी'),
        findsNothing,
        reason: 'no answer prose duplicated into quiz UI',
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'OFFLINE: exhausted is distinct from outage and supports choosing source afresh',
    (t) async {
      await show(t, const QuizV2View(state: 'exhausted', reason: 'all_seen'));
      expect(find.textContaining('सभी प्रश्न देख चुके'), findsOneWidget);
      await show(t, const QuizV2View(state: 'unavailable'));
      expect(find.textContaining('सभी प्रश्न देख चुके'), findsNothing);
      expect(t.takeException(), isNull);
    },
  );
}
