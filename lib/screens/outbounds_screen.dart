import 'package:flutter/material.dart';

import '../api/outbound_links.dart';
import '../api/panel_api.dart';
import '../l10n.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/json.dart';
import '../utils/xray_template.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';
import 'json_editor_screen.dart';
import 'xray_common.dart';

/// Lists and edits the outbounds of the panel's Xray template.
class OutboundsScreen extends StatefulWidget {
  const OutboundsScreen({super.key, required this.api});

  final PanelApi api;

  @override
  State<OutboundsScreen> createState() => _OutboundsScreenState();
}

class _OutboundsScreenState extends State<OutboundsScreen> with XrayTemplateEditor {
  @override
  PanelApi get api => widget.api;

  @override
  void initState() {
    super.initState();
    loadTemplate();
  }

  Future<void> _edit(int? index, Map<String, dynamic> initial) async {
    final s = S.of(context);
    final t = tpl!;
    final v = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => JsonEditorScreen(
          title: index == null ? s.t('add_outbound') : (asStr(initial['tag']) ?? s.t('outbounds')),
          initial: JsonEditorScreen.pretty(initial),
        ),
      ),
    );
    if (v is! Map) return;
    final o = Map<String, dynamic>.from(asMap(v));
    final oldTag = index == null ? null : asStr(t.outbounds[index]['tag']);
    o['tag'] = t.uniqueTag(asStr(o['tag']) ?? '', except: oldTag);
    change(() {
      if (index == null) {
        t.outbounds.add(o);
      } else {
        t.outbounds[index] = o;
        // Keep routing rules pointing at a renamed outbound.
        if (oldTag != null && oldTag != o['tag']) {
          for (final r in t.rules) {
            if (r['outboundTag'] == oldTag) r['outboundTag'] = o['tag'];
          }
        }
      }
    });
  }

  Future<void> _add() async {
    final s = S.of(context);
    final kind = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final (k, icon, label) in [
              ('link', Icons.link_rounded, s.t('out_from_link')),
              ('freedom', Icons.public_rounded, s.t('out_freedom')),
              ('blackhole', Icons.block_rounded, s.t('out_blackhole')),
              ('wireguard', Icons.vpn_lock_outlined, s.t('out_wireguard')),
              ('socks', Icons.lan_outlined, s.t('out_socks')),
              ('http', Icons.lan_outlined, s.t('out_http')),
            ])
              ListTile(
                leading: IconBadge(icon: icon, size: 36),
                title: Text(label),
                subtitle: k == 'link'
                    ? Text(s.t('out_from_link_hint'), textDirection: TextDirection.ltr)
                    : null,
                onTap: () => Navigator.pop(ctx, k),
              ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (kind == null || !mounted) return;
    if (kind == 'link') {
      final o = await _askLink();
      if (o != null) _edit(null, o);
    } else {
      _edit(null, outboundTemplate(kind));
    }
  }

  Future<Map<String, dynamic>?> _askLink() async {
    final s = S.of(context);
    final c = TextEditingController();
    String? error;
    final result = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setD) => AlertDialog(
          title: Text(s.t('out_from_link')),
          content: TextField(
            controller: c,
            autofocus: true,
            minLines: 2,
            maxLines: 5,
            textDirection: TextDirection.ltr,
            decoration: InputDecoration(
              hintText: s.t('out_from_link_hint'),
              errorText: error,
              errorMaxLines: 3,
            ),
          ),
          actions: [
            TextButton(onPressed: () => Navigator.pop(ctx), child: Text(s.t('cancel'))),
            FilledButton(
              onPressed: () {
                try {
                  Navigator.pop(ctx, outboundFromLink(c.text));
                } on FormatException catch (e) {
                  setD(() => error = e.message);
                } catch (e) {
                  setD(() => error = '$e');
                }
              },
              child: Text(s.t('apply')),
            ),
          ],
        ),
      ),
    );
    c.dispose();
    return result;
  }

  Future<void> _menu(int i, String action) async {
    final s = S.of(context);
    final t = tpl!;
    switch (action) {
      case 'edit':
        _edit(i, t.outbounds[i]);
      case 'default':
        change(() => t.outbounds.insert(0, t.outbounds.removeAt(i)));
      case 'up':
        change(() => t.outbounds.insert(i - 1, t.outbounds.removeAt(i)));
      case 'down':
        change(() => t.outbounds.insert(i + 1, t.outbounds.removeAt(i)));
      case 'delete':
        final tag = asStr(t.outbounds[i]['tag']) ?? '';
        final used = t.rulesUsing(tag);
        final ok = await confirmDialog(context,
            title: s.t('delete_outbound_q'),
            message: used > 0 ? '$tag\n${s.n('outbound_in_use', used)}' : tag,
            action: s.t('delete'),
            danger: true);
        if (ok) change(() => t.outbounds.removeAt(i));
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = tpl;
    final body = loadingBody() ??
        (t!.outbounds.isEmpty
            ? EmptyView(icon: Icons.call_split_rounded, title: s.t('no_outbounds'))
            : ListView.separated(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
                itemCount: t.outbounds.length,
                separatorBuilder: (_, __) => const SizedBox(height: 12),
                itemBuilder: (_, i) => _OutboundCard(
                  outbound: t.outbounds[i],
                  index: i,
                  count: t.outbounds.length,
                  rules: t.rulesUsing(asStr(t.outbounds[i]['tag']) ?? ''),
                  onTap: () => _menu(i, 'edit'),
                  onMenu: (a) => _menu(i, a),
                ),
              ));
    return PopScope(
      canPop: !dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await confirmLeave() && context.mounted) {
          setState(() => dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(
          title: Text(s.t('outbounds')),
          actions: [
            if (t != null)
              IconButton(
                  tooltip: s.t('add_outbound'),
                  icon: const Icon(Icons.add_rounded),
                  onPressed: _add),
          ],
        ),
        body: body,
        bottomNavigationBar: t == null ? null : saveBar(),
      ),
    );
  }
}

