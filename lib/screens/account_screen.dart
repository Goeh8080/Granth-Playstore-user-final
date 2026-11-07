/// Round 14: अकाउंट (optional Google sign-in) and सहायता (support tickets, CONTRACT §5.1) pages.
/// Login is never required: every other screen works the same without it.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/catalog_store.dart';
import '../services/file_actions.dart';
import '../services/firebase_bridge.dart';
import '../services/local_stats.dart';
import '../services/remote_config.dart';
import '../services/support.dart';
import '../state/router.dart';
import '../state/toast.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/overlays.dart';
import 'support_chat.dart';

InputDecoration _box(String hint) => InputDecoration(
  hintText: hint,
  filled: true,
  fillColor: GColors.cream,
  border: OutlineInputBorder(
    borderRadius: BorderRadius.circular(12),
    borderSide: const BorderSide(color: GColors.creamDark),
  ),
);

Widget _page(Key key, List<Widget> children) => SliverPadding(
  key: key,
  padding: const EdgeInsets.fromLTRB(2, 4, 2, 24),
  sliver: SliverToBoxAdapter(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  ),
);

class AccountPage extends StatelessWidget {
  const AccountPage({super.key});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: Listenable.merge([FirebaseBridge.I, RemoteConfig.I, LocalStats.I, CatalogStore.I.lastSync]),
    builder: (context, _) {
      final fb = FirebaseBridge.I;
      final a = fb.account;
      return _page(const ValueKey('account-page'), [
        SheetHead(title: 'अकाउंट', onBack: AppNav.I.back, direct: true),
        FrostCard(
          child: a == null
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text('लॉगिन ज़रूरी नहीं है', style: GText.script(size: 19, color: GColors.maroon)),
                    const SizedBox(height: 6),
                    Text('पूरा ऐप बिना लॉगिन के चलता है। Google से लॉगिन करने पर आपका नाम और Gmail यहाँ दिखेगा।', style: GText.sans(size: 14, color: GColors.muted, height: 1.45)),
                    const SizedBox(height: 12),
                    SheetButton(
                      key: const ValueKey('account-google'),
                      label: fb.busy ? 'लॉगिन हो रहा है…' : 'Google से लॉगिन करें',
                      primary: true,
                      enabled: !fb.busy,
                      onTap: () async {
                        final e = await fb.signIn();
                        if (e != null) Toast.show(e);
                      },
                    ),
                  ],
                )
              : Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        AccountAvatar(url: a.photo, name: a.name.isEmpty ? a.email : a.name),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                a.name.isEmpty ? 'भक्त' : a.name,
                                key: const ValueKey('account-name'),
                                maxLines: 2,
                                overflow: TextOverflow.ellipsis,
                                style: GText.sans(size: 17, weight: FontWeight.w700, color: GColors.maroon),
                              ),
                              Text(
                                a.email,
                                key: const ValueKey('account-email'),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: GText.sans(size: 13.5, color: GColors.muted),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    if (RemoteConfig.I.bhaktIdEnabled) ...[
                      const SizedBox(height: 12),
                      Text(
                        'भक्त ID: जल्द आ रहा है',
                        key: const ValueKey('account-bhakt-id'),
                        style: GText.sans(size: 14, color: GColors.brown),
                      ),
                    ],
                    const SizedBox(height: 14),
                    SheetButton(
                      key: const ValueKey('account-logout'),
                      icon: 'log-out',
                      label: 'लॉगआउट',
                      onTap: () async {
                        await fb.signOut();
                        Toast.show('लॉगआउट हो गया');
                      },
                    ),
                    const SizedBox(height: 10),
                    SheetButton(
                      key: const ValueKey('account-delete'),
                      icon: 'trash-2',
                      label: fb.busy && fb.stage != null ? fb.stage! : 'खाता हटाएँ',
                      enabled: !fb.busy,
                      onTap: () => confirmDeleteAccount(context),
                    ),
                    const SizedBox(height: 6),
                    Center(
                      child: TapTarget(
                        key: const ValueKey('account-delete-web'),
                        onTap: () => FileActions.openUrl(kDeleteAccountUrl),
                        child: Padding(
                          padding: const EdgeInsets.all(6),
                          child: Text(
                            'वेब से खाता हटाने का तरीका',
                            style: GText.sans(size: 13, color: GColors.saffronDark).copyWith(decoration: TextDecoration.underline, decorationColor: GColors.saffronDark),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
        ),
        const SizedBox(height: 14),
        const AccountStats(),
        const SizedBox(height: 14),
        if (RemoteConfig.I.supportEnabled)
          const Align(alignment: Alignment.centerLeft, child: SupportPills(pillKey: ValueKey('account-support'), icon: 'ticket')),
      ]);
    },
  );
}

/// Round account picture: the Google photo, else the first letter, else a person icon.
class AccountAvatar extends StatelessWidget {
  const AccountAvatar({super.key, required this.url, required this.name, this.size = 52});
  final String url, name;
  final double size;
  @override
  Widget build(BuildContext context) {
    final fallback = Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: const BoxDecoration(
        shape: BoxShape.circle,
        gradient: LinearGradient(colors: [GColors.saffron, GColors.maroon], begin: Alignment.topLeft, end: Alignment.bottomRight),
      ),
      child: name.isEmpty
          ? GIcon('user', size: size * 0.5, color: Colors.white)
          : Text(
              String.fromCharCode(name.runes.first).toUpperCase(),
              style: GText.sans(size: size * 0.4, weight: FontWeight.w700, color: Colors.white),
            ),
    );
    if (!url.startsWith('https://')) return fallback;
    return ClipOval(
      child: Image.network(url, key: const ValueKey('account-photo'), width: size, height: size, fit: BoxFit.cover, errorBuilder: (_, _, _) => fallback),
    );
  }
}

