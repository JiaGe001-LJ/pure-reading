enum SplitMethod { half, auto }

enum RotateDirection { none, left90, right90 }

enum PageOrder { leftFirst, rightFirst }

/// 漫画双页分割配置。
///
/// 将一张“竖版双页合图”按分割线切成左右两半，再各自旋转成横版单页，
/// 并按指定顺序作为第 1、2 页进入阅读序列。
/// 配置是可扩展的：预设两条，用户可新增自定义配置。
class SplitConfig {
  final String id;
  final String name;
  final SplitMethod method;
  final RotateDirection rotate;
  final PageOrder order;
  final bool isPreset;

  const SplitConfig({
    required this.id,
    required this.name,
    required this.method,
    required this.rotate,
    required this.order,
    this.isPreset = false,
  });

  static const presetNoneId = 'preset_none';
  static const presetLeftId = 'preset_left90';
  static const presetRightId = 'preset_right90';

  /// 配置一：不旋转，左半为第 1 页（保持原方向直接分割，默认配置）。
  /// 配置二：左旋90°，左半为第 1 页（适合左→右阅读的图源）。
  /// 配置三：右旋90°，右半为第 1 页（适合右→左阅读的图源）。
  static const presets = <SplitConfig>[
    SplitConfig(
      id: presetNoneId,
      name: '配置一 · 不旋转',
      method: SplitMethod.half,
      rotate: RotateDirection.none,
      order: PageOrder.leftFirst,
      isPreset: true,
    ),
    SplitConfig(
      id: presetLeftId,
      name: '配置二 · 左旋90°',
      method: SplitMethod.half,
      rotate: RotateDirection.left90,
      order: PageOrder.leftFirst,
      isPreset: true,
    ),
    SplitConfig(
      id: presetRightId,
      name: '配置三 · 右旋90°',
      method: SplitMethod.half,
      rotate: RotateDirection.right90,
      order: PageOrder.rightFirst,
      isPreset: true,
    ),
  ];

  String get methodLabel =>
      method == SplitMethod.half ? '二分之一线分割' : '自动检测分割线';

  String get rotateLabel => switch (rotate) {
        RotateDirection.none => '不旋转',
        RotateDirection.left90 => '向左旋转90°',
        RotateDirection.right90 => '向右旋转90°',
      };

  String get orderLabel =>
      order == PageOrder.leftFirst ? '左半页在前（为第1页）' : '右半页在前（为第1页）';

  Map<String, dynamic> toJson() => {
        'id': id,
        'name': name,
        'method': method.name,
        'rotate': rotate.name,
        'order': order.name,
      };

  factory SplitConfig.fromJson(Map<String, dynamic> j) => SplitConfig(
        id: j['id'] as String,
        name: j['name'] as String,
        method: SplitMethod.values.byName(j['method'] as String),
        rotate: RotateDirection.values.byName(j['rotate'] as String),
        order: PageOrder.values.byName(j['order'] as String),
      );
}
