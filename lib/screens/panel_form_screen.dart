import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../widgets/common.dart';

class PanelFormScreen extends StatefulWidget {
  const PanelFormScreen({super.key, this.panel});

  final PanelConfig? panel;

  @override
  State<PanelFormScreen> createState() => _PanelFormScreenState();
}

class _PanelFormScreenState extends State<PanelFormScreen> {
  final _form = GlobalKey<FormState>();
  late PanelType _type;
  late final TextEditingController _name, _url, _user, _pass, _token;
  bool _insecure = false;
  bool _openWeb = false;
  bool _obscure = true;
  bool _testing = false;

  @override
  void initState() {
    super.initState();
    final p = widget.panel;
    _type = p?.type ?? PanelType.threeXui;
    _name = TextEditingController(text: p?.name ?? '');
    _url = TextEditingController(text: p?.url ?? '');
    _user = TextEditingController(text: p?.username ?? '');
    _pass = TextEditingController(text: p?.password ?? '');
    _token = TextEditingController(text: p?.token ?? '');
    _insecure = p?.allowInsecure ?? false;
    _openWeb = p?.openWeb ?? false;
  }

  @override
  void dispose() {
    for (final c in [_name, _url, _user, _pass, _token]) {
      c.dispose();
    }
    super.dispose();
  }

  bool get _usesToken => _type != PanelType.alireza && _token.text.trim().isNotEmpty;

  PanelConfig _build() {
    final name = _name.text.trim();
    return PanelConfig(
      id: widget.panel?.id ?? PanelConfig.newId(),
      name: name.isNotEmpty ? name : (Uri.tryParse(normalizePanelUrl(_url.text))?.host ?? 'Panel'),
      type: _type,
      url: _url.text.trim(),
      username: _user.text.trim(),
      password: _pass.text,
      token: _type != PanelType.alireza ? _token.text.trim() : '',
      allowInsecure: _insecure,
      openWeb: _openWeb,
    );
  }

  Future<void> _test() async {
    final s = S.of(context);
    if (!_form.currentState!.validate()) return;
    setState(() => _testing = true);
    final api = PanelApi.create(_build());
    try {
      await api.login();
      final st = await api.status();
      if (!mounted) return;
      final ver = st.coreVersion != null ? ' · Xray ${st.coreVersion}' : '';
      showSnack(context, '${s.t('connection_ok')}$ver');
    } catch (e) {
      if (!mounted) return;
      showSnack(context, '$e', error: true);
    } finally {
      api.dispose();
      if (mounted) setState(() => _testing = false);
    }
  }

  Future<void> _save() async {
    if (!_form.currentState!.validate()) return;
    final cfg = _build();
    try {
      await context.read<AppState>().upsert(cfg);
    } on StateError catch (e) {
      if (mounted) showSnack(context, e.message, error: true);
      return;
    }
    if (mounted) Navigator.pop(context, cfg.id);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    String? requiredUnlessToken(String? v) =>
        !_usesToken && (v == null || v.trim().isEmpty) ? s.t('required') : null;

    return Scaffold(
      appBar: AppBar(title: Text(widget.panel == null ? s.t('new_panel') : s.t('edit_panel'))),
      body: Form(
        key: _form,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            Text(s.t('panel_type'), style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<PanelType>(
              segments: PanelType.values
                  .map((t) => ButtonSegment(value: t, label: Text(t.shortLabel)))
                  .toList(),
              selected: {_type},
              showSelectedIcon: false,
              onSelectionChanged: (v) => setState(() => _type = v.first),
            ),
            const SizedBox(height: 20),
            TextFormField(
              controller: _name,
              decoration: InputDecoration(
                  labelText: s.t('panel_name'), hintText: s.t('panel_name_hint')),
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _url,
              keyboardType: TextInputType.url,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: InputDecoration(
                labelText: s.t('panel_url'),
                hintText: 'https://example.com:2053/path',
                helperText: s.t('url_help'),
                helperMaxLines: 3,
                prefixIcon: const Icon(Icons.link),
              ),
              validator: (v) {
                if (v == null || v.trim().isEmpty) return s.t('required');
                final uri = Uri.tryParse(normalizePanelUrl(v));
                if (uri == null || uri.host.isEmpty) return s.t('invalid_url');
                return null;
              },
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _user,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              decoration: InputDecoration(
                  labelText: s.t('username'), prefixIcon: const Icon(Icons.person_outline)),
              validator: requiredUnlessToken,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _pass,
              obscureText: _obscure,
              textDirection: TextDirection.ltr,
              autocorrect: false,
              enableSuggestions: false,
              decoration: InputDecoration(
                labelText: s.t('password'),
                prefixIcon: const Icon(Icons.lock_outline),
                suffixIcon: IconButton(
                  icon: Icon(_obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                  onPressed: () => setState(() => _obscure = !_obscure),
                ),
              ),
              validator: requiredUnlessToken,
            ),
            if (_type != PanelType.alireza) ...[
              const SizedBox(height: 16),
              TextFormField(
                controller: _token,
                textDirection: TextDirection.ltr,
                autocorrect: false,
                maxLines: 2,
                minLines: 1,
                onChanged: (_) => setState(() {}),
                decoration: InputDecoration(
                  labelText: s.t('api_token'),
                  helperText: s.t('token_help'),
                  helperMaxLines: 2,
                  prefixIcon: const Icon(Icons.key_outlined),
                ),
              ),
            ],
            const SizedBox(height: 8),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('allow_insecure')),
              subtitle: Text(s.t('allow_insecure_help')),
              value: _insecure,
              onChanged: (v) => setState(() => _insecure = v),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: Text(s.t('open_web')),
              subtitle: Text(s.t('open_web_help')),
              value: _openWeb,
              onChanged: (v) => setState(() => _openWeb = v),
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: _testing ? null : _test,
                    icon: _testing
                        ? const SizedBox.square(
                            dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Icon(Icons.wifi_tethering),
                    label: Text(s.t('test_connection')),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: FilledButton.icon(
                    onPressed: _save,
                    icon: const Icon(Icons.check),
                    label: Text(s.t('save')),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
