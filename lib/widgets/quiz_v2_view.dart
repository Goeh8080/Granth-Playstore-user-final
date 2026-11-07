// Public §25 projection; app mounts it only behind the production rollout gate and capabilities.
import 'package:flutter/material.dart';
import '../ai/quiz_v2.dart';
import '../theme/colors.dart';
import 'common.dart';

class QuizV2View extends StatelessWidget {
  const QuizV2View({
    super.key,
    required this.state,
    this.question,
    this.grade,
    this.reason,
    this.reportStatus,
    this.onSource,
    this.onAnswer,
    this.onNext,
    this.onChangeSource,
    this.onReport,
    this.busy = false,
  });
  final String state;
  final QuizV2Question? question;
  final QuizV2Grade? grade;
  final String? reason, reportStatus;
  final ValueChanged<String>? onSource, onAnswer;
  final VoidCallback? onNext, onChangeSource, onReport;
  final bool busy;
  @override
  Widget build(BuildContext context) {
    if (state == 'choose_source') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            'किससे प्रश्न पूछें',
            style: GText.sans(size: 20, weight: FontWeight.w600),
          ),
          for (final pair in const {
            'ved': 'वेद से',
            'puran': 'पुराण से',
            'all': 'सारे ग्रंथ',
          }.entries)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SheetButton(
                label: pair.value,
                onTap: busy || onSource == null
                    ? null
                    : () => onSource!(pair.key),
              ),
            ),
        ],
      );
    }
    if ((state == 'question' || state == 'graded') &&
        question != null &&
        (state != 'graded' || grade != null)) {
      final q = question!, r = state == 'graded' ? grade : null;
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            q.text,
            style: GText.sans(size: 18, weight: FontWeight.w600, height: 1.5),
          ),
          for (final o in q.options)
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: Pressable(
                onTap: busy || r != null || onAnswer == null
                    ? null
                    : () => onAnswer!(o.id),
                child: AnimatedContainer(
                  key: ValueKey('quiz-v2-option-${o.id}'),
                  duration: const Duration(milliseconds: 140),
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: r == null
                        ? GColors.paper
                        : (r.correctByOption[o.id] == true
                                  ? Colors.green
                                  : Colors.red)
                              .withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: r == null
                          ? GColors.creamDark
                          : r.correctByOption[o.id] == true
                          ? Colors.green
                          : Colors.red,
                    ),
                  ),
                  child: Text(o.text, style: GText.sans(size: 16, height: 1.5)),
                ),
              ),
            ),
          if (r != null)
            Padding(
              padding: const EdgeInsets.only(top: 14),
              child: SheetButton(
                label: 'अगला प्रश्न',
                onTap: busy ? null : onNext,
              ),
            ),
          if (onReport != null)
            Padding(
              padding: const EdgeInsets.only(top: 12),
              child: SheetButton(
                label: reportStatus == 'queued'
                    ? 'रिपोर्ट भेजना बाकी'
                    : reportStatus == 'sent'
                    ? 'रिपोर्ट भेजी ✓'
                    : 'इस प्रश्न की रिपोर्ट',
                onTap: busy ? null : onReport,
              ),
            ),
        ],
      );
    }
    if (state == 'exhausted') {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(switch (reason) {
            'all_seen' => 'इस स्रोत के सभी प्रश्न देख चुके हैं।',
            'bank_empty' => 'इस स्रोत में अभी प्रश्न नहीं हैं।',
            _ => 'इस प्रकार के प्रश्न अभी उपलब्ध नहीं हैं।',
          }, style: GText.sans(size: 16, height: 1.5)),
          const SizedBox(height: 12),
          SheetButton(
            label: 'स्रोत बदलें',
            onTap: busy ? null : onChangeSource,
          ),
        ],
      );
    }
    return Text(
      'चर्चा अभी उपलब्ध नहीं है। बाद में फिर कोशिश करें।',
      style: GText.sans(size: 16, height: 1.5),
    );
  }
}
