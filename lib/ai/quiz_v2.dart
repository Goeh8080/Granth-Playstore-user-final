/// Additive CONTRACT §25. Reviewed frozen7cbcb93: LOCAL backend, production rollout intentionally OFF.
/// Public app uses only public DTOs, never Tatv's private authority/answer-key envelopes.
const kAiV2RolloutEnabled = false;

Map<String, dynamic> aiObject(Object? x) =>
    x is Map<String, dynamic> ? x : const {};

class AiV2Capabilities {
  AiV2Capabilities.parse(Object? value) : raw = aiObject(value);
  final Map<String, dynamic> raw;
  static const endpoints = {
    'create': '/ai/quiz/session',
    'next': '/ai/quiz/session/{session_id}/next',
    'attempt': '/ai/quiz/session/{session_id}/attempt',
  };
  bool get supported => raw['schema_version'] == 1;
  bool get quizEnabled {
    final q = aiObject(raw['quiz']);
    final paths = aiObject(q['endpoints']);
    return supported &&
        q['enabled'] == true &&
        (q['versions'] is List && (q['versions'] as List).contains(2)) &&
        q['identity'] == 'verified_google' &&
        q['reveal'] == 'after_submit' &&
        q['strict_source'] == true &&
        q['no_repeats'] == true &&
        q['question_types'] is List &&
        (q['question_types'] as List).length == 1 &&
        (q['question_types'] as List).single == 'single_choice' &&
        q['sources'] is List &&
        const [
          'ved',
          'puran',
          'all',
        ].every((s) => (q['sources'] as List).contains(s)) &&
        endpoints.entries.every((e) => paths[e.key] == e.value);
  }

  bool flagsEnabled(String context) {
    final f = aiObject(raw['flags']);
    return supported &&
        const ['normal_chat', 'gyan_charcha'].contains(context) &&
        f['versions'] is List &&
        (f['versions'] as List).contains(2) &&
        f['contexts'] is List &&
        (f['contexts'] as List).contains(context) &&
        f['kinds'] is List &&
        const [
          'thumbs_down',
          'correction',
        ].every((k) => (f['kinds'] as List).contains(k));
  }

  // Even a misconfigured server must not advertise unimplemented authority/voice paths.
  bool get navigatorAvailable => false;
  bool get normalChatSuppressionAvailable => false;
}

class QuizV2Option {
  const QuizV2Option(this.id, this.text);
  final String id, text;
}

class QuizV2Question {
  const QuizV2Question(
    this.sessionId,
    this.source,
    this.id,
    this.revision,
    this.attemptId,
    this.text,
    this.options,
  );
  final String sessionId, source, id, attemptId, text;
  final int revision;
  final List<QuizV2Option> options;
  static QuizV2Question? parse(Object? envelope) {
    final e = aiObject(envelope), q = aiObject(e['question']);
    bool id(Object? v) =>
        v is String && RegExp(r'^[A-Za-z0-9_.:-]{1,128}$').hasMatch(v);
    if (e['schema_version'] != 2 ||
        e['state'] != 'question' ||
        e['result'] != null ||
        !id(e['session_id']) ||
        !const ['ved', 'puran', 'all'].contains(e['source'])) {
      return null;
    }
    if (q.keys.any(
          (k) => !const [
            'question_id',
            'revision',
            'attempt_id',
            'type',
            'text',
            'options',
          ].contains(k),
        ) ||
        q['type'] != 'single_choice' ||
        !id(q['question_id']) ||
        !id(q['attempt_id']) ||
        q['revision'] is! int ||
        (q['revision'] as int) < 1 ||
        q['text'] is! String ||
        (q['text'] as String).trim().isEmpty ||
        (q['text'] as String).length > 4000 ||
        q['options'] is! List) {
      return null;
    }
    final options = <QuizV2Option>[], ids = <String>{}, texts = <String>{};
    for (final raw in q['options'] as List) {
      final o = aiObject(raw);
      if (o.keys.any((k) => k != 'id' && k != 'text') ||
          o['id'] is! String ||
          !RegExp(r'^[a-z][a-z0-9_]{0,15}$').hasMatch(o['id']) ||
          o['text'] is! String ||
          (o['text'] as String).trim().isEmpty ||
          (o['text'] as String).length > 1000 ||
          !ids.add(o['id']) ||
          !texts.add((o['text'] as String).trim())) {
        return null;
      }
      options.add(QuizV2Option(o['id'], o['text']));
    }
    if (options.length < 2 || options.length > 6) return null;
    return QuizV2Question(
      e['session_id'],
      e['source'],
      q['question_id'],
      q['revision'],
      q['attempt_id'],
      q['text'],
      List.unmodifiable(options),
    );
  }

