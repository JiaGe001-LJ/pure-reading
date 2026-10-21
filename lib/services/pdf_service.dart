import 'dart:typed_data';
import 'dart:ui';

import 'package:pdfx/pdfx.dart';

/// PDF 渲染服务：封装 pdfx（Android 端为系统 PdfRenderer）。
///
/// Android 平台不允许并行渲染，因此所有渲染通过 [_queue] 串行排队。
class PdfService {
  PdfDocument? _doc;
  int _pageCount = 0;
  Future<dynamic> _queue = Future.value();

  int get pageCount => _pageCount;

  bool get isOpen => _doc != null && !_doc!.isClosed;

  /// 打开 PDF 文件。
  Future<void> open(String path) async {
    await close();
    final doc = await PdfDocument.openFile(path);
    _doc = doc;
    _pageCount = doc.pagesCount;
  }

  /// 渲染指定页（1 起）为 JPEG 字节。
  ///
  /// [logicalWidth] 为屏幕逻辑宽度，乘以 [scale] 得到渲染像素宽度。
  Future<Uint8List> renderPage(
    int pageNumber,
    double logicalWidth, {
    double scale = 2.0,
  }) {
    return _serial(() async {
      final doc = _doc;
      if (doc == null || doc.isClosed) {
        throw StateError('PDF 文档未打开或已关闭');
      }
      final page = await doc.getPage(pageNumber);
      try {
        final targetW = (logicalWidth * scale).round();
        final targetH = (page.height * targetW / page.width).round();
        final img = await page.render(
          width: targetW.toDouble(),
          height: targetH.toDouble(),
          format: PdfPageImageFormat.jpeg,
          quality: 88,
          backgroundColor: '#FFFFFF',
        );
        if (img == null) throw StateError('PDF 页面渲染失败：$pageNumber');
        return img.bytes;
      } finally {
        if (!page.isClosed) await page.close();
      }
    });
  }

  /// 串行执行，保证 Android 上一次只渲染一页。
  Future<T> _serial<T>(Future<T> Function() fn) {
    final result = _queue.then((_) => fn());
    _queue = result.then((_) {}, onError: (_) {});
    return result;
  }

  Future<void> close() async {
    try {
      final doc = _doc;
      if (doc != null && !doc.isClosed) {
        await doc.close();
      }
    } catch (_) {}
    _doc = null;
    _pageCount = 0;
  }
}

/// 逻辑宽度快捷获取（用于渲染目标尺寸）。
double logicalWidthOf(Size size) => size.width;
