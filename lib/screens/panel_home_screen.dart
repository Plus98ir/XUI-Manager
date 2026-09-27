import 'dart:async';
import 'dart:convert';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/panel_switcher.dart';
import '../widgets/soft.dart';
import 'dashboard_tab.dart';
import 'inbounds_tab.dart';
import 'outbounds_screen.dart';
import 'panel_settings_screen.dart';
import 'panel_form_screen.dart';
import 'routing_screen.dart';
import 'settings_screen.dart';
import 'user_form_screen.dart';
import 'users_tab.dart';

class PanelHomeScreen extends StatefulWidget {
  const PanelHomeScreen({super.key, required this.panelId});

  final String panelId;

  @override
  State<PanelHomeScreen> createState() => _PanelHomeScreenState();
}

class _PanelHomeScreenState extends State<PanelHomeScreen> {
  PanelApi? _api;
  String? _apiSignature;
  ServerStats? _stats;
  Object? _error;
  UserSummary? _summary;
  int? _inboundCount;
  bool _busy = false;
  bool _restarting = false;
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    _timer = Timer.periodic(const Duration(seconds: 5), (_) {
      if (mounted && !_busy && (ModalRoute.of(context)?.isCurrent ?? false)) _loadStats();
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    _api?.dispose();
    super.dispose();
  }

  /// (Re)creates the API client when the panel's settings change.
  PanelApi _ensureApi(PanelConfig cfg) {
    final sig = jsonEncode(cfg.toJson());
    if (_api == null || sig != _apiSignature) {
      _api?.dispose();
      _api = PanelApi.create(cfg);
      _apiSignature = sig;
      _stats = null;
      _error = null;
      _summary = null;
      _inboundCount = null;
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _refreshAll();
      });
    }
    return _api!;
  }

  Future<void> _loadStats() async {
    final api = _api;
    if (api == null) return;
    _busy = true;
    try {
      final st = await api.status();
      if (!mounted || api != _api) return;
      setState(() {
        _stats = st;
        _error = null;
        _summary = UserSummary.fromStats(st) ?? _summary;
      });
    } catch (e) {
      if (mounted && api == _api) setState(() => _error = e);
    } finally {
      _busy = false;
    }
  }

  Future<void> _loadCounts() async {
    final api = _api;
    if (api == null) return;
    try {
      UserSummary? summary;
      if (!api.isMarzban) summary = UserSummary.fromUsers(await api.users());
      final inbounds = await api.inbounds();
      if (!mounted || api != _api) return;
      setState(() {
        if (summary != null) _summary = summary;
        _inboundCount = inbounds.length;
      });
    } catch (_) {
      // Status errors are shown in the header; counts are optional.
    }
  }

  Future<void> _refreshAll() => Future.wait([_loadStats(), _loadCounts()]);

  Future<void> _push(Widget page) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => page));
    if (mounted) _refreshAll();
  }

  Future<void> _restart() async {
    final s = S.of(context);
    final api = _api;
    if (api == null) return;
    final ok = await confirmDialog(context,
        title: s.t('restart_core_q'), message: s.t('restart_core_msg'), action: s.t('restart_core'));
    if (!ok) return;
    setState(() => _restarting = true);
    try {
      await api.restartCore();
      if (mounted) showSnack(context, s.t('done'));
      await _loadStats();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _restarting = false);
    }
  }

  Future<void> _openSwitcher() async {
    final result = await showPanelSwitcher(context, currentId: widget.panelId);
    if (!mounted || result == null) return;
    switch (result) {
      case SwitchTo(:final panelId):
        if (panelId != widget.panelId) _switchTo(panelId);
      case EditPanel(:final panel):
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => PanelFormScreen(panel: panel)));
      case AddPanel():
        final id = await Navigator.push<String>(
            context, MaterialPageRoute(builder: (_) => const PanelFormScreen()));
        if (id != null && mounted) _switchTo(id);
    }
  }

  void _switchTo(String id) {
    Navigator.pushReplacement(
      context,
      PageRouteBuilder(
        pageBuilder: (_, __, ___) => GlassBackdrop(child: PanelHomeScreen(panelId: id)),
        transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final cfg = context.watch<AppState>().panelById(widget.panelId);
    if (cfg == null) {
      // Panel was deleted.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) Navigator.of(context).popUntil((r) => r.isFirst);
      });
      return const Scaffold();
    }
    final api = _ensureApi(cfg);
    final sum = _summary;
    final st = _stats;

    final primary = Theme.of(context).colorScheme.primary;
    final tiles = <Widget>[
      ActionTile(
        icon: Icons.insights_rounded,
        filled: true,
        label: s.t('server_status'),
        caption: st?.cpu == null ? null : 'CPU ${st!.cpu!.toStringAsFixed(0)}%',
        onTap: () => _push(_SubPage(
            title: s.t('server_status'), child: DashboardTab(api: api, active: true))),
      ),
      ActionTile(
        icon: Icons.people_outline_rounded,
        label: s.t('users'),
        caption: sum == null ? null : '${sum.total}',
        onTap: () => _push(_SubPage(title: s.t('users'), child: UsersTab(api: api))),
      ),
      ActionTile(
        icon: Icons.wifi_tethering_rounded,
        color: okColor,
        label: s.t('online'),
        caption: sum == null ? null : '${sum.online}',
        onTap: () => _push(_SubPage(
            title: s.t('online'), child: UsersTab(api: api, initialFilter: UserFilter.online))),
      ),
      ActionTile(
        icon: Icons.person_add_alt_rounded,
        label: s.t('add_user'),
        caption: s.t('new'),
        onTap: () => _push(UserFormScreen(api: api)),
      ),
      ActionTile(
        icon: Icons.hub_outlined,
        label: s.t('inbounds'),
        caption: _inboundCount == null ? null : '$_inboundCount',
        onTap: () =>
            _push(_SubPage(title: s.t('inbounds'), child: InboundsTab(api: api, active: true))),
      ),
      if (api.hasPanelSettings) ...[
        ActionTile(
          icon: Icons.call_split_rounded,
          label: s.t('outbounds'),
          caption: 'Xray',
          onTap: () => _push(OutboundsScreen(api: api)),
        ),
        ActionTile(
          icon: Icons.alt_route_rounded,
          label: s.t('routing'),
          caption: 'Xray',
          onTap: () => _push(RoutingScreen(api: api)),
        ),
      ],
      ActionTile(
        icon: Icons.hourglass_bottom_rounded,
        color: badColor,
        label: s.t('filter_expired'),
        caption: sum == null ? null : '${sum.expired}',
        onTap: () => _push(_SubPage(
            title: s.t('filter_expired'),
            child: UsersTab(api: api, initialFilter: UserFilter.expired))),
      ),
      ActionTile(
        icon: Icons.data_usage_rounded,
        color: warnColor,
        label: s.t('filter_limited'),
        caption: sum == null ? null : '${sum.limited}',
        onTap: () => _push(_SubPage(
            title: s.t('filter_limited'),
            child: UsersTab(api: api, initialFilter: UserFilter.limited))),
      ),
      if (api.hasPanelSettings) ...[
        ActionTile(
          icon: Icons.person_off_outlined,
          color: SoftColors.of(context).muted,
          label: s.t('filter_disabled'),
          caption: sum == null ? null : '${sum.disabled}',
          onTap: () => _push(_SubPage(
              title: s.t('filter_disabled'),
              child: UsersTab(api: api, initialFilter: UserFilter.disabled))),
        ),
        ActionTile(
          icon: Icons.settings_outlined,
          label: s.t('panel_settings'),
          caption: s.t('all_settings'),
          onTap: () => _push(PanelSettingsScreen(api: api)),
        ),
      ] else
        // Marzban has no settings page, so restart lives here.
        ActionTile(
          icon: Icons.restart_alt_rounded,
          color: primary,
          label: s.t('restart_xray'),
          caption: st?.coreState == null
              ? null
              : st!.coreRunning
                  ? s.t('running')
                  : s.t('stopped'),
          busy: _restarting,
          onTap: _restart,
        ),
      ActionTile(
        icon: Icons.edit_outlined,
        label: s.t('edit_panel'),
        caption: cfg.type.shortLabel,
        onTap: () => _push(PanelFormScreen(panel: cfg)),
      ),
    ];

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SoftColors.of(context).dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _refreshAll,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              _Header(
                panel: cfg,
                stats: st,
                error: _error,
                onSwitch: _openSwitcher,
                onSettings: () => _push(const SettingsScreen()),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 20),
                child: GridView.count(
                  crossAxisCount: 3,
                  shrinkWrap: true,
                  padding: EdgeInsets.zero,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: 12,
                  crossAxisSpacing: 12,
                  childAspectRatio: 1.0,
                  children: tiles,
                ),
              ),
            ],
          ),
        ),
        bottomNavigationBar: _BottomBar(
          onHome: () => Navigator.of(context).popUntil((r) => r.isFirst),
          onSwitch: _openSwitcher,
          onRefresh: _refreshAll,
        ),
      ),
    );
  }
}

