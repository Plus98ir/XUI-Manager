import 'package:flutter/material.dart';

import '../l10n.dart';
import '../models/models.dart';
import '../theme.dart';

/// Form field that opens a searchable list of inbounds (single or multi select)
/// instead of spreading every inbound on the screen.
class InboundPickerField extends StatelessWidget {
  const InboundPickerField({
    super.key,
    required this.inbounds,
    required this.selected,
    required this.onChanged,
    this.multi = true,
    this.label,
  });

  final List<InboundInfo> inbounds;
  final Set<int> selected;
  final ValueChanged<Set<int>> onChanged;
  final bool multi;
  final String? label;

  static String describe(InboundInfo ib) =>
      '${ib.title} · ${ib.protocol}${ib.port != null ? ':${ib.port}' : ''}';

  Future<void> _open(BuildContext context) async {
    final result = await showModalBottomSheet<Set<int>>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _PickerSheet(inbounds: inbounds, initial: selected, multi: multi),
    );
    if (result != null) onChanged(result);
  }

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final chosen = inbounds.where((i) => selected.contains(i.id)).toList();
    final text = chosen.isEmpty
        ? s.t('select_inbounds')
        : chosen.length == 1
            ? describe(chosen.first)
            : s.n('n_selected', chosen.length);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: () => _open(context),
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label ?? s.t('inbound'),
          prefixIcon: const Icon(Icons.hub_outlined),
          suffixIcon: const Icon(Icons.arrow_drop_down_rounded),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(text, maxLines: 1, overflow: TextOverflow.ellipsis),
            if (chosen.length > 1)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final ib in chosen)
                      Container(
                        constraints: const BoxConstraints(maxWidth: 220),
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(ib.title,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.labelSmall),
                      ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }
}

class _PickerSheet extends StatefulWidget {
  const _PickerSheet({required this.inbounds, required this.initial, required this.multi});

  final List<InboundInfo> inbounds;
  final Set<int> initial;
  final bool multi;

  @override
  State<_PickerSheet> createState() => _PickerSheetState();
}

class _PickerSheetState extends State<_PickerSheet> {
  late final Set<int> _sel = {...widget.initial};
  String _q = '';

  @override
  Widget build(BuildContext context) {
    final s = S.of(context);
    final list = widget.inbounds
        .where((i) =>
            _q.isEmpty ||
            i.title.toLowerCase().contains(_q) ||
            '${i.port}'.contains(_q) ||
            i.protocol.contains(_q))
        .toList();
    final height = MediaQuery.sizeOf(context).height * 0.75;
    return SafeArea(
      child: SizedBox(
        height: height,
        child: Padding(
          padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(s.t('select_inbounds'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: Theme.of(context).textTheme.titleMedium),
                    ),
                    if (widget.multi)
                      TextButton(
                        onPressed: () => setState(() {
                          final ids = list.map((e) => e.id).whereType<int>();
                          if (ids.every(_sel.contains)) {
                            _sel.removeAll(ids);
                          } else {
                            _sel.addAll(ids);
                          }
                        }),
                        child: Text(s.t('select_all')),
                      ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: TextField(
                  decoration: InputDecoration(
                    isDense: true,
                    prefixIcon: const Icon(Icons.search),
                    hintText: s.t('search'),
                  ),
                  onChanged: (v) => setState(() => _q = v.trim().toLowerCase()),
                ),
              ),
              const SizedBox(height: 8),
              Expanded(
                child: ListView.builder(
                  itemCount: list.length,
                  itemBuilder: (_, i) {
                    final ib = list[i];
                    final on = _sel.contains(ib.id);
                    final sub = [
                      ib.protocol.toUpperCase(),
                      if (ib.port != null) '${s.t('port')} ${ib.port}',
                      if ((ib.network ?? '').isNotEmpty) ib.network!,
                      if ((ib.security ?? '').isNotEmpty && ib.security != 'none') ib.security!,
                    ].join(' · ');
                    return ListTile(
                      leading: widget.multi
                          ? Checkbox(value: on, onChanged: (_) => _toggle(ib))
                          : Icon(on ? Icons.radio_button_checked : Icons.radio_button_off,
                              color: on ? brandGreen : null),
                      title: Text(ib.title, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis),
                      trailing: ib.enabled
                          ? null
                          : const Icon(Icons.pause_circle_outline, color: Colors.grey),
                      onTap: () => _toggle(ib),
                    );
                  },
                ),
              ),
              if (widget.multi)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: FilledButton(
                    onPressed: () => Navigator.pop(context, _sel),
                    style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
                    child: Text('${s.t('confirm')} (${_sel.length})'),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  void _toggle(InboundInfo ib) {
    final id = ib.id;
    if (id == null) return;
    if (!widget.multi) {
      Navigator.pop(context, {id});
      return;
    }
    setState(() => _sel.contains(id) ? _sel.remove(id) : _sel.add(id));
  }
}
