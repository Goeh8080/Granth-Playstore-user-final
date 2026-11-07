/// Round 15: the first-launch login page. Shown once before the dashboard to anyone not signed
/// in. T184/§21: login is compulsory (also for users who skipped before) unless the admin sets
/// `ui.login_required:false`; only then "बाद में" appears and skips it. Back here is
/// Back on the app's first screen, so it leaves the app.
library;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/firebase_bridge.dart';
import '../services/file_actions.dart';
import '../services/native_bridge.dart';
import '../services/remote_config.dart';
import '../services/storage.dart';
import '../state/toast.dart';
import '../theme/colors.dart';
import '../widgets/common.dart';

/// Shows [LoginPage] in front of [child] until the user signs in or skips.
class LoginGate extends StatefulWidget {
  const LoginGate({super.key, required this.child});
  final Widget child;

  /// Tests turn the gate off (they boot straight into the dashboard).
  static bool enabled = true;

  static bool get seen => Store.I.getString(Store.kLoginSeen) == '1';

  /// §21: `ui.login_required` true or missing → compulsory.
  static bool get required => RemoteConfig.I.uiLoginRequired;
  static void markSeen() => Store.I.setString(Store.kLoginSeen, '1');

  /// Round-3: the terms version accepted on this device (0 = never).
  static int get termsAccepted => int.tryParse(Store.I.getString(Store.kTermsAccepted) ?? '') ?? 0;
  static void acceptTerms(int v) => Store.I.setString(Store.kTermsAccepted, '$v');

  /// Signed-in users (new or already signed in before this update) must accept the current
  /// terms version; a newer `ui.terms.version` asks again.
  static bool get needsTerms => enabled && Store.I.persistent && FirebaseBridge.I.signedIn && RemoteConfig.I.uiTerms.version > termsAccepted;

  @override
  State<LoginGate> createState() => _LoginGateState();
}

class _LoginGateState extends State<LoginGate> {
  bool _skipped = false;
  bool get _show => LoginGate.enabled && !FirebaseBridge.I.signedIn && (LoginGate.required || (!LoginGate.seen && !_skipped));

  @override
  void initState() {
    super.initState();
    FirebaseBridge.I.addListener(_auth);
    RemoteConfig.I.addListener(_cfg);
    Store.I.adopted.addListener(_cfg);
  }

  void _cfg() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    FirebaseBridge.I.removeListener(_auth);
    RemoteConfig.I.removeListener(_cfg);
    Store.I.adopted.removeListener(_cfg);
    super.dispose();
  }

  bool _wasIn = FirebaseBridge.I.signedIn;

  void _auth() {
    final inNow = FirebaseBridge.I.signedIn;
    if (_wasIn && !inNow) _skipped = false; // logged out: back to the login gate
    _wasIn = inNow;
    if (inNow && !LoginGate.seen) {
      _done();
    } else if (mounted) {
      setState(() {});
    }
  }

  void _done() {
    LoginGate.markSeen();
    if (mounted) setState(() => _skipped = true);
  }

  @override
  Widget build(BuildContext context) => AnimatedSwitcher(
    duration: const Duration(milliseconds: 320),
    child: _show
        ? LoginPage(key: const ValueKey('login-page'), onSkip: LoginGate.required ? null : _done)
        : LoginGate.needsTerms
        ? TermsPage(
            key: const ValueKey('terms-page'),
            terms: RemoteConfig.I.uiTerms,
            onAccept: () {
              LoginGate.acceptTerms(RemoteConfig.I.uiTerms.version);
              setState(() {});
            },
            onDecline: () => FirebaseBridge.I.signOut(),
          )
        : KeyedSubtree(key: const ValueKey('login-passed'), child: widget.child),
  );
}

const _gLogo =
    '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 48 48"><path fill="#EA4335" d="M24 9.5c3.54 0 6.71 1.22 9.21 3.6l6.85-6.85C35.9 2.38 30.47 0 24 0 14.62 0 6.51 5.38 2.56 13.22l7.98 6.19C12.43 13.72 17.74 9.5 24 9.5z"/><path fill="#4285F4" d="M46.98 24.55c0-1.57-.15-3.09-.38-4.55H24v9.02h12.94c-.58 2.96-2.26 5.48-4.78 7.18l7.73 6c4.51-4.18 7.09-10.36 7.09-17.65z"/><path fill="#FBBC05" d="M10.53 28.59c-.48-1.45-.76-2.99-.76-4.59s.27-3.14.76-4.59l-7.98-6.19C.92 16.46 0 20.12 0 24c0 3.88.92 7.54 2.56 10.78l7.97-6.19z"/><path fill="#34A853" d="M24 48c6.48 0 11.93-2.13 15.89-5.81l-7.73-6c-2.15 1.45-4.92 2.3-8.16 2.3-6.26 0-11.57-4.22-13.47-9.91l-7.98 6.19C6.51 42.62 14.62 48 24 48z"/></svg>';

