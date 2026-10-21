import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../services/image_splitter.dart';
import '../services/pdf_service.dart';
import '../state/app_state.dart';

/// PDF 阅读器：渲染 PDF 页为 JPEG 字节，横向翻页 + 双指缩放，
/// 支持复用「漫画双页分割配置」（把每页渲染图按配置分割成两页）。
class PdfReaderScreen extends StatefulWidget {
  final Book book;
  const PdfReaderScreen({super.key, required this.book});

  @override
  State<PdfReaderScreen> createState() => _PdfReaderScreenState();
}

class _PdfReaderScreenState extends State<PdfReaderScreen> {
  late final AppState _state;
  final PdfService _pdf = PdfService();

  bool _splitEnabled = false;
  bool _loading = true;
  String _status = '打开中…';
  int _pdfPages = 0;
  int _pageIndex = 0;
  bool _disposed = false;
  late PageController _pageController;

  final Map<int, Uint8List> _bytesCache = {};
  final Map<int, Future<Uint8List>> _displayFutures = {};
  final Map<int, Future<(Uint8List, Uint8List?)>> _pairFutures = {};
  final List<int> _cacheOrder = [];
  static const _cacheMax = 8;

  int get _displayCount => _splitEnabled ? _pdfPages * 2 : _pdfPages;

