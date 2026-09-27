import 'package:flutter/material.dart';

import '../api/panel_api.dart';
import '../l10n.dart';
import '../utils/xray_template.dart';
import '../widgets/common.dart';

/// Loads, holds and saves the Xray template for the outbound and routing
/// editors. Changes stay local until [save].
mixin XrayTemplateEditor<W extends StatefulWidget> on State<W> {
  PanelApi get api;

  XrayTemplate? tpl;
  Object? loadError;
  bool dirty = false;
  bool saving = false;

  Future<void> loadTemplate() async {
    setState(() => loadError = null);
    try {
      final t = XrayTemplate.parse(await api.xrayConfig());
      if (mounted) {
        setState(() {
          tpl = t;
          dirty = false;
        });
      }
      await onTemplateLoaded();
    } catch (e) {
      if (mounted) setState(() => loadError = e);
    }
  }

  Future<void> onTemplateLoaded() async {}

  void change(VoidCallback fn) => setState(() {
        fn();
        dirty = true;
      });

  Future<void> save() async {
    final s = S.of(context);
    final t = tpl;
    if (t == null) return;
    setState(() => saving = true);
    try {
      await api.saveXrayConfig(t.encode());
      if (!mounted) return;
      setState(() => dirty = false);
      showRestartSnack(context, api, s.t('saved_restart'));
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => saving = false);
    }
  }

  /// Asks before leaving with unsaved changes.
  Future<bool> confirmLeave() async {
    if (!dirty) return true;
    final s = S.of(context);
    return confirmDialog(context,
        title: s.t('discard_q'), action: s.t('discard'), danger: true);
  }

  Widget saveBar() {
    final s = S.of(context);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
        child: FilledButton.icon(
          onPressed: saving || !dirty ? null : save,
          icon: saving
              ? const SizedBox.square(dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.check_rounded),
          label: Text(s.t('save')),
          style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
        ),
      ),
    );
  }

  Widget? loadingBody() {
    if (tpl != null) return null;
    return loadError != null
        ? ErrorView(message: '$loadError', onRetry: loadTemplate)
        : const Center(child: CircularProgressIndicator());
  }
}

/// Snack bar with a "Restart Xray" button.
void showRestartSnack(BuildContext context, PanelApi api, String message) {
  final s = S.of(context);
  final messenger = ScaffoldMessenger.of(context);
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(SnackBar(
    content: Text(message),
    behavior: SnackBarBehavior.floating,
    duration: const Duration(seconds: 8),
    action: SnackBarAction(
      label: s.t('restart_xray'),
      onPressed: () async {
        try {
          await api.restartCore();
          messenger.showSnackBar(SnackBar(
              content: Text(s.t('done')), behavior: SnackBarBehavior.floating));
        } catch (e) {
          messenger.showSnackBar(SnackBar(
              content: Text('$e'), behavior: SnackBarBehavior.floating));
        }
      },
    ),
  ));
}

/// Restart-Xray flow with confirmation, shared by the settings screens.
Future<void> restartXray(BuildContext context, PanelApi api) async {
  final s = S.of(context);
  final ok = await confirmDialog(context,
      title: s.t('restart_core_q'), message: s.t('restart_core_msg'), action: s.t('restart_core'));
  if (!ok) return;
  try {
    await api.restartCore();
    if (context.mounted) showSnack(context, s.t('done'));
  } catch (e) {
    if (context.mounted) showSnack(context, '$e', error: true);
  }
}

IconData protocolIcon(String? protocol) => switch (protocol) {
      'freedom' => Icons.public_rounded,
      'blackhole' => Icons.block_rounded,
      'dns' => Icons.dns_outlined,
      'wireguard' => Icons.vpn_lock_outlined,
      'socks' || 'http' => Icons.lan_outlined,
      'loopback' => Icons.loop_rounded,
      _ => Icons.shield_outlined,
    };
