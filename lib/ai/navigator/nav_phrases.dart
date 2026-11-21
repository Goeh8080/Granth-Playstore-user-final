/// t361 Every line the Navigator speaks or shows, in the grammar of the selected voice:
/// a female voice (Vani / Swara, or any `gender: female`) speaks as a woman ("खोलती हूँ",
/// "समझ नहीं पाई"); a male voice (Arjun, `gender: male`) as a man ("खोलता हूँ", "समझ नहीं पाया").
///
/// t421: Tatv's free voices are `dynamic:false` — the Worker has audio ONLY for the exact
/// cached lines in [kNavCachedPhrases] (exact match, no fuzzy). So every SPOKEN line here is
/// one of them; anything else (folder names, choices, mic messages) is shown as text only and
/// never sent to `/tts` ([navPhraseCached]).
library;

import '../../services/remote_config.dart';
import 'nav_tts.dart';

enum NavGender { female, male }

/// The Worker's cached Navigator / Tatv AI lines (granth-ai phrases.json v1, 22 ids; female and
/// male text). Keep EXACTLY in sync with the Worker — one changed character = no audio.
const Map<String, (String, String)> kNavCachedPhrases = {
  'greeting': ('नमस्ते, मैं तत्व AI हूँ', 'नमस्ते, मैं तत्व AI हूँ'),
  'sat_saheb': ('सत साहेब', 'सत साहेब'),
  'how_can_i_help': ('बताइए, मैं आपकी कैसे मदद कर सकती हूँ?', 'बताइए, मैं आपकी कैसे मदद कर सकता हूँ?'),
  'listening': ('जी, सुन रही हूँ', 'जी, सुन रहा हूँ'),
  'got_it': ('ठीक है, समझ गई', 'ठीक है, समझ गया'),
  'here_it_is': ('ये रहा', 'ये रहा'),
  'here_is_the_answer': ('ये रहा उत्तर', 'ये रहा उत्तर'),
  'opening': ('खोलती हूँ', 'खोलता हूँ'),
  'opening_granth': ('यह ग्रंथ खोलती हूँ', 'यह ग्रंथ खोलता हूँ'),
  'opening_page': ('यह पृष्ठ खोलती हूँ', 'यह पृष्ठ खोलता हूँ'),
  'looking_up': ('एक क्षण, देखती हूँ', 'एक क्षण, देखता हूँ'),
  'searching': ('मैं ढूँढ रही हूँ', 'मैं ढूँढ रहा हूँ'),
  'please_wait': ('कृपया एक क्षण रुकिए', 'कृपया एक क्षण रुकिए'),
  'done': ('हो गया', 'हो गया'),
  'welcome_back': ('नमस्ते, फिर से स्वागत है', 'नमस्ते, फिर से स्वागत है'),
  'which_granth': ('कौन सा ग्रंथ खोलूँ?', 'कौन सा ग्रंथ खोलूँ?'),
  'shall_i_read': ('क्या मैं इसे पढ़ूँ?', 'क्या मैं इसे पढ़ूँ?'),
  'try_again': ('कृपया फिर से कहिए', 'कृपया फिर से कहिए'),
  'not_understood': ('माफ़ कीजिए, मैं समझ नहीं पाई', 'माफ़ कीजिए, मैं समझ नहीं पाया'),
  'network_error': ('नेटवर्क की समस्या है, थोड़ी देर बाद कोशिश कीजिए', 'नेटवर्क की समस्या है, थोड़ी देर बाद कोशिश कीजिए'),
  'voice_unavailable': ('अभी आवाज़ नहीं चला पा रही हूँ', 'अभी आवाज़ नहीं चला पा रहा हूँ'),
  'thanks': ('धन्यवाद', 'धन्यवाद'),
};

/// Every cached text (both genders).
final Set<String> kNavCachedTexts = {for (final p in kNavCachedPhrases.values) ...[p.$1, p.$2]};

/// [text] has Worker audio (exact match after trimming).
bool navPhraseCached(String text) => kNavCachedTexts.contains(text.trim());

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
  String _p(String id) {
    final p = kNavCachedPhrases[id]!;
    return _f ? p.$1 : p.$2;
  }

  /// Spoken when opening anything: the cached "यह ग्रंथ खोलती हूँ" / "यह ग्रंथ खोलता हूँ"
  /// (the folder name is never spoken — see [openingToast]).
  String opening(String label) => _p('opening_granth');

  /// On screen while opening: "वेद खोल रही हूँ" (label without its "(…)" note, max 60 chars).
  String openingToast(String label) {
    var l = _clean(label);
    if (l.runes.length > 60) l = String.fromCharCodes(l.runes.take(60));
    return l.isEmpty ? 'खोल $_raha हूँ' : '$l खोल $_raha हूँ';
  }

  /// Spoken: exactly the cached "कौन सा ग्रंथ खोलूँ?" (the choices are shown as text).
  String clarify(List<String> labels) => _p('which_granth');

  /// On screen: "कौन सा ग्रंथ खोलूँ? वेद / पुराण".
  String clarifyToast(List<String> labels) => '${_p('which_granth')} ${labels.take(3).map(_clean).join(' / ')}';

  /// Spoken when nothing matched: "माफ़ कीजिए, मैं समझ नहीं पाई / पाया".
  String get unknown => _p('not_understood');

  /// Toast for an unmatched command.
  String unknownToast(String heard) => '$unknown: ${heard.trim()}';

  /// On screen when nothing was heard (spoken: [again]).
  String get nothing => 'कुछ सुनाई नहीं दिया';
  String get again => _p('try_again');
  String get listening => _p('listening');
  String get searching => _p('searching');

  /// Text only (not cached).
  String get chooseVoice => 'आवाज़ चुनिए';

  /// Voice picker preview: the cached greeting.
  String get preview => _p('greeting');
  String get micDenied => 'माइक की अनुमति नहीं मिली';
  String get micUnavailable => 'माइक उपलब्ध नहीं';
  String get micFailed => 'माइक से सुनाई नहीं दिया';

  /// No speech recognizer on the phone (Google speech services missing / off).
  String get noRecognizer => 'इस फ़ोन में आवाज़ पहचान (Google Speech) नहीं मिली। Play Store से "Google" ऐप / Speech Services अपडेट करें, फिर हिंदी भाषा पैक डाउनलोड करें।';

  /// The recognizer has no Hindi.
  String get noHindi => 'आवाज़ पहचान में हिंदी उपलब्ध नहीं। फ़ोन की सेटिंग → Google → Voice / भाषाएँ में हिंदी (भारत) भाषा पैक डाउनलोड करें।';

  /// Every line (tests check both genders).
  List<String> all() => [opening('वेद'), openingToast('वेद'), clarify(['वेद', 'पुराण']), clarifyToast(['वेद', 'पुराण']), unknown, unknownToast('x'), nothing, again, listening, searching, chooseVoice, preview, micDenied, micUnavailable, micFailed, noRecognizer, noHindi];

  /// The lines that are spoken (each must be a cached phrase).
  List<String> spoken() => [opening('वेद'), clarify(['वेद']), unknown, again, listening, searching, preview];

  static String _clean(String l) => l.replaceAll(RegExp(r'\s*\([^)]*\)'), '').trim();
}

/// Gender of the voice that speaks now ([navSpeakVoice]: user / admin / Worker default / Vani).
String navVoiceGender() {
  final v = navSpeakVoice();
  for (final o in [...navServerVoices(), ...kNavDefaultVoices]) {
    if (o.id == v) return o.gender;
  }
  return 'female';
}