class _Header extends StatelessWidget {
  const _Header({
    required this.panel,
    required this.stats,
    required this.error,
    required this.onSwitch,
    required this.onSettings,
  });

  final PanelConfig panel;
  final ServerStats? stats;
  final Object? error;
  final VoidCallback onSwitch;
  final VoidCallback onSettings;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final g = SoftColors.of(context);
    final on = Theme.of(context).colorScheme.onSurface;
    final top = MediaQuery.paddingOf(context).top;
    final st = stats;
    double? frac(int? a, int? b) => a == null || b == null || b == 0 ? null : a / b;
    final coreColor = st?.coreState == null
        ? g.muted
        : st!.coreRunning
            ? okColor
            : badColor;

    return Padding(
      padding: EdgeInsets.fromLTRB(16, top + 8, 16, 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              GlassIconButton(
                tooltip: s.t('settings'),
                icon: Icons.tune_rounded,
                onPressed: onSettings,
              ),
              const Spacer(),
              Image.asset('assets/images/logo.png', height: 30),
            ],
          ),
          const SizedBox(height: 12),
          SoftBox(
            radius: 26,
            padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: onSwitch,
                  child: Row(
                    children: [
                      PanelTypeAvatar(type: panel.type, size: 40),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(panel.name,
                                      maxLines: 1,
                                      overflow: TextOverflow.ellipsis,
                                      style: TextStyle(
                                          color: on, fontSize: 18, fontWeight: FontWeight.w800)),
                                ),
                                Icon(Icons.expand_more_rounded, color: g.muted),
                              ],
                            ),
                            Text('${panel.type.label} · ${panel.host}',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: TextStyle(color: g.muted, fontSize: 12)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 12),
                if (st == null && error != null)
                  Row(
                    children: [
                      const Icon(Icons.error_outline, color: badColor, size: 18),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text('$error',
                            maxLines: 3,
                            overflow: TextOverflow.ellipsis,
                            style: const TextStyle(color: badColor, fontSize: 12)),
                      ),
                    ],
                  )
                else if (st == null)
                  LinearProgressIndicator(minHeight: 2, color: g.accent.first)
                else ...[
                  Row(
                    children: [
                      Icon(Icons.circle, size: 9, color: coreColor),
                      const SizedBox(width: 6),
                      Expanded(
                        child: Text(
                          'Xray ${st.coreVersion ?? ''} · ${st.coreRunning ? s.t('running') : s.t('stopped')}',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(color: on, fontSize: 12),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        '↑ ${fmtSpeed(st.netUpSpeed)}  ↓ ${fmtSpeed(st.netDownSpeed)}',
                        textDirection: TextDirection.ltr,
                        style: TextStyle(color: g.muted, fontSize: 11),
                      ),
                    ],
                  ),
                  const SizedBox(height: 10),
                  Row(
                    children: [
                      Expanded(
                        child: MiniBar(
                            label: s.t('cpu'),
                            value: st.cpu == null ? null : st.cpu! / 100,
                            text: st.cpu == null ? '-' : '${st.cpu!.toStringAsFixed(0)}%'),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: MiniBar(
                            label: s.t('ram'),
                            value: frac(st.memUsed, st.memTotal),
                            text: _pct(frac(st.memUsed, st.memTotal))),
                      ),
                      if (st.diskTotal != null && st.diskTotal! > 0) ...[
                        const SizedBox(width: 12),
                        Expanded(
                          child: MiniBar(
                              label: s.t('disk'),
                              value: frac(st.diskUsed, st.diskTotal),
                              text: _pct(frac(st.diskUsed, st.diskTotal))),
                        ),
                      ],
                    ],
                  ),
                  if (st.uptime != null) ...[
                    const SizedBox(height: 8),
                    Text('${s.t('uptime')}: ${fmtUptime(st.uptime, s)}',
                        style: TextStyle(color: g.muted, fontSize: 12)),
                  ],
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }

  static String _pct(double? v) => v == null ? '-' : '${(v * 100).toStringAsFixed(0)}%';
}

