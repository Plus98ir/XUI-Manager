import 'package:flutter/material.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/json.dart';
import '../utils/xray_template.dart';
import '../widgets/common.dart';
import '../widgets/form_section.dart';
import '../widgets/soft.dart';
import 'json_editor_screen.dart';
import 'xray_common.dart';

const _strategies = ['AsIs', 'IPIfNonMatch', 'IPOnDemand'];

/// Routing rules of the panel's Xray template: reorder, add, edit, delete.
class RoutingScreen extends StatefulWidget {
  const RoutingScreen({super.key, required this.api});

  final PanelApi api;

  @override
  State<RoutingScreen> createState() => _RoutingScreenState();
}

class _RoutingScreenState extends State<RoutingScreen> with XrayTemplateEditor {
  @override
  PanelApi get api => widget.api;

  List<String> _inboundTags = const [];

  @override
  void initState() {
    super.initState();
    loadTemplate();
  }

  @override
  Future<void> onTemplateLoaded() async {
    try {
      final ibs = await api.inbounds();
      if (!mounted) return;
      setState(() => _inboundTags = {
            ...tpl?.inboundTags ?? const <String>[],
            for (final i in ibs)
              if (i.tag.isNotEmpty) i.tag,
          }.toList());
    } catch (_) {
      if (mounted) setState(() => _inboundTags = tpl?.inboundTags ?? const []);
    }
  }

  Future<void> _edit(int? index) async {
    final t = tpl!;
    final rule = await Navigator.push<Map<String, dynamic>>(
      context,
      MaterialPageRoute(
        builder: (_) => RuleFormScreen(
          rule: index == null ? null : t.rules[index],
          targets: [...t.outboundTags, ...t.balancerTags.map((b) => 'balancer:$b')],
          inboundTags: _inboundTags,
        ),
      ),
    );
    if (rule == null) return;
    change(() => index == null ? t.rules.add(rule) : t.rules[index] = rule);
  }

  Future<void> _delete(int i) async {
    final s = S.of(context);
    final ok = await confirmDialog(context,
        title: '${s.t('delete')}?',
        message: ruleSummary(tpl!.rules[i]).join('\n'),
        action: s.t('delete'),
        danger: true);
    if (ok) change(() => tpl!.rules.removeAt(i));
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final t = tpl;
    Widget? body = loadingBody();
    if (body == null) {
      final rules = t!.rules;
      final strategy = _strategies.contains(t.domainStrategy) ? t.domainStrategy : null;
      body = CustomScrollView(
        slivers: [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
            sliver: SliverToBoxAdapter(
              child: SoftBox(
                radius: 20,
                depth: 3,
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    DropdownButtonFormField<String>(
                      initialValue: strategy,
                      decoration: InputDecoration(labelText: s.t('domain_strategy')),
                      items: [
                        for (final v in _strategies) DropdownMenuItem(value: v, child: Text(v)),
                      ],
                      onChanged: (v) => change(() => t.domainStrategy = v ?? 'AsIs'),
                    ),
                    const SizedBox(height: 10),
                    Text(s.t('rule_order_hint'),
                        style: Theme.of(context)
                            .textTheme
                            .bodySmall
                            ?.copyWith(color: SoftColors.of(context).muted)),
                  ],
                ),
              ),
            ),
          ),
          if (rules.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: EmptyView(
                  icon: Icons.alt_route_rounded,
                  title: s.t('no_rules'),
                  subtitle: s.t('no_rules_hint')),
            )
          else
            SliverPadding(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
              sliver: SliverReorderableList(
                itemCount: rules.length,
                onReorderItem: (a, b) => change(() => rules.insert(b, rules.removeAt(a))),
                itemBuilder: (_, i) => ReorderableDelayedDragStartListener(
                  key: ObjectKey(rules[i]),
                  index: i,
                  child: Padding(
                    padding: const EdgeInsets.only(bottom: 12),
                    child: _RuleCard(
                      rule: rules[i],
                      index: i,
                      onTap: () => _edit(i),
                      onDelete: () => _delete(i),
                    ),
                  ),
                ),
              ),
            ),
        ],
      );
    }
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
          title: Text(s.t('routing')),
          actions: [
            if (t != null)
              IconButton(
                  tooltip: s.t('add_rule'),
                  icon: const Icon(Icons.add_rounded),
                  onPressed: () => _edit(null)),
          ],
        ),
        body: body,
        bottomNavigationBar: t == null ? null : saveBar(),
      ),
    );
  }
}

