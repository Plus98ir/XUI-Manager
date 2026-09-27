import 'dart:convert';

import 'package:xui_manager/api/panel_api.dart';
import 'package:xui_manager/models/models.dart';
import 'package:xui_manager/utils/inbound_defaults.dart';

/// In-memory 3X-UI 3.x panel with realistic data for UI tests.
class FakeApi extends PanelApi {
  FakeApi(super.config);

  int _tick = 0;
  final saved = <Map<String, dynamic>>[];

  @override
  UserFormKind get userFormKind => UserFormKind.xuiV3;
  @override
  bool get supportsMultiInbound => true;
  @override
  bool get canManageInbounds => true;
  @override
  bool get hasPanelSettings => true;

  @override
  Future<void> login() async {}

  @override
  Future<ServerStats> status() async => const ServerStats(
        cpu: 23.4,
        cpuCores: 4,
        memUsed: 1900000000,
        memTotal: 4000000000,
        diskUsed: 21000000000,
        diskTotal: 52000000000,
        uptime: 263513,
        netUpSpeed: 1250000,
        netDownSpeed: 8400000,
        netSent: 912000000000,
        netRecv: 4400000000000,
        coreState: 'running',
        coreVersion: '26.9.9',
        panelVersion: '3.8.5',
        tcpCount: 270,
        udpCount: 31,
        loads: [0.42, 0.51, 0.47],
        ipv4: '203.0.113.10',
      );

  static final _inbounds = [
    const InboundInfo(id: 3, tag: 'inbound-2542', remark: 'DE WS', protocol: 'vless', port: 2542, network: 'ws', security: 'tls', up: 17410966013, down: 247009967247, total: 0, clientCount: 12),
    const InboundInfo(id: 6, tag: 'inbound-3103', remark: 'NL xHTTP CDN with a very long remark name', protocol: 'vless', port: 3103, network: 'xhttp', security: 'tls', up: 5100000000, down: 91000000000, total: 536870912000, clientCount: 31),
    const InboundInfo(id: 21, tag: 'inbound-8442', remark: 'Reality', protocol: 'vless', port: 8442, network: 'tcp', security: 'reality', up: 1200000000, down: 33000000000, total: 0, clientCount: 4, enabled: false),
    const InboundInfo(id: 30, tag: 'inbound-8388', remark: 'SS 2022', protocol: 'shadowsocks', port: 8388, network: 'tcp', security: 'none', up: 0, down: 0, total: 0, clientCount: 0),
  ];

  @override
  Future<List<InboundInfo>> inbounds() async => _inbounds;

  @override
  Future<List<PanelUser>> users() async {
    _tick++;
    final now = DateTime.now();
    PanelUser u(String name, UserStatus st, int up, int down, int total,
            {DateTime? exp, int? after, bool online = false, String? note, List<int> ibs = const [3, 6]}) =>
        PanelUser(
          key: 'c:$name',
          name: name,
          enabled: st != UserStatus.disabled,
          status: st,
          up: up + (online ? _tick * 2500000 : 0),
          down: down + (online ? _tick * 19000000 : 0),
          total: total,
          expiry: exp,
          expiryDaysAfterFirstUse: after,
          online: online,
          subUrl: 'https://sub.example.com:2096/sub/abc$name',
          links: ['vless://00000000-0000-4000-8000-000000000000@edge.example.com:2542?type=ws&security=tls#$name'],
          note: note,
          limitIp: 2,
          inboundId: ibs.first,
          inboundName: 'DE WS, NL xHTTP CDN',
          protocol: 'vless',
          raw: {
            'email': name,
            'uuid': '00000000-0000-4000-8000-000000000000',
            'subId': 'abc$name',
            'inboundIds': ibs,
            'limitHwid': 1,
            'tgId': 0,
            'reset': 30,
            'trafficReset': 'monthly',
            'trafficResetDay': 1,
            'group': 'vip',
          },
        );
    return [
      u('alice', UserStatus.active, 2764659298, 33453748039, 53687091200,
          exp: now.add(const Duration(days: 23)), online: true, note: 'Admin'),
      u('customer-with-a-very-long-email-name@example.com', UserStatus.active, 1200000000,
          9800000000, 10737418240, exp: now.add(const Duration(hours: 20)), online: true),
      u('bob', UserStatus.limited, 5000000000, 48687091200, 53687091200,
          exp: now.add(const Duration(days: 5))),
      u('carol', UserStatus.expired, 100000000, 900000000, 0,
          exp: now.subtract(const Duration(days: 2))),
      u('DNS', UserStatus.active, 0, 0, 0, after: 30),
      u('dave', UserStatus.disabled, 3000000, 90000000, 21474836480),
    ];
  }

