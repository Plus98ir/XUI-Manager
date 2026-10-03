import 'dart:math';

import 'json.dart';
import 'random.dart';

/// Defaults mirroring the 3X-UI inbound form, so a new inbound saved from the
/// app looks like one created in the panel.
class InboundDefaults {
  /// Protocols with the full transport (network) + TLS/Reality form.
  static const protocols = ['vless', 'vmess', 'trojan', 'shadowsocks'];

  /// Everything the panel can create, in its own picker order. 3X-UI 3.x
  /// renamed dokodemo-door to tunnel and socks to mixed, and added the rest.
  static List<String> protocolsFor({required bool v3}) => v3
      ? const [
          'vless', 'vmess', 'trojan', 'shadowsocks', 'hysteria', 'tuic', 'wireguard', //
          'amneziawg', 'mtproto', 'mixed', 'http', 'tunnel', 'tun',
        ]
      : const ['vless', 'vmess', 'trojan', 'shadowsocks', 'wireguard', 'socks', 'http', 'dokodemo-door'];

  static String protocolLabel(String p) => switch (p) {
        'vless' || 'vmess' || 'http' || 'tun' => p.toUpperCase(),
        'shadowsocks' => 'Shadowsocks',
        'hysteria' => 'Hysteria2',
        'tuic' => 'TUIC',
        'wireguard' => 'WireGuard',
        'amneziawg' => 'AmneziaWG',
        'mtproto' => 'MTProto',
        'mixed' => 'Mixed (SOCKS + HTTP)',
        'socks' => 'SOCKS',
        'tunnel' => 'Tunnel',
        'dokodemo-door' => 'Dokodemo-door',
        _ => p[0].toUpperCase() + p.substring(1),
      };

  /// No sniffing block in the panel form for these.
  static bool sniffingAllowed(String p) => p != 'mtproto' && p != 'amneziawg' && p != 'tuic';
  static const networks = ['tcp', 'ws', 'grpc', 'httpupgrade', 'xhttp', 'kcp'];
  static const xhttpModes = ['auto', 'packet-up', 'stream-up', 'stream-one'];
  static const fingerprints = [
    'chrome', 'firefox', 'safari', 'ios', 'android', 'edge', '360', 'qq', //
    'random', 'randomized', 'randomizednoalpn', 'unsafe',
  ];
  static const alpns = ['h3', 'h2', 'http/1.1'];
  static const sniffDest = ['http', 'tls', 'quic', 'fakedns'];
  static const ssMethods = [
    '2022-blake3-aes-128-gcm', '2022-blake3-aes-256-gcm', '2022-blake3-chacha20-poly1305', //
    'aes-256-gcm', 'aes-128-gcm', 'chacha20-poly1305', 'chacha20-ietf-poly1305', //
    'xchacha20-poly1305', 'xchacha20-ietf-poly1305',
  ];
  static const ssNetworks = ['tcp,udp', 'tcp', 'udp'];
  static const trafficResets = ['never', 'hourly', 'daily', 'weekly', 'monthly'];

  static int randomPort() => 10000 + Random.secure().nextInt(50000);

  static String randomShortId() {
    final r = Random.secure();
    final len = [2, 4, 6, 8, 10, 12, 14, 16][r.nextInt(8)];
    return List.generate(len, (_) => r.nextInt(16).toRadixString(16)).join();
  }

  static String ssPassword(String method) => method.startsWith('2022')
      ? randomBase64Key(method.contains('128') ? 16 : 32)
      : randomString(16);

  static Map<String, dynamic> newInbound({required bool v3}) => {
        'enable': true,
        'remark': '',
        'listen': '',
        'port': randomPort(),
        'protocol': 'vless',
        'expiryTime': 0,
        'total': 0,
        if (v3) 'trafficReset': 'never',
        if (v3) 'trafficResetDay': 1,
        'settings': settingsFor('vless'),
        'streamSettings': {
          'network': 'tcp',
          'security': 'none',
          'tcpSettings': transportFor('tcp'),
        },
        'sniffing': {
          'enabled': false,
          'destOverride': ['http', 'tls', 'quic', 'fakedns'],
          'metadataOnly': false,
          'routeOnly': false,
        },
      };

  static Map<String, dynamic> settingsFor(String protocol) => switch (protocol) {
        'vless' => {'clients': <dynamic>[], 'decryption': 'none', 'fallbacks': <dynamic>[]},
        'trojan' => {'clients': <dynamic>[], 'fallbacks': <dynamic>[]},
        'shadowsocks' => {
            'method': '2022-blake3-aes-256-gcm',
            'password': ssPassword('2022-blake3-aes-256-gcm'),
            'network': 'tcp,udp',
            'clients': <dynamic>[],
            'ivCheck': false,
          },
        'hysteria' => {'version': 2, 'clients': <dynamic>[]},
        'tuic' => {
            'server': {
              'certificate': '',
              'private_key': '',
              'congestion_control': 'bbr',
              'alpn': ['h3', 'spdy/3.1'],
              'udp_relay_mode': 'native',
              'zero_rtt_handshake': true,
              'log_level': 'info',
              'max_idle_time': 15,
              'authentication_timeout': 3,
              'max_udp_relay_packet_size': 1500,
              'sni': '',
            },
            'clients': <dynamic>[],
          },
        'wireguard' => {
            'mtu': 1420,
            'secretKey': randomWireguardKey(),
            'peers': <dynamic>[],
            'clients': <dynamic>[],
            'noKernelTun': false,
            'subnetIp': '10.0.0.0',
            'subnetCidr': 24,
          },
        // The panel generates the server block (keys + obfuscation) on save.
        'amneziawg' => {'clients': <dynamic>[]},
        'mtproto' => {'fakeTlsDomain': 'www.cloudflare.com', 'clients': <dynamic>[]},
        'mixed' || 'socks' => {
            'auth': 'password',
            'accounts': [
              {'user': randomString(8), 'pass': randomString(12)}
            ],
            'udp': false,
            'ip': '127.0.0.1',
          },
        'http' => {
            'accounts': [
              {'user': randomString(8), 'pass': randomString(12)}
            ],
            'allowTransparent': false,
          },
        'tunnel' => {'portMap': <String, dynamic>{}, 'allowedNetwork': 'tcp,udp', 'followRedirect': false},
        'dokodemo-door' => {'address': '', 'port': 0, 'network': 'tcp,udp', 'followRedirect': false},
        'tun' => {
            'name': 'xray0',
            'mtu': 1500,
            'gateway': <dynamic>[],
            'dns': <dynamic>[],
            'userLevel': 0,
            'autoSystemRoutingTable': <dynamic>[],
            'autoOutboundsInterface': 'auto',
          },
        _ => {'clients': <dynamic>[]},
      };

