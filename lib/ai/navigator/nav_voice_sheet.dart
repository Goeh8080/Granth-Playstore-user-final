/// t352 Navigator voice picker: "awaaz badlo" / "voice change" / "kaunsi awaaz" (or Settings)
/// opens this sheet. Voices come from `GET /tts/voices` (list + `default_voice_id`); offline
/// fallback is the bundled Sarah (female, default) + George (male). "फ़ोन की आवाज़" is listed
/// only when the phone has a local voice.
/// Tap = save locally + short preview; the choice goes to `/tts` as `voice_id`.
library;

import 'package:flutter/material.dart';

import '../../services/remote_config.dart';
import '../../services/storage.dart';
import '../../theme/colors.dart';
import '../../widgets/common.dart';
import '../../widgets/overlays.dart';
import 'nav_phrases.dart';
import 'nav_tts.dart';


/// The voices the sheet offers right now (server list + optional phone voice).
List<NavVoiceOption> navVoiceChoices({required bool phone}) => [
      ...navServerVoices(),
      if (phone) const NavVoiceOption(id: kPhoneVoice, name: 'फ़ोन की आवाज़ (ऑफ़लाइन)', gender: 'other'),
    ];

/// The saved choice if it is still offered, else null (= server default voice).
String? navCurrentVoice({bool phone = true}) {
  final v = navSavedVoice();
  return v == kPhoneVoice && !phone ? null : v;
}

Future<void> saveNavVoice(String id) => Store.I.setString(kNavVoiceKey, id);

/// Opens the picker; the list refreshes from `GET /tts/voices` (bundled list offline).
Future<void> showNavVoiceSheet(BuildContext context, {required NavSpeaker speaker}) async {
  final results = await Future.wait([
    speaker.audio.hasLocalVoice(),
    refreshNavVoices(speaker.client).timeout(const Duration(seconds: 4), onTimeout: () => false),
  ]);
  final phone = results[0];
  if (!context.mounted) return;
  await showPop<void>(context, (ctx) => NavVoiceSheet(speaker: speaker, phone: phone));
}

class NavVoiceSheet extends StatefulWidget {
  const NavVoiceSheet({super.key, required this.speaker, this.phone = false});
  final NavSpeaker speaker;
  final bool phone;
  @override
  State<NavVoiceSheet> createState() => _NavVoiceSheetState();
}

class _NavVoiceSheetState extends State<NavVoiceSheet> {
  late String? _sel = navCurrentVoice(phone: widget.phone) ?? navDefaultVoice() ?? navServerVoices().first.id;
  String? _playing;

  Future<void> _pick(NavVoiceOption v) async {
    setState(() {
      _sel = v.id;
      _playing = v.id;
    });
    await saveNavVoice(v.id);
    await widget.speaker.stop();
    await widget.speaker.say(NavPhrases.forGender(v.id == kPhoneVoice ? 'female' : v.gender).preview, voiceId: v.id);
    if (mounted && _playing == v.id) setState(() => _playing = null);
  }

  @override
  void dispose() {
    widget.speaker.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final list = navVoiceChoices(phone: widget.phone);
    return SheetCard(
      maxWidth: 420,
      children: [
        Text('नेविगेटर की आवाज़', style: GText.display(size: 22, color: GColors.maroon, height: 1.3)),
        const SizedBox(height: 4),
        Text('किसी आवाज़ पर टैप करें: वह सुनाई देगी और चुन ली जाएगी।', style: GText.sans(size: 13.5, color: GColors.muted, height: 1.4)),
        const SizedBox(height: 12),
        for (final v in list)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Pressable(
              key: ValueKey('nav-voice-${v.id}'),
              onTap: () => _pick(v),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                decoration: BoxDecoration(
                  color: _sel == v.id ? GColors.maroon.withValues(alpha: 0.08) : GColors.paper,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(color: _sel == v.id ? GColors.maroon : GColors.creamDark, width: _sel == v.id ? 2 : 1),
                ),
                child: Row(children: [
                  Icon(v.id == kPhoneVoice ? Icons.phone_android_rounded : v.gender == 'female' ? Icons.face_3_rounded : Icons.face_rounded, color: GColors.maroon, size: 22),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      v.id == kPhoneVoice ? v.name : '${v.name} · ${v.gender == 'female' ? 'महिला' : v.gender == 'male' ? 'पुरुष' : 'आवाज़'}',
                      style: GText.sans(size: 15.5, weight: FontWeight.w600, color: GColors.brown),
                    ),
                  ),
                  if (_playing == v.id) const Icon(Icons.graphic_eq, color: GColors.saffron, size: 20),
                  if (_sel == v.id) const Padding(padding: EdgeInsets.only(left: 6), child: Icon(Icons.check_circle_rounded, color: GColors.maroon, size: 20)),
                ]),
              ),
            ),
          ),
        const SizedBox(height: 4),
        SheetButton(key: const ValueKey('nav-voice-done'), label: 'ठीक है', primary: true, onTap: () => Navigator.pop(context)),
      ],
    );
  }
}
