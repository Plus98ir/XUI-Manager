import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xui_manager/api/panel_api.dart';
import 'package:xui_manager/models/models.dart';

/// Minimal fake of a 3X-UI panel under web base path /secret.
/// Minimal fake of a 3X-UI panel. With [csrf], every POST needs the session
/// CSRF token from GET /csrf-token, like 3X-UI 3.x.
Future<HttpServer> fakeXui(List<Map<String, String>> added, {bool csrf = false}) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final path = req.uri.path;
    final body = await utf8.decoder.bind(req).join();
    final authed = req.cookies.any((c) => c.name == '3x-ui' && c.value == 'sess');
    void json(Object o) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(o));
    }

    if (csrf && path == '/secret/csrf-token') {
      req.response.cookies.add(Cookie('3x-ui', 'pre'));
      json({'success': true, 'obj': 'tok'});
    } else if (csrf && req.method == 'POST' && req.headers.value('X-CSRF-Token') != 'tok') {
      req.response.statusCode = 403;
    } else if (path == '/secret/login' && req.method == 'POST') {
      final form = Uri.splitQueryString(body);
      if (form['username'] == 'admin' && form['password'] == 'pw') {
        req.response.cookies.add(Cookie('3x-ui', 'sess'));
        json({'success': true, 'msg': 'ok', 'obj': null});
      } else {
        json({'success': false, 'msg': 'wrong credentials', 'obj': null});
      }
    } else if (!authed) {
      req.response.statusCode = 404; // 3x-ui hides the API when logged out
    } else if (path == '/secret/panel/api/inbounds/list') {
      json({
        'success': true,
        'obj': [
          {
            'id': 1,
            'remark': 'de',
            'protocol': 'vless',
            'port': 443,
            'enable': true,
            'up': 10,
            'down': 20,
            'total': 0,
            'expiryTime': 0,
            'settings': jsonEncode({
              'clients': [
                {'id': 'uuid-1', 'email': 'u1', 'enable': true, 'totalGB': 100, 'expiryTime': 0, 'subId': 'sub1', 'flow': 'xtls-rprx-vision'},
                {'id': 'uuid-2', 'email': 'u2', 'enable': false, 'totalGB': 0, 'expiryTime': -86400000 * 7, 'subId': ''},
              ],
              'decryption': 'none',
            }),
            'streamSettings': jsonEncode({'network': 'tcp', 'security': 'none'}),
            'clientStats': [
              {'email': 'u1', 'up': 60, 'down': 50, 'total': 100, 'expiryTime': 0},
              {'email': 'u2', 'up': 0, 'down': 0, 'total': 0, 'expiryTime': 0},
            ],
          }
        ]
      });
    } else if (path == '/secret/panel/api/inbounds/onlines') {
      json({'success': true, 'obj': ['u1']});
    } else if (path == '/secret/panel/setting/all') {
      json({
        'success': true,
        'obj': {'subEnable': true, 'subPort': 2096, 'subPath': '/sub/', 'subURI': '', 'subDomain': ''}
      });
    } else if (path == '/secret/panel/api/server/status' && req.method == 'GET') {
      json({
        'success': true,
        'obj': {
          'cpu': 12.5,
          'cpuCores': 2,
          'mem': {'current': 512, 'total': 1024},
          'disk': {'current': 1, 'total': 4},
          'uptime': 3600,
          'xray': {'state': 'running', 'version': '25.1.1'},
          'netIO': {'up': 100, 'down': 200},
        }
      });
    } else if (path == '/secret/panel/api/inbounds/addClient') {
      added.add(Uri.splitQueryString(body));
      json({'success': true, 'obj': null});
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  });
  return server;
}

/// Minimal fake of a Marzban panel.
Future<HttpServer> fakeMarzban() async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final path = req.uri.path;
    final body = await utf8.decoder.bind(req).join();
    void json(Object o, [int code = 200]) {
      req.response.statusCode = code;
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode(o));
    }

    if (path == '/api/admin/token') {
      final form = Uri.splitQueryString(body);
      form['password'] == 'pw'
          ? json({'access_token': 'tok', 'token_type': 'bearer'})
          : json({'detail': 'Incorrect username or password'}, 401);
    } else if (req.headers.value('authorization') != 'Bearer tok') {
      json({'detail': 'Not authenticated'}, 401);
    } else if (path == '/api/system') {
      json({
        'version': '0.8.4',
        'mem_total': 2048,
        'mem_used': 1024,
        'cpu_cores': 4,
        'cpu_usage': 30.0,
        'total_user': 2,
        'users_active': 1,
        'online_users': 1,
        'incoming_bandwidth_speed': 10,
        'outgoing_bandwidth_speed': 20,
      });
    } else if (path == '/api/core') {
      json({'version': '1.8.24', 'started': true});
    } else if (path == '/api/users') {
      json({
        'total': 2,
        'users': [
          {
            'username': 'alice',
            'status': 'active',
            'used_traffic': 500,
            'data_limit': 1000,
            'expire': 4102444800,
            'subscription_url': '/sub/abc',
            'links': ['vless://x@h:1#a'],
            'proxies': {'vless': {}},
            'online_at': DateTime.now().toUtc().toIso8601String().replaceAll('Z', ''),
          },
          {'username': 'bob', 'status': 'on_hold', 'used_traffic': 0, 'data_limit': null, 'expire': null, 'on_hold_expire_duration': 2592000, 'proxies': {}},
        ]
      });
    } else {
      json({'detail': 'Not Found'}, 404);
    }
    await req.response.close();
  });
  return server;
}

