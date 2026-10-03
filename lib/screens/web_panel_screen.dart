import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import 'package:webview_flutter/webview_flutter.dart';

import '../l10n.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/panel_switcher.dart';
import 'panel_form_screen.dart';
import 'panel_home_screen.dart';

/// Route for [panel] in its preferred view, or the one [web] asks for.
Route<void> panelRoute(PanelConfig panel, {bool? web, bool fade = false}) {
  final Widget page = (web ?? panel.openWeb)
      ? WebPanelScreen(panelId: panel.id)
      : PanelHomeScreen(panelId: panel.id);
  if (!fade) return MaterialPageRoute(builder: (_) => page);
  return PageRouteBuilder(
    pageBuilder: (_, __, ___) => GlassBackdrop(child: page),
    transitionsBuilder: (_, anim, __, child) => FadeTransition(opacity: anim, child: child),
  );
}

/// The panel's own web UI in a WebView: what the panel's PWA shows, but one
/// app can hold any number of panels. Signs in with the saved credentials;
/// the WebView keeps the session cookie between launches like a browser.
class WebPanelScreen extends StatefulWidget {
  const WebPanelScreen({super.key, required this.panelId});

  final String panelId;

  @override
  State<WebPanelScreen> createState() => _WebPanelScreenState();
}

class _WebPanelScreenState extends State<WebPanelScreen> {
  late final PanelConfig _cfg;
  late final WebViewController _web;
  int _progress = 0;
  bool _loginTried = false;
  String? _error;

  String get _base => _cfg.baseUrl;
  String get _start => _cfg.type == PanelType.marzban ? '$_base/dashboard/' : '$_base/';

  @override
  void initState() {
    super.initState();
    _cfg = context.read<AppState>().panelById(widget.panelId)!;
    _web = WebViewController()
      ..setJavaScriptMode(JavaScriptMode.unrestricted)
      ..addJavaScriptChannel('XuiManager', onMessageReceived: _onMessage)
      ..setNavigationDelegate(NavigationDelegate(
        onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        },
        onPageStarted: (_) {
          if (mounted && _error != null) setState(() => _error = null);
        },
        onPageFinished: _onPageFinished,
        onWebResourceError: (e) {
          if (e.isForMainFrame == true && mounted) setState(() => _error = e.description);
        },
        onSslAuthError: (e) => _cfg.allowInsecure ? e.proceed() : e.cancel(),
      ))
      ..loadRequest(Uri.parse(_start));
  }

  bool _isLoginPage(String url) {
    final path = (Uri.tryParse(url)?.path ?? '').replaceAll(RegExp(r'/+$'), '');
    final base = (Uri.tryParse(_base)?.path ?? '').replaceAll(RegExp(r'/+$'), '');
    return path == base || path == '$base/login';
  }

  /// Signs in once per screen, from inside the page so the WebView stores the
  /// session cookie (3X-UI) or the dashboard token (Marzban).
  Future<void> _onPageFinished(String url) async {
    if (_loginTried) return;
    final hasCreds = _cfg.username.isNotEmpty && _cfg.password.isNotEmpty;
    final String js;
    if (_cfg.type == PanelType.marzban) {
      if (!hasCreds && _cfg.token.isEmpty) return;
      _loginTried = true;
      js = _marzbanLogin;
    } else {
      if (!hasCreds || !_isLoginPage(url)) return;
      _loginTried = true;
      js = _xuiLogin;
    }
    final args = jsonEncode({
      'base': _base,
      'username': _cfg.username,
      'password': _cfg.password,
      'token': _cfg.token,
    });
    try {
      await _web.runJavaScript('($js)($args);');
    } catch (_) {
      // Page navigated away mid-script; the user can still sign in by hand.
    }
  }

  void _onMessage(JavaScriptMessage m) {
    if (!mounted || m.message.isEmpty) return;
    showSnack(context, S.of(context).n('web_login_failed', m.message), error: true);
  }

  Future<void> _openSwitcher() async {
    final result = await showPanelSwitcher(context, currentId: widget.panelId);
    if (!mounted || result == null) return;
    final state = context.read<AppState>();
    switch (result) {
      case SwitchTo(:final panelId):
        final p = state.panelById(panelId);
        if (p != null && panelId != widget.panelId) {
          Navigator.pushReplacement(context, panelRoute(p, web: true, fade: true));
        }
      case EditPanel(:final panel):
        await Navigator.push(
            context, MaterialPageRoute(builder: (_) => PanelFormScreen(panel: panel)));
      case AddPanel():
        final id = await Navigator.push<String>(
            context, MaterialPageRoute(builder: (_) => const PanelFormScreen()));
        final p = id == null ? null : state.panelById(id);
        if (p != null && mounted) {
          Navigator.pushReplacement(context, panelRoute(p, fade: true));
        }
    }
  }

  Future<void> _back() async {
    if (await _web.canGoBack()) {
      await _web.goBack();
    } else if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _back();
      },
      child: Scaffold(
        appBar: AppBar(
          titleSpacing: 0,
          title: InkWell(
            borderRadius: BorderRadius.circular(10),
            onTap: _openSwitcher,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Flexible(
                    child: Text(_cfg.name,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.w700)),
                  ),
                  const Icon(Icons.expand_more_rounded),
                ],
              ),
            ),
          ),
          actions: [
            IconButton(
              tooltip: s.t('refresh'),
              icon: const Icon(Icons.refresh_rounded),
              onPressed: () => _web.reload(),
            ),
            IconButton(
              tooltip: s.t('app_view'),
              icon: const Icon(Icons.space_dashboard_outlined),
              onPressed: () =>
                  Navigator.pushReplacement(context, panelRoute(_cfg, web: false, fade: true)),
            ),
          ],
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(2),
            child: _progress < 100
                ? LinearProgressIndicator(value: _progress / 100, minHeight: 2)
                : const SizedBox(height: 2),
          ),
        ),
        body: _error == null
            ? WebViewWidget(controller: _web)
            : ErrorView(
                message: _error!,
                onRetry: () {
                  setState(() => _error = null);
                  _web.loadRequest(Uri.parse(_start));
                },
              ),
      ),
    );
  }
}

