import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

import '../models/book.dart';
import 'image_reader_screen.dart';
import 'pdf_reader_screen.dart';
import 'txt_reader_screen.dart';

/// 文件夹书阅读器：书架上是一本书，打开后逐层浏览章节（子文件夹），
/// 点击文件直接阅读（图片 / PDF / TXT），无需再进系统文件管理器。
class FolderReaderScreen extends StatefulWidget {
  final Book book;
  const FolderReaderScreen({super.key, required this.book});

  @override
  State<FolderReaderScreen> createState() => _FolderReaderScreenState();
}

class _FolderReaderScreenState extends State<FolderReaderScreen> {
  final List<FolderNode> _path = [];

  List<FolderNode> get _current =>
      _path.isEmpty ? (widget.book.structure ?? []) : _path.last.children;

  String get _title => _path.isEmpty
      ? widget.book.title
      : _path.map((n) => n.name).join(' / ');

  void _enterFolder(FolderNode node) {
    // 若该章节内全部是图片 → 直接以漫画方式阅读
    final images = <String>[];
    if (_collectImages(node, images) && _containsOnlyImages(node)) {
      if (images.isEmpty) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('此文件夹内没有图片')));
        return;
      }
      images.sort(_naturalCompare);
      _openReader(
        Book(
          id: '${widget.book.id}_${node.rel}',
          title: node.name,
          type: BookType.comic,
          files: images,
        ),
      );
      return;
    }
    setState(() => _path.add(node));
  }

  bool _containsOnlyImages(FolderNode node) {
    if (!node.isDir) return true;
    for (final c in node.children) {
      if (c.isDir) {
        if (!_containsOnlyImages(c)) return false;
      } else {
        final ext = p.extension(c.name).toLowerCase().replaceFirst('.', '');
        if (!_isImageExt(ext)) return false;
      }
    }
    return true;
  }

  bool _collectImages(FolderNode node, List<String> out) {
    if (!node.isDir) {
      final ext = p.extension(node.name).toLowerCase().replaceFirst('.', '');
      if (_isImageExt(ext) && node.absPath != null) out.add(node.absPath!);
      return true;
    }
    for (final c in node.children) {
      _collectImages(c, out);
    }
    return true;
  }

  bool _isImageExt(String ext) =>
      const ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'].contains(ext);

  void _openFile(FolderNode node) {
    final abs = node.absPath;
    if (abs == null) return;
    final ext = p.extension(abs).toLowerCase().replaceFirst('.', '');
    if (ext == 'pdf') {
      _openReader(Book(
        id: '${widget.book.id}_${node.rel}',
        title: node.name,
        type: BookType.pdf,
        files: [abs],
      ));
    } else if (_isImageExt(ext)) {
      _openReader(Book(
        id: '${widget.book.id}_${node.rel}',
        title: node.name,
        type: BookType.image,
        files: [abs],
      ));
    } else {
      _openReader(Book(
        id: '${widget.book.id}_${node.rel}',
        title: node.name,
        type: BookType.txt,
        files: [abs],
      ));
    }
  }

  void _openReader(Book b) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => switch (b.type) {
          BookType.pdf => PdfReaderScreen(book: b),
          BookType.txt => TxtReaderScreen(book: b),
          _ => ImageReaderScreen(book: b),
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final nodes = _current;
    return Scaffold(
      appBar: AppBar(
        title: Text(_title, overflow: TextOverflow.ellipsis),
        leading: BackButton(
          onPressed: _path.isEmpty ? null : () => setState(() => _path.removeLast()),
        ),
      ),
      body: nodes.isEmpty
          ? Center(
              child: Text('此文件夹内没有可阅读的内容',
                  style: TextStyle(color: scheme.outline)),
            )
          : ListView.builder(
              itemCount: nodes.length,
              itemBuilder: (ctx, i) {
                final n = nodes[i];
                final icon = n.isDir
                    ? Icons.folder
                    : (p.extension(n.name).toLowerCase() == '.pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.image_outlined);
                return ListTile(
                  leading: Icon(icon,
                      color: n.isDir ? scheme.primary : scheme.onSurfaceVariant),
                  title: Text(n.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                  trailing: n.isDir
                      ? const Icon(Icons.chevron_right)
                      : null,
                  onTap: () => n.isDir ? _enterFolder(n) : _openFile(n),
                );
              },
            ),
    );
  }

  static int _naturalCompare(String a, String b) {
    final re = RegExp(r'\d+');
    final am = re
        .allMatches(p.basenameWithoutExtension(a))
        .map((m) => int.parse(m.group(0)!))
        .toList();
    final bm = re
        .allMatches(p.basenameWithoutExtension(b))
        .map((m) => int.parse(m.group(0)!))
        .toList();
    final n = am.length < bm.length ? am.length : bm.length;
    for (var i = 0; i < n; i++) {
      if (am[i] != bm[i]) return am[i].compareTo(bm[i]);
    }
    return a.compareTo(b);
  }
}
