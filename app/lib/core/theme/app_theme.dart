import 'package:flutter/material.dart';

/// Tokens de design centralizados do app.
/// Ajustado para uma cor de destaque mais vibrante e viva.
class AppRadius {
  AppRadius._();

  static const double sm = 10;
  static const double md = 14;
  static const double lg = 16;
  static const double xl = 20;
}

class AppColors {
  AppColors._();

  /// Nova cor de destaque: Azul Elétrico mais vibrante
  static const Color destaque = Color(0xFF007AFF);

  static const Color fundo = Color(0xFFF6F7F9);
  static const Color superficie = Colors.white;
  static const Color superficieSecundaria = Color(0xFFF1F3F5);
  static const Color bordaSutil = Color(0xFFE7E9EC);
  static const Color textoPrimario = Color(0xFF1F2937);
  static const Color textoSecundario = Color(0xFF667085);
}

const Duration duracaoTransicaoInterativa = Duration(milliseconds: 220);

ThemeData construirTemaClaro() {
  final colorScheme = ColorScheme.fromSeed(
    seedColor: AppColors.destaque,
    brightness: Brightness.light,
  );

  final radiusBotao = BorderRadius.circular(AppRadius.md);
  final radiusCartao = BorderRadius.circular(AppRadius.lg);
  final radiusCampo = BorderRadius.circular(AppRadius.md);

  return ThemeData(
    useMaterial3: true,
    colorScheme: colorScheme,
    scaffoldBackgroundColor: AppColors.fundo,
    visualDensity: VisualDensity.comfortable,
    splashFactory: InkSparkle.splashFactory,
    textTheme: _construirTextTheme(),

    appBarTheme: const AppBarTheme(
      backgroundColor: AppColors.fundo,
      foregroundColor: AppColors.textoPrimario,
      elevation: 0,
      scrolledUnderElevation: 0,
      surfaceTintColor: Colors.transparent,
      centerTitle: false,
      titleTextStyle: TextStyle(
        color: AppColors.textoPrimario,
        fontSize: 20,
        fontWeight: FontWeight.w600,
        height: 1.3,
      ),
    ),

    cardTheme: CardThemeData(
      color: AppColors.superficie,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      margin: const EdgeInsets.symmetric(vertical: 8),
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: radiusCartao),
    ),

    inputDecorationTheme: InputDecorationTheme(
      filled: true,
      fillColor: AppColors.superficieSecundaria,
      contentPadding: const EdgeInsets.symmetric(horizontal: 18, vertical: 18),
      border: OutlineInputBorder(borderRadius: radiusCampo, borderSide: BorderSide.none),
      enabledBorder: OutlineInputBorder(borderRadius: radiusCampo, borderSide: BorderSide.none),
      disabledBorder: OutlineInputBorder(borderRadius: radiusCampo, borderSide: BorderSide.none),
      focusedBorder: OutlineInputBorder(
        borderRadius: radiusCampo,
        borderSide: BorderSide(color: colorScheme.primary, width: 1.6),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: radiusCampo,
        borderSide: BorderSide(color: colorScheme.error, width: 1.4),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: radiusCampo,
        borderSide: BorderSide(color: colorScheme.error, width: 1.6),
      ),
      labelStyle: const TextStyle(color: AppColors.textoSecundario),
      hintStyle: TextStyle(color: AppColors.textoSecundario.withValues(alpha: 0.8)),
    ),

    elevatedButtonTheme: ElevatedButtonThemeData(
      style: ButtonStyle(
        animationDuration: duracaoTransicaoInterativa,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radiusBotao)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
        elevation: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.hovered)) return 6;
          if (estados.contains(WidgetState.pressed)) return 1;
          return 2;
        }),
        shadowColor: WidgetStatePropertyAll(Colors.black.withValues(alpha: 0.15)),
      ),
    ),

    filledButtonTheme: FilledButtonThemeData(
      style: ButtonStyle(
        animationDuration: duracaoTransicaoInterativa,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radiusBotao)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
        overlayColor: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.hovered)) return Colors.white.withValues(alpha: 0.08);
          if (estados.contains(WidgetState.pressed)) return Colors.white.withValues(alpha: 0.16);
          return null;
        }),
        elevation: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.hovered)) return 4;
          return 0;
        }),
      ),
    ),

    outlinedButtonTheme: OutlinedButtonThemeData(
      style: ButtonStyle(
        animationDuration: duracaoTransicaoInterativa,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 24, vertical: 16),
        ),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radiusBotao)),
        textStyle: const WidgetStatePropertyAll(
          TextStyle(fontWeight: FontWeight.w600, letterSpacing: 0.2),
        ),
        side: WidgetStateProperty.resolveWith((estados) {
          if (estados.contains(WidgetState.hovered)) {
            return BorderSide(color: colorScheme.primary, width: 1.4);
          }
          return const BorderSide(color: AppColors.bordaSutil, width: 1.2);
        }),
      ),
    ),

    textButtonTheme: TextButtonThemeData(
      style: ButtonStyle(
        animationDuration: duracaoTransicaoInterativa,
        padding: const WidgetStatePropertyAll(
          EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        ),
        shape: WidgetStatePropertyAll(RoundedRectangleBorder(borderRadius: radiusBotao)),
        textStyle: const WidgetStatePropertyAll(TextStyle(fontWeight: FontWeight.w600)),
      ),
    ),

    chipTheme: ChipThemeData(
      backgroundColor: AppColors.superficieSecundaria,
      selectedColor: colorScheme.primaryContainer,
      disabledColor: AppColors.superficieSecundaria,
      labelStyle: const TextStyle(color: AppColors.textoPrimario, fontWeight: FontWeight.w500),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.sm),
        side: BorderSide.none,
      ),
      side: BorderSide.none,
    ),

    dividerTheme: const DividerThemeData(
      color: AppColors.bordaSutil,
      thickness: 1,
      space: 32,
    ),

    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: AppColors.superficie,
      elevation: 3,
      shadowColor: Colors.black.withValues(alpha: 0.08),
      surfaceTintColor: Colors.transparent,
      indicatorColor: colorScheme.primaryContainer,
      labelTextStyle: WidgetStateProperty.resolveWith((estados) {
        final selecionado = estados.contains(WidgetState.selected);
        return TextStyle(
          fontSize: 12,
          fontWeight: selecionado ? FontWeight.w600 : FontWeight.w500,
          color: selecionado ? colorScheme.primary : AppColors.textoSecundario,
        );
      }),
    ),

    snackBarTheme: SnackBarThemeData(
      behavior: SnackBarBehavior.floating,
      backgroundColor: AppColors.textoPrimario,
      contentTextStyle: const TextStyle(color: Colors.white),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.md)),
      insetPadding: const EdgeInsets.all(16),
    ),

    bottomSheetTheme: BottomSheetThemeData(
      backgroundColor: AppColors.superficie,
      surfaceTintColor: Colors.transparent,
      elevation: 6,
      modalElevation: 6,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
      ),
    ),

    dialogTheme: DialogThemeData(
      backgroundColor: AppColors.superficie,
      surfaceTintColor: Colors.transparent,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppRadius.lg)),
    ),

    listTileTheme: const ListTileThemeData(
      contentPadding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
    ),

    iconTheme: const IconThemeData(color: Color.fromARGB(255, 151, 143, 73)),
  );
}

