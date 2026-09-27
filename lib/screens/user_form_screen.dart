import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/panel_api.dart';
import '../api/xui_api.dart';
import '../l10n.dart';
import '../models/models.dart';
import '../theme.dart';
import '../utils/format.dart';
import '../utils/json.dart';
import '../utils/random.dart';
import '../widgets/common.dart';
import '../widgets/form_section.dart';
import '../widgets/inbound_picker.dart';

const _trafficResets = ['never', 'hourly', 'daily', 'weekly', 'monthly'];
const _flows = ['', 'xtls-rprx-vision', 'xtls-rprx-vision-udp443'];
const _vmessSecurity = ['auto', 'aes-128-gcm', 'chacha20-poly1305', 'none', 'zero'];

/// Create / edit a user with every field the panel's own form offers.
class UserFormScreen extends StatefulWidget {
  const UserFormScreen({super.key, required this.api, this.user});

  final PanelApi api;
  final PanelUser? user;

  @override
  State<UserFormScreen> createState() => _UserFormScreenState();
}

class _UserFormScreenState extends State<UserFormScreen> {
  final _form = GlobalKey<FormState>();
  final _c = <String, TextEditingController>{};
  bool _enabled = true;
  bool _startOnFirstUse = false;
  late final String _initialDays;
  late final bool _initialStart;
  Set<int> _inboundIds = {};
  Set<String> _protocols = {};
  String _flow = '';
  String _vmessSec = 'auto';
  String _trafficReset = 'never';
  List<InboundInfo>? _inbounds;
  Object? _loadError;
  bool _ready = false;
  bool _saving = false;

  bool get _isEdit => widget.user != null;
  UserFormKind get _kind => widget.api.userFormKind;
  bool get _mz => _kind == UserFormKind.marzban;
  bool get _v3 => _kind == UserFormKind.xuiV3;
  Map<String, dynamic> get _raw => widget.user?.raw ?? const {};

  TextEditingController _ctl(String key, [String initial = '']) =>
      _c.putIfAbsent(key, () => TextEditingController(text: initial));

  String _rawStr(String k) => asStr(_raw[k]) ?? '';
  String _rawInt(String k) => '${asInt(_raw[k]) ?? 0}';

  @override
  void initState() {
    super.initState();
    final u = widget.user;
    _ctl('name', u?.name ?? randomUserName());
    _ctl('gb', u == null ? '0' : bytesToGbText(u.total));
    String days;
    if (u == null) {
      days = '30';
    } else if (u.expiryDaysAfterFirstUse != null) {
      days = '${u.expiryDaysAfterFirstUse}';
      _startOnFirstUse = true;
    } else if (u.expiry == null) {
      days = '0';
    } else {
      final hours = u.expiry!.difference(DateTime.now()).inHours;
      days = hours <= 0 ? '0' : '${(hours / 24).ceil()}';
    }
    _ctl('days', days);
    _initialDays = days;
    _initialStart = _startOnFirstUse;
    _ctl('limitIp', '${u?.limitIp ?? 0}');
    _ctl('note', u?.note ?? '');
    _enabled = u?.enabled ?? true;
    _load();
  }

  @override
  void dispose() {
    for (final c in _c.values) {
      c.dispose();
    }
    super.dispose();
  }