class _RuleCard extends StatelessWidget {
  const _RuleCard({
    required this.rule,
    required this.index,
    required this.onTap,
    required this.onDelete,
  });

  final Map<String, dynamic> rule;
  final int index;
  final VoidCallback onTap, onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final g = SoftColors.of(context);
    final target = asStr(rule['outboundTag']) ??
        (rule['balancerTag'] != null ? 'balancer:${rule['balancerTag']}' : '-');
    final lines = ruleSummary(rule);
    final blocked = target.contains('block');
    return SoftBox(
      radius: 20,
      depth: 3,
      padding: const EdgeInsetsDirectional.fromSTEB(12, 10, 0, 10),
      onTap: onTap,
      child: Row(
        children: [
          Container(
            width: 28,
            height: 28,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: theme.colorScheme.primary.withValues(alpha: 0.14),
            ),
            child: Text(ltr('${index + 1}'),
                style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.w800, color: theme.colorScheme.primary)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.arrow_forward_rounded,
                        size: 16, color: blocked ? badColor : theme.colorScheme.primary),
                    const SizedBox(width: 4),
                    Flexible(
                      child: Text(target,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.w800, color: blocked ? badColor : null)),
                    ),
                  ],
                ),
                const SizedBox(height: 2),
                for (final l in lines.isEmpty ? ['-'] : lines)
                  Directionality(
                    textDirection: TextDirection.ltr,
                    child: Text(l,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: theme.textTheme.bodySmall?.copyWith(color: g.muted)),
                  ),
              ],
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded),
            color: g.muted,
            onPressed: onDelete,
          ),
          Padding(
            padding: const EdgeInsetsDirectional.only(end: 8),
            child: Icon(Icons.drag_indicator_rounded, color: g.muted.withValues(alpha: 0.6)),
          ),
        ],
      ),
    );
  }
}

/// Add / edit one routing rule. Pops with the new rule map.
class RuleFormScreen extends StatefulWidget {
  const RuleFormScreen({
    super.key,
    this.rule,
    required this.targets,
    required this.inboundTags,
  });

  final Map<String, dynamic>? rule;

  /// Outbound tags, plus balancers as `balancer:TAG`.
  final List<String> targets;
  final List<String> inboundTags;

  @override
  State<RuleFormScreen> createState() => _RuleFormScreenState();
}

const _networks = ['tcp', 'udp'];
const _protocols = ['http', 'tls', 'quic', 'bittorrent'];

class _RuleFormScreenState extends State<RuleFormScreen> {
  late Map<String, dynamic> _base;
  String? _target;
  final _domain = TextEditingController();
  final _ip = TextEditingController();
  final _port = TextEditingController();
  final _sourcePort = TextEditingController();
  final _user = TextEditingController();
  final _networkSel = <String>{};
  final _protocolSel = <String>{};
  final _inboundSel = <String>{};

  static List<String> _items(dynamic v) {
    if (v == null) return const [];
    final list = v is List ? v.map((e) => '$e') : '$v'.split(',');
    return list.map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
  }

  @override
  void initState() {
    super.initState();
    _fill(widget.rule ?? {'type': 'field'});
  }

  void _fill(Map<String, dynamic> r) {
    _base = Map<String, dynamic>.from(r);
    _target = asStr(r['outboundTag']) ??
        (r['balancerTag'] != null ? 'balancer:${r['balancerTag']}' : null);
    _domain.text = _items(r['domain']).join('\n');
    _ip.text = _items(r['ip']).join('\n');
    _user.text = _items(r['user']).join('\n');
    _port.text = asStr(r['port']) ?? '';
    _sourcePort.text = asStr(r['sourcePort']) ?? '';
    _networkSel
      ..clear()
      ..addAll(_items(r['network']));
    _protocolSel
      ..clear()
      ..addAll(_items(r['protocol']));
    _inboundSel
      ..clear()
      ..addAll(_items(r['inboundTag']));
  }

  @override
  void dispose() {
    for (final c in [_domain, _ip, _port, _sourcePort, _user]) {
      c.dispose();
    }
    super.dispose();
  }

  static List<String> _lines(TextEditingController c) =>
      c.text.split(RegExp(r'[\n,]')).map((e) => e.trim()).where((e) => e.isNotEmpty).toList();