  @override
  Future<List<String>?> fetchLinks(PanelUser user) async => null;

  @override
  Future<void> createUser(UserDraft draft) async {}
  @override
  Future<void> updateUser(PanelUser user, UserDraft draft) async {}
  @override
  Future<void> setEnabled(PanelUser user, bool enabled) async {}
  @override
  Future<void> deleteUser(PanelUser user) async {}
  @override
  Future<void> resetTraffic(PanelUser user) async {}
  @override
  Future<void> restartCore() async {}

  @override
  Future<Map<String, dynamic>> rawInbound(int id) async {
    final m = InboundDefaults.newInbound(v3: true);
    m['id'] = id;
    m['remark'] = 'Reality';
    m['port'] = 8442;
    InboundDefaults.setSecurity(m['streamSettings'] as Map<String, dynamic>, 'reality', v3: true);
    return m;
  }

  @override
  Future<void> saveInbound(Map<String, dynamic> inbound, {int? id}) async => saved.add(inbound);

  @override
  Future<(String, String)> newRealityKeys() async => ('priv-key', 'pub-key');

  @override
  Future<Map<String, dynamic>> panelSettings() async => {
        'webListen': '',
        'webDomain': '',
        'webPort': 2053,
        'webBasePath': '/y4WKNZ42jE0bvLe0bG/',
        'sessionMaxAge': 360,
        'expireDiff': 3,
        'trafficDiff': 2,
        'restartXrayOnClientDisable': true,
        'remarkTemplate': '{{INBOUND_REMARK}}-{{EMAIL}}',
        'tgBotEnable': true,
        'tgBotToken': '',
        'hasTgBotToken': true,
        'tgBotChatId': '123456',
        'subEnable': true,
        'subPort': 2096,
        'subPath': '/sub/demo/',
        'subAnnounce': 'Welcome 👋\nSupport: @support',
        'subJsonEnable': false,
        'subHappAutoDetect': false,
        'twoFactorEnable': false,
        'smtpEnable': false,
        'ldapEnable': false,
      };

  @override
  Future<String> xrayConfig() async => xray;

  String xray = jsonEncode({
    'log': {'loglevel': 'warning'},
    'inbounds': [
      {'tag': 'api', 'listen': '127.0.0.1', 'port': 62789, 'protocol': 'tunnel'}
    ],
    'outbounds': [
      {'tag': 'direct', 'protocol': 'freedom', 'settings': {'domainStrategy': 'AsIs'}},
      {'tag': 'blocked', 'protocol': 'blackhole', 'settings': {}},
      {
        'tag': 'warp',
        'protocol': 'wireguard',
        'settings': {
          'secretKey': 'x',
          'address': ['172.16.0.2/32'],
          'peers': [
            {'publicKey': 'y', 'endpoint': 'engage.cloudflareclient.com:2408'}
          ],
        },
      },
      {
        'tag': 'Germany-Reality-exit-node-with-long-name',
        'protocol': 'vless',
        'settings': {
          'vnext': [
            {
              'address': 'de.example.com',
              'port': 443,
              'users': [
                {
                  'id': '00000000-0000-4000-8000-000000000000',
                  'encryption': 'none',
                  'flow': 'xtls-rprx-vision'
                }
              ],
            }
          ],
        },
        'streamSettings': {'network': 'tcp', 'security': 'reality'},
      },
    ],
    'routing': {
      'domainStrategy': 'IPIfNonMatch',
      'rules': [
        {'type': 'field', 'inboundTag': ['api'], 'outboundTag': 'api'},
        {'type': 'field', 'outboundTag': 'blocked', 'ip': ['geoip:private']},
        {'type': 'field', 'outboundTag': 'blocked', 'protocol': ['bittorrent']},
        {
          'type': 'field',
          'outboundTag': 'warp',
          'domain': ['geosite:openai', 'geosite:google-gemini', 'domain:claude.ai', 'domain:spotify.com'],
        },
        {
          'type': 'field',
          'outboundTag': 'direct',
          'domain': ['geosite:category-ir'],
          'ip': ['geoip:ir'],
        },
      ],
    },
  });

  @override
  Future<void> saveXrayConfig(String json) async => xray = json;

  @override
  void dispose() {}
}
