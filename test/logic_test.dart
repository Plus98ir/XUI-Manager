import 'package:flutter_test/flutter_test.dart';
import 'package:xui_manager/models/models.dart';
import 'package:xui_manager/utils/inbound_defaults.dart';
import 'package:xui_manager/utils/speed_tracker.dart';

PanelUser _u(int up, int down) =>
    PanelUser(key: 'a', name: 'a', enabled: true, status: UserStatus.active, up: up, down: down);

void main() {
  test('speed tracker: bytes since last change / elapsed, stale after timeout', () {
    final t = SpeedTracker(staleAfter: const Duration(seconds: 20));
    final t0 = DateTime(2026);
    expect(t.update([_u(0, 0)], t0), isEmpty);
    // Counters unchanged at 5s, then +10 MB down at 10s -> 1 MB/s.
    expect(t.update([_u(0, 0)], t0.add(const Duration(seconds: 5)))['a']!.active, isFalse);
    final s = t.update([_u(0, 10000000)], t0.add(const Duration(seconds: 10)))['a']!;
    expect(s.down, 1000000);
    expect(s.up, 0);
    // Kept while counters are between flushes, dropped when stale.
    expect(t.update([_u(0, 10000000)], t0.add(const Duration(seconds: 15)))['a']!.down, 1000000);
    expect(t.update([_u(0, 10000000)], t0.add(const Duration(seconds: 40)))['a']!.active, isFalse);
    // A reset counter never gives a negative speed.
    expect(t.update([_u(0, 0)], t0.add(const Duration(seconds: 45)))['a']!.down, 0);
  });

  test('inbound defaults: network and security switches keep one settings block', () {
    final inb = InboundDefaults.newInbound(v3: true);
    final stream = inb['streamSettings'] as Map<String, dynamic>;
    InboundDefaults.setNetwork(stream, 'ws');
    expect(stream.containsKey('tcpSettings'), isFalse);
    expect(stream['wsSettings'], isA<Map>());
    InboundDefaults.setSecurity(stream, 'reality', v3: true);
    expect((stream['realitySettings'] as Map)['target'], isNotNull);
    InboundDefaults.setSecurity(stream, 'tls', v3: true);
    expect(stream.containsKey('realitySettings'), isFalse);
    expect(stream['tlsSettings'], isA<Map>());
    expect(InboundDefaults.realityAllowed('vless', 'ws'), isFalse);
    expect(InboundDefaults.realityAllowed('vless', 'xhttp'), isTrue);
    expect(InboundDefaults.autoTag({'port': 443, 'listen': ''}), 'inbound-443');
    expect(InboundDefaults.reality(v3: false).containsKey('dest'), isTrue);
    expect(InboundDefaults.ssPassword('2022-blake3-aes-128-gcm').length, 24);
  });
}
