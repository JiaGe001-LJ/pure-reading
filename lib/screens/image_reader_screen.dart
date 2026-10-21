import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../models/split_config.dart';
import '../services/image_splitter.dart';
import '../state/app_state.dart';

class ImageReaderScreen extends StatefulWidget {
  final Book book;
  const ImageReaderScreen({super.key, required this.book});

  @override
  State<ImageReaderScreen> createState() => _ImageReaderScreenState();
}

class _ImageReaderScreenState extends State<ImageReaderScreen> {
  late final AppState _state;

  bool _splitEnabled = false;
  bool _loading = true;
  String _status = '加载中…';
  List<String> _pages = [];
  int _pageIndex = 0;
  Directory? _cacheDir;
  bool _disposed = false;
  int _decodeWidth = 0;

  final PageController _controller = PageController();

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    final size = MediaQuery.of(context).size;
    final dpr = MediaQuery.of(context).devicePixelRatio;
    // 解码分辨率取屏幕宽 1.5 倍，兼顾放大查看与解码速度/内存。
    _decodeWidth = (size.width * dpr * 1.5).round().clamp(720, 4096);
    _resolvePages();
  }

  @override
  void dispose() {
    _disposed = true;
    _controller.dispose();
    _clearCache();
    super.dispose();
  }

  Future<void> _clearCache() async {
    try {
      if (_cacheDir != null && await _cacheDir!.exists()) {
        await _cacheDir!.delete(recursive: true);
      }
    } catch (_) {}
  }

  Future<void> _resolvePages() async {
    if (_disposed) return;
    setState(() {
      _loading = true;
      _status = _splitEnabled ? '正在分割图片…' : '加载中…';
    });
    try {
      if (!_splitEnabled) {
        _pages = List.of(widget.book.files);
      } else {
        final config = _state.activeSplitConfig;
        final cache = await getTemporaryDirectory();
        final dir =
            Directory(p.join(cache.path, 'pure_reading_split', widget.book.id));
        if (await dir.exists()) await dir.delete(recursive: true);
        await dir.create(recursive: true);
        _cacheDir = dir;
        final pages = <String>[];
        final files = widget.book.files;
        for (var i = 0; i < files.length; i++) {
          if (_disposed) return;
          setState(() => _status = '正在分割图片… ${i + 1}/${files.length}');
          try {
            final bytes = await File(files[i]).readAsBytes();
            final r = await ImageSplitter.splitToFiles(
              bytes: bytes,
              config: config,
              cacheDir: dir,
              baseName: 'p${i}_${config.id}',
            );
            pages.add(r.firstPath);
            pages.add(r.secondPath);
          } catch (_) {
            // 单页图或解析失败：按原图保留
            pages.add(files[i]);
          }
        }
        _pages = pages;
      }
      if (_disposed) return;
      setState(() {
        _loading = false;
        _pageIndex = widget.book.pageIndex.clamp(0, _pages.length - 1);
      });
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && _controller.hasClients) {
          _controller.jumpToPage(_pageIndex);
        }
      });
    } catch (e) {
      if (!_disposed) {
        setState(() {
          _loading = false;
          _status = '加载失败：$e';
        });
      }
    }
  }

  Future<void> _toggleSplit() async {
    setState(() => _splitEnabled = !_splitEnabled);
    await _resolvePages();
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
      if (_splitEnabled) await _resolvePages();
    }
  }

  void _onPageChanged(int i) {
    setState(() => _pageIndex = i);
    widget.book.pageIndex = i;
    _state.saveBooks();
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
          if (mounted && _controller.hasClients) {
            _controller.jumpToPage(_pageIndex);
          }
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = _state;
    final config = state.activeSplitConfig;
    final scheme = Theme.of(context).colorScheme;
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
      body: _buildBody(scheme, config),
    );
  }

  Widget _buildBody(ColorScheme scheme, SplitConfig config) {
    if (_loading) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const CircularProgressIndicator(),
            const SizedBox(height: 12),
            Text(_status,
                style: const TextStyle(color: Colors.white70, fontSize: 13)),
          ],
        ),
      );
    }
    if (_pages.isEmpty) {
      return const Center(
        child: Text('没有可显示的图片',
            style: TextStyle(color: Colors.white70)),
      );
    }
    return Stack(
      children: [
        PageView.builder(
          controller: _controller,
          scrollDirection:
              _state.settings.pageTransition == PageTransitionStyle.vertical
                  ? Axis.vertical
                  : Axis.horizontal,
          itemCount: _pages.length,
          onPageChanged: _onPageChanged,
          itemBuilder: (ctx, i) => _ZoomableImage(
              path: _pages[i], decodeWidth: _decodeWidth),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: 0,
          child: Container(
            color: Colors.black54,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            child: Row(
              children: [
                Expanded(
                  child: Text(
                    _splitEnabled
                        ? '双页分割：${config.name}'
                        : '双页分割：关',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(color: Colors.white70, fontSize: 12),
                  ),
                ),
                Text(
                  '${_pageIndex + 1} / ${_pages.length}',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// 支持双指缩放 / 双击放大缩小的单页图片。
class _ZoomableImage extends StatefulWidget {
  final String path;
  final int decodeWidth;
  const _ZoomableImage({required this.path, required this.decodeWidth});

  @override
  State<_ZoomableImage> createState() => _ZoomableImageState();
}

class _ZoomableImageState extends State<_ZoomableImage> {
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
          child: Image.file(
            File(widget.path),
            fit: BoxFit.contain,
            // 限制解码尺寸：大图快速解码、低内存，放大 1.5 倍内仍清晰。
            cacheWidth: widget.decodeWidth,
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
