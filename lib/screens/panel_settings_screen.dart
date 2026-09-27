import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/panel_api.dart';
import '../models/models.dart';
import '../l10n.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/form_section.dart';
import '../widgets/soft.dart';
import 'json_editor_screen.dart';
import 'xray_common.dart';

/// Every panel setting (/setting/all), grouped like the panel's own
/// settings page, with search. Saved back in one call like the panel does.
class PanelSettingsScreen extends StatefulWidget {
  const PanelSettingsScreen({super.key, required this.api});

  final PanelApi api;

  @override
  State<PanelSettingsScreen> createState() => _PanelSettingsScreenState();
}

class _Group {
  const _Group(this.id, this.icon, this.match);
  final String id;
  final IconData icon;
  final bool Function(String key) match;
}

// Match order: first match wins.
final _groups = <_Group>[
  _Group('grp_happ', Icons.phone_iphone, (k) => k.startsWith('subHapp') || k == 'happLinkEnable'),
  _Group('grp_sub_json', Icons.data_object, (k) => k.startsWith('subJson')),
  _Group('grp_sub_clash', Icons.alt_route, (k) => k.startsWith('subClash')),
  _Group('grp_sub', Icons.link, (k) => k.startsWith('sub')),
  _Group('grp_telegram', Icons.telegram, (k) => k.startsWith('tg')),
  _Group('grp_discord', Icons.forum_outlined, (k) => k.startsWith('discord')),
  _Group('grp_email', Icons.mail_outline, (k) => k.startsWith('smtp')),
  _Group('grp_ldap', Icons.account_tree_outlined, (k) => k.startsWith('ldap')),
  _Group('grp_security', Icons.security, (k) => k.startsWith('twoFactor')),
  _Group('grp_panel', Icons.dashboard_customize_outlined, (k) => true),
];

// Display order: the main panel group first.
List<_Group> get _displayOrder => [
      _groups.last,
      ..._groups.where((g) => g.id == 'grp_security'),
      ..._groups.where((g) => g.id == 'grp_sub'),
      ..._groups.where((g) => !{'grp_panel', 'grp_security', 'grp_sub'}.contains(g.id)),
    ];

// Secrets come back blank; leaving them blank keeps the stored value.
const _secrets = {'tgBotToken', 'smtpPassword', 'discordBotToken', 'ldapPassword', 'twoFactorToken'};
// Changing these needs the current 2FA code, so they are shown read-only.
const _readOnly = {'twoFactorEnable', 'twoFactorToken'};

bool _multiline(String k) => RegExp(
        r'(Rules|Template|Announce|Dns|Mux|Observatory|FinalMask|List|Routes|CIDRs|Allowlist|Events|Candidates|TruthyValues|InboundTags|Regex)$')
    .hasMatch(k);

/// "tgBotChatId" -> "Tg Bot Chat Id".
String _humanize(String key) {
  final words = key
      .replaceAllMapped(RegExp(r'([a-z0-9])([A-Z])'), (m) => '${m[1]} ${m[2]}')
      .replaceAllMapped(RegExp(r'([A-Z]+)([A-Z][a-z])'), (m) => '${m[1]} ${m[2]}');
  return words.isEmpty ? key : words[0].toUpperCase() + words.substring(1);
}

