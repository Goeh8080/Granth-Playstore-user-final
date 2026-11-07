import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/state/router.dart';

/// t184 item 1: entering AI forward (tab / link) asks for a fresh chat; Back into AI does not.
void main() {
  test('onEnterAi fires on forward entry only', () {
    final nav = AppNav();
    var n = 0;
    AppNav.onEnterAi = () => n++;
    nav.go('#/ai');
    expect(n, 1);
    nav.openLink('#/pramans?id=5'); // a praman from an answer
    nav.back(); // Back returns to the same chat
    expect(nav.route.panel, Panel.ai);
    expect(n, 1);
    nav.go('#/granths');
    nav.openLink('#/ai');
    expect(n, 2);
    AppNav.onEnterAi = null;
  });
}
