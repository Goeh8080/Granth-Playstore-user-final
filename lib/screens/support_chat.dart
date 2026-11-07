/// T184: the support ticket chat (CONTRACT §20 / §20.6 / §20.7).
/// - [TicketChatPage] `#/support?t=<id>`: a WhatsApp-style two-way thread (user right, admin
///   left, time + ✓ sent / ✓✓ read), a message box, polled every 12 s while open, acked on open.
/// - [CheckStatusPage] `#/support?check=1` ("स्थिति देखें"): a token-number search plus the
///   user's own tickets (one §20.7 call); a tap opens the chat.
/// - [UnreadBadge]: the unread-replies count on Sahayata / Mere Tickets.
library;

import 'dart:async';

import 'package:flutter/material.dart';

import '../services/support.dart';
import '../state/router.dart';
import '../state/toast.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';
import '../widgets/overlays.dart';

/// How often an open chat asks for new messages (contract: at most every 10–15 s).
const kTicketPoll = Duration(seconds: 12);

String ticketTime(String iso) {
  final d = DateTime.tryParse(iso)?.toLocal();
  if (d == null) return '';
  String two(int n) => n.toString().padLeft(2, '0');
  return '${two(d.day)}-${two(d.month)} ${two(d.hour)}:${two(d.minute)}';
}

Widget _page(Key key, List<Widget> children) => SliverPadding(
  key: key,
  padding: const EdgeInsets.fromLTRB(2, 4, 2, 24),
  sliver: SliverToBoxAdapter(
    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: children),
  ),
);

InputDecoration _box(String hint) => InputDecoration(
  hintText: hint,
  isDense: true,
  filled: true,
  fillColor: GColors.cream,
  counterText: '',
  border: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: GColors.creamDark)),
  enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(22), borderSide: const BorderSide(color: GColors.creamDark)),
);

/// A small round count (hidden at 0).
class UnreadBadge extends StatelessWidget {
  const UnreadBadge({super.key, required this.count});
  final int count;
  @override
  Widget build(BuildContext context) => count <= 0
      ? const SizedBox.shrink()
      : Container(
          constraints: const BoxConstraints(minWidth: 20, minHeight: 20),
          padding: const EdgeInsets.symmetric(horizontal: 6),
          alignment: Alignment.center,
          decoration: BoxDecoration(color: GColors.saffron, borderRadius: BorderRadius.circular(10)),
          child: Text(count > 99 ? '99+' : '$count', style: GText.sans(size: 11.5, weight: FontWeight.w700, color: Colors.white)),
        );
}

/// The Sahayata pill (+ unread badge) with the small "स्थिति देखें" button below it.
class SupportPills extends StatefulWidget {
  const SupportPills({super.key, required this.pillKey, this.icon = 'message-circle'});
  final Key pillKey;
  final String icon;
  @override
  State<SupportPills> createState() => _SupportPillsState();
}

class _SupportPillsState extends State<SupportPills> {
  @override
  void initState() {
    super.initState();
    unawaited(SupportService.I.refreshSoon());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SupportService.I,
    builder: (_, _) => Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Flexible(child: Pill(key: widget.pillKey, direct: true, icon: widget.icon, label: 'सहायता / टिकट', onTap: () => AppNav.I.openLink('#/support'))),
            const SizedBox(width: 4),
            UnreadBadge(key: ValueKey('${(widget.pillKey as ValueKey).value}-badge'), count: SupportService.I.unread),
          ],
        ),
        const SizedBox(height: 6),
        const CheckStatusButton(),
      ],
    ),
  );
}

/// "स्थिति देखें / Check status": the small button under Sahayata.
class CheckStatusButton extends StatelessWidget {
  const CheckStatusButton({super.key});
  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SupportService.I,
    builder: (_, _) => Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Flexible(
          child: Pill(key: const ValueKey('support-check'), direct: true, icon: 'eye', label: 'स्थिति देखें / Check status', fontSize: 11, padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4), onTap: () => AppNav.I.openLink('#/support?check=1')),
        ),
      ],
    ),
  );
}