class _OutboundCard extends StatelessWidget {
  const _OutboundCard({
    required this.outbound,
    required this.index,
    required this.count,
    required this.rules,
    required this.onTap,
    required this.onMenu,
  });

  final Map<String, dynamic> outbound;
  final int index, count, rules;
  final VoidCallback onTap;
  final ValueChanged<String> onMenu;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final theme = Theme.of(context);
    final g = SoftColors.of(context);
    final protocol = asStr(outbound['protocol']) ?? '?';
    final net = asStr(asMap(outbound['streamSettings'])['network']);
    final sec = asStr(asMap(outbound['streamSettings'])['security']);
    final target = outboundTarget(outbound);
    final tags = [
      protocol,
      if (net != null && net.isNotEmpty) net,
      if (sec != null && sec.isNotEmpty && sec != 'none') sec,
      if (rules > 0) '${ltr('$rules')} ${s.t('rules')}',
    ];
    return SoftBox(
      radius: 20,
      depth: 3,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 0, 10),
      onTap: onTap,
      child: Row(
        children: [
          IconBadge(icon: protocolIcon(protocol), size: 40, filled: index == 0),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Flexible(
                      child: Text(asStr(outbound['tag']) ?? '-',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w800)),
                    ),
                    if (index == 0) ...[
                      const SizedBox(width: 6),
                      _Chip(s.t('default_out'), color: theme.colorScheme.primary),
                    ],
                  ],
                ),
                if (target != null)
                  Text(target,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      textDirection: TextDirection.ltr,
                      style: theme.textTheme.bodySmall?.copyWith(color: g.muted)),
                const SizedBox(height: 4),
                Wrap(
                  spacing: 6,
                  runSpacing: 4,
                  children: [for (final t in tags) _Chip(t)],
                ),
              ],
            ),
          ),
          PopupMenuButton<String>(
            onSelected: onMenu,
            itemBuilder: (_) => [
              PopupMenuItem(value: 'edit', child: Text(s.t('edit'))),
              if (index > 0) PopupMenuItem(value: 'default', child: Text(s.t('make_default'))),
              if (index > 0) PopupMenuItem(value: 'up', child: Text(s.t('move_up'))),
              if (index < count - 1) PopupMenuItem(value: 'down', child: Text(s.t('move_down'))),
              PopupMenuItem(
                  value: 'delete',
                  child: Text(s.t('delete'), style: const TextStyle(color: badColor))),
            ],
          ),
        ],
      ),
    );
  }
}

class _Chip extends StatelessWidget {
  const _Chip(this.text, {this.color});

  final String text;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    final c = color ?? SoftColors.of(context).muted;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 1),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Text(text,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color)),
    );
  }
}