/// Google's "Sign in with Google" button (light theme: white, grey border, the 4-colour G).
class GoogleSignInButton extends StatelessWidget {
  const GoogleSignInButton({super.key, required this.onTap, this.busy = false});
  final VoidCallback onTap;
  final bool busy;
  @override
  Widget build(BuildContext context) => Material(
    color: Colors.white,
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(24),
      side: const BorderSide(color: Color(0xFF747775)),
    ),
    child: InkWell(
      customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      onTap: busy ? null : onTap,
      child: SizedBox(
        height: 48,
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            busy ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2.2)) : SvgPicture.string(_gLogo, width: 20, height: 20),
            const SizedBox(width: 12),
            Text(
              busy ? 'Signing in…' : 'Sign in with Google',
              style: const TextStyle(fontFamily: 'DMSans', fontSize: 15.5, fontWeight: FontWeight.w600, color: Color(0xFF1F1F1F), letterSpacing: 0.25),
            ),
          ],
        ),
      ),
    ),
  );
}

class LoginPage extends StatelessWidget {
  const LoginPage({super.key, required this.onSkip});
  final VoidCallback? onSkip;

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) NativeBridge.exitApp().catchError((Object _) => SystemNavigator.pop());
    },
    child: Scaffold(
      backgroundColor: GColors.cream,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF7EA), GColors.cream]),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(28, 16, 28, 20),
            child: ListenableBuilder(
              listenable: FirebaseBridge.I,
              builder: (context, _) => Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  const Spacer(flex: 3),
                  Center(
                    child: Container(
                      decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(36),
                        boxShadow: [BoxShadow(color: GColors.saffron.withValues(alpha: 0.35), blurRadius: 40, spreadRadius: 4)],
                      ),
                      child: const LogoIcon(size: 120),
                    ),
                  ),
                  const SizedBox(height: 26),
                  Text(
                    'ग्रंथ प्रबंधन',
                    textAlign: TextAlign.center,
                    style: GText.display(size: 34, color: GColors.maroon, letterSpacing: 0.5),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'सत ग्रंथों के प्रमाण, एक जगह',
                    textAlign: TextAlign.center,
                    style: GText.sans(size: 15.5, color: GColors.brown),
                  ),
                  const Spacer(flex: 2),
                  Text(
                    'लॉगिन करने पर आपका नाम, Gmail और आँकड़े अकाउंट में दिखेंगे। लॉगिन ज़रूरी नहीं है।',
                    textAlign: TextAlign.center,
                    style: GText.sans(size: 13.5, color: GColors.muted, height: 1.45),
                  ),
                  const SizedBox(height: 16),
                  GoogleSignInButton(
                    key: const ValueKey('login-google'),
                    busy: FirebaseBridge.I.busy,
                    onTap: () async {
                      final e = await FirebaseBridge.I.signIn();
                      if (e != null) Toast.show(e);
                    },
                  ),
                  // Round-2: the Toast layer lives in HomeShell, which is not mounted behind this
                  // page, so progress and the error code are shown right here.
                  if (FirebaseBridge.I.busy && FirebaseBridge.I.stage != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        FirebaseBridge.I.stage!,
                        key: const ValueKey('login-stage'),
                        textAlign: TextAlign.center,
                        style: GText.sans(size: 13.5, color: GColors.brown),
                      ),
                    ),
                  if (!FirebaseBridge.I.busy && FirebaseBridge.I.error != null)
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: SelectableText(
                        FirebaseBridge.I.error!,
                        key: const ValueKey('login-error'),
                        textAlign: TextAlign.center,
                        style: GText.sans(size: 13.5, color: const Color(0xFFB3261E)),
                      ),
                    ),
                  const SizedBox(height: 10),
                  if (onSkip != null)
                    Center(
                      child: TextButton(
                        key: const ValueKey('login-skip'),
                        onPressed: onSkip,
                        child: Text(
                          'बाद में',
                          style: GText.sans(size: 14.5, weight: FontWeight.w700, color: GColors.maroon),
                        ),
                      ),
                    ),
                  const Spacer(),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

/// Round-3: the terms page, shown after Google login and before the app. No skip; Back is the
/// same as on the login page (it leaves the app).
class TermsPage extends StatelessWidget {
  const TermsPage({super.key, required this.terms, required this.onAccept, required this.onDecline});
  final TermsInfo terms;
  final VoidCallback onAccept, onDecline;

