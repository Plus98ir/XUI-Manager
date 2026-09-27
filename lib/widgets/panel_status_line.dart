import 'package:flutter/material.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/format.dart';

/// One-line live status for a panel on the panel list (core, CPU, RAM,
/// online users). Reloads when [refreshToken] changes.
class PanelStatusLine extends StatefulWidget {
  const PanelStatusLine({super.key, required this.panel, required this.refreshToken});

  final PanelConfig panel;
  final int refreshToken;

  @override
  State<PanelStatusLine> createState() => _PanelStatusLineState();
}

class _PanelStatusLineState extends State<PanelStatusLine> {
  ServerStats? _stats;
  Object? _error;
  bool _loading = true;
  int _gen = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(PanelStatusLine old) {
    super.didUpdateWidget(old);
    if (old.refreshToken != widget.refreshToken ||
        old.panel.toJson().toString() != widget.panel.toJson().toString()) {
      _load();
    }
  }

  Future<void> _load() async {
    final gen = ++_gen;
    // Called from initState/didUpdateWidget, which rebuild anyway.
    _loading = true;
    final api = PanelApi.create(widget.panel);
    try {
      final st = await api.status();
      if (!mounted || gen != _gen) return;
      setState(() {
        _stats = st;
        _error = null;
        _loading = false;
      });
    } catch (e) {
      if (!mounted || gen != _gen) return;
      setState(() {
        _error = e;
        _loading = false;
      });
    } finally {
      api.dispose();
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final style = Theme.of(context).textTheme.bodySmall;
    if (_loading && _stats == null) {
      return const Padding(
        padding: EdgeInsets.only(top: 6),
        child: LinearProgressIndicator(minHeight: 2),
      );
    }
    if (_error != null) {
      return Padding(
        padding: const EdgeInsets.only(top: 4),
        child: Row(
          children: [
            const Icon(Icons.error_outline, size: 14, color: badColor),
            const SizedBox(width: 4),
            Expanded(
              child: Text('$_error',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: style?.copyWith(color: badColor)),
            ),
          ],
        ),
      );
    }
    final st = _stats!;
    final coreColor = st.coreState == null ? Colors.grey : (st.coreRunning ? okColor : badColor);
    final ram = st.memTotal != null && st.memTotal! > 0
        ? '${(st.memUsed! / st.memTotal! * 100).toStringAsFixed(0)}%'
        : '-';
    final parts = [
      '${s.t('cpu')} ${ltr('${st.cpu?.toStringAsFixed(0) ?? '-'}%')}',
      '${s.t('ram')} ${ltr(ram)}',
      if (st.onlineUsers != null) '${s.t('online')} ${ltr('${st.onlineUsers}')}',
      if (st.totalUsers != null) '${s.t('users')} ${ltr('${st.totalUsers}')}',
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.circle, size: 10, color: coreColor),
          const SizedBox(width: 6),
          Expanded(
            child: Text(parts.join('  ·  '),
                maxLines: 1, overflow: TextOverflow.ellipsis, style: style),
          ),
        ],
      ),
    );
  }
}
