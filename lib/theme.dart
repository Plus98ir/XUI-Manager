import 'package:flutter/material.dart';

import 'models/models.dart';

/// The two glass looks the user can pick; each has a light and a dark variant.
enum AppStyle { aurora, frost }

/// Glass colors that Material doesn't cover.
class SoftColors extends ThemeExtension<SoftColors> {
  const SoftColors({
    required this.dark,
    required this.bg,
    required this.blobs,
    required this.tile,
    required this.tileBorder,
    required this.accent,
    required this.muted,
    required this.shadow,
  });

  final bool dark;

  /// Page background gradient (top-left → bottom-right).
  final List<Color> bg;

  /// Soft colored lights floating behind the glass.
  final List<Color> blobs;

  /// Frosted surface fill and its hairline border.
  final Color tile;
  final Color tileBorder;

  /// Two-stop gradient for highlighted things (buttons, active chips).
  final List<Color> accent;
  final Color muted;
  final Color shadow;

  Color get heroTop => accent.first;
  Color get heroBottom => accent.last;

  static SoftColors of(BuildContext context) => Theme.of(context).extension<SoftColors>()!;

  @override
  SoftColors copyWith() => this;

  @override
  SoftColors lerp(ThemeExtension<SoftColors>? other, double t) =>
      other is SoftColors && t >= 0.5 ? other : this;
}

// Warm dusk glass: violet night with orange / pink lights.
const _auroraDark = SoftColors(
  dark: true,
  bg: [Color(0xFF1C1433), Color(0xFF261A47), Color(0xFF140E27)],
  blobs: [Color(0xFFFF7A45), Color(0xFFFF3D8B), Color(0xFF7C4DFF)],
  tile: Color(0x17FFFFFF),
  tileBorder: Color(0x26FFFFFF),
  accent: [Color(0xFFFFA24C), Color(0xFFFF4D8D)],
  muted: Color(0xFFB4A9D2),
  shadow: Color(0x40000000),
);

// Warm daylight glass: cream with peach / pink / lavender lights.
const _auroraLight = SoftColors(
  dark: false,
  bg: [Color(0xFFFBF0E8), Color(0xFFF5E6F0), Color(0xFFECE6FA)],
  blobs: [Color(0xFFFFB085), Color(0xFFFF8FB8), Color(0xFFB9A3FF)],
  tile: Color(0x8CFFFFFF),
  tileBorder: Color(0xD9FFFFFF),
  accent: [Color(0xFFFF8A4C), Color(0xFFEC407A)],
  muted: Color(0xFF8C7A8E),
  shadow: Color(0x1F7A4A6A),
);

// Cool daylight glass: ice white with sky / indigo lights.
const _frostLight = SoftColors(
  dark: false,
  bg: [Color(0xFFEDF3FC), Color(0xFFE5ECF9), Color(0xFFF3F6FC)],
  blobs: [Color(0xFF4FC3F7), Color(0xFF6C7BFF), Color(0xFFA5C8FF)],
  tile: Color(0x99FFFFFF),
  tileBorder: Color(0xE6FFFFFF),
  accent: [Color(0xFF38BDF8), Color(0xFF4F6BFF)],
  muted: Color(0xFF7886A3),
  shadow: Color(0x1F3A5A9A),
);

// Cool night glass: deep navy with cyan / blue lights.
const _frostDark = SoftColors(
  dark: true,
  bg: [Color(0xFF0B1629), Color(0xFF10223D), Color(0xFF091120)],
  blobs: [Color(0xFF1E88E5), Color(0xFF22D3EE), Color(0xFF6366F1)],
  tile: Color(0x14FFFFFF),
  tileBorder: Color(0x24FFFFFF),
  accent: [Color(0xFF38BDF8), Color(0xFF6366F1)],
  muted: Color(0xFF93A4C3),
  shadow: Color(0x40000000),
);

SoftColors glassColors(AppStyle style, Brightness b) => switch ((style, b)) {
      (AppStyle.aurora, Brightness.dark) => _auroraDark,
      (AppStyle.aurora, Brightness.light) => _auroraLight,
      (AppStyle.frost, Brightness.dark) => _frostDark,
      (AppStyle.frost, Brightness.light) => _frostLight,
    };

const brandGreen = Color(0xFF1FD39A);

