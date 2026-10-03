import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:xui_manager/api/panel_api.dart';
import 'package:xui_manager/models/models.dart';

/// Fake 3X-UI 3.x panel: Bearer token auth + /panel/api/clients catalog.
Future<HttpServer> fakeV3(List<(String, String, Object?)> calls) async {
  final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
  server.listen((req) async {
    final path = req.uri.path.replaceFirst('/base', '');
    final body = await utf8.decoder.bind(req).join();
    void json(Object? o) {
      req.response.headers.contentType = ContentType.json;
      req.response.write(jsonEncode({'success': true, 'msg': '', 'obj': o}));
    }

    if (req.headers.value('authorization') != 'Bearer tok') {
      req.response.statusCode = 404;
    } else if (path == '/panel/api/server/status') {
      json({'cpu': 5, 'panelVersion': '3.8.5', 'xray': {'state': 'running', 'version': '26.9.9'}});
    } else if (path == '/panel/api/clients/list') {
      json([
        {
          // Real 3.x rows are DB records: numeric id, uuid, CSV allowedIPs.
          'id': 7,
          'uuid': 'uuid-a',
          'allowedIPs': '10.0.0.2/32, fd00::2/128',
          'reverse': '',
          'keepAlive': 0,
          'createdAt': 1,
          'email': 'alice',
          'enable': true,
          'totalGB': 1000,
          'expiryTime': 0,
          'subId': 's1',
          'comment': 'vip',
          'tgId': 42,
          'inboundIds': [1, 2],
          'traffic': {'up': 100, 'down': 200, 'lastOnline': 0},
        }
      ]);
    } else if (path == '/panel/api/inbounds/list') {
      json([
        for (final id in [1, 2])
          {
            'id': id,
            'remark': 'in$id',
            'protocol': 'vless',
            'port': 1000 + id,
            'shareAddr': 'edge.example.com',
            'settings': {
              'clients': [
                {'email': 'alice', 'id': 'uuid-a', 'flow': 'xtls-rprx-vision'}
              ]
            },
            'streamSettings': {'network': 'tcp', 'security': 'reality', 'realitySettings': {}},
          }
      ]);
    } else if (path == '/panel/api/clients/onlines') {
      json(['alice']);
    } else if (path == '/panel/api/setting/all') {
      json({'subEnable': false});
    } else if (path == '/panel/api/xray/') {
      json(jsonEncode({
        'xraySetting': {'log': {'loglevel': 'warning'}},
        'inboundTags': ['inbound-1001'],
      }));
    } else if (path == '/panel/api/server/getNewX25519Cert') {
      json({'privateKey': 'priv', 'publicKey': 'pub'});
    } else if (req.method == 'POST' &&
        (path.startsWith('/panel/api/clients/') ||
            path.startsWith('/panel/api/inbounds/') ||
            path == '/panel/api/setting/update' ||
            path == '/panel/api/xray/update')) {
      Object? parsed;
      try {
        parsed = body.isEmpty ? null : jsonDecode(body);
      } on FormatException {
        parsed = Uri.splitQueryString(body);
      }
      calls.add((req.method, path, parsed));
      json(null);
    } else {
      req.response.statusCode = 404;
    }
    await req.response.close();
  });
  return server;
}