/// One ticket row (list / search result); a tap opens its chat.
class TicketRow extends StatelessWidget {
  const TicketRow({super.key, required this.t});
  final SupportTicket t;
  @override
  Widget build(BuildContext context) {
    final last = t.messages.isEmpty ? null : t.messages.last;
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: TapTarget(
        key: ValueKey('ticket-open-${t.id}'),
        onTap: () => AppNav.I.openLink('#/support?t=${t.id}'),
        child: FrostCard(
          key: ValueKey('ticket-${t.id}'),
          child: Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(t.label, style: GText.sans(size: 14.5, weight: FontWeight.w700, color: GColors.maroon)),
                    const SizedBox(height: 2),
                    Text(
                      last != null && last.fromAdmin ? 'एडमिन: ${last.text}' : (t.subject.isEmpty ? t.message : t.subject),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: GText.sans(size: 13.5, color: GColors.brown),
                    ),
                    const SizedBox(height: 2),
                    Text(t.open ? (t.replied ? 'खुला · जवाब मिला' : 'खुला · जवाब की प्रतीक्षा') : 'बंद', style: GText.sans(size: 12, color: GColors.muted)),
                  ],
                ),
              ),
              const SizedBox(width: 6),
              UnreadBadge(key: ValueKey('ticket-new-${t.id}'), count: t.unreadReplies),
              const GIcon('chevron-right', size: 18, color: GColors.muted),
            ],
          ),
        ),
      ),
    );
  }
}

class CheckStatusPage extends StatefulWidget {
  const CheckStatusPage({super.key});
  @override
  State<CheckStatusPage> createState() => _CheckStatusPageState();
}

class _CheckStatusPageState extends State<CheckStatusPage> {
  final _token = TextEditingController();
  List<SupportTicket>? _found;
  String? _err;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    unawaited(SupportService.I.refresh());
  }

  @override
  void dispose() {
    _token.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final raw = _token.text.trim().replaceAll('#', '');
    if (raw.isEmpty) {
      setState(() {
        _found = null;
        _err = null;
      });
      return;
    }
    final n = int.tryParse(raw);
    if (n == null || n <= 0) {
      setState(() {
        _found = null;
        _err = 'टोकन / टिकट नंबर केवल अंकों में लिखें।';
      });
      return;
    }
    setState(() => _busy = true);
    final r = await SupportService.I.status(token: n);
    if (!mounted) return;
    setState(() {
      _busy = false;
      _found = r.tickets;
      _err = r.error ?? (r.tickets.isEmpty ? 'इस नंबर का आपका कोई टिकट नहीं मिला।' : null);
    });
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SupportService.I,
    builder: (context, _) {
      final s = SupportService.I;
      return _page(const ValueKey('support-check-page'), [
        SheetHead(title: 'टिकट की स्थिति', onBack: AppNav.I.back, direct: true),
        FrostCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text('अपना टोकन / टिकट नंबर लिखें', style: GText.sans(size: 14, weight: FontWeight.w700, color: GColors.maroon)),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      key: const ValueKey('support-check-input'),
                      controller: _token,
                      keyboardType: TextInputType.number,
                      maxLength: 8,
                      onSubmitted: (_) => _search(),
                      style: GText.sans(size: 15),
                      decoration: _box('जैसे 3'),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Pill(key: const ValueKey('support-check-go'), direct: true, icon: 'eye', label: _busy ? '…' : 'देखें', tone: PillTone.maroon, onTap: _search),
                ],
              ),
              if (_err != null) Padding(padding: const EdgeInsets.only(top: 8), child: Text(_err!, key: const ValueKey('support-check-error'), style: GText.sans(size: 13, color: GColors.muted))),
            ],
          ),
        ),
        const SizedBox(height: 12),
        for (final t in _found ?? const <SupportTicket>[]) TicketRow(key: ValueKey('found-${t.id}'), t: t),
        if (_found == null) ...[
          Row(
            children: [
              Expanded(child: Text('मेरे टिकट', style: GText.sans(size: 16, weight: FontWeight.w700, color: GColors.maroon))),
              UnreadBadge(key: const ValueKey('check-mine-badge'), count: s.unread),
            ],
          ),
          const SizedBox(height: 8),
          if (s.error != null && s.tickets.isEmpty) Text(s.error!, key: const ValueKey('support-error'), style: GText.sans(size: 13.5, color: GColors.muted)),
          if (s.error == null && !s.loading && s.tickets.isEmpty) Text('अभी कोई टिकट नहीं है।', style: GText.sans(size: 13.5, color: GColors.muted)),
          for (final t in s.tickets) TicketRow(t: t),
        ],
      ]);
    },
  );
}