  /// Detects the panel kind, then fills panel-specific fields.
  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      await widget.api.prepare();
      List<InboundInfo> list = [];
      if (!_isEdit || _v3) {
        list = await widget.api.inbounds();
        if (!_mz) list = list.where(XuiApi.supportsClients).toList();
      }
      if (!mounted) return;
      final u = widget.user;
      setState(() {
        _inbounds = list;
        if (u != null && _v3) {
          _inboundIds = asList(_raw['inboundIds']).map(asInt).whereType<int>().toSet();
        } else if (_inboundIds.isEmpty && list.isNotEmpty && !_mz) {
          _inboundIds = {list.first.id!};
        }
        if (_mz && !_isEdit) _protocols = list.map((e) => e.protocol).toSet();
        // Credentials / extras: prefilled from the user or freshly generated.
        _ctl('uuid', u != null ? (_rawStr('uuid').isNotEmpty ? _rawStr('uuid') : _rawStr('id')) : uuidV4());
        _ctl('password', u != null ? _rawStr('password') : randomString(16));
        _ctl('subId', u != null ? _rawStr('subId') : randomString(16));
        _ctl('limitHwid', u != null ? _rawInt('limitHwid') : '0');
        _ctl('tgId', u != null ? _rawInt('tgId') : '0');
        _ctl('group', _rawStr('group'));
        _ctl('reset', u != null ? _rawInt('reset') : '0');
        _ctl('resetDay', u != null ? _rawInt('resetDay') : '0');
        _ctl('resetMax', u != null ? _rawInt('resetMax') : '0');
        _ctl('trafficResetDay', u != null && (asInt(_raw['trafficResetDay']) ?? 0) > 0 ? _rawInt('trafficResetDay') : '1');
        _flow = _flows.contains(_rawStr('flow')) ? _rawStr('flow') : '';
        _vmessSec = _vmessSecurity.contains(_rawStr('security')) ? _rawStr('security') : 'auto';
        _trafficReset = _trafficResets.contains(_rawStr('trafficReset')) ? _rawStr('trafficReset') : 'never';
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  Set<String> get _selectedProtocols {
    if (_isEdit && !_v3) return {widget.user?.protocol ?? ''};
    final list = _inbounds ?? const [];
    return list.where((i) => _inboundIds.contains(i.id)).map((i) => i.protocol).toSet();
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final days = int.tryParse(_ctl('days').text) ?? 0;
    final picked = await showDatePicker(
      context: context,
      initialDate: now.add(Duration(days: days > 0 ? days : 30)),
      firstDate: now,
      lastDate: now.add(const Duration(days: 3650)),
    );
    if (picked == null) return;
    final end = DateTime(picked.year, picked.month, picked.day, 23, 59);
    setState(() {
      _startOnFirstUse = false;
      _ctl('days').text = '${(end.difference(now).inHours / 24).ceil()}';
    });
  }

  int _int(String k) => int.tryParse(_ctl(k).text.trim()) ?? 0;

  Future<void> _save() async {
    final s = S.of(context);
    if (!_form.currentState!.validate()) return;
    if (!_mz && (!_isEdit || _v3) && _inboundIds.isEmpty) {
      showSnack(context, s.t('select_inbounds'), error: true);
      return;
    }
    if (!_isEdit && _mz && _protocols.isEmpty) {
      showSnack(context, s.t('select_protocol'), error: true);
      return;
    }
    final u = widget.user;
    final gb = double.tryParse(_ctl('gb').text.trim()) ?? 0;
    final days = _int('days');
    DateTime? expiry;
    int? afterFirstUse;
    final expiryChanged = _ctl('days').text.trim() != _initialDays || _startOnFirstUse != _initialStart;
    if (u != null && !expiryChanged) {
      expiry = u.expiry;
      afterFirstUse = u.expiryDaysAfterFirstUse;
    } else if (days > 0) {
      if (_startOnFirstUse) {
        afterFirstUse = days;
      } else {
        expiry = DateTime.now().add(Duration(days: days));
      }
    }
    final protos = _selectedProtocols;
    final extra = <String, dynamic>{};
    if (!_mz) {
      extra['subId'] = _ctl('subId').text.trim();
      extra['reset'] = _int('reset');
      if (protos.contains('vless') || protos.contains('vmess') || _v3) {
        extra['uuid'] = _ctl('uuid').text.trim();
      }
      if (protos.contains('trojan') || protos.contains('shadowsocks') || _v3) {
        extra['password'] = _ctl('password').text.trim();
      }
      // Empty flow on create lets the panel inherit the inbound's flow.
      if (protos.contains('vless') && (_flow.isNotEmpty || _isEdit)) extra['flow'] = _flow;
      if (protos.contains('vmess')) extra['security'] = _vmessSec;
      if (_v3) {
        extra.addAll({
          'limitHwid': _int('limitHwid'),
          'tgId': _int('tgId'),
          'group': _ctl('group').text.trim(),
          'resetDay': _int('resetDay'),
          'resetMax': _int('resetMax'),
          'trafficReset': _trafficReset,
          'trafficResetDay': _int('trafficResetDay') == 0 ? 1 : _int('trafficResetDay'),
        });
      }
    }
    final draft = UserDraft(
      name: _ctl('name').text.trim(),
      totalBytes: (gb * 1073741824).round(),
      expiry: expiry,
      expiryDaysAfterFirstUse: afterFirstUse,
      enabled: _enabled,
      limitIp: _int('limitIp'),
      note: _ctl('note').text.trim(),
      inboundId: _inboundIds.isEmpty ? null : _inboundIds.first,
      inboundIds: _v3 ? _inboundIds : const {},
      protocols: _protocols,
      flow: _flow,
      extra: extra,
    );
    setState(() => _saving = true);
    try {
      if (u != null) {
        await widget.api.updateUser(u, draft);
      } else {
        await widget.api.createUser(draft);
      }
      if (!mounted) return;
      showSnack(context, s.t('done'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ------------------------------------------------------------------ widgets

  Widget _num(String key, String label, {String? helper, String? suffix, bool decimal = false}) =>
      TextFormField(
        controller: _ctl(key),
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(decimal ? r'[0-9.]' : r'[0-9]'))
        ],
        decoration: InputDecoration(
          labelText: label,
          helperText: helper,
          helperMaxLines: 2,
          suffixText: suffix,
        ),
      );

  Widget _text(String key, String label,
          {IconData? icon, VoidCallback? regen, bool ltr = true, int maxLines = 1}) =>
      TextFormField(
        controller: _ctl(key),
        textDirection: ltr ? TextDirection.ltr : null,
        autocorrect: false,
        maxLines: maxLines,
        minLines: 1,
        decoration: InputDecoration(
          labelText: label,
          prefixIcon: icon == null ? null : Icon(icon),
          suffixIcon: regen == null
              ? null
              : IconButton(
                  tooltip: S.of(context).t('generate'),
                  icon: const Icon(Icons.autorenew_rounded),
                  onPressed: regen,
                ),
        ),
      );

  Widget _dropdown<T>(String label, T value, List<T> items, String Function(T) text,
          ValueChanged<T> onChanged) =>
      DropdownButtonFormField<T>(
        key: ValueKey('$label$value'),
        initialValue: value,
        isExpanded: true,
        decoration: InputDecoration(labelText: label),
        items: [
          for (final i in items)
            DropdownMenuItem(
                value: i, child: Text(text(i), maxLines: 1, overflow: TextOverflow.ellipsis)),
        ],
        onChanged: (v) {
          if (v != null) setState(() => onChanged(v));
        },
      );

  Widget _pair(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
      );

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    Widget body;
    if (_loadError != null) {
      body = ErrorView(message: '$_loadError', onRetry: _load);
    } else if (!_ready) {
      body = const Center(child: CircularProgressIndicator());
    } else {
      body = Form(key: _form, child: _fields(s));
    }
    return Scaffold(
      appBar: AppBar(title: Text(_isEdit ? s.t('edit_user') : s.t('add_user'))),
      body: body,
      bottomNavigationBar: !_ready
          ? null
          : SafeArea(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                child: FilledButton.icon(
                  onPressed: _saving ? null : _save,
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

  Widget _fields(S s) {
    final protos = _selectedProtocols;
    final showInbounds = !_mz && (!_isEdit || _v3);
    const gap = SizedBox(height: 14);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        FormSection(
          title: s.t('section_basic'),
          icon: Icons.person_outline,
          children: [
            if (showInbounds) ...[
              if ((_inbounds ?? const []).isEmpty)
                Text(s.t('no_inbounds'))
              else
                InboundPickerField(
                  inbounds: _inbounds!,
                  selected: _inboundIds,
                  multi: _v3,
                  onChanged: (v) => setState(() => _inboundIds = v),
                ),
              gap,
            ],
            if (_mz && !_isEdit) ...[
              _MarzbanProtocols(
                all: (_inbounds ?? const []).map((e) => e.protocol).toSet(),
                selected: _protocols,
                onChanged: (v) => setState(() => _protocols = v),
              ),
              if (_protocols.contains('vless')) ...[
                gap,
                _dropdown<String>(s.t('flow'), _flow, _flows,
                    (f) => f.isEmpty ? s.t('flow_none') : f, (v) => _flow = v),
              ],
              gap,
            ],
            TextFormField(
              controller: _ctl('name'),
              enabled: !(_isEdit && _mz),
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: _mz ? s.t('username') : s.t('user_name'),
                helperText: _mz ? s.t('username_rule') : null,
                prefixIcon: const Icon(Icons.badge_outlined),
                suffixIcon: _isEdit
                    ? null
                    : IconButton(
                        tooltip: s.t('generate'),
                        icon: const Icon(Icons.casino_outlined),
                        onPressed: () => _ctl('name').text = randomUserName(),
                      ),
              ),
              validator: (v) {
                final t = v?.trim() ?? '';
                if (t.isEmpty) return s.t('required');
                if (_mz && !RegExp(r'^[a-z0-9_]{3,32}$').hasMatch(t)) return s.t('username_rule');
                return null;
              },
            ),
            gap,
            _pair(
              _num('gb', s.t('data_limit_gb'),
                  helper: s.t('zero_unlimited'), suffix: 'GB', decimal: true),
              TextFormField(
                controller: _ctl('days'),
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                  labelText: s.t('duration_days'),
                  helperText: s.t('zero_unlimited'),
                  suffixIcon: IconButton(
                    tooltip: s.t('pick_date'),
                    icon: const Icon(Icons.event_outlined),
                    onPressed: _pickDate,
                  ),
                ),
              ),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('start_on_first_use')),
              subtitle: Text(s.t('start_on_first_use_help')),
              value: _startOnFirstUse,
              onChanged: (v) => setState(() => _startOnFirstUse = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('enabled')),
              value: _enabled,
              onChanged: (v) => setState(() => _enabled = v),
            ),
          ],
        ),
        if (!_mz) ...[
          FormSection(
            title: s.t('section_limits'),
            icon: Icons.devices_outlined,
            children: [
              if (_v3)
                _pair(_num('limitIp', s.t('ip_limit'), helper: s.t('zero_unlimited')),
                    _num('limitHwid', s.t('hwid_limit'), helper: s.t('zero_unlimited')))
              else
                _num('limitIp', s.t('ip_limit'), helper: s.t('zero_unlimited')),
            ],
          ),
          FormSection(
            title: s.t('section_renew'),
            icon: Icons.autorenew_rounded,
            initiallyExpanded: _isEdit && (asInt(_raw['reset']) ?? 0) > 0,
            children: [
              _num('reset', s.t('renew_days'), helper: s.t('renew_days_help')),
              if (_v3) ...[
                gap,
                _pair(_num('resetDay', s.t('renew_on_day'), helper: '0-31'),
                    _num('resetMax', s.t('renew_max'), helper: s.t('zero_unlimited'))),
                gap,
                _dropdown<String>(s.t('traffic_reset'), _trafficReset, _trafficResets,
                    (r) => s.t('reset_$r'), (v) => _trafficReset = v),
                if (_trafficReset == 'monthly') ...[
                  gap,
                  _num('trafficResetDay', s.t('traffic_reset_day'), helper: '1-31'),
                ],
              ],
            ],
          ),
        ],
        FormSection(
          title: s.t('section_more'),
          icon: Icons.notes_outlined,
          initiallyExpanded: (widget.user?.note ?? '').isNotEmpty,
          children: [
            _text('note', s.t('note'), icon: Icons.notes_outlined, ltr: false, maxLines: 3),
            if (_v3) ...[
              gap,
              _pair(_text('group', s.t('group'), ltr: false),
                  _num('tgId', s.t('telegram_id'))),
            ],
          ],
        ),
        if (!_mz)
          FormSection(
            title: s.t('section_credentials'),
            icon: Icons.key_outlined,
            children: [
              if (protos.contains('vless') || protos.contains('vmess') || _v3) ...[
                _text('uuid', 'UUID', regen: () => setState(() => _ctl('uuid').text = uuidV4())),
                gap,
              ],
              if (protos.contains('trojan') || protos.contains('shadowsocks') || _v3) ...[
                _text('password', s.t('password'),
                    regen: () => setState(() => _ctl('password').text = randomString(16))),
                gap,
              ],
              _text('subId', s.t('sub_id'),
                  regen: () => setState(() => _ctl('subId').text = randomString(16))),
              if (protos.contains('vless')) ...[
                gap,
                _dropdown<String>(s.t('flow'), _flow, _flows,
                    (f) => f.isEmpty ? s.t('flow_none') : f, (v) => _flow = v),
              ],
              if (protos.contains('vmess')) ...[
                gap,
                _dropdown<String>(s.t('vmess_security'), _vmessSec, _vmessSecurity, (v) => v,
                    (v) => _vmessSec = v),
              ],
            ],
          ),
      ],
    );
  }
}

class _MarzbanProtocols extends StatelessWidget {
  const _MarzbanProtocols({required this.all, required this.selected, required this.onChanged});

  final Set<String> all;
  final Set<String> selected;
  final ValueChanged<Set<String>> onChanged;

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final list = all.toList()..sort();
    if (list.isEmpty) return Text(s.t('no_inbounds'));
    return InputDecorator(
      decoration: InputDecoration(labelText: s.t('protocols')),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final p in list)
            FilterChip(
              label: Text(p.toUpperCase()),
              selected: selected.contains(p),
              selectedColor: brandGreen.withValues(alpha: 0.25),
              onSelected: (v) => onChanged({...selected}..let(v, p)),
            ),
        ],
      ),
    );
  }
}

extension on Set<String> {
  Set<String> let(bool add, String p) {
    add ? this.add(p) : remove(p);
    return this;
  }
}
