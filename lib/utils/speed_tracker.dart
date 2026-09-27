import 'dart:math';

import '../models/models.dart';

class Speed {
  const Speed(this.up, this.down);

  static const zero = Speed(0, 0);

  final double up, down; // bytes per second

  bool get active => up > 0 || down > 0;
}

class _Snap {
  const _Snap(this.time, this.up, this.down, this.speed);
  final DateTime time; // when the counters last changed
  final int up, down;
  final Speed speed;
}

/// Live per-user speed from polled traffic counters, the same idea as the
/// panel's speed tag: bytes moved since the last change / seconds elapsed.
/// Panels only flush counters every few seconds, so the speed is kept until
/// the counters stop moving for [staleAfter].
class SpeedTracker {
  SpeedTracker({this.staleAfter = const Duration(seconds: 30)});

  final Duration staleAfter;
  final _last = <String, _Snap>{};

  Map<String, Speed> update(Iterable<PanelUser> users, DateTime now) {
    final out = <String, Speed>{};
    for (final u in users) {
      final prev = _last[u.key];
      if (prev == null) {
        _last[u.key] = _Snap(now, u.up, u.down, Speed.zero);
        continue;
      }
      if (u.up != prev.up || u.down != prev.down) {
        final dt = now.difference(prev.time).inMilliseconds / 1000;
        // A counter that went down was reset; count it as no traffic.
        final du = max(0, u.up - prev.up);
        final dd = max(0, u.down - prev.down);
        final speed = dt > 0 ? Speed(du / dt, dd / dt) : prev.speed;
        _last[u.key] = _Snap(now, u.up, u.down, speed);
        out[u.key] = speed;
      } else {
        out[u.key] = now.difference(prev.time) > staleAfter ? Speed.zero : prev.speed;
      }
    }
    return out;
  }
}
