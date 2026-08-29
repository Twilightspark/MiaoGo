import 'package:flutter/material.dart';

/// 喵棋设计令牌（Design Tokens）。
///
/// 色彩体系：宣纸白背景 + 暖米色卡片，松柏青为主色、棋盘木色为强调色。
/// 与 Android 原生 res 颜色同步（`values/colors.xml`）。
abstract final class GoColors {
  /// 主背景 · 宣纸白。
  static const Color background = Color(0xFFF7F2EA);

  /// 卡片 · 暖米色。
  static const Color surface = Color(0xFFEFE3D5);

  /// 主色 · 松柏青：当前选中状态、AI 提示、等级（级）、成就。
  static const Color pine = Color(0xFF4C8B70);

  /// 深松柏青：次级强调、图标。
  static const Color pineDark = Color(0xFF3B6B56);

  /// 浅松柏青：头像/浅色底。
  static const Color pineContainer = Color(0xFFD7E7DE);

  /// 深松柏青文字（用于浅松柏青底）。
  static const Color onPineContainer = Color(0xFF2C5745);

  /// 强调色 · 棋盘木色：积分、段位（段）、金牌。
  static const Color wood = Color(0xFFA56A3A);

  /// 深木色：次级强调、图标。
  static const Color woodDark = Color(0xFF7A4B28);

  /// 浅木色：积分等浅色底。
  static const Color woodContainer = Color(0xFFF0E0CE);

  /// 一级文字。
  static const Color textPrimary = Color(0xFF2B2926);

  /// 二级文字。
  static const Color textSecondary = Color(0xFF77716B);

  /// 白色（主色/强调色底上的文字）。
  static const Color white = Color(0xFFFFFFFF);

  /// 边框。
  static const Color outline = Color(0xFFC6BCAC);

  /// 浅边框/分隔线。
  static const Color outlineVariant = Color(0xFFDED4C5);
}

/// 构建喵棋主题：显式色板 + 组件主题。
ThemeData buildGoTheme() {
  const scheme = ColorScheme.light(
    primary: GoColors.pine,
    onPrimary: GoColors.white,
    primaryContainer: GoColors.pineContainer,
    onPrimaryContainer: GoColors.onPineContainer,
    secondary: GoColors.wood,
    onSecondary: GoColors.white,
    secondaryContainer: GoColors.woodContainer,
    onSecondaryContainer: GoColors.woodDark,
    tertiary: GoColors.pine,
    onTertiary: GoColors.white,
    tertiaryContainer: GoColors.pineContainer,
    onTertiaryContainer: GoColors.onPineContainer,
    error: Color(0xFFB3261E),
    onError: GoColors.white,
    surface: GoColors.background,
    onSurface: GoColors.textPrimary,
    onSurfaceVariant: GoColors.textSecondary,
    surfaceContainerLowest: Color(0xFFFCFAF6),
    surfaceContainerLow: Color(0xFFF6F0E6),
    surfaceContainer: Color(0xFFF2EBDE),
    surfaceContainerHigh: Color(0xFFEEE5D6),
    surfaceContainerHighest: GoColors.surface,
    outline: GoColors.outline,
    outlineVariant: GoColors.outlineVariant,
    inverseSurface: GoColors.textPrimary,
    inversePrimary: GoColors.pineContainer,
  );

  return ThemeData(
    useMaterial3: true,
    colorScheme: scheme,
    scaffoldBackgroundColor: GoColors.background,
    appBarTheme: const AppBarTheme(
      backgroundColor: GoColors.background,
      foregroundColor: GoColors.textPrimary,
      elevation: 0,
      scrolledUnderElevation: 0,
    ),
    cardTheme: const CardThemeData(
      color: GoColors.surface,
      elevation: 0,
    ),
    dividerTheme: const DividerThemeData(color: GoColors.outlineVariant),
    navigationBarTheme: NavigationBarThemeData(
      backgroundColor: GoColors.surface,
      indicatorColor: GoColors.pine,
      iconTheme: WidgetStateProperty.resolveWith(
        (states) => IconThemeData(
          color: states.contains(WidgetState.selected)
              ? GoColors.white
              : GoColors.textSecondary,
        ),
      ),
      labelTextStyle: WidgetStateProperty.resolveWith(
        (states) => TextStyle(
          fontSize: 12,
          fontWeight: states.contains(WidgetState.selected)
              ? FontWeight.w600
              : FontWeight.w500,
          color: states.contains(WidgetState.selected)
              ? GoColors.white
              : GoColors.textSecondary,
        ),
      ),
    ),
    segmentedButtonTheme: SegmentedButtonThemeData(
      style: ButtonStyle(
        backgroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? GoColors.pine
              : Colors.transparent,
        ),
        foregroundColor: WidgetStateProperty.resolveWith(
          (states) => states.contains(WidgetState.selected)
              ? GoColors.white
              : GoColors.textSecondary,
        ),
        side: WidgetStateProperty.resolveWith(
          (states) => BorderSide(
            color: states.contains(WidgetState.selected)
                ? GoColors.pine
                : GoColors.outlineVariant,
          ),
        ),
      ),
    ),
    tabBarTheme: const TabBarThemeData(
      labelColor: GoColors.pine,
      unselectedLabelColor: GoColors.textSecondary,
      indicatorColor: GoColors.pine,
      dividerColor: GoColors.outlineVariant,
    ),
  );
}