  Map<String, dynamic> toEnvelope() => {
    'schema_version': 2,
    'state': 'question',
    'session_id': sessionId,
    'source': source,
    'question': {
      'question_id': id,
      'revision': revision,
      'attempt_id': attemptId,
      'type': 'single_choice',
      'text': text,
      'options': [
        for (final o in options) {'id': o.id, 'text': o.text},
      ],
    },
    'result': null,
  };
}

class QuizV2Grade {
  const QuizV2Grade(this.correctByOption, this.feedback);
  final Map<String, bool> correctByOption;
  final String? feedback;
  static QuizV2Grade? parse(
    Object? envelope,
    QuizV2Question question,
    String selected,
  ) {
    final e = aiObject(envelope), r = aiObject(e['result']);
    if (e['schema_version'] != 2 ||
        e['state'] != 'graded' ||
        e['question'] != null ||
        e['session_id'] != question.sessionId ||
        r['status'] != 'graded' ||
        r['attempt_id'] != question.attemptId ||
        r['question_id'] != question.id ||
        r['revision'] != question.revision ||
        r['correct'] is! bool ||
        r['option_results'] is! List ||
        r['selected_option_ids'] is! List ||
        r['correct_option_ids'] is! List) {
      return null;
    }
    final selectedIds = r['selected_option_ids'] as List,
        correctIds = r['correct_option_ids'] as List;
    if (selectedIds.length != 1 ||
        selectedIds.single != selected ||
        correctIds.length != 1) {
      return null;
    }
    final colors = <String, bool>{};
    for (final raw in r['option_results'] as List) {
      final o = aiObject(raw);
      if (!question.options.any((x) => x.id == o['id']) ||
          colors.containsKey(o['id']) ||
          o['is_correct'] is! bool ||
          o['selected'] is! bool ||
          o['selected'] != (o['id'] == selected)) {
        return null;
      }
      colors[o['id']] = o['is_correct'];
    }
    if (colors.length != question.options.length ||
        colors.values.where((b) => b).length != 1 ||
        colors[correctIds.single] != true ||
        r['correct'] != colors[selected]) {
      return null;
    }
    return QuizV2Grade(
      Map.unmodifiable(colors),
      r['feedback'] is String ? r['feedback'] : null,
    );
  }

  Map<String, dynamic> toEnvelope(QuizV2Question q, String selected) => {
    'schema_version': 2,
    'state': 'graded',
    'session_id': q.sessionId,
    'question': null,
    'can_request_next': true,
    'result': {
      'status': 'graded',
      'question_id': q.id,
      'revision': q.revision,
      'attempt_id': q.attemptId,
      'correct': correctByOption[selected],
      'selected_option_ids': [selected],
      'correct_option_ids': [
        for (final e in correctByOption.entries)
          if (e.value) e.key,
      ],
      'option_results': [
        for (final e in correctByOption.entries)
          {'id': e.key, 'is_correct': e.value, 'selected': e.key == selected},
      ],
      'feedback': feedback,
      'refs': [],
    },
  };
}
