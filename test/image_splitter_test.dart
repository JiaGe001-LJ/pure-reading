import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:pure_reading/models/split_config.dart';
import 'package:pure_reading/services/image_splitter.dart';

/// 构造一张合成“双页合图”：
/// 宽 400 × 高 1000（竖版），左半为红色 + 顶部一行白色标记，
/// 右半为绿色 + 顶部一行白色标记。
Uint8List _makeSpread() {
  final image = img.Image(width: 400, height: 1000);
  img.fill(image, color: img.ColorRgb8(255, 0, 0)); // 左半红
  for (var y = 0; y < 1000; y++) {
    for (var x = 200; x < 400; x++) {
      image.setPixelRgb(x, y, 0, 255, 0); // 右半绿
    }
  }
  // 左半顶部一行白色
  for (var x = 0; x < 200; x++) {
    image.setPixelRgb(x, 0, 255, 255, 255);
  }
  // 右半顶部一行白色
  for (var x = 200; x < 400; x++) {
    image.setPixelRgb(x, 0, 255, 255, 255);
  }
  return img.encodePng(image);
}

double _lum(img.Pixel px) => 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
bool _isWhite(img.Pixel px) => _lum(px) > 200;
bool _isRed(img.Pixel px) => px.r > 200 && px.g < 100 && px.b < 100;
bool _isGreen(img.Pixel px) => px.g > 200 && px.r < 100 && px.b < 100;

void main() {
  test('配置一：不旋转，左半为第1页，保持原方向', () async {
    final dir = await Directory.systemTemp.createTemp('split_test1');
    addTearDown(() => dir.delete(recursive: true));

    final r = await ImageSplitter.splitToFiles(
      bytes: _makeSpread(),
      config: SplitConfig.presets.first, // 配置一：half + none + leftFirst
      cacheDir: dir,
      baseName: 't1',
    );

    final p1 = img.decodeImage(File(r.firstPath).readAsBytesSync())!;
    final p2 = img.decodeImage(File(r.secondPath).readAsBytesSync())!;

    // 不旋转：仍为竖版窄条（高 > 宽）
    expect(p1.height, greaterThan(p1.width));
    expect(p2.height, greaterThan(p2.width));

    // 第1页 = 左半（红），第2页 = 右半（绿）
    expect(_isRed(p1.getPixel(p1.width ~/ 2, p1.height ~/ 2)), isTrue);
    expect(_isGreen(p2.getPixel(p2.width ~/ 2, p2.height ~/ 2)), isTrue);

    // 不旋转：白色上边沿仍在顶部（y=0），不在左右边沿
    expect(_isWhite(p1.getPixel(p1.width ~/ 2, 0)), isTrue,
        reason: '不旋转时白色上边沿应保留在顶部');
    expect(_isWhite(p1.getPixel(0, p1.height ~/ 2)), isFalse,
        reason: '不旋转时左右边沿不应出现白色上边沿');
  });

  test('配置二：左半为第1页，左旋90°后原图上边沿落在结果左边沿', () async {
    final dir = await Directory.systemTemp.createTemp('split_test2');
    addTearDown(() => dir.delete(recursive: true));

    final r = await ImageSplitter.splitToFiles(
      bytes: _makeSpread(),
      config: SplitConfig.presets[1], // 配置二：half + left90 + leftFirst
      cacheDir: dir,
      baseName: 't2',
    );

    final p1 = img.decodeImage(File(r.firstPath).readAsBytesSync())!;
    final p2 = img.decodeImage(File(r.secondPath).readAsBytesSync())!;

    // 都是横版（旋转后：高 > 宽 的窄条变横）
    expect(p1.width, greaterThan(p1.height));
    expect(p2.width, greaterThan(p2.height));

    // 第1页 = 左半（红），第2页 = 右半（绿）
    expect(_isRed(p1.getPixel(p1.width ~/ 2, p1.height ~/ 2)), isTrue);
    expect(_isGreen(p2.getPixel(p2.width ~/ 2, p2.height ~/ 2)), isTrue);

    // 左旋90°：原图（窄条）的上边沿白色行 → 结果图的左边沿白色列
    expect(_isWhite(p1.getPixel(0, p1.height ~/ 2)), isTrue,
        reason: '左旋90°后白色上边沿应位于结果图左边');
    expect(_isWhite(p1.getPixel(p1.width - 1, p1.height ~/ 2)), isFalse,
        reason: '左旋90°后结果图右边沿不应是原图的上边沿');
  });

  test('配置三：右半为第1页，右旋90°后原图上边沿落在结果右边沿', () async {
    final dir = await Directory.systemTemp.createTemp('split_test3');
    addTearDown(() => dir.delete(recursive: true));

    final r = await ImageSplitter.splitToFiles(
      bytes: _makeSpread(),
      config: SplitConfig.presets[2], // 配置三：half + right90 + rightFirst
      cacheDir: dir,
      baseName: 't3',
    );

    final p1 = img.decodeImage(File(r.firstPath).readAsBytesSync())!;
    final p2 = img.decodeImage(File(r.secondPath).readAsBytesSync())!;

    expect(p1.width, greaterThan(p1.height));
    expect(p2.width, greaterThan(p2.height));

    // 第1页 = 右半（绿），第2页 = 左半（红）
    expect(_isGreen(p1.getPixel(p1.width ~/ 2, p1.height ~/ 2)), isTrue);
    expect(_isRed(p2.getPixel(p2.width ~/ 2, p2.height ~/ 2)), isTrue);

    // 右旋90°：原图的上边沿白色行 → 结果图的右边沿白色列
    expect(_isWhite(p1.getPixel(p1.width - 1, p1.height ~/ 2)), isTrue,
        reason: '右旋90°后白色上边沿应位于结果图右边');
    expect(_isWhite(p1.getPixel(0, p1.height ~/ 2)), isFalse,
        reason: '右旋90°后结果图左边沿不应是原图的上边沿');
  });

  test('自动检测分割线：对有明显亮缝的图能离开正中', () {
    final image = img.Image(width: 400, height: 200);
    img.fill(image, color: img.ColorRgb8(240, 240, 240));
    // 在 x=250 处画一条白色亮缝（模拟页间缝隙）
    for (var y = 0; y < 200; y++) {
      for (var x = 248; x < 252; x++) {
        image.setPixelRgb(x, y, 255, 255, 255);
      }
    }
    final x = ImageSplitter.detectSplitX(image);
    expect((x - 250).abs(), lessThan(20),
        reason: '自动检测应定位到亮缝附近，实际 $x');
  });

  test('旋转方向互为逆操作', () {
    final src = img.Image(width: 3, height: 1);
    src.setPixelRgb(0, 0, 255, 0, 0);
    src.setPixelRgb(1, 0, 0, 255, 0);
    src.setPixelRgb(2, 0, 0, 0, 255);

    final left = img.copyRotate(src, angle: 270);
    final right = img.copyRotate(left, angle: 90);
    expect(right.width, src.width);
    expect(right.height, src.height);
    expect(right.getPixel(0, 0).r, closeTo(255, 5));
    expect(right.getPixel(1, 0).g, closeTo(255, 5));
    expect(right.getPixel(2, 0).b, closeTo(255, 5));
  });
}