class TicketChatPage extends StatefulWidget {
  const TicketChatPage({super.key, required this.id});
  final int id;
  @override
  State<TicketChatPage> createState() => _TicketChatPageState();
}

class _TicketChatPageState extends State<TicketChatPage> {
  final _text = TextEditingController();
  Timer? _poll;
  bool _sending = false;
  String? _err;
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    unawaited(_load(first: true));
    _poll = Timer.periodic(kTicketPoll, (_) => _load());
  }

  Future<void> _load({bool first = false}) async {
    final e = await SupportService.I.thread(widget.id);
    if (!mounted) return;
    setState(() {
      _loaded = true;
      if (first || e == null) _err = e;
    });
    final t = SupportService.I.byId(widget.id);
    if (e == null && t != null && (first || t.hasNewReply || t.messages.any((m) => m.fromAdmin && !m.read))) {
      await SupportService.I.ack([widget.id]);
    }
  }

  @override
  void dispose() {
    _poll?.cancel();
    _text.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    if (_sending) return;
    setState(() => _sending = true);
    final e = await SupportService.I.send(widget.id, _text.text);
    if (!mounted) return;
    setState(() => _sending = false);
    if (e != null) {
      Toast.show(e);
      return;
    }
    _text.clear();
  }

  Widget _bubble(SupportMsg m, int i) {
    final mine = !m.fromAdmin;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 300),
        child: Container(
          key: ValueKey('chat-msg-$i'),
          margin: EdgeInsets.only(bottom: 8, left: mine ? 36 : 0, right: mine ? 0 : 36),
          padding: const EdgeInsets.fromLTRB(12, 8, 10, 6),
          decoration: BoxDecoration(
            color: mine ? const Color(0xFFF7E3C0) : Colors.white,
            borderRadius: BorderRadius.only(
              topLeft: const Radius.circular(16),
              topRight: const Radius.circular(16),
              bottomLeft: Radius.circular(mine ? 16 : 4),
              bottomRight: Radius.circular(mine ? 4 : 16),
            ),
            boxShadow: [BoxShadow(color: GColors.shadow(0.08), blurRadius: 6, offset: const Offset(0, 2))],
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Align(
                alignment: Alignment.centerLeft,
                child: Text(m.text, style: GText.sans(size: 14.5, height: 1.4, color: GColors.brown)),
              ),
              const SizedBox(height: 2),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(ticketTime(m.at), style: GText.sans(size: 10.5, color: GColors.muted)),
                  if (mine) ...[
                    const SizedBox(width: 4),
                    Semantics(
                      label: m.read ? 'पढ़ा गया' : 'भेजा गया',
                      child: Row(
                        key: ValueKey('chat-tick-$i-${m.read ? 'read' : 'sent'}'),
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          GIcon('check', size: 12, color: m.read ? const Color(0xFF2F80ED) : GColors.muted),
                          if (m.read) Transform.translate(offset: const Offset(-6, 0), child: const GIcon('check', size: 12, color: Color(0xFF2F80ED))),
                        ],
                      ),
                    ),
                  ],
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SupportService.I,
    builder: (context, _) {
      final t = SupportService.I.byId(widget.id);
      final msgs = t?.messages ?? const <SupportMsg>[];
      return _page(const ValueKey('ticket-chat-page'), [
        SheetHead(title: t?.label ?? 'टिकट', onBack: AppNav.I.back, direct: true),
        if (t != null)
          Padding(
            padding: const EdgeInsets.only(bottom: 10),
            child: Text(t.open ? 'टिकट खुला है · एडमिन का जवाब यहीं आएगा' : 'यह टिकट बंद हो चुका है', key: const ValueKey('chat-status'), style: GText.sans(size: 13, color: GColors.muted)),
          ),
        if (_err != null && t == null) Text(_err!, key: const ValueKey('chat-error'), style: GText.sans(size: 13.5, color: GColors.muted)),
        if (!_loaded && t == null) Text('लोड हो रहा है…', style: GText.sans(size: 13.5, color: GColors.muted)),
        Container(
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(color: GColors.creamDark.withValues(alpha: 0.45), borderRadius: BorderRadius.circular(18)),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              if (msgs.isEmpty && t != null) _bubble(SupportMsg(false, t.message, '${t.raw['created_at'] ?? ''}'), 0),
              for (final (i, m) in msgs.indexed) _bubble(m, i),
            ],
          ),
        ),
        const SizedBox(height: 10),
        if (t != null && !t.open)
          FrostCard(
            key: const ValueKey('chat-closed'),
            child: Text('टिकट बंद है — नया संदेश भेजने के लिए नया टिकट बनाएँ।', style: GText.sans(size: 13.5, color: GColors.brown)),
          )
        else if (t != null)
          Row(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Expanded(
                child: TextField(
                  key: const ValueKey('chat-input'),
                  controller: _text,
                  minLines: 1,
                  maxLines: 4,
                  maxLength: 2000,
                  style: GText.sans(size: 15),
                  decoration: _box('संदेश लिखें…'),
                ),
              ),
              const SizedBox(width: 8),
              TapTarget(
                key: const ValueKey('chat-send'),
                onTap: _send,
                child: Container(
                  width: 46,
                  height: 46,
                  alignment: Alignment.center,
                  decoration: const BoxDecoration(color: GColors.maroon, shape: BoxShape.circle),
                  child: _sending ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white)) : const GIcon('send', size: 18, color: Colors.white),
                ),
              ),
            ],
          ),
      ]);
    },
  );
}