String _when(int? ms) {
  if (ms == null) return 'अभी नहीं';
  final d = DateTime.fromMillisecondsSinceEpoch(ms);
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}/${two(d.month)}/${d.year} · ${two(d.hour)}:${two(d.minute)}';
}

/// "आपके आँकड़े": counted on this phone only ([LocalStats]); nothing is fetched or sent.
class AccountStats extends StatelessWidget {
  const AccountStats({super.key});

  @override
  Widget build(BuildContext context) {
    final st = LocalStats.I;
    final rows = <(String, String, String, String)>[
      ('days', 'calendar-days', 'सक्रिय दिन', '${st.daysActive}'),
      ('opens', 'history', 'ऐप खोला', '${st.count('app_open')}'),
      ('granths', 'book-open', 'ग्रंथ खोले', '${st.count('granth_open')}'),
      ('pramans', 'file-text', 'प्रमाण खोले', '${st.count('praman_open')}'),
      ('pdf-down', 'folder-down', 'PDF डाउनलोड', '${st.count('pdf_download')}'),
      ('pdf-gen', 'folder-plus', 'PDF बनाए', '${st.count('pdf_generate')}'),
      ('ai', 'sparkles', 'AI से प्रश्न', '${st.count('ai_ask')}'),
    ];
    return FrostCard(
      key: const ValueKey('account-stats'),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('आपके आँकड़े', style: GText.script(size: 19, color: GColors.maroon)),
          const SizedBox(height: 2),
          Text('सिर्फ़ इसी फ़ोन पर गिने जाते हैं, कहीं भेजे नहीं जाते।', style: GText.sans(size: 12.5, color: GColors.muted)),
          const SizedBox(height: 12),
          LayoutBuilder(
            builder: (context, c) {
              final w = (c.maxWidth - 10) / 2;
              return Wrap(
                spacing: 10,
                runSpacing: 10,
                children: [
                  for (final (id, icon, label, value) in rows)
                    Container(
                      key: ValueKey('stat-$id'),
                      width: w,
                      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                      decoration: BoxDecoration(
                        color: GColors.cream,
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(color: GColors.creamDark),
                      ),
                      child: Row(
                        children: [
                          GIcon(icon, size: 18, color: GColors.saffron),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  value,
                                  style: GText.sans(size: 18, weight: FontWeight.w800, color: GColors.maroon),
                                ),
                                Text(
                                  label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: GText.sans(size: 12, color: GColors.muted),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                ],
              );
            },
          ),
          const SizedBox(height: 12),
          Row(
            key: const ValueKey('stat-sync'),
            children: [
              const GIcon('refresh-cw', size: 16, color: GColors.muted),
              const SizedBox(width: 8),
              Expanded(
                child: Text('आख़िरी सिंक: ${_when(CatalogStore.I.syncedAt)}', style: GText.sans(size: 13, color: GColors.brown)),
              ),
            ],
          ),
          if (st.since != null)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Text('पहली बार: ${st.since!.split('-').reversed.join('/')}', style: GText.sans(size: 12, color: GColors.muted)),
            ),
        ],
      ),
    );
  }
}

