import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/import_service.dart';
import '../state/app_state.dart';
import '../widgets/book_cover.dart';
import 'image_reader_screen.dart';
import 'pdf_reader_screen.dart';
import 'txt_reader_screen.dart';

class BookshelfScreen extends StatelessWidget {
  const BookshelfScreen({super.key});

  Future<void> _import(BuildContext context) async {
    final state = context.read<AppState>();
    final importer = ImportService(state.storage);
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.description_outlined),
              title: const Text('导入文本（TXT）'),
              onTap: () => Navigator.pop(ctx, 'txt'),
            ),
            ListTile(
              leading: const Icon(Icons.photo_library_outlined),
              title: const Text('导入图片 / 漫画（选文件）'),
              subtitle: const Text('多张图片按文件名排序，作为一本漫画'),
              onTap: () => Navigator.pop(ctx, 'img'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('导入漫画文件夹（整目录）'),
              subtitle: const Text('扫描文件夹内全部图片（含子目录），作为一本漫画'),
              onTap: () => Navigator.pop(ctx, 'imgdir'),
            ),
            ListTile(
              leading: const Icon(Icons.picture_as_pdf_outlined),
              title: const Text('导入 PDF（漫画 / 文档）'),
              subtitle: const Text('PDF 每页转图，支持双页分割配置'),
              onTap: () => Navigator.pop(ctx, 'pdf'),
            ),
            ListTile(
              leading: const Icon(Icons.link),
              title: const Text('从网址导入'),
              onTap: () => Navigator.pop(ctx, 'url'),
            ),
          ],
        ),
      ),
    );
    if (action == null || !context.mounted) return;
    try {
      switch (action) {
        case 'txt':
          final books = await importer.pickTextFiles();
          if (books.isNotEmpty) await state.addBooks(books);
          break;
        case 'img':
          final book = await importer.pickImagesAsComic();
          if (book != null) await state.addBooks([book]);
          break;
        case 'imgdir':
          await _importFolderWithProgress(context, state, importer);
          break;
        case 'pdf':
          final books = await importer.pickPdfFiles();
          if (books.isNotEmpty) await state.addBooks(books);
          break;
        case 'url':
          await _importUrl(context, importer, state);
          break;
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('导入失败：$e')));
      }
    }
  }

  /// 文件夹导入：复制图片可能耗时较长（大目录），显示"正在导入"进度框，
  /// 避免用户以为卡死；完成后自动关闭并加入书架。
  Future<void> _importFolderWithProgress(
      BuildContext context, AppState state, ImportService importer) async {
    if (!context.mounted) return;
    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Dialog(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(
                width: 28,
                height: 28,
                child: CircularProgressIndicator(strokeWidth: 3),
              ),
              SizedBox(width: 16),
              Flexible(
                child: Text('正在导入图片…请稍候'),
              ),
            ],
          ),
        ),
      ),
    );
    Book? book;
    try {
      book = await importer.pickImageFolderAsComic();
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    if (book != null && context.mounted) {
      await state.addBooks([book]);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('未导入任何图片')));
    }
  }

  Future<void> _importUrl(
      BuildContext context, ImportService importer, AppState state) async {
    final controller = TextEditingController();
    final url = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('从网址导入'),
        content: TextField(
          controller: controller,
          keyboardType: TextInputType.url,
          decoration: const InputDecoration(
            hintText: 'https://example.com/book.txt',
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx), child: const Text('取消')),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text.trim()),
            child: const Text('下载'),
          ),
        ],
      ),
    );
    if (url == null || url.isEmpty) return;
    final book = await importer.importFromUrl(url);
    if (book != null) {
      await state.addBooks([book]);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('下载失败，请检查网址')));
    }
  }

  void _openBook(BuildContext context, Book book) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => switch (book.type) {
          BookType.txt => TxtReaderScreen(book: book),
          BookType.pdf => PdfReaderScreen(book: book),
          _ => ImageReaderScreen(book: book),
        },
      ),
    );
  }

  Future<void> _showBookMenu(BuildContext context, Book book) async {
    final state = context.read<AppState>();
    final action = await showModalBottomSheet<String>(
      context: context,
      showDragHandle: true,
      builder: (ctx) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            ListTile(
              leading: const Icon(Icons.delete_outline),
              title: const Text('从书架删除'),
              onTap: () => Navigator.pop(ctx, 'del'),
            ),
          ],
        ),
      ),
    );
    if (action == 'del') {
      await state.removeBook(book.id);
    }
  }

  @override
  Widget build(BuildContext context) {
    final state = context.watch<AppState>();
    final books = state.books;
    return Scaffold(
      appBar: AppBar(title: const Text('书架')),
      floatingActionButton: FloatingActionButton(
        onPressed: () => _import(context),
        tooltip: '导入',
        child: const Icon(Icons.add),
      ),
      body: books.isEmpty
          ? const _EmptyShelf()
          : GridView.builder(
              padding: const EdgeInsets.fromLTRB(12, 12, 12, 88),
              gridDelegate: const SliverGridDelegateWithMaxCrossAxisExtent(
                maxCrossAxisExtent: 150,
                mainAxisSpacing: 14,
                crossAxisSpacing: 14,
                childAspectRatio: 0.62,
              ),
              itemCount: books.length,
              itemBuilder: (ctx, i) {
                final b = books[i];
                return GestureDetector(
                  onTap: () => _openBook(ctx, b),
                  onLongPress: () => _showBookMenu(ctx, b),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(child: BookCover(book: b)),
                      const SizedBox(height: 4),
                      Text(
                        b.title,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: Theme.of(context).textTheme.bodySmall,
                      ),
                    ],
                  ),
                );
              },
            ),
    );
  }
}

class _EmptyShelf extends StatelessWidget {
  const _EmptyShelf();

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.auto_stories_outlined,
              size: 72, color: scheme.outlineVariant),
          const SizedBox(height: 16),
          Text('书架空空如也',
              style: Theme.of(context)
                  .textTheme
                  .titleMedium
                  ?.copyWith(color: scheme.outline)),
          const SizedBox(height: 8),
          Text('点击右下角 + 导入 TXT / 图片漫画 / PDF',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline)),
        ],
      ),
    );
  }
}