  void _cachePut(int index, Uint8List bytes) {
    if (_disposed) return;
    if (!_bytesCache.containsKey(index)) _cacheOrder.add(index);
    _bytesCache[index] = bytes;
    while (_cacheOrder.length > _cacheMax) {
      final old = _cacheOrder.removeAt(0);
      _bytesCache.remove(old);
      _displayFutures.remove(old);
    }
  }

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _pageController = PageController(initialPage: _pageIndex);
    _open();
  }

  @override
  void dispose() {
    _disposed = true;
    _pageController.dispose();
    _pdf.close();
    super.dispose();
  }

  Future<void> _open() async {
    try {
      await _pdf.open(widget.book.files.first);
      _pdfPages = _pdf.pageCount;
      if (_disposed) return;
      setState(() {
        _loading = false;
        _pageIndex =
            widget.book.pageIndex.clamp(0, (_pdfPages - 1).clamp(0, 1 << 30));
      });
      _prefetch(_pageIndex);
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && _pageController.hasClients) {
          _pageController.jumpToPage(_pageIndex);
        }
      });
    } catch (e) {
      if (!_disposed) {
        setState(() {
          _loading = false;
          _status = '打开 PDF 失败：$e';
        });
      }
    }
  }

  /// 展示序列索引 → 内存字节。同一索引复用同一个 Future，避免
  /// FutureBuilder 因 future 对象频繁更换而显示抖动。
  Future<Uint8List> _pageBytes(int displayIndex) {
    return _displayFutures.putIfAbsent(displayIndex, () async {
      final cached = _bytesCache[displayIndex];
      if (cached != null) return cached;

      final width = MediaQuery.of(context).size.width;
      if (!_splitEnabled) {
        final bytes = await _pdf.renderPage(displayIndex + 1, width);
        debugPrint('PDF_RENDER i=$displayIndex page=${displayIndex + 1}');
        _cachePut(displayIndex, bytes);
        return bytes;
      }

      // 分割模式：同一 PDF 页的两个半页共用一个渲染+分割 Future
      final pairIndex = displayIndex ~/ 2;
      final isFirst = displayIndex % 2 == 0;
      final pair = _pairFutures.putIfAbsent(pairIndex, () async {
        final pageNo = pairIndex + 1;
        final bytes = await _pdf.renderPage(pageNo, width);
        debugPrint('PDF_RENDER page=$pageNo split=true');
        try {
          final r = await ImageSplitter.splitToBytes(
            bytes: bytes,
            config: _state.activeSplitConfig,
          );
          return (r.first, r.second);
        } catch (e) {
          // 分割失败（非双页图等）：回退为整页渲染图
          debugPrint('PDF_SPLIT_FAIL page=$pageNo e=$e');
          return (bytes, null);
        }
      });
      final r = await pair;
      if (r.$2 == null) {
        _cachePut(pairIndex * 2, r.$1);
        _cachePut(pairIndex * 2 + 1, r.$1);
        return r.$1;
      }
      final b = isFirst ? r.$1 : r.$2!;
      _cachePut(displayIndex, b);
      return b;
    });
  }

  void _prefetch(int index) {
    if (_splitEnabled) {
      final pairIndex = index ~/ 2;
      for (var d = -1; d <= 1; d++) {
        final i = (pairIndex + d) * 2;
        if (i >= 0 && i < _displayCount) _pageBytes(i);
      }
    } else {
      for (var d = -1; d <= 1; d++) {
        final i = index + d;
        if (i >= 0 && i < _displayCount) _pageBytes(i);
      }
    }
  }

  void _onPageChanged(int i) {
    debugPrint('PDF_PAGE_CHANGED $i');
    setState(() => _pageIndex = i);
    widget.book.pageIndex = i;
    _state.saveBooks();
    _prefetch(i);
  }

  Future<void> _toggleSplit() async {
    setState(() => _splitEnabled = !_splitEnabled);
    _bytesCache.clear();
    _displayFutures.clear();
    _pairFutures.clear();
    _cacheOrder.clear();
    final target = widget.book.pageIndex;
    setState(() {
      _pageIndex = target.clamp(0, _displayCount - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_disposed && _pageController.hasClients) {
        _pageController.jumpToPage(_pageIndex);
      }
    });
    _prefetch(_pageIndex);
  }

  Future<void> _pickConfig() async {
    final state = _state;
    final configs = state.allSplitConfigs;
    final selected = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              title: Text('选择分割配置',
                  style: Theme.of(ctx).textTheme.titleMedium),
            ),
            RadioGroup<String>(
              groupValue: state.settings.activeSplitConfigId,
              onChanged: (v) {
                if (v != null) Navigator.pop(ctx, v);
              },
              child: Column(
                children: configs
                    .map(
                      (c) => RadioListTile<String>(
                        value: c.id,
                        title: Text(c.name),
                        subtitle: Text(
                          '${c.methodLabel} · ${c.rotateLabel} · ${c.orderLabel}',
                          style: Theme.of(ctx).textTheme.bodySmall,
                        ),
                      ),
                    )
                    .toList(),
              ),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
    if (selected != null && selected != state.settings.activeSplitConfigId) {
      await state.setActiveSplitConfig(selected);
      if (_splitEnabled) {
        _bytesCache.clear();
        _displayFutures.clear();
        _pairFutures.clear();
        _cacheOrder.clear();
        _prefetch(_pageIndex);
        setState(() {});
      }
    }
  }

  Future<void> _pickTransition() async {
    final state = _state;
    final current = state.settings.pageTransition;
    final selected = await showModalBottomSheet<PageTransitionStyle>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('翻页方向', style: Theme.of(ctx).textTheme.titleMedium),
              const SizedBox(height: 12),
              SegmentedButton<PageTransitionStyle>(
                segments: const [
                  ButtonSegment(
                      value: PageTransitionStyle.horizontal,
                      label: Text('左右')),
                  ButtonSegment(
                      value: PageTransitionStyle.vertical,
                      label: Text('上下')),
                ],
                selected: {current},
                onSelectionChanged: (s) => Navigator.pop(ctx, s.first),
              ),
              const SizedBox(height: 16),
            ],
          ),
        ),
      ),
    );
    if (selected != null && selected != state.settings.pageTransition) {
      await state.setPageTransition(selected);
      // 方向切换：PageView 重建后偏移语义变化，跳回当前页修正。
      // 不重建 controller（避免 disposed position 导致拖动手势失效）。
      if (mounted) {
        setState(() {});
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted && _pageController.hasClients) {
            _pageController.jumpToPage(_pageIndex);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = _state.activeSplitConfig;
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        foregroundColor: Colors.white,
        title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
        actions: [
          IconButton(
            tooltip: '翻页方向',
            icon: const Icon(Icons.swap_vert),
            onPressed: _pickTransition,
          ),
          IconButton(
            tooltip: '分割配置',
            icon: const Icon(Icons.auto_stories_outlined),
            onPressed: _pickConfig,
          ),
          IconButton(
            tooltip: _splitEnabled ? '关闭双页分割' : '开启双页分割',
            icon: Icon(_splitEnabled
                ? Icons.crop_rotate
                : Icons.crop_16_9_outlined),
            onPressed: _toggleSplit,
          ),
        ],
      ),
      body: _loading
          ? Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const CircularProgressIndicator(),
                  const SizedBox(height: 12),
                  Text(_status,
                      style:
                          const TextStyle(color: Colors.white70, fontSize: 13)),
                ],
              ),
            )
          : (_pdfPages == 0
              ? const Center(
                  child: Text('PDF 没有可显示的页面',
                      style: TextStyle(color: Colors.white70)),
                )
              : Stack(
                  children: [
                    PageView.builder(
                      controller: _pageController,
                      scrollDirection: _state.settings.pageTransition ==
                              PageTransitionStyle.vertical
                          ? Axis.vertical
                          : Axis.horizontal,
                      itemCount: _displayCount,
                      onPageChanged: _onPageChanged,
                      itemBuilder: (ctx, i) => _PdfPageWidget(
                        future: _pageBytes(i),
                        index: i,
                        current: i == _pageIndex,
                      ),
                    ),
                    Positioned(
                      left: 0,
                      right: 0,
                      bottom: 0,
                      child: Container(
                        color: Colors.black54,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 12, vertical: 6),
                        child: Row(
                          children: [
                            Expanded(
                              child: Text(
                                _splitEnabled
                                    ? '双页分割：${config.name}'
                                    : '双页分割：关',
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ),
                            Text(
                              '${_pageIndex + 1} / $_displayCount',
                              style: const TextStyle(
                                  color: Colors.white70, fontSize: 12),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ],
                )),
    );
  }
}

class _PdfPageWidget extends StatefulWidget {
  final Future<Uint8List> future;
  final int index;
  final bool current;
  const _PdfPageWidget({
    required this.future,
    required this.index,
    required this.current,
  });

  @override
  State<_PdfPageWidget> createState() => _PdfPageWidgetState();
}

class _PdfPageWidgetState extends State<_PdfPageWidget> {
  late Future<Uint8List> _future;

  @override
  void initState() {
    super.initState();
    _future = widget.future;
  }

  @override
  void didUpdateWidget(covariant _PdfPageWidget old) {
    super.didUpdateWidget(old);
    if (old.future != widget.future) {
      _future = widget.future;
    }
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<Uint8List>(
      future: _future,
      builder: (ctx, snap) {
        if (snap.connectionState != ConnectionState.done ||
            !snap.hasData ||
            snap.data!.isEmpty) {
          return const Center(
            child: CircularProgressIndicator(color: Colors.white24),
          );
        }
        debugPrint('PDF_PAGE_SHOW idx=${widget.index} len=${snap.data!.length}');
        return _ZoomableBytes(bytes: snap.data!);
      },
    );
  }
}

/// 支持双指缩放 / 双击放大缩小的 PDF 页图片（内存字节）。
/// 未放大时 InteractiveViewer 完全禁用手势（scaleEnabled/panEnabled 均关），
/// 把单指滑动手势让给外层 PageView 翻页；双击放大后才启用缩放与平移。
class _ZoomableBytes extends StatefulWidget {
  final Uint8List bytes;
  const _ZoomableBytes({required this.bytes});

  @override
  State<_ZoomableBytes> createState() => _ZoomableBytesState();
}

class _ZoomableBytesState extends State<_ZoomableBytes> {
  final TransformationController _tc = TransformationController();
  double _scale = 1.0;
  bool _zoomed = false;

  @override
  void dispose() {
    _tc.dispose();
    super.dispose();
  }

  void _syncZoom() {
    final s = _tc.value.getMaxScaleOnAxis();
    final z = s > 1.05;
    if (z != _zoomed) setState(() => _zoomed = z);
  }

  void _onDoubleTap() {
    final target = _scale > 1.2 ? 1.0 : 2.5;
    setState(() => _scale = target);
    _tc.value = Matrix4.identity()..scaleByDouble(target, target, 1, 1);
    _syncZoom();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onDoubleTap: _onDoubleTap,
      child: InteractiveViewer(
        transformationController: _tc,
        minScale: 1.0,
        maxScale: 5.0,
        // 未放大时完全禁用手势，翻页交给 PageView；放大后启用缩放+平移。
        panEnabled: _zoomed,
        scaleEnabled: _zoomed,
        onInteractionUpdate: (_) => _syncZoom(),
        onInteractionEnd: (_) => _syncZoom(),
        child: Center(
          child: Image.memory(
            widget.bytes,
            fit: BoxFit.contain,
            errorBuilder: (_, __, ___) => const Center(
              child: Icon(Icons.broken_image_outlined,
                  color: Colors.white38, size: 48),
            ),
          ),
        ),
      ),
    );
  }
}
