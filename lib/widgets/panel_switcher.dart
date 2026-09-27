import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../models/models.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../utils/format.dart';
import 'panel_status_line.dart';
import 'soft.dart';

/// Result of the switcher sheet.
sealed class SwitcherResult {}

class SwitchTo extends SwitcherResult {
  SwitchTo(this.panelId);
  final String panelId;
}

class EditPanel extends SwitcherResult {
  EditPanel(this.panel);
  final PanelConfig panel;
}

class AddPanel extends SwitcherResult {}

Future<SwitcherResult?> showPanelSwitcher(BuildContext context, {String? currentId}) {
  return showModalBottomSheet<SwitcherResult>(
    context: context,
    isScrollControlled: true,
    showDragHandle: true,
    builder: (ctx) => _SwitcherSheet(currentId: currentId),
  );
}

class _SwitcherSheet extends StatelessWidget {
  const _SwitcherSheet({this.currentId});

  final String? currentId;

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = S.of(context);
    final panels = state.panels;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(20, 0, 20, 16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(s.t('switch_panel'),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.titleLarge),
                ),
                Text(ltr('${panels.length} / ${AppState.maxPanels}'),
                    style: TextStyle(color: SoftColors.of(context).muted)),
              ],
            ),
            const SizedBox(height: 16),
            Flexible(
              child: ListView.separated(
                shrinkWrap: true,
                itemCount: panels.length,
                separatorBuilder: (_, __) => const SizedBox(height: 14),
                itemBuilder: (_, i) {
                  final p = panels[i];
                  final current = p.id == currentId;
                  return SoftBox(
                    depth: 4,
                    radius: 20,
                    padding: const EdgeInsets.fromLTRB(12, 10, 4, 10),
                    onTap: () => Navigator.pop(context, SwitchTo(p.id)),
                    child: Row(
                      children: [
                        PanelTypeAvatar(type: p.type, size: 42),
                        const SizedBox(width: 12),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  Flexible(
                                    child: Text(p.name,
                                        maxLines: 1,
                                        overflow: TextOverflow.ellipsis,
                                        style: const TextStyle(fontWeight: FontWeight.w700)),
                                  ),
                                  if (current) ...[
                                    const SizedBox(width: 6),
                                    const Icon(Icons.check_circle, size: 16, color: brandGreen),
                                  ],
                                ],
                              ),
                              PanelStatusLine(panel: p, refreshToken: 0),
                            ],
                          ),
                        ),
                        IconButton(
                          tooltip: s.t('edit'),
                          icon: const Icon(Icons.edit_outlined),
                          onPressed: () => Navigator.pop(context, EditPanel(p)),
                        ),
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 16),
            FilledButton.tonalIcon(
              onPressed: state.canAddPanel ? () => Navigator.pop(context, AddPanel()) : null,
              icon: const Icon(Icons.add),
              label: Text(state.canAddPanel
                  ? s.t('add_panel')
                  : s.n('max_panels', AppState.maxPanels)),
              style: FilledButton.styleFrom(minimumSize: const Size.fromHeight(48)),
            ),
          ],
        ),
      ),
    );
  }
}