/// "खाता हटाएँ": confirm, then [FirebaseBridge.deleteAccount] (login gate shows after).
Future<void> confirmDeleteAccount(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (c) => AlertDialog(
      key: const ValueKey('account-delete-dialog'),
      title: Text('खाता हटाएँ?', style: GText.sans(size: 18, weight: FontWeight.w700, color: GColors.maroon)),
      content: Text(
        'आपका Google खाता इस ऐप से हटा दिया जाएगा, आपके सहायता टिकट और ऐप से जुड़ा डेटा सर्वर से मिटा दिया जाएगा। यह वापस नहीं होगा।',
        style: GText.sans(size: 14.5, height: 1.5),
      ),
      actions: [
        TextButton(key: const ValueKey('account-delete-cancel'), onPressed: () => Navigator.pop(c, false), child: const Text('रद्द करें')),
        TextButton(
          key: const ValueKey('account-delete-confirm'),
          onPressed: () => Navigator.pop(c, true),
          child: Text('हाँ, हटाएँ', style: GText.sans(size: 15, weight: FontWeight.w700, color: GColors.maroon)),
        ),
      ],
    ),
  );
  if (ok != true) return;
  final e = await FirebaseBridge.I.deleteAccount();
  Toast.show(e ?? 'खाता हटा दिया गया');
}

class SupportPage extends StatefulWidget {
  const SupportPage({super.key});
  @override
  State<SupportPage> createState() => _SupportPageState();
}

class _SupportPageState extends State<SupportPage> {
  final _msg = TextEditingController();
  final _subject = TextEditingController();
  bool _sending = false;

  @override
  void initState() {
    super.initState();
    unawaited(SupportService.I.refresh());
  }

  @override
  void dispose() {
    _msg.dispose();
    _subject.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final a = FirebaseBridge.I.account;
    final e = await SupportService.I.create(_msg.text, subject: _subject.text, name: a?.name ?? '', contact: a?.email ?? '');
    if (!mounted) return;
    setState(() => _sending = false);
    if (e != null) {
      Toast.show(e);
      return;
    }
    _msg.clear();
    _subject.clear();
    final t = SupportService.I.tickets.isEmpty ? null : SupportService.I.tickets.first;
    Toast.show(t == null ? 'टिकट भेज दिया गया' : 'टिकट भेज दिया गया · ${t.label}');
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SupportService.I,
    builder: (context, _) {
      final s = SupportService.I;
      return _page(const ValueKey('support-page'), [
        SheetHead(title: 'सहायता', onBack: AppNav.I.back, direct: true),
        FrostCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('नया टिकट', style: GText.script(size: 19, color: GColors.maroon)),
              const SizedBox(height: 4),
              Text('अपनी समस्या लिखें। हर टिकट को उस दिन का टोकन नंबर मिलता है। जवाब यहीं दिखेगा।', style: GText.sans(size: 13.5, color: GColors.muted, height: 1.45)),
              const SizedBox(height: 10),
              TextField(key: const ValueKey('support-subject'), controller: _subject, maxLength: 120, style: GText.sans(size: 15), decoration: _box('विषय (वैकल्पिक)')),
              TextField(key: const ValueKey('support-message'), controller: _msg, minLines: 3, maxLines: 6, maxLength: 2000, style: GText.sans(size: 15), decoration: _box('संदेश')),
              const SizedBox(height: 6),
              SheetButton(key: const ValueKey('support-send'), label: _sending ? 'भेजा जा रहा है…' : 'टिकट भेजें', primary: true, enabled: !_sending, onTap: _send),
            ],
          ),
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            Expanded(
              child: Text(
                'मेरे टिकट',
                style: GText.sans(size: 16, weight: FontWeight.w700, color: GColors.maroon),
              ),
            ),
            UnreadBadge(key: const ValueKey('support-mine-badge'), count: s.unread),
            const SizedBox(width: 6),
            Pill(key: const ValueKey('support-refresh'), direct: true, icon: 'refresh-cw', label: s.loading ? '…' : 'ताज़ा करें', onTap: s.refresh),
          ],
        ),
        const SizedBox(height: 8),
        if (s.error != null && s.tickets.isEmpty)
          Text(
            s.error!,
            key: const ValueKey('support-error'),
            style: GText.sans(size: 13.5, color: GColors.muted),
          ),
        if (s.error == null && !s.loading && s.tickets.isEmpty) Text('अभी कोई टिकट नहीं है।', style: GText.sans(size: 13.5, color: GColors.muted)),
        // T184 item 6: no reply form here; a tap opens the two-way chat.
        for (final t in s.tickets) TicketRow(t: t),
      ]);
    },
  );
}
