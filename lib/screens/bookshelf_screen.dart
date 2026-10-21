import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../models/book.dart';
import '../services/import_service.dart';
import '../state/app_state.dart';
import '../widgets/book_cover.dart';
import 'folder_picker_screen.dart';
import 'folder_reader_screen.dart';
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
              leading: const Icon(Icons.file_open_outlined),
              title: const Text('导入文件（TXT / 图片 / PDF）'),
              subtitle: const Text('选择一个或多个文件，自动识别类型，合并成书'),
              onTap: () => Navigator.pop(ctx, 'files'),
            ),
            ListTile(
              leading: const Icon(Icons.folder_outlined),
              title: const Text('导入文件夹（图片漫画 / PDF / 章节）'),
              subtitle: const Text('自动识别内容；子文件夹=章节，在 App 内继续打开'),
              onTap: () => Navigator.pop(ctx, 'folder'),
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
        case 'files':
          final books = await importer.pickFiles();
          if (books.isNotEmpty) await state.addBooks(books);
          break;
        case 'folder':
          await _importFolder(context, state, importer);
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

  /// 文件夹导入：优先内置文件夹浏览器（真机 SAF 权限对话框不稳定），
  /// 未开启"所有文件访问权限"时引导授权；复制耗时较长时显示进度框。
  Future<void> _importFolder(
      BuildContext context, AppState state, ImportService importer) async {
    String? dirPath;
    if (Platform.isAndroid) {
      var hasAccess = await importer.hasAllFilesAccess();
      if (!hasAccess) {
        if (!context.mounted) return;
        final choice = await showDialog<String>(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('选择文件夹的方式'),
            content: const Text(
                '为了稳定选择文件夹（避免系统文件选择器偶尔闪退），推荐开启"所有文件访问权限"，'
                '之后直接在洁阅读内浏览文件夹。\n\n也可以继续用系统文件选择器。'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'saf'),
                child: const Text('用系统选择器（备用）'),
              ),
              TextButton(
                onPressed: () => Navigator.pop(ctx, 'grant'),
                child: const Text('去开启权限'),
              ),
            ],
          ),
        );
        if (!context.mounted) return;
        if (choice == 'grant') {
          await importer.requestAllFilesAccess();
          hasAccess = await importer.hasAllFilesAccess();
          if (hasAccess && context.mounted) {
            dirPath = await Navigator.of(context).push<String>(
              MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
            );
          } else if (context.mounted) {
            ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                content: Text('未开启权限，无法使用内置文件夹浏览器')));
            return;
          } else {
            return;
          }
        } else {
          // 备选：系统 SAF 选择器
          await _importFolderWithProgress(context, state, importer, null);
          return;
        }
      } else if (context.mounted) {
        dirPath = await Navigator.of(context).push<String>(
          MaterialPageRoute(builder: (_) => const FolderPickerScreen()),
        );
      }
    } else {
      // 非 Android：file_picker 目录选择
      dirPath = await FilePicker.platform.getDirectoryPath();
    }
    if (!context.mounted) return;
    if (dirPath == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('已取消导入（请选择文件夹，不要选 mobi / zip 等压缩包文件）')));
      return;
    }
    await _importFolderWithProgress(context, state, importer, dirPath);
  }

  /// 文件夹导入：复制图片可能耗时较长（大目录），显示"正在导入"进度框，
  /// 避免用户以为卡死；完成后自动关闭并加入书架。
  /// [dirPath] 非空时按真实路径导入（内置浏览器）；为空时走系统 SAF。
  Future<void> _importFolderWithProgress(BuildContext context, AppState state,
      ImportService importer, String? dirPath) async {
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
      book = dirPath == null
          ? await importer.pickBookFolder()
          : await importer.pickBookFolderByPath(dirPath);
    } finally {
      if (context.mounted) {
        Navigator.of(context, rootNavigator: true).pop();
      }
    }
    if (book != null && context.mounted) {
      await state.addBooks([book]);
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('已取消导入（请选择文件夹，不要选 mobi / zip 等压缩包文件）'),
      ));
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
          BookType.folder => FolderReaderScreen(book: book),
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
          Text('点击右下角 + 导入文件 / 文件夹 / 网址',
              style: Theme.of(context)
                  .textTheme
                  .bodySmall
                  ?.copyWith(color: scheme.outline)),
        ],
      ),
    );
  }
}
