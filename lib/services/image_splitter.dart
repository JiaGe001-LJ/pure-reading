import 'dart:io';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/split_config.dart';

class SplitPageFiles {
  final String firstPath;
  final String secondPath;
  const SplitPageFiles(this.firstPath, this.secondPath);
}

/// 内存版分割结果。
class SplitPageBytes {
  final Uint8List first;
  final Uint8List second;
  const SplitPageBytes(this.first, this.second);
}

/// 漫画双页分割核心。
///
/// 输入一张“竖版双页合图”（左半一页、右半一页），
/// 按配置在竖中线（或自动检测）处切成两半，各自旋转成横版，
/// 并按配置指定的顺序输出两张单页。
class ImageSplitter {
  static const int _maxDim = 4096;
  static const int _jpegQuality = 92;

  /// 内存版分割：返回两张单页的 JPEG 字节，不落盘。
  static Future<SplitPageBytes> splitToBytes({
    required Uint8List bytes,
    required SplitConfig config,
  }) async {
    final (first, second) = _split(bytes, config);
    return SplitPageBytes(
      Uint8List.fromList(img.encodeJpg(first, quality: _jpegQuality)),
      Uint8List.fromList(img.encodeJpg(second, quality: _jpegQuality)),
    );
  }

  static (img.Image, img.Image) _split(
      Uint8List bytes, SplitConfig config) {
    var src = img.decodeImage(bytes);
    if (src == null) throw const FormatException('无法解析图片');
    if (src.width > _maxDim || src.height > _maxDim) {
      final scale =
          _maxDim / (src.width > src.height ? src.width : src.height);
      src = img.copyResize(
        src,
        width: (src.width * scale).round(),
        height: (src.height * scale).round(),
      );
    }
    final w = src.width;
    final h = src.height;

    var splitX =
        config.method == SplitMethod.auto ? detectSplitX(src) : w ~/ 2;
    splitX = splitX.clamp((w * 0.15).round(), (w * 0.85).round());

    final left = img.copyCrop(src, x: 0, y: 0, width: splitX, height: h);
    final right =
        img.copyCrop(src, x: splitX, y: 0, width: w - splitX, height: h);

    if (config.order == PageOrder.leftFirst) {
      return (_rotate(left, config.rotate), _rotate(right, config.rotate));
    }
    return (_rotate(right, config.rotate), _rotate(left, config.rotate));
  }

  static Future<SplitPageFiles> splitToFiles({
    required Uint8List bytes,
    required SplitConfig config,
    required Directory cacheDir,
    required String baseName,
  }) async {
    final (first, second) = _split(bytes, config);

    final f1 = File(p.join(cacheDir.path, '${baseName}_1.jpg'));
    final f2 = File(p.join(cacheDir.path, '${baseName}_2.jpg'));
    await f1.writeAsBytes(img.encodeJpg(first, quality: _jpegQuality),
        flush: true);
    await f2.writeAsBytes(img.encodeJpg(second, quality: _jpegQuality),
        flush: true);
    return SplitPageFiles(f1.path, f2.path);
  }

  static img.Image _rotate(img.Image src, RotateDirection dir) {
    switch (dir) {
      case RotateDirection.left90:
        // 左旋90°（逆时针）：原图的上边沿落到结果图的左边沿。
        // image 包：正角度为顺时针，故左旋用 270。
        return img.copyRotate(src, angle: 270);
      case RotateDirection.right90:
        // 右旋90°（顺时针）：原图的上边沿落到结果图的右边沿。
        return img.copyRotate(src, angle: 90);
      case RotateDirection.none:
        return src;
    }
  }

  /// 自动检测分割线：在图像中央 25%–75% 区间内，
  /// 找与中位亮度偏差最大的一列（亮缝或书脊阴影都算），
  /// 偏差太小则回退到二分之一线。
  static int detectSplitX(img.Image src) {
    final w = src.width;
    final h = src.height;
    if (w < 100) return w ~/ 2;
    const stepX = 4;
    const stepY = 8;
    final cols = (w / stepX).ceil();
    final sums = List<double>.filled(cols, 0);
    final counts = List<int>.filled(cols, 0);
    for (var y = 0; y < h; y += stepY) {
      for (var x = 0; x < w; x += stepX) {
        final px = src.getPixel(x, y);
        final lum = 0.299 * px.r + 0.587 * px.g + 0.114 * px.b;
        final i = x ~/ stepX;
        sums[i] += lum;
        counts[i]++;
      }
    }
    final avg = List<double>.generate(
        cols, (i) => counts[i] == 0 ? 255 : sums[i] / counts[i]);
    // 亮缝用 ±1 最大值滤波（保留窄缝），书脊阴影用 ±1 最小值滤波。
    final bright = List<double>.generate(cols, (i) {
      var m = -1.0;
      for (var j = i - 1; j <= i + 1; j++) {
        if (j >= 0 && j < cols && avg[j] > m) m = avg[j];
      }
      return m;
    });
    final dark = List<double>.generate(cols, (i) {
      var m = 1e9;
      for (var j = i - 1; j <= i + 1; j++) {
        if (j >= 0 && j < cols && avg[j] < m) m = avg[j];
      }
      return m;
    });
    final lo = (cols * 0.25).round();
    final hi = (cols * 0.75).round();
    final band = avg.sublist(lo, hi + 1)..sort();
    final median = band[band.length ~/ 2];
    var best = -1;
    var bestDev = -1.0;
    for (var i = lo; i <= hi; i++) {
      final devB = (bright[i] - median).abs();
      final devD = (dark[i] - median).abs();
      final dev = devB > devD ? devB : devD;
      if (dev > bestDev) {
        bestDev = dev;
        best = i;
      }
    }
    if (best >= 0 && bestDev >= 10) return (best * stepX).clamp(0, w - 1);
    return w ~/ 2;
  }
}
