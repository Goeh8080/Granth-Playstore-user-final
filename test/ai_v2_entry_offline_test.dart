// OFFLINE actual app entry tests, frozen7cbcb93 public contract. No live verification.
import 'dart:async';
import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/ai/ai_client.dart';
import 'package:granthprabandhan/ai/chat_controller.dart';
import 'package:granthprabandhan/ai/chat_store.dart';
import 'package:granthprabandhan/ai/quiz_v2_flow.dart';
import 'package:granthprabandhan/ai/v2_drafts.dart';
import 'package:granthprabandhan/screens/ai_screen.dart';
import 'package:granthprabandhan/services/ai_feedback.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/theme/colors.dart';
import 'helpers.dart';
import 'ai_v2_flow_offline_test.dart' show QuizNet;

void main() {
  late QuizNet net;
  late AiV2Flow flow;
  late AiV2Flow old;
  String? owner;
  setUp(() async {
    await setUpApp();
    RemoteConfig.I.debugReset();
    owner = 'owner-a';
    net = QuizNet();
    old = AiV2Flow.I;
    flow = AiV2Flow.I = AiV2Flow(
      dio: Dio()..httpClientAdapter = net,
      base: 'https://offline.invalid',
      appKey: 'test-key',
      owner: () => owner,
      token: () async => 'mock-token',
      rollout: true,
      drafts: AiV2DraftStore(),
    );
    ChatController.I = ChatController(
      client: AiClient(endpoint: 'https://offline.invalid/ask'),
      store: ChatStore.fresh(),
    );
    AiFeedback.I = AiFeedback(enabled: false);
  });
  tearDown(() {
    AiV2Flow.I = old;
    flow.dispose();
  });
  Future<void> show(WidgetTester t, {bool bubble = false}) async {
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
            child: CustomScrollView(
              slivers: [
                if (bubble)
                  SliverToBoxAdapter(
                    child: AnswerBubble(
                      msg: const ChatMsg(
                        role: 'assistant',
                        text: 'उत्तर',
                        at: 42,
                      ),
                      question: 'प्रश्न',
                      find: (_) => null,
                      chatId: 'chat',
                    ),
                  )
                else
                  const AiPanel(),
              ],
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
  }

  Future<void> settleNet(WidgetTester t) async {
    for (var i = 0; i < 8; i++) {
      await t.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await t.pump(const Duration(milliseconds: 400));
    }
    await t.pumpAndSettle();
  }

  testWidgets(
    'OFFLINE actual Gyan entry: source choice, submitted colors, owned quiz report and logout hiding',
    (t) async {
      await show(t);
      await t.tap(find.byKey(const ValueKey('ai-gyan')));
      await settleNet(t);
      expect(find.text('वेद से'), findsOneWidget);
      expect(find.text('पुराण से'), findsOneWidget);
      expect(find.text('सारे ग्रंथ'), findsOneWidget);
      await t.tap(find.text('वेद से'));
      await t.pumpAndSettle();
      expect(flow.question, isNotNull);
      expect(flow.grade, isNull);
      await t.tap(find.byKey(const ValueKey('quiz-v2-option-a')));
      await t.pumpAndSettle();
      expect(flow.grade!.correctByOption['a'], false);
      expect(flow.grade!.correctByOption['b'], true);
      net.flagsStatus = 503;
      await t.ensureVisible(find.text('इस प्रश्न की रिपोर्ट'));
      await t.tap(find.text('इस प्रश्न की रिपोर्ट'));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('ai-reason-send')));
      await t.pumpAndSettle();
      await settleNet(t);
      expect(flow.drafts.reports('owner-a').length, 1);
      final draft = flow.drafts.reports('owner-a').single;
      expect((draft['payload'] as Map)['context'], 'gyan_charcha');
      expect((draft['payload'] as Map).containsKey('question'), false);
      expect(draft['status'], 'queued');
      owner = null;
      await t.runAsync(flow.prepare);
      await t.pumpAndSettle();
      expect(flow.question, isNull);
      expect(flow.grade, isNull);
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'OFFLINE actual normal-chat flags: durable queued label, 202 ACK and distinct context',
    (t) async {
      net.flagsStatus = 503;
      await show(t, bubble: true);
      await t.ensureVisible(find.byKey(const ValueKey('ai-down')));
      await t.tap(find.byKey(const ValueKey('ai-down')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const ValueKey('ai-reason-send')));
      await t.pumpAndSettle();
      await settleNet(t);
      expect(find.text('भेजना बाकी'), findsOneWidget);
      expect(flow.drafts.reports('owner-a').length, 1);
      final report = flow.drafts.reports('owner-a').single;
      expect((report['payload'] as Map)['context'], 'normal_chat');
      final id = (report['payload'] as Map)['client_report_id'];
      net.flagsStatus = 202;
      unawaited(flow.flushReports());
      await settleNet(t);
      await t.pumpAndSettle();
      expect(find.text('भेजा ✓'), findsOneWidget);
      expect(
        (flow.drafts.reports('owner-a').single['payload']
            as Map)['client_report_id'],
        id,
      );
      expect(t.takeException(), isNull);
    },
  );
  testWidgets(
    'OFFLINE known admin-disabled quiz does not fall back to legacy ask',
    (t) async {
      net.enabled = false;
      await show(t);
      await t.tap(find.byKey(const ValueKey('ai-gyan')));
      await settleNet(t);
      expect(net.paths.where((p) => p.endsWith('/capabilities')).length, 1);
      expect(
        net.paths.any((p) => p.contains('/session') || p.contains('/ask')),
        false,
      );
      expect(find.text('वेद से'), findsNothing);
      await t.pump(const Duration(seconds: 3));
    },
  );
}
