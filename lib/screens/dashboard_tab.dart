import 'dart:async';

import 'package:flutter/material.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/live_chart.dart';
import '../widgets/soft.dart';

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
  bool _showIp = false;
  final _cpu = Series(), _ram = Series(), _swap = Series(), _disk = Series();
  final _up = Series(), _down = Series(), _tcp = Series(), _udp = Series();

  void _record(ServerStats st) {
    double? pct(int? a, int? b) => a == null || b == null || b == 0 ? null : a * 100 / b;
    _cpu.add(st.cpu);
    _ram.add(pct(st.memUsed, st.memTotal));
    _swap.add(pct(st.swapUsed, st.swapTotal) ?? 0);
    _disk.add(pct(st.diskUsed, st.diskTotal));
    _up.add(st.netUpSpeed?.toDouble());
    _down.add(st.netDownSpeed?.toDouble());
    _tcp.add(st.tcpCount?.toDouble());
    _udp.add(st.udpCount?.toDouble());
  }

  @override
  void initState() {
    super.initState();
    _load();
    _timer = Timer.periodic(const Duration(seconds: 2), (_) {
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
        if (!silent || summary == null || _tick % 15 == 0) {
          summary = UserSummary.fromUsers(await widget.api.users());
        }
      }
      _tick++;
      if (!mounted) return;
      setState(() {
        _record(st);
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

    double? pct(int? used, int? total) =>
        used == null || total == null || total == 0 ? null : used * 100 / total;
    final g = SoftColors.of(context);
    final up = g.accent.last;
    const down = Color(0xFF22D3EE);

    final metrics = <Widget>[
      _MetricCard(
        icon: Icons.memory_rounded,
        title: s.t('cpu'),
        value: st.cpu,
        sub: [
          if (st.cpuCores != null) '${ltr('${st.cpuCores}')} ${s.t('cores')}',
          if (st.logicalCores != null && st.logicalCores != st.cpuCores) ltr('${st.logicalCores}T'),
          if (st.cpuMhz != null && st.cpuMhz! > 0) ltr('${(st.cpuMhz! / 1000).toStringAsFixed(2)} GHz'),
        ].join(' · '),
        series: _cpu,
        color: g.accent.first,
      ),
      _MetricCard(
        icon: Icons.storage_rounded,
        title: s.t('ram'),
        value: pct(st.memUsed, st.memTotal),
        sub: ltr('${fmtBytes(st.memUsed)} / ${fmtBytes(st.memTotal)}'),
        series: _ram,
        color: warnColor,
      ),
      _MetricCard(
        icon: Icons.swap_horiz_rounded,
        title: s.t('swap'),
        value: pct(st.swapUsed, st.swapTotal) ?? 0,
        sub: ltr('${fmtBytes(st.swapUsed ?? 0)} / ${fmtBytes(st.swapTotal ?? 0)}'),
        series: _swap,
        color: g.accent.last,
      ),
      _MetricCard(
        icon: Icons.sd_storage_outlined,
        title: s.t('disk'),
        value: pct(st.diskUsed, st.diskTotal),
        sub: ltr('${fmtBytes(st.diskUsed)} / ${fmtBytes(st.diskTotal)}'),
        series: _disk,
        color: down,
      ),
    ];

    final ips = [if (st.ipv4 != null) st.ipv4!, if (st.ipv6 != null) st.ipv6!];

    return RefreshIndicator(
      onRefresh: _load,
      child: ListView(
        padding: const EdgeInsets.fromLTRB(14, 8, 14, 24),
        children: [
          _CoreCard(stats: st, restarting: _restarting, onRestart: _restart),
          const SizedBox(height: 12),
          GridView.count(
            crossAxisCount: 2,
            shrinkWrap: true,
            padding: EdgeInsets.zero,
            physics: const NeverScrollableScrollPhysics(),
            mainAxisSpacing: 12,
            crossAxisSpacing: 12,
            childAspectRatio: 0.98,
            children: metrics,
          ),
          const SizedBox(height: 12),
          // Network speed, both directions on one chart.
          _Panel(
            icon: Icons.speed_rounded,
            title: s.t('overall_speed'),
            trailing: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                _Legend(color: up, text: '↑ ${fmtSpeed(st.netUpSpeed)}'),
                _Legend(color: down, text: '↓ ${fmtSpeed(st.netDownSpeed)}'),
              ],
            ),
            children: [
              LiveChart(
                height: 110,
                lines: [ChartLine(_down.values, down), ChartLine(_up.values, up)],
              ),
              const SizedBox(height: 10),
              _Stats(items: [
                (s.t('total_sent'), fmtBytes(st.netSent)),
                (s.t('total_received'), fmtBytes(st.netRecv)),
                (s.t('peak'), fmtSpeed((_up.peak + _down.peak).round())),
              ]),
            ],
          ),
          if (st.tcpCount != null) ...[
            const SizedBox(height: 12),
            _Panel(
              icon: Icons.hub_outlined,
              title: s.t('open_sockets'),
              trailing: Text(ltr('${(st.tcpCount ?? 0) + (st.udpCount ?? 0)}'),
                  style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
              children: [
                LiveChart(
                  height: 80,
                  lines: [ChartLine(_tcp.values, up), ChartLine(_udp.values, down, fill: false)],
                ),
                const SizedBox(height: 8),
                Row(
                  children: [
                    _Legend(color: up, text: 'TCP ${st.tcpCount}'),
                    const SizedBox(width: 16),
                    _Legend(color: down, text: 'UDP ${st.udpCount ?? 0}'),
                  ],
                ),
              ],
            ),
          ],
          const SizedBox(height: 12),
          _Panel(
            icon: Icons.timer_outlined,
            title: s.t('uptime'),
            children: [
              _Stats(items: [
                if (st.uptime != null) (s.t('os'), fmtUptime(st.uptime, s)),
                if (st.appUptime != null) (s.t('panel'), fmtUptime(st.appUptime, s)),
                if (st.loads.isNotEmpty)
                  (s.t('load'), st.loads.map((e) => e.toStringAsFixed(2)).join(' ')),
              ]),
              if (st.appMem != null || st.panelVersion != null) ...[
                const Divider(height: 22),
                _Stats(items: [
                  if (st.panelVersion != null) (s.t('panel_version'), st.panelVersion!),
                  if (st.appMem != null) (s.t('panel_ram'), fmtBytes(st.appMem)),
                  if (st.appThreads != null) (s.t('threads'), '${st.appThreads}'),
                ]),
              ],
              if (ips.isNotEmpty) ...[
                const Divider(height: 22),
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(s.t('ip_addresses'),
                              style: Theme.of(context).textTheme.labelSmall?.copyWith(color: g.muted)),
                          for (final ip in ips)
                            Directionality(
                              textDirection: TextDirection.ltr,
                              child: Text(_showIp ? ip : ip.replaceAll(RegExp(r'[0-9a-fA-F]'), '•'),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: const TextStyle(fontWeight: FontWeight.w600)),
                            ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(_showIp ? Icons.visibility_off_outlined : Icons.visibility_outlined),
                      onPressed: () => setState(() => _showIp = !_showIp),
                    ),
                  ],
                ),
              ],
            ],
          ),
          if (_summary != null) ...[
            const SizedBox(height: 12),
            _SummaryCard(summary: _summary!),
          ],
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

/// Glass panel with an uppercase-style header row.
class _Panel extends StatelessWidget {
  const _Panel({required this.icon, required this.title, required this.children, this.trailing});

  final IconData icon;
  final String title;
  final Widget? trailing;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final g = SoftColors.of(context);
    return SoftBox(
      radius: 22,
      depth: 3,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Icon(icon, size: 16, color: Theme.of(context).colorScheme.primary),
              const SizedBox(width: 6),
              Expanded(
                child: Text(title,
                    style: Theme.of(context)
                        .textTheme
                        .labelMedium
                        ?.copyWith(color: g.muted, fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              ),
              if (trailing != null) trailing!,
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }
}

/// One resource: big percentage, detail line, live chart, avg / peak.
class _MetricCard extends StatelessWidget {
  const _MetricCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.sub,
    required this.series,
    required this.color,
  });

  final IconData icon;
  final String title;
  final double? value;
  final String sub;
  final Series series;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final g = SoftColors.of(context);
    final small = Theme.of(context).textTheme.labelSmall?.copyWith(color: g.muted);
    return SoftBox(
      radius: 22,
      depth: 3,
      padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Icon(icon, size: 15, color: color),
              const SizedBox(width: 5),
              Expanded(
                child: Text(title,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: small?.copyWith(fontWeight: FontWeight.w700, letterSpacing: 0.4)),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Directionality(
            textDirection: TextDirection.ltr,
            child: Text.rich(
              TextSpan(children: [
                TextSpan(
                    text: value == null ? '-' : value!.toStringAsFixed(1),
                    style: const TextStyle(fontSize: 24, fontWeight: FontWeight.w800, height: 1.2)),
                TextSpan(text: ' %', style: small),
              ]),
            ),
          ),
          Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: small),
          const Spacer(),
          LiveChart(
            height: 40,
            maxY: 100,
            grid: false,
            avg: series.values.length > 1 ? series.avg : null,
            lines: [ChartLine(series.values, color)],
          ),
          const SizedBox(height: 4),
          Row(
            children: [
              Text('${s.t('avg')} ${ltr('${series.avg.toStringAsFixed(0)}%')}', style: small),
              const Spacer(),
              Text('${s.t('peak')} ${ltr('${series.peak.toStringAsFixed(0)}%')}', style: small),
            ],
          ),
        ],
      ),
    );
  }
}

class _Legend extends StatelessWidget {
  const _Legend({required this.color, required this.text});

  final Color color;
  final String text;

  @override
  Widget build(BuildContext context) => Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 10, height: 3, color: color),
          const SizedBox(width: 6),
          Text(text,
              textDirection: TextDirection.ltr,
              style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w700)),
        ],
      );
}

/// Row of label / value pairs split by thin dividers.
class _Stats extends StatelessWidget {
  const _Stats({required this.items});

  final List<(String, String)> items;

  @override
  Widget build(BuildContext context) {
    final g = SoftColors.of(context);
    final theme = Theme.of(context);
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          for (final (i, (label, value)) in items.indexed) ...[
            if (i > 0) VerticalDivider(width: 18, color: g.tileBorder),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.labelSmall?.copyWith(color: g.muted)),
                  FittedBox(
                    fit: BoxFit.scaleDown,
                    alignment: AlignmentDirectional.centerStart,
                    child: Text(value,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 15)),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}
