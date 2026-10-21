import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../app_info.dart';
import '../models/app_settings.dart';
import '../state/app_state.dart';
import 'donation_screen.dart';
import 'split_config_screen.dart';

class SettingsScreen extends StatelessWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final settings = state.settings;
    return Scaffold(
      appBar: AppBar(title: const Text('我的设置')),
      body: ListView(
        padding: const EdgeInsets.only(bottom: 32),
        children: [
          _sectionTitle(context, '外观'),
          ListTile(
            leading: const Icon(Icons.brightness_6_outlined),
            title: const Text('主题模式'),
            subtitle: Padding(
              padding: const EdgeInsets.only(top: 8),
              child: SegmentedButton<ThemePref>(
                segments: const [
                  ButtonSegment(
                      value: ThemePref.system, label: Text('跟随系统')),
                  ButtonSegment(value: ThemePref.light, label: Text('浅色')),
                  ButtonSegment(value: ThemePref.dark, label: Text('深色')),
                ],
                selected: {settings.themePref},
                onSelectionChanged: (s) => state.setThemePref(s.first),
              ),
            ),
          ),
          const Divider(),
          _sectionTitle(context, '阅读'),
          ListTile(
            leading: const Icon(Icons.format_size),
            title: const Text('正文字号'),
            subtitle: Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () =>
                      state.setFontSize(settings.fontSize - 1),
                ),
                Expanded(
                  child: Slider(
                    value: settings.fontSize,
                    min: 12,
                    max: 32,
                    divisions: 20,
                    label: '${settings.fontSize.round()}',
                    onChanged: (v) => state.setFontSize(v),
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () =>
                      state.setFontSize(settings.fontSize + 1),
                ),
              ],
            ),
          ),
          ListTile(
            leading: const Icon(Icons.auto_stories_outlined),
            title: const Text('漫画双页分割配置'),
            subtitle: Text(state.activeSplitConfig.name),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const SplitConfigScreen()),
            ),
          ),
          const Divider(),
          _sectionTitle(context, '支持'),
          ListTile(
            leading: const Icon(Icons.favorite_outline),
            title: const Text('捐赠支持'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => const DonationScreen()),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('关于'),
            subtitle: const Text('$appName · v$appVersion · 作者 $appAuthor'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _showAbout(context),
          ),
        ],
      ),
    );
  }

  void _showAbout(BuildContext context) {
    showAboutDialog(
      context: context,
      applicationName: appName,
      applicationVersion: 'v$appVersion',
      applicationIcon: const Icon(Icons.auto_stories_outlined, size: 48),
      children: [
        const Text('轻量、本地优先的文本与漫画阅读器。'),
        const SizedBox(height: 12),
        const Text('作者：$appAuthor'),
        const SizedBox(height: 12),
        const Text('功能：\n'
            '· TXT 文本阅读（编码自动识别、字号/字体/翻页方向可调）\n'
            '· 图片 / 漫画阅读（支持文件夹整目录导入）\n'
            '· PDF 阅读与漫画双页分割（不旋转 / 左旋 / 右旋三种预置配置）\n'
            '· 浅色 / 深色 / 跟随系统主题\n'
            '· 阅读进度本地记忆，无需联网',
            style: null),
        const SizedBox(height: 12),
        const Text('v1.0.5 更新：\n'
            '· TXT 排版全面提速（2MB 级文件秒开，增量排版）\n'
            '· 翻页动画改为翻页方向：左右 / 上下，无需特效更省资源\n'
            '· 分割配置重排：配置一=不旋转（默认）\n'
            '· 支持按文件夹导入漫画\n'
            '· 阅读设置新增字体选择',
            style: null),
      ],
    );
  }

  Widget _sectionTitle(BuildContext context, String title) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
        child: Text(
          title,
          style: Theme.of(context).textTheme.labelLarge?.copyWith(
                color: Theme.of(context).colorScheme.primary,
              ),
        ),
      );
}
