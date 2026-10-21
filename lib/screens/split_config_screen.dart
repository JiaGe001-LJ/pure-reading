import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/split_config.dart';
import '../state/app_state.dart';

class SplitConfigScreen extends StatelessWidget {
  const SplitConfigScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final configs = state.allSplitConfigs;
    return Scaffold(
      appBar: AppBar(title: const Text('漫画分割配置')),
      body: ListView(
        padding: const EdgeInsets.all(12),
        children: [
          Card(
            child: Padding(
              padding: const EdgeInsets.all(12),
              child: Text(
                '用于把一张“竖版双页合图”切成两张单页。\n'
                '配置一：不旋转，左半为第 1 页（默认配置）；\n'
                '配置二：左半为第 1 页、向左旋转 90°，适合左→右阅读的图源；\n'
                '配置三：右半为第 1 页、向右旋转 90°，适合右→左阅读的图源。\n'
                '分割线可选“二分之一”或“自动检测”；可新增任意配置。',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ),
          ),
          const SizedBox(height: 8),
          RadioGroup<String>(
            groupValue: state.settings.activeSplitConfigId,
            onChanged: (v) {
              if (v != null) state.setActiveSplitConfig(v);
            },
            child: Column(
              children: configs
                  .map(
                    (c) => RadioListTile<String>(
                      value: c.id,
                      title: Text(c.name),
                      subtitle: Text(
                        '${c.methodLabel} · ${c.rotateLabel} · ${c.orderLabel}',
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                      secondary: c.isPreset
                          ? const Icon(Icons.lock_outline, size: 18)
                          : IconButton(
                              icon: const Icon(Icons.delete_outline, size: 18),
                              onPressed: () => state.removeSplitConfig(c.id),
                            ),
                      controlAffinity: ListTileControlAffinity.leading,
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            icon: const Icon(Icons.add),
            label: const Text('新增配置'),
            onPressed: () => _addConfig(context, state),
          ),
        ],
      ),
    );
  }

  Future<void> _addConfig(BuildContext context, AppState state) async {
    final nameCtrl = TextEditingController();
    var method = SplitMethod.half;
    var rotate = RotateDirection.left90;
    var order = PageOrder.leftFirst;

    Widget radioGroup<T>({
      required String title,
      required T value,
      required List<(T, String)> options,
      required ValueChanged<T> onChanged,
    }) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: Theme.of(context).textTheme.labelMedium),
          RadioGroup<T>(
            groupValue: value,
            onChanged: (v) {
              if (v != null) onChanged(v);
            },
            child: Column(
              children: options
                  .map(
                    (o) => RadioListTile<T>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(o.$2),
                      value: o.$1,
                    ),
                  )
                  .toList(),
            ),
          ),
          const SizedBox(height: 8),
        ],
      );
    }

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setState) => AlertDialog(
          title: const Text('新增分割配置'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: nameCtrl,
                  decoration: const InputDecoration(
                    labelText: '配置名称',
                    hintText: '如：配置三 · 自动检测左旋',
                  ),
                ),
                const SizedBox(height: 12),
                radioGroup<SplitMethod>(
                  title: '分割线方式',
                  value: method,
                  options: const [
                    (SplitMethod.half, '二分之一线分割'),
                    (SplitMethod.auto, '自动检测分割线'),
                  ],
                  onChanged: (v) => setState(() => method = v),
                ),
                radioGroup<RotateDirection>(
                  title: '旋转方向',
                  value: rotate,
                  options: const [
                    (RotateDirection.left90, '向左旋转 90°'),
                    (RotateDirection.right90, '向右旋转 90°'),
                    (RotateDirection.none, '不旋转'),
                  ],
                  onChanged: (v) => setState(() => rotate = v),
                ),
                radioGroup<PageOrder>(
                  title: '页面顺序',
                  value: order,
                  options: const [
                    (PageOrder.leftFirst, '左半页在前（为第1页）'),
                    (PageOrder.rightFirst, '右半页在前（为第1页）'),
                  ],
                  onChanged: (v) => setState(() => order = v),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('取消'),
            ),
            FilledButton(
              onPressed: () {
                final n = nameCtrl.text.trim();
                if (n.isEmpty) return;
                state.addSplitConfig(SplitConfig(
                  id: 'c_${DateTime.now().microsecondsSinceEpoch}',
                  name: n,
                  method: method,
                  rotate: rotate,
                  order: order,
                ));
                Navigator.pop(ctx);
              },
              child: const Text('保存'),
            ),
          ],
        ),
      ),
    );
  }
}