TextTheme _construirTextTheme() {
  const cor = AppColors.textoPrimario;
  const corSecundaria = AppColors.textoSecundario;

  return const TextTheme(
    displayLarge: TextStyle(color: cor, height: 1.2, fontWeight: FontWeight.w700),
    displayMedium: TextStyle(color: cor, height: 1.2, fontWeight: FontWeight.w700),
    displaySmall: TextStyle(color: cor, height: 1.25, fontWeight: FontWeight.w700),
    headlineLarge: TextStyle(color: cor, height: 1.25, fontWeight: FontWeight.w700),
    headlineMedium: TextStyle(color: cor, height: 1.25, fontWeight: FontWeight.w700),
    headlineSmall: TextStyle(color: cor, height: 1.3, fontWeight: FontWeight.w700),
    titleLarge: TextStyle(color: cor, height: 1.3, fontWeight: FontWeight.w700, letterSpacing: 0.1),
    titleMedium: TextStyle(color: cor, height: 1.35, fontWeight: FontWeight.w600, letterSpacing: 0.1),
    titleSmall: TextStyle(color: cor, height: 1.35, fontWeight: FontWeight.w600),
    bodyLarge: TextStyle(color: cor, height: 1.5),
    bodyMedium: TextStyle(color: cor, height: 1.5),
    bodySmall: TextStyle(color: corSecundaria, height: 1.45),
    labelLarge: TextStyle(color: cor, height: 1.3, fontWeight: FontWeight.w600),
    labelMedium: TextStyle(color: cor, height: 1.3, fontWeight: FontWeight.w500),
    labelSmall: TextStyle(color: corSecundaria, height: 1.3, fontWeight: FontWeight.w500),
  );
}