import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../services/text_loader.dart';
import '../state/app_state.dart';

class TxtReaderScreen extends StatefulWidget {
  final Book book;
  const TxtReaderScreen({super.key, required this.book});

  @override
  State<TxtReaderScreen> createState() => _TxtReaderScreenState();
}

class _TxtReaderScreenState extends State<TxtReaderScreen> {
  late final AppState _state;

  String? _text;
  String? _error;
  List<String> _pages = [];
  int _pageIndex = 0;
  double _fontSize = 18;
  String _fontFamily = '';
  PageTransitionStyle _transition = PageTransitionStyle.horizontal;
  bool _paging = false;
  String _status = '';
  bool _barsVisible = true;
  Size? _pagedSize;
  bool _disposed = false;

  final PageController _controller = PageController();

  @override
  void initState() {
    super.initState();
    _state = context.read<AppState>();
    _fontSize = _state.settings.fontSize;
    _fontFamily = _state.settings.fontFamily;
    _transition = _state.settings.pageTransition;
    _loadText();
  }

  @override
  void dispose() {
    _disposed = true;
    _saveProgress();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _loadText() async {
    try {
      final text = await TextLoader.loadFile(widget.book.files.first);
      if (_disposed) return;
      setState(() => _text = text);
    } catch (e) {
      if (_disposed) return;
      setState(() => _error = '$e');
    }
  }

  TextStyle get _textStyle => TextStyle(
        fontSize: _fontSize,
        height: 1.7,
        fontFamily: _fontFamily.isEmpty ? null : _fontFamily,
      );

  Future<void> _paginate(Size viewport) async {
    final text = _text;
    if (text == null || _paging) return;
    final w = viewport.width - 36;
    final h = viewport.height - 24;
    if (w <= 0 || h <= 0) return;
    final p = Paginator(text: text, width: w, height: h, style: _textStyle);
    setState(() {
      _paging = true;
      _status = '正在排版…';
      _pages = [];
    });
    // 先排少量页立即显示，剩余后台补完。
    await p.nextBatch(maxPages: 4);
    if (_disposed) return;
    setState(() {
      _pages = p.pages;
      _pagedSize = viewport;
      _pageIndex = widget.book.pageIndex.clamp(0, _pages.length - 1);
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_disposed) return;
      if (_controller.hasClients) _controller.jumpToPage(_pageIndex);
      if (!p.complete) _continuePaginating(p);
    });
  }

  Future<void> _continuePaginating(Paginator p) async {
    while (!p.complete) {
      if (_disposed) return;
      final before = p.pageCount;
      await p.nextBatch(maxPages: 64);
      if (_disposed) return;
      setState(() {
        _pages = p.pages;
        _status = p.complete ? '' : '正在排版… 已生成 ${p.pageCount} 页';
      });
      if (p.pageCount == before) break;
    }
    if (!_disposed) {
      setState(() {
        _pages = p.pages;
        _paging = false;
        _status = '';
      });
    }
  }

  void _saveProgress() {
    if (_pages.isEmpty) return;
    widget.book.pageIndex = _pageIndex;
    _state.saveBooks();
  }

  void _onPageChanged(int i) {
    setState(() => _pageIndex = i);
    _saveProgress();
  }

