import 'dart:async';
import 'dart:convert';

import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/ai_client.dart';
import 'package:granthprabandhan/ai/chat_controller.dart';
import 'package:granthprabandhan/ai/chat_store.dart';
import 'package:granthprabandhan/ai/retriever.dart';
import 'package:granthprabandhan/screens/ai_screen.dart';
import 'package:granthprabandhan/services/ai_feedback.dart';
import 'package:granthprabandhan/services/catalog_store.dart';
import 'package:granthprabandhan/state/places.dart';
import 'package:granthprabandhan/state/router.dart';

import 'ai_chat_ui_test.dart' show GateClient, catalog, until;
import 'helpers.dart';
import 'links_grid_test.dart' show settle;
import 'round14_test.dart' as r14;
import 'round5_test.dart' show fingerTap, openApp;

void main() {
  group('refs / correction parsing', () {
    test('missing fields: nothing changes (w2 answers)', () {
      expect(parseRefs(null), isEmpty);
      expect(AiCorrection.fromJson(null), isNull);
      expect(AiCorrection.fromJson({'detected': false}), isNull);
      final m = ChatMsg.fromJson({'role': 'assistant', 'text': 'x', 'at': 1})!;
      expect(m.refs, isEmpty);
      expect(m.correction, isNull);
      expect(m.toJson().containsKey('refs'), isFalse);
      expect(m.toJson().containsKey('correction'), isFalse);
    });
    test('bad items are dropped, routes are whitelisted, at most 12', () {
      final r = parseRefs([
        {'type': 'praman', 'id': 442, 'title': 'T', 'route': '#/pramans?id=442', 'cited': true},
        {'type': 'note', 'id': 3, 'title': 'N', 'route': null, 'cited': true},
        {'type': 'topic', 'id': 5, 'route': 'https://evil.example', 'cited': false},
        {'type': 'video', 'id': 1},
        {'type': 'granth', 'id': '4'},
        'junk',
        for (var i = 1; i <= 20; i++) {'type': 'granth', 'id': i, 'route': '#/pramans?granth=$i'},
      ]);
      expect(r.length, 9, reason: 'take(12) applies to the raw list; 3 of those are invalid');
      expect(r[0].route, '#/pramans?id=442');
      expect(r[0].cited, isTrue);
      expect(r[1].route, isNull);
      expect(r[2].route, isNull);
    });
    test('refs and correction survive a save/load', () {
      final m = ChatMsg(
        role: 'assistant',
        text: 'x',
        refs: const [AiRef(type: 'topic', id: 7, title: 'विषय', route: '#/pramans?topic=7')],
        correction: const AiCorrection(question: 'q', answer: 'a', text: 't'),
      );
      final back = ChatMsg.fromJson(jsonDecode(jsonEncode(m.toJson())))!;
      expect(back.refs.single.route, '#/pramans?topic=7');
      expect(back.correction!.text, 't');
    });
    test('correct() posts kind:"correction" to /ai/flags', () async {
      final f = r14.Fake([202]);
      final fb = AiFeedback(dio: Dio()..httpClientAdapter = f, base: 'https://a.test', appKey: 'k', iid: () => 'iid1', enabled: true);
      await fb.correct('c-1', question: 'प्रश्न', answer: 'उत्तर', correction: ' सही उत्तर ');
      final body = f.seen.single.data is String ? jsonDecode(f.seen.single.data as String) : f.seen.single.data;
      expect(f.seen.single.uri.toString(), 'https://a.test/ai/flags');
      expect(body['kind'], 'correction');
      expect(body['correction'], 'सही उत्तर');
      expect(fb.queue, isEmpty);
    });
  });

  group('refs pills + correction button (320dp)', () {
    late GateClient client;
    setUp(() async {
      await setUpApp();
      Places.forgetLive();
      Retriever.I.reset();
      CatalogStore.I.debugSetCatalog(catalog());
      client = GateClient();
      ChatController.I = ChatController(client: client, store: ChatStore.fresh());
    });

    Future<void> ask(WidgetTester t, AiAnswer a) async {
      client.next = a;
      await openApp(t);
      await t.binding.setSurfaceSize(const Size(320, 640));
      addTearDown(() => t.binding.setSurfaceSize(null));
      t.platformDispatcher.textScaleFactorTestValue = 1.3;
      addTearDown(t.platformDispatcher.clearTextScaleFactorTestValue);
      AppNav.I.go('#/ai');
      await settle(t);
      await until(t, () => ChatController.I.loaded);
      unawaited(askQuestion('प्रश्न'));
      await until(t, () => ChatController.I.messages.length == 2);
    }

    testWidgets('refs show as pills, cited first; a tap opens the route; no overflow', (t) async {
      final p = CatalogStore.I.pramans.first;
      final long = 'बहुत लंबा शीर्षक ' * 8;
      await ask(
        t,
        AiAnswer(
          answer: 'उत्तर',
          cited: [int.parse(p.id)],
          provider: 'x',
          refs: [
            const AiRef(type: 'topic', id: 9, title: 'विषय', route: '#/pramans?topic=9'),
            AiRef(type: 'praman', id: int.parse(p.id), title: long, route: '#/pramans?id=${p.id}', cited: true),
            const AiRef(type: 'note', id: 3, title: 'नोट', cited: true),
          ],
        ),
      );
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('ai-refs')), findsOneWidget);
      expect(find.byKey(ValueKey('ai-ref-0-praman-${p.id}')), findsOneWidget, reason: 'cited first');
      expect(find.byKey(const ValueKey('ai-ref-1-topic-9')), findsOneWidget);
      expect(find.byKey(const ValueKey('ai-ref-1-note-3')), findsNothing, reason: 't184: note refs are hidden');
      expect(find.textContaining('नोट'), findsNothing);
      expect(find.byKey(const ValueKey('ai-send-correction')), findsNothing);
      await t.ensureVisible(find.byKey(const ValueKey('ai-ref-1-topic-9')));
      await settle(t, 3);
      await fingerTap(t, find.byKey(const ValueKey('ai-ref-1-topic-9')), wobble: Offset.zero);
      await settle(t, 4);
      expect(AppNav.I.hash, '#/pramans?topic=9');
      await t.pumpWidget(const SizedBox());
      await until(t, () => false);
    });

    testWidgets('a correction answer offers "सुधार एडमिन को भेजें"', (t) async {
      await ask(
        t,
        const AiAnswer(answer: 'धन्यवाद, आपका सुधार', cited: [], provider: 'x', correction: AiCorrection(question: 'q', answer: 'a', text: 'ये गलत है, असल में …')),
      );
      expect(t.takeException(), isNull);
      expect(find.byKey(const ValueKey('ai-send-correction')), findsOneWidget);
      expect(find.text('सुधार एडमिन को भेजें'), findsOneWidget);
      await t.pump(const Duration(seconds: 8));
    });
  });
}
