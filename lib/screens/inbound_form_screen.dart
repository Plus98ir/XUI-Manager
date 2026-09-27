import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../utils/format.dart';
import '../utils/inbound_defaults.dart';
import '../utils/json.dart';
import '../utils/random.dart';
import '../widgets/common.dart';
import '../widgets/form_section.dart';
import 'json_editor_screen.dart';

/// Add or edit an inbound: basics, protocol, transport, security, sniffing,
/// plus a raw JSON editor for everything else the panel supports.
class InboundFormScreen extends StatefulWidget {
  const InboundFormScreen({super.key, required this.api, this.inboundId});

  final PanelApi api;
  final int? inboundId;

  @override
  State<InboundFormScreen> createState() => _InboundFormScreenState();
}

class _InboundFormScreenState extends State<InboundFormScreen> {
  final _form = GlobalKey<FormState>();
  Map<String, dynamic> _inb = {};
  bool _v3 = false;
  bool _ready = false;
  bool _saving = false;
  bool _genKeys = false;
  Object? _loadError;
  int _rev = 0; // bumps when fields must re-read their initial values
  final _gb = TextEditingController();
  final _days = TextEditingController();
  String _initialDays = '0';

  bool get _isEdit => widget.inboundId != null;
  Map<String, dynamic> get _stream =>
      (_inb['streamSettings'] ??= <String, dynamic>{}) as Map<String, dynamic>;
  String get _protocol => asStr(_inb['protocol']) ?? 'vless';
  String get _network => asStr(_stream['network']) ?? 'tcp';
  String get _security => asStr(_stream['security']) ?? 'none';

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _gb.dispose();
    _days.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    setState(() => _loadError = null);
    try {
      await widget.api.prepare();
      _v3 = widget.api.userFormKind == UserFormKind.xuiV3;
      final inb = _isEdit
          ? await widget.api.rawInbound(widget.inboundId!)
          : InboundDefaults.newInbound(v3: _v3);
      if (!mounted) return;
      setState(() {
        _inb = _normalize(inb);
        _inb['streamSettings'] = asMap(_inb['streamSettings']);
        _inb['sniffing'] = asMap(_inb['sniffing']);
        _gb.text = bytesToGbText(asInt(_inb['total']) ?? 0);
        final exp = asInt(_inb['expiryTime']) ?? 0;
        final hours = exp > 0
            ? DateTime.fromMillisecondsSinceEpoch(exp).difference(DateTime.now()).inHours
            : 0;
        _days.text = hours > 0 ? '${(hours / 24).ceil()}' : '0';
        _initialDays = _days.text;
        _ready = true;
      });
    } catch (e) {
      if (mounted) setState(() => _loadError = e);
    }
  }

  /// Deep copy with plain `Map<String, dynamic>` / `List<dynamic>` everywhere,
  /// so nested values can be replaced with any type.
  static Map<String, dynamic> _normalize(Map<String, dynamic> m) => asMap(jsonDecode(jsonEncode(m)));

  void _restructure(void Function() change) {
    setState(() {
      change();
      _inb = _normalize(_inb);
      _rev++;
    });
  }

  /// Reads a value by path; numeric segments index into lists.
  dynamic _get(List<String> path) {
    dynamic cur = _inb;
    for (final p in path) {
      if (cur is Map) {
        cur = cur[p];
      } else if (cur is List) {
        final i = int.tryParse(p);
        cur = i != null && i < cur.length ? cur[i] : null;
      } else {
        return null;
      }
    }
    return cur;
  }

  /// Writes a value by path, creating maps/lists on the way.
  void _set(List<String> path, dynamic value) {
    dynamic cur = _inb;
    for (var k = 0; k < path.length - 1; k++) {
      final p = path[k];
      final nextIsIndex = int.tryParse(path[k + 1]) != null;
      dynamic next;
      if (cur is Map) {
        next = cur[p];
        if (next is! Map && next is! List) {
          next = nextIsIndex ? <dynamic>[] : <String, dynamic>{};
          cur[p] = next;
        }
      } else if (cur is List) {
        final i = int.parse(p);
        while (cur.length <= i) {
          cur.add(nextIsIndex ? <dynamic>[] : <String, dynamic>{});
        }
        next = cur[i];
      }
      cur = next;
    }
    final last = path.last;
    if (cur is Map) {
      cur[last] = value;
    } else if (cur is List) {
      final i = int.parse(last);
      while (cur.length <= i) {
        cur.add(null);
      }
      cur[i] = value;
    }
  }

  // ------------------------------------------------------------ field helpers

  Widget _tf(List<String> path, String label,
      {bool number = false,
      String? helper,
      bool ltr = true,
      Widget? suffix,
      int maxLines = 1,
      String? Function(String)? validator}) {
    return TextFormField(
      key: ValueKey('${path.join('.')}#$_rev'),
      initialValue: _get(path)?.toString() ?? '',
      keyboardType: number ? TextInputType.number : null,
      inputFormatters: number ? [FilteringTextInputFormatter.digitsOnly] : null,
      textDirection: ltr ? TextDirection.ltr : null,
      autocorrect: false,
      maxLines: maxLines,
      minLines: 1,
      decoration: InputDecoration(
        labelText: label,
        helperText: helper,
        helperMaxLines: 3,
        suffixIcon: suffix,
      ),
      validator: validator == null ? null : (v) => validator(v ?? ''),
      onChanged: (v) => _set(path, number ? (int.tryParse(v) ?? 0) : v),
    );
  }

  /// Comma separated list stored as a JSON array.
  Widget _csv(List<String> path, String label, {String? helper, Widget? suffix}) {
    final list = asList(_get(path)).map((e) => '$e').join(', ');
    return TextFormField(
      key: ValueKey('${path.join('.')}#$_rev'),
      initialValue: list,
      textDirection: TextDirection.ltr,
      autocorrect: false,
      decoration: InputDecoration(
          labelText: label, helperText: helper, helperMaxLines: 2, suffixIcon: suffix),
      onChanged: (v) => _set(
          path, v.split(',').map((e) => e.trim()).where((e) => e.isNotEmpty).toList()),
    );
  }

  Widget _dd(List<String> path, String label, List<String> options,
      {String Function(String)? text, void Function(String)? onChanged, String? fallback}) {
    var value = asStr(_get(path)) ?? fallback ?? options.first;
    final opts = [...options, if (!options.contains(value)) value];
    return DropdownButtonFormField<String>(
      key: ValueKey('${path.join('.')}#$_rev'),
      initialValue: value,
      isExpanded: true,
      decoration: InputDecoration(labelText: label),
      items: [
        for (final o in opts)
          DropdownMenuItem(
            value: o,
            child: Text(text?.call(o) ?? o, maxLines: 1, overflow: TextOverflow.ellipsis),
          ),
      ],
      onChanged: (v) {
        if (v == null) return;
        if (onChanged != null) {
          onChanged(v);
        } else {
          setState(() => _set(path, v));
        }
      },
    );
  }

  Widget _sw(List<String> path, String label, {String? subtitle}) => SwitchListTile(
        contentPadding: EdgeInsets.zero,
        title: Text(label),
        subtitle: subtitle == null ? null : Text(subtitle),
        value: _get(path) == true,
        onChanged: (v) => setState(() => _set(path, v)),
      );

  Widget _chips(List<String> path, String label, List<String> options) {
    final sel = asList(_get(path)).map((e) => '$e').toSet();
    return InputDecorator(
      decoration: InputDecoration(labelText: label),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final o in options)
            FilterChip(
              label: Text(o),
              selected: sel.contains(o),
              onSelected: (v) => setState(() {
                v ? sel.add(o) : sel.remove(o);
                _set(path, options.where(sel.contains).toList());
              }),
            ),
        ],
      ),
    );
  }

  Widget _pair(Widget a, Widget b) => Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [Expanded(child: a), const SizedBox(width: 12), Expanded(child: b)],
      );

  // ----------------------------------------------------------------- actions

  Future<void> _generateRealityKeys() async {
    final s = S.of(context);
    setState(() => _genKeys = true);
    try {
      final (priv, pub) = await widget.api.newRealityKeys();
      if (!mounted) return;
      _restructure(() {
        _set(['streamSettings', 'realitySettings', 'privateKey'], priv);
        _set(['streamSettings', 'realitySettings', 'settings', 'publicKey'], pub);
      });
      showSnack(context, s.t('done'));
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _genKeys = false);
    }
  }

  Future<void> _editJson() async {
    final s = S.of(context);
    final result = await Navigator.push<Object?>(
      context,
      MaterialPageRoute(
        builder: (_) => JsonEditorScreen(
          title: s.t('advanced_json'),
          initial: JsonEditorScreen.pretty(_inb),
          help: s.t('advanced_json_help'),
        ),
      ),
    );
    if (result is Map) {
      _restructure(() => _inb = asMap(result));
      _gb.text = bytesToGbText(asInt(_inb['total']) ?? 0);
    }
  }

  Future<void> _save() async {
    final s = S.of(context);
    if (!_form.currentState!.validate()) return;
    final body = _normalize(_inb);
    body['total'] = ((double.tryParse(_gb.text.trim()) ?? 0) * 1073741824).round();
    if (_days.text.trim() != _initialDays) {
      final days = int.tryParse(_days.text.trim()) ?? 0;
      body['expiryTime'] =
          days > 0 ? DateTime.now().add(Duration(days: days)).millisecondsSinceEpoch : 0;
    }
    final tag = asStr(body['tag']) ?? '';
    if (InboundDefaults.isAutoTag(tag)) body['tag'] = InboundDefaults.autoTag(body);

    final stream = asMap(body['streamSettings']);
    if (_security == 'reality') {
      final r = asMap(stream['realitySettings']);
      if ((asStr(r['privateKey']) ?? '').isEmpty ||
          (asStr(asMap(r['settings'])['publicKey']) ?? '').isEmpty) {
        showSnack(context, s.t('reality_keys_missing'), error: true);
        return;
      }
    }
    // Older panels expect at least one client on a new inbound.
    if (!_isEdit && !_v3 && InboundDefaults.protocols.contains(_protocol)) {
      final settings = asMap(body['settings']);
      final clients = asList(settings['clients']);
      if (clients.isEmpty) {
        settings['clients'] = [
          {
            'email': randomUserName(),
            'enable': true,
            'subId': randomString(16),
            'totalGB': 0,
            'expiryTime': 0,
            'limitIp': 0,
            'reset': 0,
            if (_protocol == 'vless' || _protocol == 'vmess') 'id': uuidV4(),
            if (_protocol == 'vless') 'flow': '',
            if (_protocol == 'vmess') 'security': 'auto',
            if (_protocol == 'trojan') 'password': randomString(12),
            if (_protocol == 'shadowsocks') ...{
              'method': '',
              'password': InboundDefaults.ssPassword(asStr(settings['method']) ?? ''),
            },
          }
        ];
        body['settings'] = settings;
      }
    }
    setState(() => _saving = true);
    try {
      await widget.api.saveInbound(body, id: widget.inboundId);
      if (!mounted) return;
      showSnack(context, s.t('done'));
      Navigator.pop(context, true);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // -------------------------------------------------------------------- build

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
      appBar: AppBar(
        title: Text(_isEdit ? s.t('edit_inbound') : s.t('add_inbound')),
        actions: [
          if (_ready)
            IconButton(
              tooltip: s.t('advanced_json'),
              icon: const Icon(Icons.data_object_rounded),
              onPressed: _editJson,
            ),
        ],
      ),
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
    const gap = SizedBox(height: 14);
    final supported = InboundDefaults.protocols.contains(_protocol);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 24),
      children: [
        FormSection(
          title: s.t('section_basic'),
          icon: Icons.tune_rounded,
          children: [
            _sw(['enable'], s.t('enabled')),
            _tf(['remark'], s.t('remark'), ltr: false),
            gap,
            if (_isEdit)
              InputDecorator(
                decoration: InputDecoration(labelText: s.t('protocol')),
                child: Text(_protocol.toUpperCase()),
              )
            else
              _dd(['protocol'], s.t('protocol'), InboundDefaults.protocols,
                  text: (p) => p.toUpperCase(),
                  onChanged: (p) => _restructure(() {
                        _inb['protocol'] = p;
                        _inb['settings'] = InboundDefaults.settingsFor(p);
                        if (!InboundDefaults.realityAllowed(p, _network) &&
                            _security == 'reality') {
                          InboundDefaults.setSecurity(_stream, 'none', v3: _v3);
                        }
                      })),
            gap,
            _pair(
              _tf(['listen'], s.t('listen_ip'), helper: s.t('listen_ip_help')),
              _tf(['port'], s.t('port'),
                  number: true,
                  helper: '1-65535',
                  suffix: IconButton(
                    tooltip: s.t('generate'),
                    icon: const Icon(Icons.casino_outlined),
                    onPressed: () =>
                        _restructure(() => _inb['port'] = InboundDefaults.randomPort()),
                  ),
                  validator: (v) {
                    final p = int.tryParse(v) ?? 0;
                    return p < 1 || p > 65535 ? s.t('invalid_port') : null;
                  }),
            ),
            gap,
            _pair(
              TextFormField(
                controller: _gb,
                keyboardType: const TextInputType.numberWithOptions(decimal: true),
                inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9.]'))],
                decoration: InputDecoration(
                    labelText: s.t('data_limit_gb'),
                    suffixText: 'GB',
                    helperText: s.t('zero_unlimited')),
              ),
              TextFormField(
                controller: _days,
                keyboardType: TextInputType.number,
                inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                decoration: InputDecoration(
                    labelText: s.t('duration_days'),
                    suffixText: s.t('days'),
                    helperText: s.t('zero_unlimited')),
              ),
            ),
            if (_v3) ...[
              gap,
              _dd(['trafficReset'], s.t('traffic_reset'), InboundDefaults.trafficResets,
                  text: (r) => s.t('reset_$r'), fallback: 'never'),
              if (_get(['trafficReset']) == 'monthly') ...[
                gap,
                _tf(['trafficResetDay'], s.t('traffic_reset_day'), number: true),
              ],
            ],
          ],
        ),
        if (_protocol == 'shadowsocks')
          FormSection(
            title: 'Shadowsocks',
            icon: Icons.lock_outline,
            children: [
              _dd(['settings', 'method'], s.t('ss_method'), InboundDefaults.ssMethods,
                  onChanged: (m) => _restructure(() {
                        _set(['settings', 'method'], m);
                        _set(['settings', 'password'], InboundDefaults.ssPassword(m));
                      })),
              gap,
              _tf(['settings', 'password'], s.t('password'),
                  suffix: IconButton(
                    tooltip: s.t('generate'),
                    icon: const Icon(Icons.autorenew_rounded),
                    onPressed: () => _restructure(() => _set(['settings', 'password'],
                        InboundDefaults.ssPassword(asStr(_get(['settings', 'method'])) ?? ''))),
                  )),
              gap,
              _dd(['settings', 'network'], s.t('network'), InboundDefaults.ssNetworks,
                  fallback: 'tcp,udp'),
            ],
          ),
        if (supported) ...[
          FormSection(
            title: s.t('section_transport'),
            icon: Icons.swap_calls_rounded,
            children: _transportFields(s),
          ),
          FormSection(
            title: s.t('section_security'),
            icon: Icons.shield_outlined,
            children: _securityFields(s),
          ),
        ],
        FormSection(
          title: s.t('section_sniffing'),
          icon: Icons.travel_explore_outlined,
          initiallyExpanded: false,
          children: [
            _sw(['sniffing', 'enabled'], s.t('enabled')),
            if (_get(['sniffing', 'enabled']) == true) ...[
              _chips(['sniffing', 'destOverride'], s.t('dest_override'), InboundDefaults.sniffDest),
              _sw(['sniffing', 'metadataOnly'], 'Metadata only'),
              _sw(['sniffing', 'routeOnly'], 'Route only'),
            ],
          ],
        ),
        const SizedBox(height: 14),
        OutlinedButton.icon(
          onPressed: _editJson,
          icon: const Icon(Icons.data_object_rounded),
          label: Text(s.t('advanced_json')),
          style: OutlinedButton.styleFrom(minimumSize: const Size.fromHeight(48)),
        ),
        if (!supported)
          Padding(
            padding: const EdgeInsets.only(top: 12),
            child: Text(s.t('protocol_json_only'), textAlign: TextAlign.center),
          ),
      ],
    );
  }

  List<Widget> _transportFields(S s) {
    const gap = SizedBox(height: 14);
    final net = _network;
    final key = InboundDefaults.settingsKey(net);
    final base = ['streamSettings', key];
    return [
      _dd(['streamSettings', 'network'], s.t('network'), InboundDefaults.networks,
          text: (n) => n == 'tcp' ? 'TCP (RAW)' : n.toUpperCase(),
          onChanged: (n) => _restructure(() {
                final stream = _stream;
                InboundDefaults.setNetwork(stream, n);
                if (_security == 'reality' && !InboundDefaults.realityAllowed(_protocol, n)) {
                  InboundDefaults.setSecurity(stream, 'none', v3: _v3);
                }
                _inb['streamSettings'] = stream;
              })),
      gap,
      ...switch (net) {
        'tcp' => [
            _dd([...base, 'header', 'type'], s.t('header_type'), const ['none', 'http'],
                onChanged: (v) => _restructure(() {
                      _set([...base, 'header'], {
                        'type': v,
                        if (v == 'http')
                          'request': {
                            'version': '1.1',
                            'method': 'GET',
                            'path': ['/'],
                            'headers': {'Host': <String>[]},
                          },
                        if (v == 'http')
                          'response': {
                            'version': '1.1',
                            'status': '200',
                            'reason': 'OK',
                            'headers': <String, dynamic>{},
                          },
                      });
                    })),
            if (_get([...base, 'header', 'type']) == 'http') ...[
              gap,
              _csv([...base, 'header', 'request', 'path'], s.t('path')),
              gap,
              _csv([...base, 'header', 'request', 'headers', 'Host'], s.t('host')),
            ],
            _sw([...base, 'acceptProxyProtocol'], 'Proxy Protocol'),
          ],
        'ws' || 'httpupgrade' => [
            _pair(_tf([...base, 'path'], s.t('path')), _tf([...base, 'host'], s.t('host'))),
            _sw([...base, 'acceptProxyProtocol'], 'Proxy Protocol'),
          ],
        'grpc' => [
            _tf([...base, 'serviceName'], 'Service name'),
            gap,
            _tf([...base, 'authority'], 'Authority'),
            _sw([...base, 'multiMode'], 'Multi mode'),
          ],
        'xhttp' => [
            _pair(_tf([...base, 'path'], s.t('path')), _tf([...base, 'host'], s.t('host'))),
            gap,
            _dd([...base, 'mode'], s.t('mode'), InboundDefaults.xhttpModes, fallback: 'auto'),
          ],
        'kcp' => [
            _tf([...base, 'seed'], 'Seed'),
            gap,
            _pair(_tf([...base, 'mtu'], 'MTU', number: true), _tf([...base, 'tti'], 'TTI', number: true)),
          ],
        _ => <Widget>[],
      },
    ];
  }

  List<Widget> _securityFields(S s) {
    const gap = SizedBox(height: 14);
    final options = [
      'none',
      if (InboundDefaults.tlsAllowed(_protocol)) 'tls',
      if (InboundDefaults.realityAllowed(_protocol, _network)) 'reality',
    ];
    final tls = ['streamSettings', 'tlsSettings'];
    final re = ['streamSettings', 'realitySettings'];
    // 3.x calls the Reality destination `target`; older panels use `dest`.
    final targetKey = _get([...re, 'target']) != null || (_v3 && _get([...re, 'dest']) == null)
        ? 'target'
        : 'dest';
    return [
      _dd(['streamSettings', 'security'], s.t('security'), options,
          text: (o) => o == 'none' ? s.t('none') : o.toUpperCase(),
          onChanged: (v) => _restructure(() {
                final stream = _stream;
                InboundDefaults.setSecurity(stream, v, v3: _v3);
                _inb['streamSettings'] = stream;
              })),
      if (_security == 'tls') ...[
        gap,
        _tf([...tls, 'serverName'], 'SNI (Server name)'),
        gap,
        _chips([...tls, 'alpn'], 'ALPN', InboundDefaults.alpns),
        gap,
        _dd([...tls, 'settings', 'fingerprint'], 'uTLS fingerprint', InboundDefaults.fingerprints,
            fallback: 'chrome'),
        gap,
        _tf([...tls, 'certificates', '0', 'certificateFile'], s.t('cert_file'),
            helper: '/root/cert/example.com/fullchain.pem'),
        gap,
        _tf([...tls, 'certificates', '0', 'keyFile'], s.t('key_file'),
            helper: '/root/cert/example.com/privkey.pem'),
        gap,
        _pair(
          _dd([...tls, 'minVersion'], 'Min TLS', const ['1.0', '1.1', '1.2', '1.3'], fallback: '1.2'),
          _dd([...tls, 'maxVersion'], 'Max TLS', const ['1.0', '1.1', '1.2', '1.3'], fallback: '1.3'),
        ),
        _sw([...tls, 'rejectUnknownSni'], 'Reject unknown SNI'),
      ],
      if (_security == 'reality') ...[
        gap,
        _tf([...re, targetKey], s.t('reality_target'), helper: 'www.speedtest.net:443'),
        gap,
        _csv([...re, 'serverNames'], 'Server names (SNI)', helper: s.t('comma_separated')),
        gap,
        _dd([...re, 'settings', 'fingerprint'], 'uTLS fingerprint', InboundDefaults.fingerprints,
            fallback: 'chrome'),
        gap,
        _tf([...re, 'privateKey'], s.t('private_key')),
        gap,
        _tf([...re, 'settings', 'publicKey'], s.t('public_key')),
        gap,
        OutlinedButton.icon(
          onPressed: _genKeys ? null : _generateRealityKeys,
          icon: _genKeys
              ? const SizedBox.square(dimension: 16, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.vpn_key_outlined),
          label: Text(s.t('generate_keys')),
        ),
        gap,
        _csv([...re, 'shortIds'], 'Short IDs',
            helper: s.t('comma_separated'),
            suffix: IconButton(
              tooltip: s.t('generate'),
              icon: const Icon(Icons.autorenew_rounded),
              onPressed: () => _restructure(() => _set([...re, 'shortIds'],
                  [for (var i = 0; i < 4; i++) InboundDefaults.randomShortId()])),
            )),
        gap,
        _tf([...re, 'settings', 'spiderX'], 'SpiderX'),
        _sw([...re, 'show'], 'Show (debug)'),
      ],
    ];
  }
}
