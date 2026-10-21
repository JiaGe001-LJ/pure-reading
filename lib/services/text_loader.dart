import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:fast_gbk/fast_gbk.dart';
import 'package:flutter/painting.dart';

class Chapter {
  final String title;
  final int offset;
  const Chapter(this.title, this.offset);
}

class TextLoader {
  /// 自动识别编码：BOM → UTF-8 → GBK。
  static String decodeText(Uint8List bytes) {
    if (bytes.length >= 3 && bytes[0] == 0xEF && bytes[1] == 0xBB && bytes[2] == 0xBF) {
      return utf8.decode(bytes.sublist(3));
    }
    if (bytes.length >= 2 && bytes[0] == 0xFF && bytes[1] == 0xFE) {
      return _decodeUtf16(bytes.sublist(2), true);
    }
    if (bytes.length >= 2 && bytes[0] == 0xFE && bytes[1] == 0xFF) {
      return _decodeUtf16(bytes.sublist(2), false);
    }
    try {
      return utf8.decode(bytes);
    } catch (_) {}
    try {
      return gbk.decode(bytes);
    } catch (_) {}
    return utf8.decode(bytes, allowMalformed: true);
  }

  static String _decodeUtf16(Uint8List b, bool littleEndian) {
    final sb = StringBuffer();
    for (var i = 0; i + 1 < b.length; i += 2) {
      final code = littleEndian ? (b[i] | (b[i + 1] << 8)) : ((b[i] << 8) | b[i + 1]);
      sb.writeCharCode(code);
    }
    return sb.toString();
  }

  static Future<String> loadFile(String path) async {
    final bytes = await File(path).readAsBytes();
    return decodeText(bytes);
  }

  /// 识别“第X章/节/回/话/卷/集/部/篇”样式的章节标题。
  static List<Chapter> parseChapters(String text) {
    final chapters = <Chapter>[];
    final re = RegExp(
      r'^\s*第\s*[0-9一二三四五六七八九十百千万零两]+\s*[章节回话卷集部篇].*$',
    );
    var offset = 0;
    for (final line in const LineSplitter().convert(text)) {
      final t = line.trim();
      if (t.isNotEmpty && t.length <= 40 && re.hasMatch(t)) {
        chapters.add(Chapter(t, offset));
      }
      offset += line.length + 1;
    }
    return chapters;
  }
}

/// 基于字符宽度估算的增量逐页排版。
///
/// 与 TextPainter 逐段测量不同，本实现只测量两次基准宽度
/// （全角字、半角字），之后按宽度估算切行、按行高切页，
/// 全程 O(n) 无布局调用，2MB 级文本秒开。
///
/// 结果保证：pages 顺序拼接（无分隔符）后等于原文本。
/// 先调用 [nextBatch] 排少量页即可显示，剩余后台继续排完。
class Paginator {
  static const double _safe = 1.06; // 保守系数：估算宽度×1.06，防止渲染溢出

  final String text;
  final double width;
  final double height;
  final TextStyle style;

  final List<String> _pages = [];
  var _pos = 0;
  bool _complete = false;
  bool _measured = false;

  late double _cjkW; // 全角字符估算宽
  late double _halfW; // 半角字符估算宽
  late double _lineH; // 行高
  late int _linesPerPage;

  Paginator({
    required this.text,
    required this.width,
    required this.height,
    required this.style,
  });

  bool get complete => _complete;
  int get pageCount => _pages.length;
  List<String> get pages => List.unmodifiable(_pages);

  void _measure() {
    final probeCjk = TextPainter(
      text: TextSpan(text: '中', style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    final probeAscii = TextPainter(
      text: TextSpan(text: 'A', style: style),
      textDirection: TextDirection.ltr,
    )..layout(maxWidth: double.infinity);
    _cjkW = probeCjk.width * _safe;
    _halfW = probeAscii.width * _safe;
    _lineH = probeCjk.height;
    _linesPerPage = ((height / _lineH).floor()).clamp(1, 1 << 16);
    _measured = true;
  }

  /// 继续排版最多 [maxPages] 页，返回当前总页数。
  Future<int> nextBatch({int maxPages = 64}) async {
    if (!_measured) _measure();
    if (text.isEmpty) {
      _complete = true;
      return 0;
    }
    final startCount = _pages.length;
    while (!_complete && _pages.length - startCount < maxPages) {
      _buildNextPage();
      if ((_pages.length - startCount) % 24 == 0) {
        await Future<void>.delayed(Duration.zero);
      }
    }
    return _pages.length;
  }

  void _buildNextPage() {
    final sb = StringBuffer();
    var lines = 0;
    while (lines < _linesPerPage && _pos < text.length) {
      sb.write(_nextLine());
      lines++;
    }
    if (sb.isEmpty) {
      _complete = true;
      return;
    }
    _pages.add(sb.toString());
    if (_pos >= text.length) _complete = true;
  }

  /// 从 [_pos] 取一行：按估算宽度切行，换行符保留在行尾。
  String _nextLine() {
    final sb = StringBuffer();
    var w = 0.0;
    var lastSpace = -1; // 本行内最后空格相对偏移
    var i = _pos;
    while (i < text.length) {
      final c = text.codeUnitAt(i);
      if (c == 0x0A) {
        sb.writeCharCode(c);
        _pos = i + 1;
        return sb.toString();
      }
      if (c == 0x0D) {
        // CR：宽度不计，保留字符（兼容 \r\n）
        sb.writeCharCode(c);
        i++;
        continue;
      }
      final cw = c < 0x80 ? _halfW : _cjkW;
      if (w + cw > width) {
        if (lastSpace >= 0) {
          final cut = lastSpace + 1;
          final seg = text.substring(_pos, _pos + cut);
          _pos += cut;
          return seg;
        }
        final seg = text.substring(_pos, i);
        _pos = i;
        return seg;
      }
      sb.writeCharCode(c);
      w += cw;
      if (c == 0x20) lastSpace = i - _pos;
      i++;
    }
    final seg = text.substring(_pos);
    _pos = text.length;
    return seg;
  }
}
