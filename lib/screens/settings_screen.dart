import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n.dart';
import '../state/app_state.dart';
import '../theme.dart';
import '../widgets/common.dart';
import '../widgets/soft.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final s = S.of(context);
    final brightness = Theme.of(context).brightness;
    return Scaffold(
      appBar: AppBar(title: Text(s.t('settings'))),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          SectionTitle(s.t('style')),
          Row(
            children: [
              for (final (i, st) in AppStyle.values.indexed) ...[
                if (i > 0) const SizedBox(width: 12),
                Expanded(
                  child: _StylePreview(
                    style: st,
                    brightness: brightness,
                    label: s.t('style_${st.name}'),
                    selected: state.style == st,
                    onTap: () => state.setStyle(st),
                  ),
                ),
              ],
            ],
          ),
          SectionTitle(s.t('mode')),
          SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                  value: ThemeMode.system,
                  icon: const Icon(Icons.brightness_auto_outlined),
                  label: Text(s.t('theme_system'))),
              ButtonSegment(
                  value: ThemeMode.light,
                  icon: const Icon(Icons.light_mode_outlined),
                  label: Text(s.t('theme_light'))),
              ButtonSegment(
                  value: ThemeMode.dark,
                  icon: const Icon(Icons.dark_mode_outlined),
                  label: Text(s.t('theme_dark'))),
            ],
            selected: {state.themeMode},
            onSelectionChanged: (v) => state.setTheme(v.first),
          ),
          SectionTitle(s.t('language')),
          SegmentedButton<String>(
            segments: const [
              ButtonSegment(value: 'fa', label: Text('فارسی')),
              ButtonSegment(value: 'en', label: Text('English')),
            ],
            selected: {state.locale.languageCode},
            onSelectionChanged: (v) => state.setLocale(v.first),
          ),
          SectionTitle(s.t('about')),
          SoftBox(
            radius: 20,
            depth: 3,
            padding: EdgeInsets.zero,
            child: ListTile(
              leading: const Icon(Icons.info_outline),
              title: Text(s.t('app_name')),
              subtitle: Text(s.t('about_text')),
            ),
          ),
        ],
      ),
    );
  }
}

/// Mini glass scene showing what a style looks like.
class _StylePreview extends StatelessWidget {
  const _StylePreview({
    required this.style,
    required this.brightness,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  final AppStyle style;
  final Brightness brightness;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final g = glassColors(style, brightness);
    final on = g.dark ? Colors.white : const Color(0xFF1E1B2E);
    final r = BorderRadius.circular(20);
    Widget blob(Color c, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [c.withValues(alpha: 0.75), c.withValues(alpha: 0)]),
          ),
        );
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        height: 150,
        decoration: BoxDecoration(
          borderRadius: r,
          border: Border.all(
            color: selected ? g.accent.first : Colors.transparent,
            width: 2.5,
          ),
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(18),
          child: DecoratedBox(
            decoration: BoxDecoration(
              gradient: LinearGradient(
                  colors: g.bg, begin: Alignment.topLeft, end: Alignment.bottomRight),
            ),
            child: Stack(
              children: [
                Positioned(top: -30, right: -30, child: blob(g.blobs[0], 120)),
                Positioned(bottom: -40, left: -30, child: blob(g.blobs[1], 130)),
                Positioned(
                  left: 12,
                  right: 12,
                  top: 14,
                  child: Row(
                    children: [
                      for (final filled in [true, false, false]) ...[
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            gradient: filled ? LinearGradient(colors: g.accent) : null,
                            color: filled ? null : g.tile,
                            border: Border.all(color: g.tileBorder),
                          ),
                        ),
                        const SizedBox(width: 6),
                      ],
                    ],
                  ),
                ),
                Positioned(
                  left: 12,
                  right: 12,
                  bottom: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    decoration: BoxDecoration(
                      color: g.tile,
                      borderRadius: BorderRadius.circular(14),
                      border: Border.all(color: g.tileBorder),
                    ),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(label,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(color: on, fontWeight: FontWeight.w700)),
                        ),
                        Icon(
                          selected ? Icons.check_circle_rounded : Icons.circle_outlined,
                          size: 20,
                          color: selected ? g.accent.first : on.withValues(alpha: 0.4),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
