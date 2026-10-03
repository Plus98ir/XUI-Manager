import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/panel_status_line.dart';
import '../widgets/soft.dart';
import 'panel_form_screen.dart';
import 'settings_screen.dart';
import 'web_panel_screen.dart';

class PanelsScreen extends StatefulWidget {
  const PanelsScreen({super.key});

  @override
  State<PanelsScreen> createState() => _PanelsScreenState();
}

class _PanelsScreenState extends State<PanelsScreen> {
  int _refreshToken = 0;

  Future<void> _refresh() async => setState(() => _refreshToken++);

  Future<void> _openForm([PanelConfig? panel]) async {
    await Navigator.push(
        context, MaterialPageRoute(builder: (_) => PanelFormScreen(panel: panel)));
    _refresh();
  }

  Future<void> _openPanel(PanelConfig p, {bool? web}) async {
    await Navigator.push(context, panelRoute(p, web: web));
    _refresh();
  }

  Future<void> _delete(PanelConfig p) async {
    final s = S.of(context);
    final state = context.read<AppState>();
    final ok = await confirmDialog(context,
        title: s.t('delete_panel_q'),
        message: '${p.name}\n${s.t('delete_panel_msg')}',
        action: s.t('delete'),
        danger: true);
    if (ok) await state.remove(p.id);
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = S.of(context);
    final panels = state.panels;
    final top = MediaQuery.paddingOf(context).top;

    final g = SoftColors.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: g.dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark,
      child: Scaffold(
        body: RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: EdgeInsets.zero,
            children: [
              HeroBackground(
                child: Padding(
                  padding: EdgeInsets.fromLTRB(20, top + 12, 20, 20),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Image.asset('assets/images/logo.png', height: 40),
                          const Spacer(),
                          GlassIconButton(
                            tooltip: s.t('settings'),
                            icon: Icons.tune_rounded,
                            onPressed: () => Navigator.push(context,
                                MaterialPageRoute(builder: (_) => const SettingsScreen())),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(s.t('app_name'),
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 4),
                      Text(
                        s.n('panels_count', ltr('${panels.length} / ${AppState.maxPanels}')),
                        style: TextStyle(color: g.muted),
                      ),
                    ],
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (panels.isEmpty)
                      Padding(
                        padding: const EdgeInsets.only(bottom: 20),
                        child: EmptyView(
                            icon: Icons.dns_outlined,
                            title: s.t('no_panels'),
                            subtitle: s.t('no_panels_hint')),
                      ),
                    for (final p in panels) ...[
                      _PanelCard(
                        panel: p,
                        refreshToken: _refreshToken,
                        onTap: () => _openPanel(p),
                        onOpenOther: () => _openPanel(p, web: !p.openWeb),
                        onEdit: () => _openForm(p),
                        onDelete: () => _delete(p),
                      ),
                      const SizedBox(height: 18),
                    ],
                    SoftBox(
                      radius: 22,
                      onTap: state.canAddPanel ? () => _openForm() : null,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          GradientIcon(Icons.add_circle_outline_rounded,
                              colors: state.canAddPanel ? g.accent : const [Colors.grey, Colors.grey],
                              size: 26),
                          const SizedBox(width: 10),
                          Text(
                            state.canAddPanel
                                ? s.t('add_panel')
                                : s.n('max_panels', AppState.maxPanels),
                            style: const TextStyle(fontWeight: FontWeight.w700),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _PanelCard extends StatelessWidget {
  const _PanelCard({
    required this.panel,
    required this.refreshToken,
    required this.onTap,
    required this.onOpenOther,
    required this.onEdit,
    required this.onDelete,
  });

  final PanelConfig panel;
  final int refreshToken;
  final VoidCallback onTap, onOpenOther, onEdit, onDelete;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final p = panel;
    return SoftBox(
      radius: 24,
      padding: const EdgeInsets.fromLTRB(14, 14, 4, 14),
      onTap: onTap,
      child: Row(
        children: [
          PanelTypeAvatar(type: p.type),
          const SizedBox(width: 14),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(p.name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: Theme.of(context)
                        .textTheme
                        .titleMedium
                        ?.copyWith(fontWeight: FontWeight.w800)),
                Text('${p.type.label} · ${p.host}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: SoftColors.of(context).muted, fontSize: 12)),
                PanelStatusLine(panel: p, refreshToken: refreshToken),
              ],
            ),
          ),
          IconButton(
            tooltip: p.openWeb ? s.t('app_view') : s.t('web_panel'),
            icon: Icon(p.openWeb ? Icons.space_dashboard_outlined : Icons.language_rounded),
            onPressed: onOpenOther,
          ),
          PopupMenuButton<String>(
            onSelected: (v) => switch (v) {
              'edit' => onEdit(),
              'other' => onOpenOther(),
              _ => onDelete(),
            },
            itemBuilder: (_) => [
              PopupMenuItem(
                  value: 'other', child: Text(p.openWeb ? s.t('app_view') : s.t('web_panel'))),
              PopupMenuItem(value: 'edit', child: Text(s.t('edit_panel'))),
              PopupMenuItem(value: 'delete', child: Text(s.t('delete'))),
            ],
          ),
        ],
      ),
    );
  }
}
