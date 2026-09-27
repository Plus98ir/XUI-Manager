import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:xui_manager/api/xui_links.dart';
import 'package:xui_manager/models/models.dart';
import 'package:xui_manager/utils/format.dart';

void main() {
  test('normalizePanelUrl strips browser paths and keeps web base path', () {
    expect(normalizePanelUrl('https://a.com:2053/secret/panel/inbounds'),
        'https://a.com:2053/secret');
    expect(normalizePanelUrl('a.com:8000/dashboard/#/'), 'https://a.com:8000');
    expect(normalizePanelUrl('http://1.2.3.4:54321/'), 'http://1.2.3.4:54321');
  });

  test('fmtBytes', () {
    String plain(String s) => s.replaceAll(RegExp('[\u2066\u2069]'), '');
    expect(plain(fmtBytes(0)), '0 B');
    expect(plain(fmtBytes(1024)), '1.00 KB');
    expect(plain(fmtBytes(1073741824)), '1.00 GB');
  });

  test('builds a vless reality link', () {
    final inbound = {
      'protocol': 'vless',
      'port': 443,
      'remark': 'de',
      'settings': jsonEncode({'decryption': 'none', 'clients': []}),
      'streamSettings': jsonEncode({
        'network': 'tcp',
        'security': 'reality',
        'realitySettings': {
          'serverNames': ['www.example.com'],
          'shortIds': ['ab12'],
          'settings': {'publicKey': 'PBK', 'fingerprint': 'chrome', 'spiderX': '/'},
        },
      }),
    };
    final client = {'id': 'uuid-1', 'email': 'u1', 'flow': 'xtls-rprx-vision'};
    final links = buildXuiLinks(inbound, client, 'srv.example.com');
    expect(links, hasLength(1));
    final l = links.first;
    expect(l, startsWith('vless://uuid-1@srv.example.com:443?'));
    expect(l, contains('security=reality'));
    expect(l, contains('pbk=PBK'));
    expect(l, contains('flow=xtls-rprx-vision'));
    expect(l, endsWith('#de-u1'));
  });
}
