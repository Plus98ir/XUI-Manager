import 'dart:async';

import 'package:flutter/material.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';

class DashboardTab extends StatefulWidget {
  const DashboardTab({super.key, required this.api, required this.active});

  final PanelApi api;
  final bool active;

  @override
  State<DashboardTab> createState() => _DashboardTabState();
}

class _DashboardTabState extends State<DashboardTab> {
  ServerStats? _stats;
  UserSummary? _summary;
  Object? _error;
  bool _busy = false;
  bool _restarting = false;
  int _tick = 0;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (widget.active && mounted && !_busy) _load(silent: true);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  Future<void> _load({bool silent = false}) async {
    _busy = true;
    try {
      final st = await widget.api.status();
      var summary = UserSummary.fromStats(st);
      // x-ui has no user counters in its status; count from the user list,
      // but not on every tick.
      if (summary == null) {
        summary = _summary;
        if (!silent || summary == null || _tick % 6 == 0) {
          summary = UserSummary.fromUsers(await widget.api.users());
        }
      }
      _tick++;
      if (!mounted) return;
      setState(() {
        _stats = st;
        _summary = summary;
        _error = null;
      });
    } catch (e) {
      if (!mounted) return;
      if (!silent || _stats == null) setState(() => _error = e);
    } finally {
      _busy = false;
    }
  }

  Future<void> _restart() async {
    final s = S.of(context);
    final ok = await confirmDialog(context,
        title: s.t('restart_core_q'),
        message: s.t('restart_core_msg'),
        action: s.t('restart_core'));
    if (!ok) return;
    setState(() => _restarting = true);
    try {
      await widget.api.restartCore();
      if (mounted) showSnack(context, s.t('done'));
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final st = _stats;
    if (st == null) {
      if (_error != null) {
        return ErrorView(
            message: '$_error',
            onRetry: () {
              setState(() => _error = null);
              _load();
            });
      }
      return const Center(child: CircularProgressIndicator());
    }

    double? frac(int? used, int? total) =>
        used == null || total == null || total == 0 ? null : used / total;

    final gauges = <Widget>[
      _Gauge(
        title: s.t('cpu'),
        value: st.cpu == null ? null : st.cpu! / 100,
        center: st.cpu == null ? '-' : '${st.cpu!.toStringAsFixed(1)}%',
        subtitle: st.cpuCores == null ? '' : '${st.cpuCores} ${s.t('cores')}',
      ),
      _Gauge(
        title: s.t('ram'),
        value: frac(st.memUsed, st.memTotal),
        subtitle: '${fmtBytes(st.memUsed)} / ${fmtBytes(st.memTotal)}',
      ),
      if (st.diskTotal != null && st.diskTotal! > 0)
        _Gauge(
          title: s.t('disk'),
          value: frac(st.diskUsed, st.diskTotal),
          subtitle: '${fmtBytes(st.diskUsed)} / ${fmtBytes(st.diskTotal)}',
        ),
      if (st.swapTotal != null && st.swapTotal! > 0)
        _Gauge(
          title: s.t('swap'),
          value: frac(st.swapUsed, st.swapTotal),
          subtitle: '${fmtBytes(st.swapUsed)} / ${fmtBytes(st.swapTotal)}',
        ),
    ];

    final info = <(IconData, String, String)>[
      if (st.uptime != null) (Icons.timer_outlined, s.t('uptime'), fmtUptime(st.uptime, s)),
      (Icons.arrow_upward_rounded, s.t('upload_speed'), fmtSpeed(st.netUpSpeed)),
      (Icons.arrow_downward_rounded, s.t('download_speed'), fmtSpeed(st.netDownSpeed)),
      (Icons.cloud_upload_outlined, s.t('total_sent'), fmtBytes(st.netSent)),
      (Icons.cloud_download_outlined, s.t('total_received'), fmtBytes(st.netRecv)),
      if (st.tcpCount != null)
        (Icons.swap_vert_rounded, s.t('connections'), '${st.tcpCount} / ${st.udpCount ?? 0}'),
      if (st.loads.isNotEmpty)
        (Icons.show_chart, s.t('load'), st.loads.map((e) => e.toStringAsFixed(2)).join('  ')),
      if (st.panelVersion != null) (Icons.info_outline, s.t('panel_version'), st.panelVersion!),
      if (st.ipv4 != null) (Icons.public, s.t('ipv4'), st.ipv4!),
      if (st.ipv6 != null) (Icons.public, s.t('ipv6'), st.ipv6!),
    ];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          _CoreCard(stats: st, restarting: _restarting, onRestart: _restart),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 1.05,
            children: gauges,
          ),
          if (_summary != null) ...[
            const SizedBox(height: 12),
            _SummaryCard(summary: _summary!),
          ],
          const SizedBox(height: 12),
          Card(
            child: Column(
              children: [
                for (final (icon, label, value) in info)
                  ListTile(
                    dense: true,
                    leading: Icon(icon, size: 20),
                    title: Text(label),
                    trailing: Directionality(
                      textDirection: TextDirection.ltr,
                      child: Text(value,
                          style: const TextStyle(fontWeight: FontWeight.w600)),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _CoreCard extends StatelessWidget {
  const _CoreCard({required this.stats, required this.restarting, required this.onRestart});

  final ServerStats stats;
  final bool restarting;
  final VoidCallback onRestart;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final running = stats.coreRunning;
    final color = stats.coreState == null ? Colors.grey : (running ? okColor : badColor);
    final error = stats.coreError ?? '';
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                CircleAvatar(
                  backgroundColor: color.withValues(alpha: 0.15),
                  foregroundColor: color,
                  child: const Icon(Icons.bolt),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Xray ${stats.coreVersion ?? ''}',
                          style: Theme.of(context).textTheme.titleMedium),
                      Text(
                        stats.coreState == null
                            ? '-'
                            : running
                                ? s.t('running')
                                : '${s.t('stopped')} (${stats.coreState})',
                        style: TextStyle(color: color, fontWeight: FontWeight.w600),
                      ),
                    ],
                  ),
                ),
                FilledButton.tonalIcon(
                  onPressed: restarting ? null : onRestart,
                  icon: restarting
                      ? const SizedBox.square(
                          dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.restart_alt),
                  label: Text(s.t('restart_core')),
                ),
              ],
            ),
            if (error.isNotEmpty) ...[
              const SizedBox(height: 8),
              Text(error, style: const TextStyle(color: badColor)),
            ],
          ],
        ),
      ),
    );
  }
}

