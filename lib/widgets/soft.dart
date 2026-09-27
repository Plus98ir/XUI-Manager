import 'package:flutter/material.dart';

import '../models/models.dart';
import '../theme.dart';

List<BoxShadow> softShadow(BuildContext context, {double depth = 6}) {
  final g = SoftColors.of(context);
  return [
    BoxShadow(color: g.shadow, offset: Offset(0, depth * 0.8), blurRadius: depth * 3.2),
  ];
}

/// Frosted glass surface: translucent fill, hairline light border and a
/// faint top highlight.
class SoftBox extends StatelessWidget {
  const SoftBox({
    super.key,
    required this.child,
    this.radius = 24,
    this.padding = const EdgeInsets.all(16),
    this.onTap,
    this.onLongPress,
    this.color,
    this.depth = 6,
  });

  final Widget child;
  final double radius;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final VoidCallback? onLongPress;
  final Color? color;
  final double depth;

  @override
  Widget build(BuildContext context) {
    final g = SoftColors.of(context);
    final r = BorderRadius.circular(radius);
    final fill = color ?? g.tile;
    return Container(
      decoration: BoxDecoration(
        borderRadius: r,
        gradient: LinearGradient(
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
          colors: [
            Color.lerp(fill, Colors.white, g.dark ? 0.05 : 0.25)!,
            fill,
          ],
        ),
        border: Border.all(color: g.tileBorder),
        boxShadow: depth <= 0 ? null : softShadow(context, depth: depth),
      ),
      child: Material(
        type: MaterialType.transparency,
        child: InkWell(
          borderRadius: r,
          onTap: onTap,
          onLongPress: onLongPress,
          child: Padding(padding: padding, child: child),
        ),
      ),
    );
  }
}

class GradientIcon extends StatelessWidget {
  const GradientIcon(this.icon, {super.key, required this.colors, this.size = 30});

  final IconData icon;
  final List<Color> colors;
  final double size;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ).createShader(r),
        child: Icon(icon, size: size, color: Colors.white),
      );
}

/// Small line icon in a tinted glass circle. With [filled] the circle takes
/// the accent gradient (used for the highlighted action).
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.size = 40, this.filled = false});

  final IconData icon;
  final Color? color;
  final double size;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final g = SoftColors.of(context);
    final c = color ?? Theme.of(context).colorScheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: filled
            ? LinearGradient(
                colors: g.accent, begin: Alignment.topLeft, end: Alignment.bottomRight)
            : null,
        color: filled ? null : c.withValues(alpha: g.dark ? 0.16 : 0.13),
        border: filled ? null : Border.all(color: c.withValues(alpha: 0.28)),
        boxShadow: filled
            ? [BoxShadow(color: g.accent.last.withValues(alpha: 0.4), blurRadius: 12, offset: const Offset(0, 4))]
            : null,
      ),
      child: Icon(icon, size: size * 0.52, color: filled ? Colors.white : c),
    );
  }
}

/// Compact action tile: small icon, label and a caption.
class ActionTile extends StatelessWidget {
  const ActionTile({
    super.key,
    required this.icon,
    required this.label,
    this.color,
    this.caption,
    this.onTap,
    this.busy = false,
    this.filled = false,
  });

  final IconData icon;
  final Color? color;
  final String label;
  final String? caption;
  final VoidCallback? onTap;
  final bool busy;
  final bool filled;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SoftBox(
      radius: 22,
      depth: 3,
      padding: const EdgeInsets.fromLTRB(6, 10, 6, 8),
      onTap: busy ? null : onTap,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          busy
              ? const SizedBox.square(
                  dimension: 40,
                  child: Padding(
                    padding: EdgeInsets.all(10),
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  ))
              : IconBadge(icon: icon, color: color, filled: filled),
          const Spacer(),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              textAlign: TextAlign.center,
              style: theme.textTheme.labelLarge?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          Text(
            caption ?? '',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: theme.textTheme.labelSmall?.copyWith(color: SoftColors.of(context).muted),
          ),
        ],
      ),
    );
  }
}

/// Header area. The glass backdrop is painted by the route, so this only
/// keeps the old API for screens that wrap their header in it.
class HeroBackground extends StatelessWidget {
  const HeroBackground({super.key, required this.child, this.depth = 56});

  final Widget child;
  final double depth;

  @override
  Widget build(BuildContext context) => child;
}

List<Color> panelTypeColors(PanelType type) => switch (type) {
      PanelType.threeXui => const [Color(0xFF34E3B0), Color(0xFF0E9F74)],
      PanelType.alireza => const [Color(0xFFA78BFA), Color(0xFF6D28D9)],
      PanelType.marzban => const [Color(0xFF60A5FA), Color(0xFF1D4ED8)],
    };

class PanelTypeAvatar extends StatelessWidget {
  const PanelTypeAvatar({super.key, required this.type, this.size = 46});

  final PanelType type;
  final double size;

  @override
  Widget build(BuildContext context) {
    final text = switch (type) {
      PanelType.threeXui => '3X',
      PanelType.alireza => 'AX',
      PanelType.marzban => 'MZ',
    };
    final colors = panelTypeColors(type);
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.32),
        gradient: LinearGradient(
          colors: colors,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
        boxShadow: [
          BoxShadow(
              color: colors.last.withValues(alpha: 0.4), blurRadius: 10, offset: const Offset(0, 4)),
        ],
      ),
      alignment: Alignment.center,
      child: Text(text,
          style: TextStyle(
              color: Colors.white, fontWeight: FontWeight.w800, fontSize: size * 0.34)),
    );
  }
}

/// Small labelled progress bar used on dark headers.
class MiniBar extends StatelessWidget {
  const MiniBar({super.key, required this.label, required this.value, required this.text});

  final String label;
  final double? value;
  final String text;

  @override
  Widget build(BuildContext context) {
    final v = value?.clamp(0.0, 1.0).toDouble();
    final g = SoftColors.of(context);
    final on = Theme.of(context).colorScheme.onSurface;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Text(label, style: TextStyle(color: g.muted, fontSize: 12)),
            const Spacer(),
            Text(text,
                textDirection: TextDirection.ltr,
                style: TextStyle(color: on, fontSize: 12, fontWeight: FontWeight.w700)),
          ],
        ),
        const SizedBox(height: 4),
        ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: LinearProgressIndicator(
            value: v ?? 0,
            minHeight: 5,
            backgroundColor: on.withValues(alpha: 0.1),
            color: v == null ? on.withValues(alpha: 0.2) : (v >= 0.9 ? badColor : v >= 0.7 ? warnColor : g.accent.first),
          ),
        ),
      ],
    );
  }
}

/// Round frosted icon button for page headers.
class GlassIconButton extends StatelessWidget {
  const GlassIconButton({super.key, required this.icon, required this.onPressed, this.tooltip});

  final IconData icon;
  final VoidCallback onPressed;
  final String? tooltip;

  @override
  Widget build(BuildContext context) {
    final g = SoftColors.of(context);
    return Tooltip(
      message: tooltip ?? '',
      child: Material(
        color: g.tile,
        shape: CircleBorder(side: BorderSide(color: g.tileBorder)),
        child: InkWell(
          customBorder: const CircleBorder(),
          onTap: onPressed,
          child: SizedBox.square(
            dimension: 42,
            child: Icon(icon, size: 20, color: Theme.of(context).colorScheme.onSurface),
          ),
        ),
      ),
    );
  }
}
