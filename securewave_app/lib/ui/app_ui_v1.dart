import 'package:flutter/material.dart';

class AppUIv1 {
  static const background = Color(0xFF050B14);
  static const surface = Color(0xFF0A1524);
  static const surfaceMuted = Color(0xFF0F1E30);
  static const surfaceRaised = Color(0xFF14273D);
  static const graphite = Color(0xFFF7FAFC);
  static const graphiteMuted = Color(0xFFA9BDD0);
  static const graphiteSubtle = Color(0xFF7F97AD);
  static const line = Color(0xFF263C53);
  static const lineStrong = Color(0xFF3B5C7A);
  static const primary = Color(0xFF236FDC);
  static const primaryHover = Color(0xFF1F6FD8);
  static const primaryPressed = Color(0xFF195CBD);
  static const primarySoft = Color(0xFF102E52);
  static const cyan = Color(0xFF35D0E5);
  static const cyanSoft = Color(0xFF0C3340);
  static const focus = Color(0xFF78DEFF);
  static const amber = Color(0xFFF2B84B);
  static const amberSoft = Color(0xFF33280E);
  static const red = Color(0xFFFF6B6B);
  static const redSoft = Color(0xFF35171B);
  static const disabled = Color(0xFF52687C);

  static const radius = 10.0;
  static const radiusSmall = 8.0;
  static const maxWidth = 1160.0;
  static const contentMaxWidth = 760.0;
  static const mobileMax = 760.0;
  static const mobilePadding = 16.0;
  static const desktopPadding = 28.0;

  static const panelShadow = BoxShadow(
    color: Color(0x52000000),
    blurRadius: 8,
    offset: Offset(0, 2),
  );

  static const accentGlow = BoxShadow(
    color: Color(0x2435D0E5),
    blurRadius: 8,
  );