void main() {
  group('3X-UI', () {
    late HttpServer server;
    final added = <Map<String, String>>[];
    late PanelApi api;

    setUp(() async {
      server = await fakeXui(added);
      // The user pasted the browser URL; the app must strip /panel/inbounds.
      api = PanelApi.create(PanelConfig(
        id: 'x',
        name: 'x',
        type: PanelType.threeXui,
        url: 'http://127.0.0.1:${server.port}/secret/panel/inbounds',
        username: 'admin',
        password: 'pw',
      ));
    });

    tearDown(() async {
      api.dispose();
      await server.close(force: true);
    });

    test('status falls back to the newer route', () async {
      final st = await api.status();
      expect(st.cpu, 12.5);
      expect(st.coreRunning, isTrue);
      expect(st.coreVersion, '25.1.1');
    });

    test('lists users with stats, online and sub link', () async {
      final users = await api.users();
      expect(users, hasLength(2));
      final u1 = users.firstWhere((u) => u.name == 'u1');
      expect(u1.used, 110);
      expect(u1.status, UserStatus.limited);
      expect(u1.online, isTrue);
      expect(u1.subUrl, 'http://127.0.0.1:2096/sub/sub1');
      expect(u1.links.single, startsWith('vless://uuid-1@127.0.0.1:443'));
      final u2 = users.firstWhere((u) => u.name == 'u2');
      expect(u2.status, UserStatus.disabled);
      expect(u2.expiryDaysAfterFirstUse, 7);
    });

    test('adds a client with the inbound flow', () async {
      await api.createUser(UserDraft(name: 'new1', totalBytes: 5, inboundId: 1));
      final settings = jsonDecode(added.last['settings']!) as Map;
      final client = (settings['clients'] as List).single as Map;
      expect(added.last['id'], '1');
      expect(client['email'], 'new1');
      expect(client['flow'], 'xtls-rprx-vision');
      expect(client.containsKey('tgId'), isFalse);
    });

    test('sends the CSRF token on login and writes (3X-UI 3.x)', () async {
      final csrfServer = await fakeXui(added, csrf: true);
      final v3 = PanelApi.create(PanelConfig(
          id: 'c',
          name: 'c',
          type: PanelType.threeXui,
          url: 'http://127.0.0.1:${csrfServer.port}/secret',
          username: 'admin',
          password: 'pw'));
      try {
        await v3.login();
        await v3.createUser(UserDraft(name: 'csrf1', totalBytes: 0, inboundId: 1));
        expect(added.last['id'], '1');
      } finally {
        v3.dispose();
        await csrfServer.close(force: true);
      }
    });

    test('wrong password shows the panel message', () async {
      final bad = PanelApi.create(PanelConfig(
          id: 'b',
          name: 'b',
          type: PanelType.threeXui,
          url: 'http://127.0.0.1:${server.port}/secret',
          username: 'admin',
          password: 'nope'));
      await expectLater(bad.login(), throwsA(predicate((e) => '$e' == 'wrong credentials')));
      bad.dispose();
    });
  });

  group('Marzban', () {
    late HttpServer server;
    late PanelApi api;

    setUp(() async {
      server = await fakeMarzban();
      api = PanelApi.create(PanelConfig(
        id: 'm',
        name: 'm',
        type: PanelType.marzban,
        url: 'http://127.0.0.1:${server.port}/dashboard/#/',
        username: 'admin',
        password: 'pw',
      ));
    });

    tearDown(() async {
      api.dispose();
      await server.close(force: true);
    });

    test('status and counters', () async {
      final st = await api.status();
      expect(st.coreRunning, isTrue);
      expect(st.totalUsers, 2);
      expect(st.onlineUsers, 1);
    });

    test('users', () async {
      final users = await api.users();
      final alice = users.firstWhere((u) => u.name == 'alice');
      expect(alice.online, isTrue);
      expect(alice.usage, 0.5);
      expect(alice.subUrl, 'http://127.0.0.1:${server.port}/sub/abc');
      final bob = users.firstWhere((u) => u.name == 'bob');
      expect(bob.status, UserStatus.onHold);
      expect(bob.expiryDaysAfterFirstUse, 30);
    });
  });
}