  /// A faithful short form of the Hindi terms (granth-management.web.app/terms, version 1).
  static const points = [
    'ऐप की सामग्री केवल व्यक्तिगत, अध्ययन व धार्मिक उपयोग के लिए है; इसे बेचना या गलत रूप में प्रस्तुत करना मना है।',
    'Google से लॉगिन वैकल्पिक है; अपने खाते की सुरक्षा आपकी ज़िम्मेदारी है।',
    'AI के जवाब स्वचालित हैं और गलत हो सकते हैं; मूल ग्रंथ/प्रमाण से जाँच करें। AI से अवैध, अपमानजनक या हानिकारक प्रश्न न पूछें।',
    'ऐप "जैसा है" दिया जाता है; सेवा कभी भी बदली या बंद की जा सकती है। दुरुपयोग पर पहुँच रोकी जा सकती है, और शर्तें बदलने पर ऐप दोबारा सहमति माँग सकता है।',
  ];

  @override
  Widget build(BuildContext context) => PopScope(
    canPop: false,
    onPopInvokedWithResult: (didPop, _) {
      if (!didPop) NativeBridge.exitApp().catchError((Object _) => SystemNavigator.pop());
    },
    child: Scaffold(
      backgroundColor: GColors.cream,
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: [Color(0xFFFFF7EA), GColors.cream]),
        ),
        child: SafeArea(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Expanded(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(24, 28, 24, 12),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      const Center(child: LogoIcon(size: 72)),
                      const SizedBox(height: 18),
                      Text(
                        'नियम और शर्तें',
                        textAlign: TextAlign.center,
                        style: GText.display(size: 28, color: GColors.maroon),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        'Terms & Conditions',
                        textAlign: TextAlign.center,
                        style: GText.sans(size: 13, color: GColors.muted),
                      ),
                      const SizedBox(height: 20),
                      Container(
                        padding: const EdgeInsets.all(16),
                        decoration: BoxDecoration(
                          color: GColors.paper,
                          borderRadius: BorderRadius.circular(18),
                          border: Border.all(color: GColors.gold.withValues(alpha: 0.4)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'आगे बढ़ने से पहले संक्षेप में:',
                              style: GText.sans(size: 14.5, weight: FontWeight.w700, color: GColors.brown),
                            ),
                            const SizedBox(height: 10),
                            for (final p in points)
                              Padding(
                                padding: const EdgeInsets.only(bottom: 8),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text('•  ', style: GText.sans(size: 14, color: GColors.maroon)),
                                    Expanded(
                                      child: Text(p, style: GText.sans(size: 14, color: GColors.text, height: 1.45)),
                                    ),
                                  ],
                                ),
                              ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 12),
                      Wrap(
                        alignment: WrapAlignment.center,
                        children: [
                          TextButton(
                            key: const ValueKey('terms-link'),
                            onPressed: () => FileActions.openUrl(terms.url).catchError((Object _) {}),
                            child: Text(
                              'पूरे नियम पढ़ें',
                              style: GText.sans(size: 14.5, weight: FontWeight.w700, color: GColors.maroon).copyWith(decoration: TextDecoration.underline),
                            ),
                          ),
                          TextButton(
                            key: const ValueKey('privacy-link'),
                            onPressed: () => FileActions.openUrl(terms.privacyUrl).catchError((Object _) {}),
                            child: Text(
                              'गोपनीयता नीति',
                              style: GText.sans(size: 14.5, weight: FontWeight.w700, color: GColors.maroon).copyWith(decoration: TextDecoration.underline),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 6, 24, 18),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      '"स्वीकार करें" दबाकर आप इन नियमों (संस्करण ${terms.version}) से सहमत होते हैं।',
                      textAlign: TextAlign.center,
                      style: GText.sans(size: 12.5, color: GColors.muted, height: 1.4),
                    ),
                    const SizedBox(height: 10),
                    FilledButton(
                      key: const ValueKey('terms-accept'),
                      style: FilledButton.styleFrom(
                        backgroundColor: GColors.maroon,
                        foregroundColor: GColors.paper,
                        minimumSize: const Size.fromHeight(50),
                        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(25)),
                      ),
                      onPressed: onAccept,
                      child: Text(
                        'स्वीकार करें',
                        style: GText.sans(size: 16, weight: FontWeight.w700, color: GColors.paper),
                      ),
                    ),
                    const SizedBox(height: 4),
                    TextButton(
                      key: const ValueKey('terms-decline'),
                      onPressed: onDecline,
                      child: Text(
                        'अस्वीकार (लॉगआउट करें)',
                        style: GText.sans(size: 14, weight: FontWeight.w600, color: GColors.muted),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}