class _PanelSettingsScreenState extends State<PanelSettingsScreen> {
  Map<String, dynamic>? _settings;
  Object? _error;
  bool _saving = false;
  bool _dirty = false;
  String _q = '';
  int _rev = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _error = null);
    try {
      final m = await widget.api.panelSettings();
      if (mounted) {
        setState(() {
          _settings = m;
          _dirty = false;
          _rev++;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _error = e);
    }
  }

  void _set(String k, dynamic v) {
    _settings![k] = v;
    if (!_dirty) setState(() => _dirty = true);
  }

  Future<void> _save() async {
    final s = S.of(context);
    setState(() => _saving = true);
    try {
      final body = Map<String, dynamic>.from(_settings!)
        ..removeWhere((k, _) => k.startsWith('has'));
      await widget.api.savePanelSettings(body);
      if (!mounted) return;
      showSnack(context, s.t('settings_saved'));
      await _load();
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _restartPanel() async {
    final s = S.of(context);
    final ok = await confirmDialog(context,
        title: s.t('restart_panel_q'), message: s.t('restart_panel_msg'), action: s.t('restart_panel'));
    if (!ok) return;
    try {
      await widget.api.restartPanel();
      if (mounted) showSnack(context, s.t('done'));
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    }
  }

  String _label(S s, String key) {
    final t = s.t('set_$key');
    return t == 'set_$key' ? _humanize(key) : t;
  }

  Widget _keyText(String key) => Directionality(
        textDirection: TextDirection.ltr,
        child: Text(key,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: Theme.of(context)
                .textTheme
                .labelSmall
                ?.copyWith(color: SoftColors.of(context).muted)),
      );

  Widget _field(S s, String key, dynamic value) {
    final label = _label(s, key);
    final readOnly = _readOnly.contains(key);
    if (value is bool) {
      return Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: Material(
          color: Theme.of(context).inputDecorationTheme.fillColor,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(
                color: Theme.of(context).inputDecorationTheme.enabledBorder!.borderSide.color),
          ),
          child: SwitchListTile(
            contentPadding: const EdgeInsetsDirectional.only(start: 14, end: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
            title: Text(label, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
            subtitle: _keyText(key),
            value: value,
            onChanged: readOnly ? null : (v) => setState(() => _set(key, v)),
          ),
        ),
      );
    }
    final isInt = value is int;
    final secret = _secrets.contains(key);
    final hasSecret = _settings!['has${key[0].toUpperCase()}${key.substring(1)}'] == true;
    // Label sits above a clearly framed box, so empty fields still look
    // like something to fill in.
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.only(start: 4, bottom: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(label,
                      maxLines: 2,
                      style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 14)),
                ),
                const SizedBox(width: 8),
                Flexible(child: _keyText(key)),
              ],
            ),
          ),
          TextFormField(
            key: ValueKey('$key#$_rev'),
            initialValue: value?.toString() ?? '',
            enabled: !readOnly,
            obscureText: secret,
            textDirection: TextDirection.ltr,
            autocorrect: false,
            keyboardType: isInt ? TextInputType.number : null,
            inputFormatters: isInt ? [FilteringTextInputFormatter.allow(RegExp(r'[-0-9]'))] : null,
            maxLines: secret ? 1 : (_multiline(key) ? 4 : 1),
            minLines: 1,
            decoration: InputDecoration(
              isDense: true,
              hintText: secret && hasSecret ? s.t('secret_keep') : s.t('field_empty'),
            ),
            onChanged: (v) => _set(key, isInt ? (int.tryParse(v) ?? 0) : v),
          ),
        ],
      ),
    );
  }

  bool _loadingXray = false;

  Future<void> _openXray() async {
    final s = S.of(context);
    setState(() => _loadingXray = true);
    try {
      final json = await widget.api.xrayConfig();
      if (!mounted) return;
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => JsonEditorScreen(
            title: s.t('xray_config'),
            initial: json,
            help: s.t('xray_config_help'),
            onSave: widget.api.saveXrayConfig,
          ),
        ),
      );
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _loadingXray = false);
    }
  }

  Widget _actions(S s) => Padding(
        padding: const EdgeInsets.only(top: 12),
        child: SizedBox(
          height: 104,
          child: Row(
            children: [
              Expanded(
                child: ActionTile(
                  icon: Icons.data_object_rounded,
                  label: s.t('xray_config'),
                  caption: 'JSON',
                  busy: _loadingXray,
                  onTap: _openXray,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionTile(
                  icon: Icons.restart_alt_rounded,
                  label: s.t('restart_xray'),
                  caption: 'Xray',
                  onTap: () => restartXray(context, widget.api),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: ActionTile(
                  icon: Icons.power_settings_new_rounded,
                  color: badColor,
                  label: s.t('restart_panel'),
                  caption: widget.api.config.type.shortLabel,
                  onTap: _restartPanel,
                ),
              ),
            ],
          ),
        ),
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final st = _settings;
    Widget body;
    if (st == null) {
      body = _error != null
          ? ErrorView(message: '$_error', onRetry: _load)
          : const Center(child: CircularProgressIndicator());
    } else {
      final grouped = <String, List<String>>{};
      for (final k in st.keys) {
        if (k.startsWith('has')) continue;
        final v = st[k];
        if (v is! bool && v is! num && v is! String && v != null) continue;
        if (_q.isNotEmpty &&
            !k.toLowerCase().contains(_q) &&
            !_label(s, k).toLowerCase().contains(_q)) {
          continue;
        }
        final g = _groups.firstWhere((g) => g.match(k));
        grouped.putIfAbsent(g.id, () => []).add(k);
      }
      body = ListView(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
        children: [
          _actions(s),
          const SizedBox(height: 12),
          TextField(
            decoration: InputDecoration(
              isDense: true,
              prefixIcon: const Icon(Icons.search),
              hintText: s.t('search_settings'),
            ),
            onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
          ),
          for (final g in _displayOrder)
            if (grouped[g.id] != null)
              FormSection(
                key: ValueKey('${g.id}#${_q.isNotEmpty}'),
                title: s.t(g.id),
                badge: '${grouped[g.id]!.length}',
                icon: g.icon,
                initiallyExpanded: _q.isNotEmpty || g.id == 'grp_panel',
                children: [for (final k in grouped[g.id]!) _field(s, k, st[k])],
              ),
        ],
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(s.t('panel_settings')),
        actions: [
          PopupMenuButton<String>(
            onSelected: (v) => v == 'restart' ? _restartPanel() : _load(),
            itemBuilder: (_) => [
              PopupMenuItem(value: 'reload', child: Text(s.t('refresh'))),
              PopupMenuItem(value: 'restart', child: Text(s.t('restart_panel'))),
            ],
          ),
        ],
      ),
      body: body,
      bottomNavigationBar: st == null
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _saving || !_dirty ? null : _save,
                  icon: _saving
                      ? const SizedBox.square(
                          dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                      : const Icon(Icons.check),
                  label: Text(s.t('save')),
                  style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
                ),
              ),
            ),
    );
  }
}
