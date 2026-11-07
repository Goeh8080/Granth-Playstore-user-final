import 'package:dio/dio.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:granthprabandhan/services/analytics.dart';
import 'package:granthprabandhan/services/remote_config.dart';
import 'package:granthprabandhan/state/router.dart';

import 'analytics_test.dart' show Ingest;
import 'helpers.dart';

/// Round-2 analytics: per-id topic/praman opens, praman_open carries folder_id, folder_open on
/// every folder open, and one grid_pages parser.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Ingest net;
  late RemoteConfig cfg;
  late DateTime clock;
  late Analytics an;
  final ga = <(String, Map<String, Object>)>[];

  setUp(() async {
    await setUpApp();
    net = Ingest();
    cfg = RemoteConfig(publicKey: const [])..enabled = false;
    clock = DateTime.utc(2026, 11, 1, 9);
    an = Analytics(dio: Dio()..httpClientAdapter = net, now: () => clock, config: () => cfg, url: 'https://ev.test/events', enabled: true);
    ga.clear();
    Analytics.forward = (n, p) => ga.add((n, p));
    Analytics.granthOfPraman = (id) => id == '7' ? '44' : null;
    Analytics.folderOfGranth = (g) => g == '44' ? 'hindu/puran' : null;
  });
  tearDown(() => Analytics.forward = null);

  Future<void> nav(String h) async {
    AppNav.I.openLink(h);
    await Future<void>.delayed(Duration.zero);
    clock = clock.add(const Duration(seconds: 3));
  }

  Future<Map<String, dynamic>> send() async {
    await an.flush(force: true);
    return net.bodies.last;
  }

  test('open.t / open.p are keyed by topic_id / praman_id, plus topic_open / praman_open named events', () async {
    an.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await nav('#/pramans?topic=5');
    await nav('#/pramans?id=7');
    await nav('#/pramans?id=9');
    await nav('#/pramans?id=7&topic=5');
    final b = await send();
    expect((b['open'] as Map)['t'], {'5': 2});
    expect((b['open'] as Map)['p'], {'7': 2, '9': 1});
    final ev = (b['events'] as List).cast<Map>();
    expect(ev.where((e) => e['name'] == 'topic_open').single, {'name': 'topic_open', 'id': '5', 'n': 2});
    expect(ev.firstWhere((e) => e['name'] == 'praman_open' && e['id'] == '7'), {'name': 'praman_open', 'id': '7', 'folder_id': 'hindu/puran', 'n': 2});
    expect(ev.firstWhere((e) => e['name'] == 'praman_open' && e['id'] == '9'), {'name': 'praman_open', 'id': '9', 'n': 1});
    expect(Analytics.namedEvents, containsAll(['topic_open', 'praman_open']));
  });

  test('GA4 praman_open carries praman_id, granth_id and folder_id; topic_open carries topic_id', () async {
    an.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await nav('#/pramans?id=7');
    await nav('#/pramans?topic=5');
    expect(ga.firstWhere((e) => e.$1 == 'praman_open').$2, {'praman_id': '7', 'granth_id': '44', 'folder_id': 'hindu/puran'});
    expect(ga.firstWhere((e) => e.$1 == 'topic_open').$2, {'topic_id': '5'});
  });

  test('folder_open is sent on EVERY folder open, also when re-opened and also with /events off', () async {
    an.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await nav('#/granths?r=hindu&g=puran');
    await nav('#/pramans?granth=44');
    await nav('#/granths?r=hindu&g=puran');
    await nav('#/granths?r=hindu&g=ved');
    await nav('#/granths?r=hindu&g=puran');
    expect(ga.where((e) => e.$1 == 'folder_open').map((e) => e.$2['folder_id']), ['hindu/puran', 'hindu/puran', 'hindu/ved', 'hindu/puran']);
    final b = await send();
    final ev = (b['events'] as List).cast<Map>();
    expect(ev.firstWhere((e) => e['name'] == 'folder_open' && e['id'] == 'hindu/puran')['n'], 3);
  });

  test('with /events switched off, GA4 still gets folder_open', () async {
    final off = Analytics(dio: Dio()..httpClientAdapter = net, now: () => clock, config: () => cfg, url: 'x', enabled: false);
    off.start();
    await Future<void>.delayed(const Duration(milliseconds: 20));
    await nav('#/granths?r=hindu&g=ved');
    expect(ga.where((e) => e.$1 == 'folder_open').map((e) => e.$2['folder_id']), ['hindu/ved']);
    expect(off.debugQueue, isEmpty);
  });

  test('grid_pages: one parser accepts N, {default:N} and {force:N}; anything else is ignored', () {
    final ui = {
      'grid_pages': {
        'granths': 3,
        'pramans': {'default': 1},
        'topics': {'force': 2},
        'gallery': {'default': 2, 'force': 1},
        'shelves': '2',
        'dashboard': {'force': 4},
      },
    };
    expect(parseGridPages(ui), {'granths': 3, 'pramans': 1, 'gallery': 2});
    expect(parseGridForce(ui), {'topics': 2, 'gallery': 1});
  });
}