class _Gauge extends StatelessWidget {
  const _Gauge({required this.title, required this.value, this.center, required this.subtitle});

  final String title;
  final double? value;
  final String? center;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final v = value?.clamp(0.0, 1.0).toDouble();
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(12),
        child: Column(
          children: [
            Text(title, style: theme.textTheme.titleSmall),
            Expanded(
              child: Center(
                child: SizedBox.square(
                  dimension: 76,
                  child: Stack(
                    fit: StackFit.expand,
                    children: [
                      CircularProgressIndicator(
                        value: v ?? 0,
                        strokeWidth: 8,
                        strokeCap: StrokeCap.round,
                        backgroundColor: theme.colorScheme.surfaceContainerHighest,
                        color: usageColor(v),
                      ),
                      Center(
                        child: Text(
                          center ?? (v == null ? '-' : '${(v * 100).toStringAsFixed(0)}%'),
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Text(subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                textDirection: TextDirection.ltr,
                style: theme.textTheme.bodySmall),
          ],
        ),
      ),
    );
  }
}

class _SummaryCard extends StatelessWidget {
  const _SummaryCard({required this.summary});

  final UserSummary summary;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final items = [
      (s.t('total'), summary.total, Theme.of(context).colorScheme.primary),
      (s.t('online'), summary.online, okColor),
      (s.status(UserStatus.active), summary.active, okColor),
      (s.status(UserStatus.disabled), summary.disabled, Colors.grey),
      (s.status(UserStatus.expired), summary.expired, badColor),
      (s.status(UserStatus.limited), summary.limited, warnColor),
      if (summary.onHold > 0) (s.status(UserStatus.onHold), summary.onHold, statusColor(UserStatus.onHold)),
    ];
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(s.t('users_summary'), style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 12),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                for (final (label, count, color) in items)
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    decoration: BoxDecoration(
                      color: color.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(12),
                    ),
                    child: Text('$label: $count',
                        style: TextStyle(color: color, fontWeight: FontWeight.w600)),
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
