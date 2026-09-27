import 'dart:convert';

import 'package:flutter/material.dart';

import '../l10n.dart';
import '../widgets/common.dart';

/// Full-screen JSON editor. Pops with the parsed value when saved, or runs
/// [onSave] (for editors that save straight to the panel).
class JsonEditorScreen extends StatefulWidget {
  const JsonEditorScreen({
    super.key,
    required this.title,
    required this.initial,
    this.onSave,
    this.help,
  });

  final String title;
  final String initial;
  final String? help;
  final Future<void> Function(String json)? onSave;

  static String pretty(Object? value) => const JsonEncoder.withIndent('  ').convert(value);

  @override
  State<JsonEditorScreen> createState() => _JsonEditorScreenState();
}

class _JsonEditorScreenState extends State<JsonEditorScreen> {
  late final TextEditingController _c = TextEditingController(text: widget.initial);
  String? _error;
  bool _saving = false;

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  Object? _parse() {
    try {
      final v = jsonDecode(_c.text);
      setState(() => _error = null);
      return v;
    } on FormatException catch (e) {
      setState(() => _error = e.message);
      return null;
    }
  }

  void _format() {
    final v = _parse();
    if (v != null) _c.text = JsonEditorScreen.pretty(v);
  }

  Future<void> _save() async {
    final s = S.of(context);
    final v = _parse();
    if (v == null) return;
    if (widget.onSave == null) {
      Navigator.pop(context, v);
      return;
    }
    setState(() => _saving = true);
    try {
      await widget.onSave!(_c.text);
      if (!mounted) return;
      showSnack(context, s.t('done'));
      Navigator.pop(context, v);
    } catch (e) {
      if (mounted) showSnack(context, '$e', error: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.title, maxLines: 1, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
              tooltip: s.t('format_json'),
              icon: const Icon(Icons.auto_fix_high_outlined),
              onPressed: _format),
          IconButton(
              tooltip: s.t('copy'),
              icon: const Icon(Icons.copy_rounded),
              onPressed: () => copyText(context, _c.text)),
        ],
      ),
      body: Column(
        children: [
          if (widget.help != null)
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              child: Text(widget.help!, style: Theme.of(context).textTheme.bodySmall),
            ),
          if (_error != null)
            Container(
              width: double.infinity,
              margin: const EdgeInsets.fromLTRB(16, 4, 16, 4),
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(_error!, style: const TextStyle(color: Colors.red)),
            ),
          Expanded(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 4, 12, 4),
              child: Directionality(
                textDirection: TextDirection.ltr,
                child: TextField(
                  controller: _c,
                  expands: true,
                  maxLines: null,
                  minLines: null,
                  keyboardType: TextInputType.multiline,
                  autocorrect: false,
                  enableSuggestions: false,
                  textAlignVertical: TextAlignVertical.top,
                  style: const TextStyle(fontFamily: 'monospace', fontSize: 12.5, height: 1.35),
                  decoration: const InputDecoration(contentPadding: EdgeInsets.all(12)),
                ),
              ),
            ),
          ),
        ],
      ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: FilledButton.icon(
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Icon(Icons.check),
            label: Text(widget.onSave == null ? s.t('apply') : s.t('save')),
            style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(50)),
          ),
        ),
      ),
    );
  }
}