void main() {
  late HttpServer server;
  late PanelApi api;
  final calls = <(String, String, Object?)>[];

  setUp(() async {
    calls.clear();
    server = await fakeV3(calls);
    api = PanelApi.create(PanelConfig(
      id: 'v3',
      name: 'v3',
      type: PanelType.threeXui,
      url: 'http://127.0.0.1:${server.port}/base/',
      token: 'tok',
    ));
  });

  tearDown(() async {
    api.dispose();
    await server.close(force: true);
  });

  test('token login and one user per catalog client', () async {
    await api.login();
    final users = await api.users();
    expect(users, hasLength(1));
    final a = users.single;
    expect(a.used, 300);
    expect(a.online, isTrue);
    expect(a.inboundName, 'in1, in2');
    expect(a.links, hasLength(2));
    expect(a.links.first, startsWith('vless://uuid-a@edge.example.com:1001'));
    expect(api.supportsMultiInbound, isTrue);
  });

  test('create posts client + inboundIds as JSON', () async {
    await api.createUser(UserDraft(name: 'bob', totalBytes: 5, inboundIds: {1, 2}));
    final (_, path, body) = calls.single;
    expect(path, '/panel/api/clients/add');
    final m = body as Map;
    expect(m['inboundIds'], [1, 2]);
    expect(m['client']['email'], 'bob');
    expect(m['client']['flow'], 'xtls-rprx-vision');
    expect(m['client']['tgId'], 0);
  });

  test('edit attaches and detaches changed inbounds', () async {
    final u = (await api.users()).single;
    await api.updateUser(u, UserDraft(name: 'alice', inboundIds: {2, 7}, extra: {'limitHwid': 3, 'uuid': 'u-1'}));
    final paths = calls.map((c) => c.$2).toList();
    expect(paths, [
      '/panel/api/clients/update/alice',
      '/panel/api/clients/alice/attach',
      '/panel/api/clients/alice/detach',
    ]);
    final body = calls[0].$3 as Map;
    expect(body['limitHwid'], 3);
    expect(body['id'], 'u-1');
    expect((calls[1].$3 as Map)['inboundIds'], [7]);
    expect((calls[2].$3 as Map)['inboundIds'], [1]);
  });

  test('inbound add/update/enable/delete/reset use 3.x routes with objects', () async {
    final raw = await api.rawInbound(1);
    expect(raw['settings'], isA<Map>());
    raw['remark'] = 'changed';
    await api.saveInbound(raw, id: 1);
    expect(calls.last.$2, '/panel/api/inbounds/update/1');
    expect((calls.last.$3 as Map)['settings'], isA<Map>());
    expect((calls.last.$3 as Map)['remark'], 'changed');
    await api.saveInbound({'protocol': 'vless', 'port': 5555, 'settings': {}, 'streamSettings': {}, 'sniffing': {}});
    expect(calls.last.$2, '/panel/api/inbounds/add');
    await api.setInboundEnabled(1, false);
    expect(calls.last.$2, '/panel/api/inbounds/setEnable/1');
    expect(calls.last.$3, {'enable': false});
    await api.resetInboundTraffic(1);
    expect(calls.last.$2, '/panel/api/inbounds/1/resetTraffic');
    await api.deleteInbound(1);
    expect(calls.last.$2, '/panel/api/inbounds/del/1');
    expect(await api.newRealityKeys(), ('priv', 'pub'));
  });

  test('panel settings and xray config round-trip', () async {
    final s = await api.panelSettings();
    expect(s['subEnable'], false);
    await api.savePanelSettings({...s, 'subEnable': true});
    expect(calls.last.$2, '/panel/api/setting/update');
    expect((calls.last.$3 as Map)['subEnable'], true);
    final cfg = await api.xrayConfig();
    expect(jsonDecode(cfg), {'log': {'loglevel': 'warning'}});
    await api.saveXrayConfig('{"log":{}}');
    expect(calls.last.$2, '/panel/api/xray/update');
    expect((calls.last.$3 as Map)['xraySetting'], '{"log":{}}');
    expect(() => api.saveXrayConfig('{bad'), throwsFormatException);
  });

  test('update sends the full row, disable/delete/reset use v3 routes', () async {
    final u = (await api.users()).single;
    await api.updateUser(u, UserDraft(name: 'alice', totalBytes: 9, note: 'vip'));
    final (_, p1, b1) = calls.last;
    expect(p1, '/panel/api/clients/update/alice');
    expect((b1 as Map)['tgId'], 42); // kept from the original row
    expect(b1.containsKey('traffic'), isFalse);
    expect(b1['totalGB'], 9);
    // Shaped like model.Client, or the server fails to unmarshal it.
    expect(b1['id'], 'uuid-a');
    expect(b1['allowedIPs'], ['10.0.0.2/32', 'fd00::2/128']);
    expect(b1.containsKey('reverse'), isFalse);
    expect(b1.containsKey('uuid'), isFalse);
    expect(b1.containsKey('createdAt'), isFalse);

    await api.setEnabled(u, false);
    expect(calls.last.$2, '/panel/api/clients/bulkDisable');
    expect((calls.last.$3 as Map)['emails'], ['alice']);
    await api.resetTraffic(u);
    expect(calls.last.$2, '/panel/api/clients/resetTraffic/alice');
    await api.deleteUser(u);
    expect(calls.last.$2, '/panel/api/clients/del/alice');
  });
}
