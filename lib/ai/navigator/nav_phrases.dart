/// t361 Every line the Navigator speaks or shows, in the grammar of the selected voice:
/// a female voice (Sarah, or any `gender: female`, and the phone voice) speaks as a woman
/// ("खोल रही हूँ", "समझ नहीं पाई"); a male voice as a man ("खोल रहा हूँ", "समझ नहीं पाया").
library;

import '../../services/remote_config.dart';
import 'nav_tts.dart';

enum NavGender { female, male }

class NavPhrases {
  const NavPhrases._(this.gender);
  final NavGender gender;

  static const female = NavPhrases._(NavGender.female);
  static const male = NavPhrases._(NavGender.male);

  /// `male` → masculine; everything else (`female`, `other`, unknown) → feminine.
  static NavPhrases forGender(String? gender) => gender?.trim().toLowerCase() == 'male' ? male : female;

  /// Phrases for the voice that will speak now (saved choice, else the Worker default).
  static NavPhrases current() => forGender(navVoiceGender());

  bool get _f => gender == NavGender.female;
  String get _raha => _f ? 'रही' : 'रहा';

  /// "वेद खोल रही हूँ" (label without its "(…)" note, max 60 chars).
  String opening(String label) {
    var l = _clean(label);
    if (l.runes.length > 60) l = String.fromCharCodes(l.runes.take(60));
    return l.isEmpty ? 'खोल $_raha हूँ' : '$l खोल $_raha हूँ';
  }

  /// "कौन-सा खोलूँ? वेद या पुराण" (same for both).
  String clarify(List<String> labels) => 'कौन-सा खोलूँ? ${labels.take(3).map(_clean).join(' या ')}';

  /// Spoken when nothing matched: "समझ नहीं पाई" / "समझ नहीं पाया".
  String get unknown => _f ? 'समझ नहीं पाई' : 'समझ नहीं पाया';

  /// Toast for an unmatched command.
  String unknownToast(String heard) => '$unknown: ${heard.trim()}';

  String get nothing => 'कुछ सुनाई नहीं दिया';
  String get again => 'फिर से बोलिए';
  String get listening => 'सुन $_raha हूँ…';
  String get searching => 'ढूँढ $_raha हूँ';
  String get chooseVoice => 'आवाज़ चुनिए';
  String get preview => _f ? 'नमस्ते, मैं इस आवाज़ में बोलूँगी' : 'नमस्ते, मैं इस आवाज़ में बोलूँगा';
  String get micDenied => 'माइक की अनुमति नहीं मिली';
  String get micUnavailable => 'माइक उपलब्ध नहीं';
  String get micFailed => 'माइक से सुनाई नहीं दिया';

  /// Every line (tests check both genders).
  List<String> all() => [opening('वेद'), clarify(['वेद', 'पुराण']), unknown, unknownToast('x'), nothing, again, listening, searching, chooseVoice, preview, micDenied, micUnavailable, micFailed];

  static String _clean(String l) => l.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
}

/// Gender of the voice that speaks now: phone voice → female; saved server voice → its
/// gender; nothing saved → the Worker default (`default_voice_id`, else Sarah, female).
String navVoiceGender() {
  final v = navSavedVoice() ?? navDefaultVoice() ?? kNavDefaultVoices.first.id;
  if (v == kPhoneVoice) return 'female';
  for (final o in [...navServerVoices(), ...kNavDefaultVoices]) {
    if (o.id == v) return o.gender;
  }
  return 'female';
}