/// T184 item 5: the dashboard card under Sampark; opens the latest ticket's chat (or the
/// Sahayata page when there is none yet).
class SupportDashCard extends StatefulWidget {
  const SupportDashCard({super.key});
  @override
  State<SupportDashCard> createState() => _SupportDashCardState();
}

class _SupportDashCardState extends State<SupportDashCard> {
  @override
  void initState() {
    super.initState();
    unawaited(SupportService.I.refreshSoon());
  }

  @override
  Widget build(BuildContext context) => ListenableBuilder(
    listenable: SupportService.I,
    builder: (context, _) => LookBuilder(
      builder: (context, _) {
        final s = SupportService.I;
        final t = s.tickets.isEmpty ? null : s.tickets.first;
        return Pressable(
          key: const ValueKey('dash-support'),
          onTap: () => AppNav.I.openLink(t == null ? '#/support' : '#/support?t=${t.id}'),
          scale: 0.98,
          child: Container(
            margin: const EdgeInsets.only(top: 14),
            padding: const EdgeInsets.all(16),
            decoration: themedSurface(BoxDecoration(color: GColors.paper, border: Border.all(color: GColors.creamDark), borderRadius: BorderRadius.circular(14))),
            child: Row(
              children: [
                const IconBox(tone: Tone.maroon, icon: 'message-circle', size: 44, radius: 12, iconSize: 22),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('सहायता / टिकट', style: GText.sans(size: 16, weight: FontWeight.w700, color: GColors.maroon)),
                      const SizedBox(height: 2),
                      Text(
                        t == null ? 'कोई समस्या? हमें लिखें — जवाब यहीं चैट में मिलेगा।' : '${t.label} · ${s.unread > 0 ? 'नया जवाब' : 'चैट खोलें'}',
                        style: GText.sans(size: 13.5, color: GColors.muted, height: 1.4),
                      ),
                    ],
                  ),
                ),
                UnreadBadge(key: const ValueKey('dash-support-badge'), count: s.unread),
                const GIcon('chevron-right', size: 18, color: GColors.muted),
              ],
            ),
          ),
        );
      },
    ),
  );
}