  Map<String, dynamic> _build() {
    final r = Map<String, dynamic>.from(_base)
      ..remove('outboundTag')
      ..remove('balancerTag');
    r['type'] = r['type'] ?? 'field';
    final t = _target ?? '';
    if (t.startsWith('balancer:')) {
      r['balancerTag'] = t.substring(9);
    } else if (t.isNotEmpty) {
      r['outboundTag'] = t;
    }
    void put(String k, Object? v) {
      final empty = v == null || (v is String && v.isEmpty) || (v is List && v.isEmpty);
      empty ? r.remove(k) : r[k] = v;
    }

    put('domain', _lines(_domain));
    put('ip', _lines(_ip));
    put('user', _lines(_user));
    put('port', _port.text.trim());
    put('sourcePort', _sourcePort.text.trim());
    put('network', _networkSel.join(','));
    put('protocol', _protocolSel.toList());
    put('inboundTag', _inboundSel.toList());
    return r;
  }

  void _submit() {
    final s = S.of(context);
    final r = _build();
    if (_target == null || _target!.isEmpty) {
      showSnack(context, s.t('rule_no_target'), error: true);
      return;
    }
    if (ruleSummary(r).isEmpty && r['attrs'] == null) {
      showSnack(context, s.t('rule_empty'), error: true);
      return;
    }
    Navigator.pop(context, r);
  }

  Future<void> _json() async {
    final s = S.of(context);
    final v = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => JsonEditorScreen(
            title: s.t('advanced_json'), initial: JsonEditorScreen.pretty(_build())),
      ),
    );
    if (v is Map) setState(() => _fill(Map<String, dynamic>.from(asMap(v))));
  }

  Widget _chips(List<String> options, Set<String> sel) => Wrap(
        spacing: 8,
        runSpacing: 6,
        children: [
          for (final o in {...options, ...sel})
            FilterChip(
              label: Text(o),
              selected: sel.contains(o),
              onSelected: (v) => setState(() => v ? sel.add(o) : sel.remove(o)),
            ),
        ],
      );

  Widget _label(String text) => Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 6),
        child: Text(text, style: const TextStyle(fontWeight: FontWeight.w600)),
      );

  Widget _field(String label, TextEditingController c, {String? hint, int lines = 1}) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _label(label),
            TextField(
              controller: c,
              minLines: lines,
              maxLines: lines == 1 ? 1 : 8,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: InputDecoration(hintText: hint, isDense: true),
            ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final targets = {...widget.targets, if (_target != null) _target!}.toList();
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.rule == null ? s.t('new_rule') : s.t('edit_rule')),
        actions: [
          IconButton(
              tooltip: s.t('advanced_json'),
              icon: const Icon(Icons.data_object_rounded),
              onPressed: _json),
        ],
      ),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 24),
        children: [
          FormSection(
            title: s.t('rule_target'),
            icon: Icons.call_split_rounded,
            children: [
              DropdownButtonFormField<String>(
                initialValue: _target,
                isExpanded: true,
                decoration: InputDecoration(labelText: s.t('rule_target')),
                items: [
                  for (final t in targets)
                    DropdownMenuItem(
                        value: t,
                        child: Text(t, maxLines: 1, overflow: TextOverflow.ellipsis)),
                ],
                onChanged: (v) => setState(() => _target = v),
              ),
            ],
          ),
          FormSection(
            title: s.t('rule_match'),
            icon: Icons.filter_alt_outlined,
            children: [
              Text(s.t('rule_match_hint'),
                  style: Theme.of(context)
                      .textTheme
                      .bodySmall
                      ?.copyWith(color: SoftColors.of(context).muted)),
              const SizedBox(height: 8),
              _field(s.t('rule_domain'), _domain, hint: s.t('rule_domain_hint'), lines: 3),
              _field(s.t('rule_ip'), _ip, hint: s.t('rule_ip_hint'), lines: 3),
              _field(s.t('rule_port'), _port, hint: '53,443,1000-2000'),
              _label(s.t('rule_network')),
              _chips(_networks, _networkSel),
              const SizedBox(height: 10),
              _label(s.t('rule_protocol')),
              _chips(_protocols, _protocolSel),
              const SizedBox(height: 10),
              if (widget.inboundTags.isNotEmpty || _inboundSel.isNotEmpty) ...[
                _label(s.t('rule_inbound')),
                _chips(widget.inboundTags, _inboundSel),
                const SizedBox(height: 10),
              ],
            ],
          ),
          FormSection(
            title: s.t('more_options'),
            icon: Icons.tune_rounded,
            initiallyExpanded: _sourcePort.text.isNotEmpty || _user.text.isNotEmpty,
            children: [
              _field(s.t('rule_source_port'), _sourcePort),
              _field(s.t('rule_user'), _user, lines: 2),
            ],
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _submit,
            icon: const Icon(Icons.check_rounded),
            label: Text(s.t('apply')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
        ),
      ),
    );
  }
}
