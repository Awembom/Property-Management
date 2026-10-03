import 'package:flutter/material.dart';
import 'package:rental_app/core/theme/app_colors.dart';

/// The app's look: Poppins, warm off-white background, white rounded cards,
/// orange buttons, filled input fields and a white bottom bar. Every screen
/// picks this up through `Theme.of(context)`, so screens rarely set colours.
class AppTheme {
  AppTheme._();

  static ThemeData lightTheme = _build(Brightness.light);
  static ThemeData darkTheme = _build(Brightness.dark);

  static ThemeData _build(Brightness brightness) {
    final dark = brightness == Brightness.dark;
    final surface = dark ? AppColors.darkSurface : AppColors.surface;
    final line = dark ? AppColors.darkLine : AppColors.line;
    final ink = dark ? Colors.white : AppColors.ink;
    final muted = dark ? const Color(0xFFA3A2A9) : AppColors.muted;

    final colors = ColorScheme.fromSeed(
      seedColor: AppColors.primary,
      brightness: brightness,
    ).copyWith(
      primary: AppColors.primary,
      onPrimary: Colors.white,
      secondary: AppColors.accent,
      surface: surface,
      onSurface: ink,
      onSurfaceVariant: muted,
      outline: line,
      outlineVariant: line,
      surfaceTint: Colors.transparent,
      error: AppColors.overdue,
    );

    final base = ThemeData(useMaterial3: true, brightness: brightness, fontFamily: 'Poppins');
    final text = base.textTheme.apply(bodyColor: ink, displayColor: ink).copyWith(
          headlineMedium: base.textTheme.headlineMedium?.copyWith(fontWeight: FontWeight.w700, color: ink),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(fontWeight: FontWeight.w700, color: ink),
          titleLarge: base.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: ink),
          titleMedium: base.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w600, color: ink),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(color: ink, height: 1.4),
          bodySmall: base.textTheme.bodySmall?.copyWith(color: muted),
        );
    final rounded = BorderRadius.circular(14);

    return base.copyWith(
      colorScheme: colors,
      textTheme: text,
      // Screens and app bars are see-through: every page sits on the
      // GeometricBackdrop (faint shapes on the background colour), added to
      // each route by AppRoute in app_router.dart.
      scaffoldBackgroundColor: Colors.transparent,
      appBarTheme: AppBarTheme(
        centerTitle: true,
        elevation: 0,
        scrolledUnderElevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: ink,
        titleTextStyle: TextStyle(
          fontFamily: 'Poppins',
          fontSize: 18,
          fontWeight: FontWeight.w600,
          color: ink,
        ),
      ),
      cardTheme: CardThemeData(
        elevation: 0,
        surfaceTintColor: Colors.transparent,
        margin: EdgeInsets.zero,
        color: surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(20),
          side: BorderSide(color: line),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(color: line, space: 1),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        hintStyle: TextStyle(color: muted),
        labelStyle: TextStyle(color: muted),
        contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        border: OutlineInputBorder(borderRadius: rounded, borderSide: BorderSide(color: line)),
        enabledBorder: OutlineInputBorder(borderRadius: rounded, borderSide: BorderSide(color: line)),
        disabledBorder: OutlineInputBorder(borderRadius: rounded, borderSide: BorderSide(color: line)),
        focusedBorder: OutlineInputBorder(
          borderRadius: rounded,
          borderSide: const BorderSide(color: AppColors.primary, width: 1.6),
        ),
        errorBorder: OutlineInputBorder(
          borderRadius: rounded,
          borderSide: const BorderSide(color: AppColors.overdue),
        ),
        focusedErrorBorder: OutlineInputBorder(
          borderRadius: rounded,
          borderSide: const BorderSide(color: AppColors.overdue, width: 1.6),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          backgroundColor: AppColors.primary,
          foregroundColor: Colors.white,
          minimumSize: const Size(64, 54),
          shape: RoundedRectangleBorder(borderRadius: rounded),
          textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          foregroundColor: ink,
          minimumSize: const Size(64, 54),
          side: BorderSide(color: line),
          backgroundColor: surface,
          shape: RoundedRectangleBorder(borderRadius: rounded),
          textStyle: const TextStyle(fontFamily: 'Poppins', fontSize: 15, fontWeight: FontWeight.w600),
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          foregroundColor: AppColors.primary,
          textStyle: const TextStyle(fontFamily: 'Poppins', fontWeight: FontWeight.w600),
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: AppColors.primary,
        foregroundColor: Colors.white,
        // Flat, like the rest of the design (no dark shadow ring).
        elevation: 0,
        focusElevation: 0,
        hoverElevation: 0,
        highlightElevation: 0,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: AppColors.soft(AppColors.primary),
        side: BorderSide(color: line),
        labelStyle: TextStyle(fontFamily: 'Poppins', color: ink, fontWeight: FontWeight.w500),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        showCheckmark: false,
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          backgroundColor: surface,
          selectedBackgroundColor: AppColors.soft(AppColors.primary),
          selectedForegroundColor: AppColors.primaryDark,
          side: BorderSide(color: line),
        ),
      ),
      navigationBarTheme: NavigationBarThemeData(
        backgroundColor: surface,
        elevation: 0,
        height: 68,
        indicatorColor: AppColors.soft(AppColors.primary),
        labelTextStyle: WidgetStateProperty.resolveWith(
          (states) => TextStyle(
            fontFamily: 'Poppins',
            fontSize: 12,
            fontWeight: states.contains(WidgetState.selected) ? FontWeight.w600 : FontWeight.w500,
            color: states.contains(WidgetState.selected) ? AppColors.primary : muted,
          ),
        ),
        iconTheme: WidgetStateProperty.resolveWith(
          (states) => IconThemeData(
            color: states.contains(WidgetState.selected) ? AppColors.primary : muted,
          ),
        ),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: AppColors.primary,
        unselectedLabelColor: muted,
        indicatorColor: AppColors.primary,
        dividerColor: line,
      ),
      checkboxTheme: CheckboxThemeData(
        fillColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primary : null,
        ),
      ),
      switchTheme: SwitchThemeData(
        trackColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primary : line,
        ),
        thumbColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? Colors.white : muted,
        ),
        trackOutlineColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected) ? AppColors.primary : muted,
        ),
      ),
      progressIndicatorTheme: const ProgressIndicatorThemeData(color: AppColors.primary),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        backgroundColor: dark ? AppColors.darkSurface : AppColors.ink,
        contentTextStyle: const TextStyle(fontFamily: 'Poppins', color: Colors.white),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      ),
      listTileTheme: ListTileThemeData(iconColor: muted),
    );
  }
}