class _BottomBar extends StatelessWidget {
  const _BottomBar({required this.onHome, required this.onSwitch, required this.onRefresh});

  final VoidCallback onHome;
  final VoidCallback onSwitch;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final g = SoftColors.of(context);
    return SafeArea(
      top: false,
      child: SizedBox(
        height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Positioned(
              left: 16,
              right: 16,
              bottom: 10,
              height: 58,
              child: ClipRRect(
                borderRadius: BorderRadius.circular(29),
                child: BackdropFilter(
                  filter: ImageFilter.blur(sigmaX: 18, sigmaY: 18),
                  child: Container(
                    decoration: BoxDecoration(
                      color: g.tile,
                      borderRadius: BorderRadius.circular(29),
                      border: Border.all(color: g.tileBorder),
                    ),
                    padding: const EdgeInsets.symmetric(horizontal: 14),
                    child: Row(
                      children: [
                        IconButton(
                            tooltip: s.t('all_panels'),
                            icon: const Icon(Icons.home_outlined),
                            onPressed: onHome),
                        const Spacer(),
                        IconButton(
                            tooltip: s.t('refresh'),
                            icon: const Icon(Icons.refresh_rounded),
                            onPressed: onRefresh),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            Positioned(
              bottom: 17,
              child: GestureDetector(
                onTap: onSwitch,
                child: Tooltip(
                  message: s.t('switch_panel'),
                  child: Container(
                    width: 50,
                    height: 50,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      gradient: LinearGradient(
                        colors: g.accent,
                        begin: Alignment.topLeft,
                        end: Alignment.bottomRight,
                      ),
                      boxShadow: [
                        BoxShadow(
                            color: g.accent.last.withValues(alpha: 0.45),
                            blurRadius: 16,
                            offset: const Offset(0, 6)),
                      ],
                    ),
                    child: const Icon(Icons.swap_horiz_rounded, color: Colors.white, size: 26),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Plain page wrapper for tabs opened from the tile grid.
class _SubPage extends StatelessWidget {
  const _SubPage({required this.title, required this.child});

  final String title;
  final Widget child;

  @override
  Widget build(BuildContext context) => Scaffold(
        appBar: AppBar(title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700))),
        body: child,
      );
}
