import 'package:flutter/material.dart';

import 'split_config.dart';

enum ThemePref { system, light, dark }

/// 翻页方向（左右 / 上下）。
enum PageTransitionStyle { horizontal, vertical }

class AppSettings {
  ThemePref themePref;
  double fontSize;
  String fontFamily;
  PageTransitionStyle pageTransition;
  String activeSplitConfigId;
  List<SplitConfig> customSplitConfigs;

  AppSettings({
    this.themePref = ThemePref.system,
    this.fontSize = 18,
    this.fontFamily = '',
    this.pageTransition = PageTransitionStyle.horizontal,
    this.activeSplitConfigId = SplitConfig.presetNoneId,
    List<SplitConfig>? customSplitConfigs,
  }) : customSplitConfigs = customSplitConfigs ?? [];

  ThemeMode get themeMode => switch (themePref) {
        ThemePref.system => ThemeMode.system,
        ThemePref.light => ThemeMode.light,
        ThemePref.dark => ThemeMode.dark,
      };
}