  /// streamSettings the panel form sets when this protocol is picked.
  static Map<String, dynamic> streamFor(String protocol, Map<String, dynamic> current) =>
      switch (protocol) {
        'hysteria' => {
            'network': 'hysteria',
            'security': 'tls',
            'hysteriaSettings': {'version': 2, 'auth': '', 'udpIdleTimeout': 60},
            'tlsSettings': tls()
              ..['alpn'] = ['h3']
              ..['settings'] = {'fingerprint': ''},
            'finalmask': {
              'tcp': <dynamic>[],
              'udp': [
                {
                  'type': 'salamander',
                  'settings': {'password': randomString(16)},
                }
              ],
            },
          },
        'wireguard' || 'tunnel' => {'security': 'none'},
        _ => current['network'] == null || current['network'] == 'hysteria'
            ? {'network': 'tcp', 'security': 'none', 'tcpSettings': transportFor('tcp')}
            : current,
      };

  static String settingsKey(String network) => '${network}Settings';

  static Map<String, dynamic> transportFor(String network) => switch (network) {
        'ws' => {
            'acceptProxyProtocol': false,
            'path': '/',
            'host': '',
            'headers': <String, dynamic>{},
            'heartbeatPeriod': 0,
          },
        'grpc' => {'serviceName': '', 'authority': '', 'multiMode': false},
        'httpupgrade' => {
            'acceptProxyProtocol': false,
            'path': '/',
            'host': '',
            'headers': <String, dynamic>{},
          },
        'xhttp' => {'path': '/', 'host': '', 'mode': 'auto', 'headers': <String, dynamic>{}},
        'kcp' => {
            'mtu': 1350,
            'tti': 20,
            'uplinkCapacity': 5,
            'downlinkCapacity': 20,
            'congestion': false,
            'readBufferSize': 1,
            'writeBufferSize': 1,
            'header': {'type': 'none'},
            'seed': randomString(10),
          },
        _ => {
            'acceptProxyProtocol': false,
            'header': {'type': 'none'},
          },
      };

  static Map<String, dynamic> tls() => {
        'serverName': '',
        'minVersion': '1.2',
        'maxVersion': '1.3',
        'cipherSuites': '',
        'rejectUnknownSni': false,
        'certificates': [
          {
            'certificateFile': '',
            'keyFile': '',
            'ocspStapling': 3600,
            'oneTimeLoading': false,
            'usage': 'encipherment',
            'buildChain': false,
          }
        ],
        'alpn': ['h2', 'http/1.1'],
        'settings': {'fingerprint': 'chrome'},
      };

  static Map<String, dynamic> reality({required bool v3}) => {
        'show': false,
        'xver': 0,
        v3 ? 'target' : 'dest': 'www.speedtest.net:443',
        'serverNames': ['www.speedtest.net'],
        'privateKey': '',
        'minClientVer': '',
        'maxClientVer': '',
        'maxTimediff': 0,
        'shortIds': [for (var i = 0; i < 4; i++) randomShortId()],
        'settings': {
          'publicKey': '',
          'fingerprint': 'chrome',
          'serverName': '',
          'spiderX': '/',
        },
      };

  /// Reality works with VLESS/Trojan over raw TCP, gRPC and XHTTP.
  static bool realityAllowed(String protocol, String network) =>
      (protocol == 'vless' || protocol == 'trojan') &&
      (network == 'tcp' || network == 'grpc' || network == 'xhttp');

  static bool tlsAllowed(String protocol) => protocols.contains(protocol);

  /// Switches the transport, dropping the old transport's settings block.
  static void setNetwork(Map<String, dynamic> stream, String network) {
    for (final n in networks) {
      if (n != network) stream.remove(settingsKey(n));
    }
    stream['network'] = network;
    stream[settingsKey(network)] ??= transportFor(network);
  }

  /// Switches security, adding the new block and removing the others.
  static void setSecurity(Map<String, dynamic> stream, String security, {required bool v3}) {
    stream['security'] = security;
    if (security != 'tls') stream.remove('tlsSettings');
    if (security != 'reality') stream.remove('realitySettings');
    if (security == 'tls') stream['tlsSettings'] ??= tls();
    if (security == 'reality') stream['realitySettings'] ??= reality(v3: v3);
  }

  /// Auto tag the panel uses: `inbound-PORT` or `inbound-LISTEN:PORT`.
  static String autoTag(Map<String, dynamic> inbound) {
    final listen = asStr(inbound['listen']) ?? '';
    final port = asInt(inbound['port']) ?? 0;
    return listen.isEmpty || listen == '0.0.0.0' ? 'inbound-$port' : 'inbound-$listen:$port';
  }

  static bool isAutoTag(String tag) => tag.isEmpty || RegExp(r'^inbound-').hasMatch(tag);
}