  static ThemeData get theme {
    const scheme = ColorScheme.dark(
      primary: primary,
      onPrimary: Colors.white,
      primaryContainer: primarySoft,
      onPrimaryContainer: graphite,
      secondary: cyan,
      onSecondary: background,
      secondaryContainer: cyanSoft,
      onSecondaryContainer: graphite,
      error: red,
      onError: background,
      errorContainer: redSoft,
      onErrorContainer: graphite,
      surface: surface,
      onSurface: graphite,
      surfaceContainerHighest: surfaceRaised,
      onSurfaceVariant: graphiteMuted,
      outline: lineStrong,
      outlineVariant: line,
      shadow: Colors.black,
      scrim: Color(0xB3000000),
    );

    final baseTextTheme = ThemeData.dark(useMaterial3: true).textTheme;
    final textTheme = baseTextTheme.copyWith(
      headlineLarge: const TextStyle(
        fontSize: 30,
        height: 1.15,
        fontWeight: FontWeight.w700,
        color: graphite,
      ),
      headlineMedium: const TextStyle(
        fontSize: 25,
        height: 1.18,
        fontWeight: FontWeight.w700,
        color: graphite,
      ),
      headlineSmall: const TextStyle(
        fontSize: 21,
        height: 1.22,
        fontWeight: FontWeight.w700,
        color: graphite,
      ),
      titleLarge: const TextStyle(
        fontSize: 19,
        height: 1.28,
        fontWeight: FontWeight.w700,
        color: graphite,
      ),
      titleMedium: const TextStyle(
        fontSize: 16,
        height: 1.32,
        fontWeight: FontWeight.w700,
        color: graphite,
      ),
      titleSmall: const TextStyle(
        fontSize: 14,
        height: 1.3,
        fontWeight: FontWeight.w600,
        color: graphite,
      ),
      bodyLarge: const TextStyle(
        fontSize: 16,
        height: 1.45,
        color: graphite,
      ),
      bodyMedium: const TextStyle(
        fontSize: 14,
        height: 1.42,
        color: graphiteMuted,
      ),
      bodySmall: const TextStyle(
        fontSize: 12.5,
        height: 1.38,
        color: graphiteMuted,
      ),
      labelLarge: const TextStyle(
        fontSize: 14,
        height: 1.2,
        fontWeight: FontWeight.w700,
        color: graphite,
      ),
      labelMedium: const TextStyle(
        fontSize: 12.5,
        height: 1.2,
        fontWeight: FontWeight.w600,
        color: graphiteMuted,
      ),
    );

    return ThemeData(
      useMaterial3: true,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      canvasColor: background,
      disabledColor: disabled,
      focusColor: focus.withValues(alpha: 0.18),
      hoverColor: primary.withValues(alpha: 0.10),
      highlightColor: primary.withValues(alpha: 0.14),
      splashFactory: InkSparkle.splashFactory,
      textTheme: textTheme,
      primaryTextTheme: textTheme,
      iconTheme: const IconThemeData(color: graphiteMuted, size: 20),
      dividerTheme: const DividerThemeData(color: line, thickness: 1),
      textSelectionTheme: const TextSelectionThemeData(
        cursorColor: cyan,
        selectionColor: primarySoft,
        selectionHandleColor: cyan,
      ),
      appBarTheme: const AppBarTheme(
        centerTitle: false,
        elevation: 0,
        scrolledUnderElevation: 0,
        toolbarHeight: 68,
        backgroundColor: surface,
        foregroundColor: graphite,
        surfaceTintColor: Colors.transparent,
        shape: Border(bottom: BorderSide(color: line)),
      ),
      cardTheme: const CardThemeData(
        color: surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(radius)),
          side: BorderSide(color: line),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 46)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 18, vertical: 12),
          ),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return surfaceRaised;
            if (states.contains(WidgetState.pressed)) return primaryPressed;
            if (states.contains(WidgetState.hovered)) return primaryHover;
            return primary;
          }),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return graphiteSubtle;
            return Colors.white;
          }),
          overlayColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.focused)) {
              return focus.withValues(alpha: 0.18);
            }
            if (states.contains(WidgetState.pressed)) {
              return Colors.white.withValues(alpha: 0.08);
            }
            return null;
          }),
          elevation: const WidgetStatePropertyAll(0),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSmall),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 44)),
          padding: const WidgetStatePropertyAll(
            EdgeInsets.symmetric(horizontal: 16, vertical: 11),
          ),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return graphiteSubtle;
            if (states.contains(WidgetState.hovered)) return Colors.white;
            return graphite;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return primarySoft;
            if (states.contains(WidgetState.hovered)) return surfaceRaised;
            return Colors.transparent;
          }),
          side: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) {
              return const BorderSide(color: line);
            }
            if (states.contains(WidgetState.focused)) {
              return const BorderSide(color: focus, width: 2);
            }
            return const BorderSide(color: lineStrong);
          }),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSmall),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: ButtonStyle(
          minimumSize: const WidgetStatePropertyAll(Size(0, 40)),
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return graphiteSubtle;
            if (states.contains(WidgetState.hovered)) return focus;
            return cyan;
          }),
          overlayColor: WidgetStatePropertyAll(
            primary.withValues(alpha: 0.10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSmall),
            ),
          ),
          textStyle: const WidgetStatePropertyAll(
            TextStyle(fontWeight: FontWeight.w700),
          ),
        ),
      ),
      iconButtonTheme: IconButtonThemeData(
        style: ButtonStyle(
          foregroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.disabled)) return graphiteSubtle;
            if (states.contains(WidgetState.hovered)) return Colors.white;
            return graphiteMuted;
          }),
          backgroundColor: WidgetStateProperty.resolveWith((states) {
            if (states.contains(WidgetState.pressed)) return primarySoft;
            if (states.contains(WidgetState.hovered)) return surfaceRaised;
            return Colors.transparent;
          }),
          overlayColor: WidgetStatePropertyAll(
            primary.withValues(alpha: 0.10),
          ),
          shape: WidgetStatePropertyAll(
            RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(radiusSmall),
            ),
          ),
        ),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surfaceMuted,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
        labelStyle: const TextStyle(color: graphiteMuted),
        floatingLabelStyle: const TextStyle(color: focus),
        hintStyle: const TextStyle(color: graphiteSubtle),
        errorStyle: const TextStyle(color: red),
        border: _inputBorder(line),
        enabledBorder: _inputBorder(line),
        disabledBorder: _inputBorder(line),
        focusedBorder: _inputBorder(focus, width: 2),
        errorBorder: _inputBorder(red),
        focusedErrorBorder: _inputBorder(red, width: 2),
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 68,
        elevation: 0,
        backgroundColor: surface,
        surfaceTintColor: Colors.transparent,
        indicatorColor: primarySoft,
        shadowColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        iconTheme: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const IconThemeData(color: cyan, size: 22);
          }
          return const IconThemeData(color: graphiteMuted, size: 22);
        }),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          if (states.contains(WidgetState.selected)) {
            return const TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w700,
              color: graphite,
            );
          }
          return const TextStyle(fontSize: 12, color: graphiteMuted);
        }),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(
        color: cyan,
        circularTrackColor: surfaceRaised,
        linearTrackColor: surfaceRaised,
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surfaceMuted,
        disabledColor: surfaceMuted,
        selectedColor: primarySoft,
        secondarySelectedColor: cyanSoft,
        side: const BorderSide(color: line),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        labelStyle: const TextStyle(
          color: graphite,
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
        ),
        secondaryLabelStyle: const TextStyle(color: graphite),
        brightness: Brightness.dark,
        padding: const EdgeInsets.symmetric(horizontal: 8),
      ),
      tooltipTheme: TooltipThemeData(
        decoration: BoxDecoration(
          color: surfaceRaised,
          border: Border.all(color: lineStrong),
          borderRadius: BorderRadius.circular(radiusSmall),
        ),
        textStyle: const TextStyle(color: graphite, fontSize: 12.5),
      ),
      scrollbarTheme: const ScrollbarThemeData(
        thumbColor: WidgetStatePropertyAll(lineStrong),
        trackColor: WidgetStatePropertyAll(surfaceMuted),
        radius: Radius.circular(4),
        thickness: WidgetStatePropertyAll(6),
      ),
      snackBarTheme: const SnackBarThemeData(
        backgroundColor: surfaceRaised,
        contentTextStyle: TextStyle(color: graphite),
        actionTextColor: cyan,
        behavior: SnackBarBehavior.floating,
        elevation: 2,
      ),
    );
  }

  static OutlineInputBorder _inputBorder(Color color, {double width = 1}) {
    return OutlineInputBorder(
      borderRadius: BorderRadius.circular(radiusSmall),
      borderSide: BorderSide(color: color, width: width),
    );
  }
}