/// 3X-UI / Alireza: POST /login from the login page (with the CSRF token new
/// 3X-UI requires), then reload the root, which redirects to the panel.
const _xuiLogin = r'''
async function (a) {
  const report = (m) => { try { XuiManager.postMessage(String(m)); } catch (_) {} };
  try {
    let csrf = '';
    try {
      const r = await fetch(a.base + '/csrf-token', {
        credentials: 'same-origin',
        headers: { 'X-Requested-With': 'XMLHttpRequest' },
      });
      const j = await r.json();
      if (j && j.success && typeof j.obj === 'string') csrf = j.obj;
    } catch (_) {}
    const headers = {
      'Content-Type': 'application/x-www-form-urlencoded; charset=UTF-8',
      'X-Requested-With': 'XMLHttpRequest',
    };
    if (csrf) headers['X-CSRF-Token'] = csrf;
    const r = await fetch(a.base + '/login', {
      method: 'POST',
      credentials: 'same-origin',
      headers,
      body: new URLSearchParams({ username: a.username, password: a.password }).toString(),
    });
    let j = null;
    try { j = await r.json(); } catch (_) {}
    if (j && j.success) {
      location.replace(a.base + '/');
    } else {
      report((j && j.msg) || ('HTTP ' + r.status));
    }
  } catch (e) {
    report(e && e.message ? e.message : e);
  }
}
''';

/// Marzban: the dashboard keeps its bearer token in localStorage["token"].
/// Keep a working one; otherwise fetch a fresh token and reload.
const _marzbanLogin = r'''
async function (a) {
  const report = (m) => { try { XuiManager.postMessage(String(m)); } catch (_) {} };
  try {
    const valid = async (t) => {
      if (!t) return false;
      const r = await fetch(a.base + '/api/admin', { headers: { Authorization: 'Bearer ' + t } });
      return r.ok;
    };
    if (await valid(localStorage.getItem('token'))) return;
    let token = '';
    if (a.username && a.password) {
      const r = await fetch(a.base + '/api/admin/token', {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({ username: a.username, password: a.password }).toString(),
      });
      const j = await r.json().catch(() => null);
      if (j && j.access_token) token = j.access_token;
      else return report((j && j.detail) || ('HTTP ' + r.status));
    } else if (await valid(a.token)) {
      token = a.token;
    } else {
      return report('token rejected');
    }
    localStorage.setItem('token', token);
    location.replace(a.base + '/dashboard/');
  } catch (e) {
    report(e && e.message ? e.message : e);
  }
}
''';
