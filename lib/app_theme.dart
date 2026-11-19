import 'package:flutter/material.dart';

/// One compact system for every route, nested form, dialog and admin page.
class AppTheme {
  static ThemeData build(Brightness brightness, {bool desktop = false}) {
    final dark = brightness == Brightness.dark;
    final seeded = ColorScheme.fromSeed(
      seedColor: const Color(0xFF00B98F),
      brightness: brightness,
    );
    final colors = dark
        ? (desktop
              ? seeded.copyWith(
                  primary: const Color(0xFF75DFC5),
                  primaryContainer: const Color(0xFF194E47),
                  onPrimaryContainer: const Color(0xFFD5FFF3),
                  surface: const Color(0xFF172638),
                  onSurface: const Color(0xFFE6EDF8),
                  secondary: const Color(0xFFAAC5F5),
                  outlineVariant: const Color(0xFF35485E),
                )
              : seeded)
        : seeded.copyWith(
            primary: const Color(0xFF007C65),
            onPrimary: Colors.white,
            primaryContainer: const Color(0xFFDFF9F0),
            onPrimaryContainer: const Color(0xFF10265B),
            secondary: const Color(0xFF10265B),
            onSurface: const Color(0xFF14233D),
            surface: Colors.white,
            outlineVariant: const Color(0xFFBED0E9),
          );
    final base = ThemeData(useMaterial3: true, colorScheme: colors);
    const shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(12)),
    );
    final text = base.textTheme
        .copyWith(
          headlineLarge: base.textTheme.headlineLarge?.copyWith(
            fontSize: 24,
            fontWeight: FontWeight.w600,
          ),
          headlineMedium: base.textTheme.headlineMedium?.copyWith(
            fontSize: 22,
            fontWeight: FontWeight.w600,
          ),
          headlineSmall: base.textTheme.headlineSmall?.copyWith(
            fontSize: 20,
            fontWeight: FontWeight.w600,
          ),
          titleLarge: base.textTheme.titleLarge?.copyWith(
            fontSize: 18,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
          titleMedium: base.textTheme.titleMedium?.copyWith(
            fontSize: 14,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          titleSmall: base.textTheme.titleSmall?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            height: 1.4,
          ),
          bodyLarge: base.textTheme.bodyLarge?.copyWith(
            fontSize: 14,
            height: 1.5,
          ),
          bodyMedium: base.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            height: 1.5,
          ),
          bodySmall: base.textTheme.bodySmall?.copyWith(
            fontSize: 12,
            height: 1.45,
          ),
          labelLarge: base.textTheme.labelLarge?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.w600,
          ),
          labelMedium: base.textTheme.labelMedium?.copyWith(fontSize: 12),
          labelSmall: base.textTheme.labelSmall?.copyWith(
            fontSize: 11,
            height: 1.4,
          ),
        )
        .apply(
          fontSizeFactor: 1,
          fontFamily: desktop ? 'Segoe UI' : null,
          fontFamilyFallback: desktop ? const ['Myanmar Text'] : null,
        );
    final result = base.copyWith(
      scaffoldBackgroundColor: dark
          ? const Color(0xFF111C20)
          : const Color(0xFFF6F8FB),
      textTheme: text,
      appBarTheme: AppBarTheme(
        backgroundColor: dark ? colors.surface : const Color(0xFF21CDAA),
        foregroundColor: colors.onSurface,
        elevation: 0,
        scrolledUnderElevation: 1,
        centerTitle: false,
        toolbarHeight: 56,
        titleTextStyle: text.titleMedium?.copyWith(
          fontSize: 17,
          fontWeight: FontWeight.w700,
        ),
      ),
      cardTheme: CardThemeData(
        color: colors.surface,
        elevation: .5,
        shadowColor: const Color(0x180C2450),
        margin: const EdgeInsets.symmetric(vertical: 4),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(14),
          side: BorderSide(color: colors.outlineVariant),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: colors.surface,
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(
          horizontal: 12,
          vertical: 14,
        ),
        labelStyle: text.bodyMedium,
        hintStyle: text.bodySmall,
        helperStyle: text.bodySmall,
        errorStyle: text.bodySmall,
        border: const OutlineInputBorder(
          borderRadius: BorderRadius.all(Radius.circular(12)),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.outlineVariant),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(12),
          borderSide: BorderSide(color: colors.primary, width: 1.5),
        ),
      ),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          shape: shape,
          elevation: 1,
          textStyle: text.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: const Size(48, 48),
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          shape: shape,
          side: BorderSide(color: colors.outlineVariant),
          textStyle: text.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(
          minimumSize: const Size(48, 48),
          textStyle: text.labelLarge,
        ),
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: dark
            ? colors.primaryContainer
            : const Color(0xFF75EFCA),
        foregroundColor: dark
            ? colors.onPrimaryContainer
            : const Color(0xFF10265B),
        elevation: 2,
        shape: const StadiumBorder(),
        extendedTextStyle: text.labelLarge,
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 2),
        minLeadingWidth: 24,
        horizontalTitleGap: 10,
        titleTextStyle: text.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
        subtitleTextStyle: text.bodySmall,
        iconColor: colors.secondary,
        shape: shape,
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.all(Radius.circular(20)),
        ),
        titleTextStyle: text.titleLarge,
        contentTextStyle: text.bodyMedium,
        insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: colors.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(22)),
        ),
        clipBehavior: Clip.antiAlias,
      ),
      dividerTheme: DividerThemeData(
        color: colors.outlineVariant,
        thickness: 1,
        space: 20,
      ),
      chipTheme: base.chipTheme.copyWith(
        backgroundColor: colors.surface,
        selectedColor: colors.primaryContainer,
        labelStyle: text.bodySmall,
        side: BorderSide(color: colors.outlineVariant),
        shape: shape,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 72,
        backgroundColor: colors.surface,
        elevation: 0,
        indicatorColor: colors.primaryContainer,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        labelTextStyle: WidgetStatePropertyAll(
          text.labelSmall?.copyWith(fontSize: 10, fontWeight: FontWeight.w500),
        ),
      ),
      dataTableTheme: DataTableThemeData(
        headingTextStyle: text.labelMedium?.copyWith(
          fontWeight: FontWeight.w700,
        ),
        dataTextStyle: text.bodySmall?.copyWith(
          fontFeatures: const [FontFeature.tabularFigures()],
        ),
        columnSpacing: 18,
        horizontalMargin: 12,
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        contentTextStyle: text.bodyMedium?.copyWith(
          color: colors.onInverseSurface,
        ),
        shape: shape,
      ),
    );
    return desktop
        ? result.copyWith(
            visualDensity: VisualDensity.compact,
            materialTapTargetSize: MaterialTapTargetSize.shrinkWrap,
            cardTheme: result.cardTheme.copyWith(
              elevation: 1,
              shadowColor: const Color(0x200C2450),
              margin: const EdgeInsets.symmetric(vertical: 2),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(6),
                side: BorderSide(color: colors.outlineVariant),
              ),
            ),
            inputDecorationTheme: result.inputDecorationTheme.copyWith(
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(color: colors.outlineVariant),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(5),
                borderSide: BorderSide(color: colors.primary),
              ),
            ),
            filledButtonTheme: FilledButtonThemeData(
              style: FilledButton.styleFrom(
                minimumSize: const Size(64, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                textStyle: text.labelLarge,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
                elevation: 2,
                shadowColor: const Color(0x4000354A),
                surfaceTintColor: Colors.transparent,
              ),
            ),
            outlinedButtonTheme: OutlinedButtonThemeData(
              style: OutlinedButton.styleFrom(
                backgroundColor: dark
                    ? const Color(0xFF293C55)
                    : const Color(0xFFFCFEFF),
                foregroundColor: colors.secondary,
                side: BorderSide(color: colors.outlineVariant),
                elevation: 1,
                shadowColor: const Color(0x280C2450),
                surfaceTintColor: Colors.transparent,
                minimumSize: const Size(64, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 7,
                ),
                textStyle: text.labelLarge,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            textButtonTheme: TextButtonThemeData(
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 32),
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                textStyle: text.labelLarge,
              ),
            ),
            iconButtonTheme: IconButtonThemeData(
              style: IconButton.styleFrom(
                minimumSize: const Size(30, 30),
                padding: const EdgeInsets.all(4),
                iconSize: 19,
                foregroundColor: colors.primary,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(5),
                ),
              ),
            ),
            listTileTheme: result.listTileTheme.copyWith(
              dense: true,
              minVerticalPadding: 4,
              shape: const RoundedRectangleBorder(),
              titleTextStyle: text.bodyMedium?.copyWith(
                fontWeight: FontWeight.w500,
              ),
            ),
            dialogTheme: result.dialogTheme.copyWith(
              elevation: 10,
              shadowColor: const Color(0x500C2450),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
                side: BorderSide(color: colors.outlineVariant),
              ),
              insetPadding: const EdgeInsets.all(24),
            ),
            dataTableTheme: result.dataTableTheme.copyWith(
              headingRowColor: WidgetStatePropertyAll(
                dark ? const Color(0xFF234B4C) : const Color(0xFFCDF6E9),
              ),
              dividerThickness: .7,
              headingRowHeight: 34,
              dataRowMinHeight: 34,
              dataRowMaxHeight: 44,
              columnSpacing: 18,
            ),
            popupMenuTheme: PopupMenuThemeData(
              color: colors.surface,
              elevation: 6,
              shadowColor: const Color(0x400C2450),
              surfaceTintColor: Colors.transparent,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(7),
                side: BorderSide(color: colors.outlineVariant),
              ),
            ),
            scaffoldBackgroundColor: dark
                ? const Color(0xFF101C2B)
                : const Color(0xFFF4F7FC),
            appBarTheme: result.appBarTheme.copyWith(
              elevation: 1,
              shadowColor: const Color(0x200C2450),
              surfaceTintColor: Colors.transparent,
              backgroundColor: dark
                  ? const Color(0xFF1B2B42)
                  : const Color(0xFFECF2FC),
              foregroundColor: colors.onSurface,
              scrolledUnderElevation: 0,
              toolbarHeight: 44,
              titleTextStyle: text.titleLarge?.copyWith(
                fontSize: 18,
                fontWeight: FontWeight.w600,
                color: colors.onSurface,
              ),
            ),
          )
        : result;
  }
}
