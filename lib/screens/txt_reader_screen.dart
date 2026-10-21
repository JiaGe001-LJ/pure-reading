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
  bool _fullscreen = false;
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

  void _setFullscreen(bool v) {
    setState(() {
      _fullscreen = v;
      // 清空分页：全屏切换后视口尺寸变化，build 时会自动重新排版
      _pagedSize = null;
      _pages = [];
      _paging = false;
    });
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
    if (_fullscreen) {
      // 全屏下：点中间区域呼出菜单（可关闭全屏），左右仍为翻页
      if (x < size.width / 3) {
        _prev();
      } else if (x > size.width * 2 / 3) {
        _next();
      } else {
        _openMenu();
      }
      return;
    }
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
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setSheetState) => _ReaderMenu(
          fontSize: _fontSize,
          fontFamily: _fontFamily,
          transition: _transition,
          fullscreen: _fullscreen,
          hasBookmark: _hasBookmark,
          onFontSizeChanged: _setFontSize,
          onFontFamilyChanged: _setFontFamily,
          onTransitionChanged: _setTransition,
          onFullscreenChanged: (v) {
            setSheetState(() {});
            _setFullscreen(v);
          },
          onToggleBookmark: _toggleBookmark,
          onShowBookmarks: _showBookmarks,
        ),
      ),
    );
    if (changed == true && _pagedSize != null) {
      _paginate(_pagedSize!);
    }
  }

  bool get _hasBookmark => widget.book.bookmarks.contains(_pageIndex);

  void _toggleBookmark() {
    setState(() {
      if (_hasBookmark) {
        widget.book.bookmarks.remove(_pageIndex);
      } else {
        widget.book.bookmarks.add(_pageIndex);
      }
    });
    _state.saveBooks();
  }

  void _showBookmarks() {
    final marks = [...widget.book.bookmarks]..sort();
    if (marks.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('还没有书签，阅读时在菜单里点“添加书签”')));
      return;
    }
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: Text('书签列表（${marks.length}）',
                  style: Theme.of(ctx).textTheme.labelLarge),
            ),
            Flexible(
              child: ListView.builder(
                shrinkWrap: true,
                itemCount: marks.length,
                itemBuilder: (ctx, i) {
                  final m = marks[i];
                  return ListTile(
                    dense: true,
                    leading: const Icon(Icons.bookmark, size: 20),
                    title: Text('第 ${m + 1} 页'),
                    trailing: IconButton(
                      icon: const Icon(Icons.delete_outline, size: 20),
                      tooltip: '删除书签',
                      onPressed: () {
                        setState(() => widget.book.bookmarks.remove(m));
                        _state.saveBooks();
                        Navigator.of(ctx).pop();
                        _showBookmarks();
                      },
                    ),
                    onTap: () {
                      _controller.jumpToPage(m);
                      setState(() => _pageIndex = m);
                      _saveProgress();
                      Navigator.of(ctx).pop();
                    },
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final safeTop = MediaQuery.of(context).padding.top;
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      appBar: _barsVisible && !_fullscreen
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
      body: _buildBody(scheme, safeTop),
    );
  }

  Widget _buildBody(ColorScheme scheme, double safeTop) {
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
              // 全屏时顶部预留摄像头/刘海安全区，避免遮挡正文
              Padding(
                padding: EdgeInsets.only(
                    top: _fullscreen ? safeTop + 8 : 0),
                child: PageView.builder(
                  controller: _controller,
                  scrollDirection:
                      _transition == PageTransitionStyle.vertical
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
              if (_barsVisible && _pages.isNotEmpty && !_paging &&
                  !_fullscreen)
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
              // 全屏模式：仅显示页码（底部居中）；系统时间由系统状态栏显示，
              // 顶部预留摄像头/刘海安全区见上方 Padding
              if (_fullscreen && _pages.isNotEmpty && !_paging)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 18,
                  child: Center(
                    child: _MiniChip('${_pageIndex + 1} / ${_pages.length}'),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }
}

class _MiniChip extends StatelessWidget {
  final String text;
  const _MiniChip(this.text);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.45),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        text,
        style: const TextStyle(color: Colors.white, fontSize: 12),
      ),
    );
  }
}

class _ReaderMenu extends StatelessWidget {
  final double fontSize;
  final String fontFamily;
  final PageTransitionStyle transition;
  final bool fullscreen;
  final bool hasBookmark;
  final ValueChanged<double> onFontSizeChanged;
  final ValueChanged<String> onFontFamilyChanged;
  final ValueChanged<PageTransitionStyle> onTransitionChanged;
  final ValueChanged<bool> onFullscreenChanged;
  final VoidCallback onToggleBookmark;
  final VoidCallback onShowBookmarks;

  const _ReaderMenu({
    required this.fontSize,
    required this.fontFamily,
    required this.transition,
    required this.fullscreen,
    required this.hasBookmark,
    required this.onFontSizeChanged,
    required this.onFontFamilyChanged,
    required this.onTransitionChanged,
    required this.onFullscreenChanged,
    required this.onToggleBookmark,
    required this.onShowBookmarks,
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
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('全屏阅读'),
              subtitle: const Text('隐藏工具栏，仅显示页码与系统时间'),
              secondary: const Icon(Icons.fullscreen),
              value: fullscreen,
              onChanged: onFullscreenChanged,
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(hasBookmark
                  ? Icons.bookmark
                  : Icons.bookmark_add_outlined),
              title: Text(hasBookmark ? '移除当前页书签' : '添加当前页书签'),
              onTap: () {
                Navigator.of(context).pop(false);
                onToggleBookmark();
              },
            ),
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: const Icon(Icons.bookmarks_outlined),
              title: const Text('书签列表'),
              onTap: () {
                Navigator.of(context).pop(false);
                onShowBookmarks();
              },
            ),
            const Divider(),
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