enum AppStatusTone { neutral, info, success, warning, error }

enum AppNoticeTone { info, warning, error }

enum AppStateTone { loading, empty, warning, error }

class AppPanel extends StatelessWidget {
  const AppPanel({
    required this.child,
    super.key,
    this.padding = const EdgeInsets.all(18),
    this.color = AppUIv1.surface,
    this.showShadow = true,
  });

  final Widget child;
  final EdgeInsets padding;
  final Color color;
  final bool showShadow;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: color,
        border: Border.all(color: AppUIv1.line),
        borderRadius: BorderRadius.circular(AppUIv1.radius),
        boxShadow: showShadow ? const [AppUIv1.panelShadow] : null,
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}

class AppStatusChip extends StatelessWidget {
  const AppStatusChip({
    required this.label,
    super.key,
    this.tone = AppStatusTone.neutral,
  });

  final String label;
  final AppStatusTone tone;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, border) = switch (tone) {
      AppStatusTone.neutral => (
          AppUIv1.graphiteMuted,
          AppUIv1.surfaceMuted,
          AppUIv1.line,
        ),
      AppStatusTone.info => (
          AppUIv1.focus,
          AppUIv1.primarySoft,
          AppUIv1.lineStrong,
        ),
      AppStatusTone.success => (
          AppUIv1.cyan,
          AppUIv1.cyanSoft,
          AppUIv1.cyan,
        ),
      AppStatusTone.warning => (
          AppUIv1.amber,
          AppUIv1.amberSoft,
          AppUIv1.amber,
        ),
      AppStatusTone.error => (
          AppUIv1.red,
          AppUIv1.redSoft,
          AppUIv1.red,
        ),
    };
    return Semantics(
      label: 'Status: $label',
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 5),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: border),
          borderRadius: BorderRadius.circular(AppUIv1.radiusSmall),
        ),
        child: Text(
          label,
          style: Theme.of(context).textTheme.labelMedium?.copyWith(
                color: foreground,
                fontWeight: FontWeight.w700,
              ),
        ),
      ),
    );
  }
}

class AppInlineNotice extends StatelessWidget {
  const AppInlineNotice({
    required this.text,
    super.key,
    this.tone = AppNoticeTone.info,
  });

  final String text;
  final AppNoticeTone tone;

  @override
  Widget build(BuildContext context) {
    final (foreground, background, icon) = switch (tone) {
      AppNoticeTone.info => (
          AppUIv1.focus,
          AppUIv1.primarySoft,
          Icons.info_outline_rounded,
        ),
      AppNoticeTone.warning => (
          AppUIv1.amber,
          AppUIv1.amberSoft,
          Icons.warning_amber_rounded,
        ),
      AppNoticeTone.error => (
          AppUIv1.red,
          AppUIv1.redSoft,
          Icons.error_outline_rounded,
        ),
    };
    return Semantics(
      liveRegion: tone == AppNoticeTone.error,
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: background,
          border: Border.all(color: foreground),
          borderRadius: BorderRadius.circular(AppUIv1.radiusSmall),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(icon, color: foreground, size: 18),
            const SizedBox(width: 9),
            Expanded(
              child: Text(
                text,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                      color: foreground,
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AppProgressIndicator extends StatelessWidget {
  const AppProgressIndicator({super.key, this.label = 'Loading'});

  final String label;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: label,
      value: 'In progress',
      child: const SizedBox(
        width: 20,
        height: 20,
        child: CircularProgressIndicator(strokeWidth: 2),
      ),
    );
  }
}

class AppStatePanel extends StatelessWidget {
  const AppStatePanel({
    required this.title,
    required this.message,
    required this.tone,
    super.key,
  });

  final String title;
  final String message;
  final AppStateTone tone;

  @override
  Widget build(BuildContext context) {
    final (icon, color) = switch (tone) {
      AppStateTone.loading => (Icons.sync_rounded, AppUIv1.cyan),
      AppStateTone.empty => (Icons.inbox_outlined, AppUIv1.graphiteMuted),
      AppStateTone.warning => (Icons.warning_amber_rounded, AppUIv1.amber),
      AppStateTone.error => (Icons.error_outline_rounded, AppUIv1.red),
    };
    return AppPanel(
      showShadow: false,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (tone == AppStateTone.loading)
            const AppProgressIndicator()
          else
            Icon(icon, color: color, size: 20),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(title, style: Theme.of(context).textTheme.titleMedium),
                const SizedBox(height: 4),
                Text(message, style: Theme.of(context).textTheme.bodyMedium),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