ThemeData buildTheme(Brightness brightness, [AppStyle style = AppStyle.aurora]) {
  final dark = brightness == Brightness.dark;
  final g = glassColors(style, brightness);
  final primary = dark ? g.accent.first : Color.lerp(g.accent.first, g.accent.last, 0.35)!;
  final base = ColorScheme.fromSeed(seedColor: g.accent.last, brightness: brightness);
  final onSurface = dark ? const Color(0xFFF3F1FA) : const Color(0xFF1E1B2E);
  final scheme = base.copyWith(
    primary: primary,
    onPrimary: dark ? const Color(0xFF1A1030) : Colors.white,
    secondary: g.accent.last,
    surface: Color.lerp(g.bg[1], dark ? Colors.black : Colors.white, 0.08),
    onSurface: onSurface,
    onSurfaceVariant: g.muted,
    surfaceContainerLow: g.tile,
    surfaceContainerHighest:
        dark ? Colors.white.withValues(alpha: 0.12) : Colors.black.withValues(alpha: 0.07),
    outline: g.muted,
    outlineVariant: g.tileBorder,
  );
  // Sheets and dialogs sit above the glass, so they need a solid color.
  final solid = Color.lerp(g.bg[1], dark ? Colors.black : Colors.white, dark ? 0.15 : 0.55)!;
  final fieldBorder = dark ? const Color(0x33FFFFFF) : g.muted.withValues(alpha: 0.35);
  OutlineInputBorder border(Color c, [double w = 1]) => OutlineInputBorder(
      borderRadius: BorderRadius.circular(14), borderSide: BorderSide(color: c, width: w));

  return ThemeData(
    useMaterial3: true,
    brightness: brightness,
    colorScheme: scheme,
    fontFamily: 'Vazirmatn',
    scaffoldBackgroundColor: Colors.transparent,
    canvasColor: solid,
    extensions: [g],
    pageTransitionsTheme: const PageTransitionsTheme(builders: {
      TargetPlatform.android: GlassPageTransitions(ZoomPageTransitionsBuilder()),
      TargetPlatform.iOS: GlassPageTransitions(ZoomPageTransitionsBuilder()),
      TargetPlatform.linux: GlassPageTransitions(ZoomPageTransitionsBuilder()),
      TargetPlatform.macOS: GlassPageTransitions(ZoomPageTransitionsBuilder()),
      TargetPlatform.windows: GlassPageTransitions(ZoomPageTransitionsBuilder()),
      TargetPlatform.fuchsia: GlassPageTransitions(ZoomPageTransitionsBuilder()),
    }),
    appBarTheme: AppBarTheme(
      backgroundColor: Colors.transparent,
      foregroundColor: onSurface,
      surfaceTintColor: Colors.transparent,
      centerTitle: true,
      elevation: 0,
      scrolledUnderElevation: 0,
      titleTextStyle: TextStyle(
          fontFamily: 'Vazirmatn', fontSize: 18, fontWeight: FontWeight.w700, color: onSurface),
    ),
    cardTheme: CardThemeData(
      color: g.tile,
      elevation: 0,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(22),
        side: BorderSide(color: g.tileBorder),
      ),
    ),
    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      // Clearly framed so empty fields still read as "type here".
      fillColor: dark ? const Color(0x14FFFFFF) : const Color(0xB3FFFFFF),
      hintStyle: TextStyle(color: g.muted.withValues(alpha: 0.8)),
      border: border(fieldBorder),
      enabledBorder: border(fieldBorder),
      disabledBorder: border(fieldBorder.withValues(alpha: 0.15)),
      focusedBorder: border(primary, 1.6),
    ),
    filledButtonTheme: FilledButtonThemeData(
      style: FilledButton.styleFrom(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      ),
    ),
    floatingActionButtonTheme: FloatingActionButtonThemeData(
      backgroundColor: primary,
      foregroundColor: scheme.onPrimary,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
    ),
    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: solid,
      surfaceTintColor: Colors.transparent,
    ),
    dialogTheme: DialogThemeData(backgroundColor: solid, surfaceTintColor: Colors.transparent),
    popupMenuTheme: PopupMenuThemeData(color: solid, surfaceTintColor: Colors.transparent),
    dividerTheme: DividerThemeData(color: g.tileBorder),
  );
}

/// Paints the glass backdrop behind every pushed page, then runs the
/// platform transition, so each route is opaque during animations.
class GlassPageTransitions extends PageTransitionsBuilder {
  const GlassPageTransitions(this.inner);

  final PageTransitionsBuilder inner;

  @override
  Widget buildTransitions<T>(PageRoute<T> route, BuildContext context, Animation<double> animation,
          Animation<double> secondaryAnimation, Widget child) =>
      inner.buildTransitions(
          route, context, animation, secondaryAnimation, GlassBackdrop(child: child));
}

/// Gradient page background with blurred colored lights, like frosted glass
/// floating over a softly lit scene.
class GlassBackdrop extends StatelessWidget {
  const GlassBackdrop({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    final g = SoftColors.of(context);
    final a = g.dark ? 0.42 : 0.5;
    Widget blob(Color c, double size) => Container(
          width: size,
          height: size,
          decoration: BoxDecoration(
            shape: BoxShape.circle,
            gradient: RadialGradient(colors: [
              c.withValues(alpha: a),
              c.withValues(alpha: a * 0.35),
              c.withValues(alpha: 0),
            ], stops: const [0, 0.5, 1]),
          ),
        );
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: g.bg,
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Stack(
        fit: StackFit.expand,
        children: [
          Positioned(top: -120, right: -110, child: blob(g.blobs[0], 360)),
          Positioned(top: 260, left: -150, child: blob(g.blobs[2], 380)),
          Positioned(bottom: -140, right: -90, child: blob(g.blobs[1], 400)),
          child,
        ],
      ),
    );
  }
}

const okColor = Color(0xFF22C55E);
const warnColor = Color(0xFFF59E0B);
const badColor = Color(0xFFEF4444);

Color statusColor(UserStatus s) => switch (s) {
      UserStatus.active => okColor,
      UserStatus.disabled => Colors.grey,
      UserStatus.expired => badColor,
      UserStatus.limited => warnColor,
      UserStatus.onHold => const Color(0xFF3B82F6),
    };

/// Green → amber → red as the fraction grows.
Color usageColor(double? v) {
  if (v == null) return okColor;
  if (v >= 0.9) return badColor;
  if (v >= 0.7) return warnColor;
  return okColor;
}