  void _prev() {
    if (_pageIndex > 0) {
      _controller.previousPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  void _next() {
    if (_pageIndex < _pages.length - 1) {
      _controller.nextPage(
        duration: const Duration(milliseconds: 260),
        curve: Curves.easeOut,
      );
    }
  }

  void _onTapUp(TapUpDetails d, Size size) {
    final x = d.localPosition.dx;
    if (x < size.width / 3) {
      _prev();
    } else if (x > size.width * 2 / 3) {
      _next();
    } else {
      setState(() => _barsVisible = !_barsVisible);
    }
  }

  void _setFontSize(double v) {
    setState(() {
      _fontSize = v;
      _pagedSize = null;
      _pages = [];
      _paging = false;
    });
    _state.setFontSize(v);
  }

  void _setFontFamily(String v) {
    setState(() {
      _fontFamily = v;
      _pagedSize = null;
      _pages = [];
      _paging = false;
    });
    _state.setFontFamily(v);
  }

  void _setTransition(PageTransitionStyle v) {
    final dirChanged = v != _transition;
    setState(() => _transition = v);
    _state.setPageTransition(v);
    if (dirChanged) {
      // 方向切换：PageView 重建后偏移语义变化，跳回当前页修正。
      // 不重建 controller（避免 disposed position 导致拖动手势失效）。
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!_disposed && _controller.hasClients) {
          _controller.jumpToPage(_pageIndex);
        }
      });
    }
  }

  Future<void> _openMenu() async {
    final changed = await showModalBottomSheet<bool>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (ctx) => _ReaderMenu(
        fontSize: _fontSize,
        fontFamily: _fontFamily,
        transition: _transition,
        onFontSizeChanged: _setFontSize,
        onFontFamilyChanged: _setFontFamily,
        onTransitionChanged: _setTransition,
      ),
    );
    if (changed == true && _pagedSize != null) {
      _paginate(_pagedSize!);
    }
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _barsVisible
          ? AppBar(
              title: Text(widget.book.title, overflow: TextOverflow.ellipsis),
              actions: [
                IconButton(
                  icon: const Icon(Icons.tune),
                  tooltip: '设置',
                  onPressed: _openMenu,
                ),
              ],
            )
          : null,
      body: _buildBody(scheme),
    );
  }

  Widget _buildBody(ColorScheme scheme) {
    if (_error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.error_outline, size: 48),
              const SizedBox(height: 12),
              Text('读取失败：$_error', textAlign: TextAlign.center),
            ],
          ),
        ),
      );
    }
    if (_text == null) {
      return const Center(child: CircularProgressIndicator());
    }
    return LayoutBuilder(
      builder: (context, constraints) {
        final size = constraints.biggest;
        if (_pages.isEmpty && !_paging && _pagedSize != size) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!_disposed) _paginate(size);
          });
        }
        return GestureDetector(
          behavior: HitTestBehavior.opaque,
          onTapUp: (d) => _onTapUp(d, size),
          child: Stack(
            children: [
              PageView.builder(
                controller: _controller,
                scrollDirection: _transition == PageTransitionStyle.vertical
                    ? Axis.vertical
                    : Axis.horizontal,
                itemCount: _pages.isEmpty ? 1 : _pages.length,
                onPageChanged: _onPageChanged,
                itemBuilder: (ctx, i) {
                  if (_pages.isEmpty) return const SizedBox.shrink();
                  return Padding(
                    padding: const EdgeInsets.symmetric(
                        horizontal: 18, vertical: 12),
                    child: Text(
                      _pages[i],
                      style: _textStyle,
                      textAlign: TextAlign.justify,
                    ),
                  );
                },
              ),
              if (_paging)
                Center(
                  child: Card(
                    child: Padding(
                      padding: const EdgeInsets.all(16),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const CircularProgressIndicator(),
                          const SizedBox(height: 12),
                          Text(_status),
                        ],
                      ),
                    ),
                  ),
                ),
              if (_barsVisible && _pages.isNotEmpty && !_paging)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 0,
                  child: Container(
                    color: scheme.surfaceContainer.withValues(alpha: 0.9),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 12, vertical: 6),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${_pages.length} 页',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                                fontSize: 12, color: scheme.onSurfaceVariant),
                          ),
                        ),
                        Text(
                          '${_pageIndex + 1} / ${_pages.length}',
                          style: TextStyle(
                              fontSize: 12, color: scheme.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _ReaderMenu extends StatelessWidget {
  final double fontSize;
  final String fontFamily;
  final PageTransitionStyle transition;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<String> onFontFamilyChanged;
  final ValueChanged<PageTransitionStyle> onTransitionChanged;

  const _ReaderMenu({
    required this.fontSize,
    required this.fontFamily,
    required this.transition,
    required this.onFontSizeChanged,
    required this.onFontFamilyChanged,
    required this.onTransitionChanged,
  });

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text('字号', style: Theme.of(context).textTheme.labelLarge),
            Row(
              children: [
                IconButton(
                  icon: const Icon(Icons.remove_circle_outline),
                  onPressed: () => onFontSizeChanged(
                      (fontSize - 1).clamp(12, 32).toDouble()),
                ),
                Expanded(
                  child: Slider(
                    value: fontSize,
                    min: 12,
                    max: 32,
                    divisions: 20,
                    label: '${fontSize.round()}',
                    onChanged: onFontSizeChanged,
                  ),
                ),
                IconButton(
                  icon: const Icon(Icons.add_circle_outline),
                  onPressed: () => onFontSizeChanged(
                      (fontSize + 1).clamp(12, 32).toDouble()),
                ),
              ],
            ),
            const Divider(),
            Text('字体', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              segments: const [
                ButtonSegment(value: '', label: Text('默认')),
                ButtonSegment(value: 'serif', label: Text('衬线')),
                ButtonSegment(value: 'monospace', label: Text('等宽')),
              ],
              selected: {fontFamily},
              onSelectionChanged: (s) => onFontFamilyChanged(s.first),
            ),
            const Divider(),
            Text('翻页方向', style: Theme.of(context).textTheme.labelLarge),
            const SizedBox(height: 8),
            SegmentedButton<PageTransitionStyle>(
              segments: const [
                ButtonSegment(
                    value: PageTransitionStyle.horizontal,
                    label: Text('左右')),
                ButtonSegment(
                    value: PageTransitionStyle.vertical,
                    label: Text('上下')),
              ],
              selected: {transition},
              onSelectionChanged: (s) => onTransitionChanged(s.first),
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }
}
