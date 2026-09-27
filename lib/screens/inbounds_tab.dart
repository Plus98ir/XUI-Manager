import 'package:flutter/material.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';
import 'inbound_form_screen.dart';

class InboundsTab extends StatefulWidget {
  const InboundsTab({super.key, required this.api, required this.active});

  final PanelApi api;
  final bool active;

  @override
  State<InboundsTab> createState() => _InboundsTabState();
}

class _InboundsTabState extends State<InboundsTab> {
  List<InboundInfo>? _list;
  Object? _error;
  bool _started = false;
  final Set<int> _busy = {};

  @override
  void initState() {
    super.initState();
    if (widget.active) _start();
  }

  @override
  void didUpdateWidget(InboundsTab oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.active && !_started) _start();
  }

  void _start() {
    _started = true;
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.api.inbounds();
      if (mounted) {
        setState(() {
          _list = list;
          _error = null;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  Future<void> _openForm([InboundInfo? ib]) async {
    final ok = await Navigator.push<bool>(
      context,
      MaterialPageRoute(builder: (_) => InboundFormScreen(api: widget.api, inboundId: ib?.id)),
    );
    if (ok == true) _load();
  }

  Future<void> _run(int id, Future<void> Function() op) async {
    final s = S.of(context);
    setState(() => _busy.add(id));
    try {
      await op();
      if (mounted) showSnack(context, s.t('done'));
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _busy.remove(id));
    }
  }

  Future<void> _menu(InboundInfo ib, String action) async {
    final s = S.of(context);
    final id = ib.id!;
    switch (action) {
      case 'edit':
        await _openForm(ib);
      case 'reset':
        if (await confirmDialog(context,
            title: s.t('reset_traffic'),
            message: '${ib.title}\n${s.t('reset_inbound_traffic_q')}',
            action: s.t('reset_traffic'))) {
          await _run(id, () => widget.api.resetInboundTraffic(id));
        }
      case 'delete':
        if (await confirmDialog(context,
            title: s.t('delete_inbound_q'),
            message: '${ib.title}\n${s.t('delete_inbound_msg')}',
            action: s.t('delete'),
            danger: true)) {
          await _run(id, () => widget.api.deleteInbound(id));
        }
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final list = _list;
    final manage = widget.api.canManageInbounds;
    Widget body;
    if (list == null) {
      body = _error != null
          ? ErrorView(
              message: '$_error',
              onRetry: () {
                setState(() => _error = null);
                _load();
              })
          : const Center(child: CircularProgressIndicator());
    } else {
      body = RefreshIndicator(
        onRefresh: _load,
        child: list.isEmpty
            ? ListView(children: [
                SizedBox(
                    height: 300,
                    child: EmptyView(icon: Icons.lan_outlined, title: s.t('no_inbounds_list'))),
              ])
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 96),
                itemCount: list.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) {
                  final ib = list[i];
                  return _InboundCard(
                    inbound: ib,
                    busy: _busy.contains(ib.id),
                    manage: manage && ib.id != null,
                    onTap: manage && ib.id != null ? () => _openForm(ib) : null,
                    onToggle: (v) => _run(ib.id!, () => widget.api.setInboundEnabled(ib.id!, v)),
                    onMenu: (a) => _menu(ib, a),
                  );
                },
              ),
      );
    }
    return Scaffold(
      backgroundColor: Colors.transparent,
      floatingActionButton: manage
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add),
              label: Text(s.t('add_inbound')),
            )
          : null,
      body: body,
    );
  }
}

class _InboundCard extends StatelessWidget {
  const _InboundCard({
    required this.inbound,
    required this.busy,
    required this.manage,
    required this.onTap,
    required this.onToggle,
    required this.onMenu,
  });

  final InboundInfo inbound;
  final bool busy;
  final bool manage;
  final VoidCallback? onTap;
  final ValueChanged<bool> onToggle;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final soft = SoftColors.of(context);
    final ib = inbound;
    final used = (ib.up ?? 0) + (ib.down ?? 0);
    final tags = <String>[
      if (ib.port != null) '${s.t('port')} ${ltr('${ib.port}')}',
      if ((ib.network ?? '').isNotEmpty) ib.network!.toUpperCase(),
      if ((ib.security ?? '').isNotEmpty && ib.security != 'none') ib.security!.toUpperCase(),
      if (ib.up != null)
        ltr((ib.total ?? 0) > 0 ? '${fmtBytes(used)} / ${fmtBytes(ib.total)}' : fmtBytes(used)),
      if (ib.clientCount != null) '${ltr('${ib.clientCount}')} ${s.t('clients')}',
    ];
    return SoftBox(
      radius: 22,
      depth: 5,
      padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 4, 12),
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              IconBadge(
                icon: Icons.hub_outlined,
                size: 40,
                color: ib.enabled ? null : soft.muted,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(ib.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    Text(
                      ib.protocol.toUpperCase(),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(color: soft.muted),
                    ),
                  ],
                ),
              ),
              if (busy)
                const Padding(
                  padding: EdgeInsets.all(12),
                  child: SizedBox.square(dimension: 20, child: CircularProgressIndicator(strokeWidth: 2)),
                )
              else if (manage) ...[
                Switch(value: ib.enabled, onChanged: onToggle),
                PopupMenuButton<String>(
                  onSelected: onMenu,
                  itemBuilder: (_) => [
                    PopupMenuItem(value: 'edit', child: Text(s.t('edit'))),
                    PopupMenuItem(value: 'reset', child: Text(s.t('reset_traffic'))),
                    PopupMenuItem(
                        value: 'delete',
                        child: Text(s.t('delete'), style: const TextStyle(color: badColor))),
                  ],
                ),
              ] else
                Padding(
                  padding: const EdgeInsets.all(12),
                  child: Icon(ib.enabled ? Icons.check_circle : Icons.pause_circle,
                      color: ib.enabled ? okColor : Colors.grey),
                ),
            ],
          ),
          if (tags.isNotEmpty) ...[
            const SizedBox(height: 10),
            Padding(
              padding: const EdgeInsetsDirectional.only(end: 10),
              child: Wrap(
                spacing: 6,
                runSpacing: 6,
                children: [for (final tag in tags) _Tag(tag)],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _Tag extends StatelessWidget {
  const _Tag(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.10),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Text(text, style: Theme.of(context).textTheme.labelSmall),
      );
}
