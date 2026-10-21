import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/services.dart' show MethodChannel;
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/book.dart';
import 'storage_service.dart';

class ImportService {
  final StorageService storage;

  ImportService(this.storage);

  static const MethodChannel _importerChannel =
      MethodChannel('pure_reading/importer');

  static const _imageExts = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'];
  static const _pdfExts = ['pdf'];
  static const _txtExts = ['txt', 'text'];

  String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      Random().nextInt(9999).toString();

  /// 导入一个或多个文件（TXT / 图片 / PDF 混合），自动识别类型：
  /// - 每个 TXT / PDF 各成为一本书；
  /// - 多张图片合并为一本漫画（按文件名自然排序）。
  Future<List<Book>> pickFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: [..._imageExts, ..._pdfExts, ..._txtExts],
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return [];
    final txts = <PlatformFile>[];
    final images = <PlatformFile>[];
    final pdfs = <PlatformFile>[];
    for (final f in result.files) {
      final ext = p.extension(f.name).toLowerCase().replaceFirst('.', '');
      if (_txtExts.contains(ext)) {
        txts.add(f);
      } else if (_imageExts.contains(ext)) {
        images.add(f);
      } else if (_pdfExts.contains(ext)) {
        pdfs.add(f);
      }
    }
    final books = <Book>[];
    for (final f in txts) {
      if (f.path == null) continue;
      final src = File(f.path!);
      final id = _newId();
      final dest = await _copyIntoLibrary(src, id);
      books.add(Book(
        id: id,
        title: p.basenameWithoutExtension(src.path),
        type: BookType.txt,
        files: [dest.path],
      ));
    }
    if (images.isNotEmpty) {
      final id = _newId();
      final paths = <String>[];
      for (final f in images) {
        if (f.path == null) continue;
        final src = File(f.path!);
        final dest = await _copyIntoLibrary(src, id);
        paths.add(dest.path);
      }
      paths.sort(_naturalCompare);
      final cover = await _makeCover(paths.first);
      books.add(Book(
        id: id,
        title: p.basenameWithoutExtension(paths.first),
        type: BookType.comic,
        files: paths,
        coverPath: cover?.path,
      ));
    }
    for (final f in pdfs) {
      if (f.path == null) continue;
      final src = File(f.path!);
      final id = _newId();
      final dest = await _copyIntoLibrary(src, id);
      books.add(Book(
        id: id,
        title: p.basenameWithoutExtension(src.path),
        type: BookType.pdf,
        files: [dest.path],
      ));
    }
    return books;
  }

  /// 选择整个文件夹导入为“书”，自动识别内容：
  /// - 根目录只有顺序图片（无子目录）→ 一本平铺漫画；
  /// - 根目录含 PDF 或子文件夹 → 文件夹书（子文件夹 = 章节），
  ///   在 App 内逐层浏览，无需再进系统文件管理器。
  ///
  /// Android 走系统目录选择器（SAF）+ DocumentsContract 枚举真实文件
  /// 并复制到书库目录（保持子目录层级）。其他平台回退到 file_picker。
  Future<Book?> pickBookFolder() async {
    final id = _newId();
    final destDir = p.join(storage.booksDir.path, id);
    final List<FolderFile> items;
    final String folderName;
    if (Platform.isAndroid) {
      try {
        final result = await _importerChannel
            .invokeMapMethod<String, dynamic>(
              'pickBookFolderAndCopy',
              {'destDir': destDir},
            )
            .timeout(const Duration(seconds: 90));
        if (result == null) return null;
        folderName = result['folderName'] as String? ?? p.basename(destDir);
        items = ((result['files'] as List?) ?? const [])
            .map((e) => FolderFile(
                  rel: (e as Map)['rel'] as String,
                  path: e['path'] as String,
                ))
            .toList();
      } catch (_) {
        // 通道失败（如选择器异常）回退到 file_picker 目录选择
        return _pickBookFolderFallback(destDir);
      }
    } else {
      return _pickBookFolderFallback(destDir);
    }
    if (items.isEmpty) return null;
    return _buildBookFromFolder(id, destDir, folderName, items);
  }

  /// Android 是否已开启"所有文件访问权限"（内置文件夹浏览器需要）。
  Future<bool> hasAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _importerChannel.invokeMethod<bool>('hasAllFilesAccess') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 跳转系统设置页开启"所有文件访问权限"。返回后需重新调用
  /// [hasAllFilesAccess] 确认是否已授权。
  Future<bool> requestAllFilesAccess() async {
    if (!Platform.isAndroid) return true;
    try {
      return await _importerChannel.invokeMethod<bool>('requestAllFilesAccess') ??
          false;
    } catch (_) {
      return false;
    }
  }

  /// 按真实路径导入整个文件夹为"书"（内置文件夹浏览器选择结果）。
  /// 自动判别：根目录纯顺序图片 → 平铺漫画；含子目录 / PDF → 文件夹书。
  Future<Book?> pickBookFolderByPath(String dirPath) async {
    final root = Directory(dirPath);
    if (!await root.exists()) return null;
    final id = _newId();
    final destDir = p.join(storage.booksDir.path, id);
    final items = <FolderFile>[];
    try {
      await for (final e in root.list(recursive: true, followLinks: false)) {
        if (e is! File) continue;
        final ext = p.extension(e.path).toLowerCase().replaceFirst('.', '');
        if (!_imageExts.contains(ext) && !_pdfExts.contains(ext)) continue;
        final rel = p.relative(e.path, from: root.path);
        items.add(FolderFile(rel: rel.replaceAll('\\', '/'), path: e.path));
      }
    } catch (_) {
      return null;
    }
    if (items.isEmpty) return null;
    final copied = <FolderFile>[];
    for (final f in items) {
      final src = File(f.path);
      final rel = f.rel;
      final targetDir = rel.contains('/')
          ? Directory(p.join(destDir, p.dirname(rel.replaceAll('/', p.separator))))
          : Directory(destDir);
      await targetDir.create(recursive: true);
      var base = p.basename(src.path);
      var dest = File(p.join(targetDir.path, base));
      var n = 1;
      while (await dest.exists()) {
        base =
            '${p.basenameWithoutExtension(src.path)}_$n.${p.extension(src.path)}';
        dest = File(p.join(targetDir.path, base));
        n++;
      }
      await src.copy(dest.path);
      copied.add(FolderFile(
          rel: rel.contains('/')
              ? '${p.dirname(rel.replaceAll('/', p.separator)).replaceAll(p.separator, '/')}/$base'
              : base,
          path: dest.path));
    }
    return _buildBookFromFolder(id, destDir, p.basename(root.path), copied);
  }

  Future<Book?> _pickBookFolderFallback(String destDir) async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return null;
    final root = Directory(dirPath);
    if (!await root.exists()) return null;
    final items = <FolderFile>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is! File) continue;
      final ext = p.extension(e.path).toLowerCase().replaceFirst('.', '');
      if (!_imageExts.contains(ext) && !_pdfExts.contains(ext)) continue;
      final rel = p.relative(e.path, from: root.path);
      items.add(FolderFile(rel: rel.replaceAll('\\', '/'), path: e.path));
    }
    if (items.isEmpty) return null;
    final folderName = p.basename(root.path);
    final copied = <FolderFile>[];
    for (final f in items) {
      final src = File(f.path);
      final rel = f.rel;
      final targetDir = rel.contains('/')
          ? Directory(p.join(destDir, p.dirname(rel.replaceAll('/', p.separator))))
          : Directory(destDir);
      await targetDir.create(recursive: true);
      var base = p.basename(src.path);
      var dest = File(p.join(targetDir.path, base));
      var n = 1;
      while (await dest.exists()) {
        base =
            '${p.basenameWithoutExtension(src.path)}_$n.${p.extension(src.path)}';
        dest = File(p.join(targetDir.path, base));
        n++;
      }
      await src.copy(dest.path);
      copied.add(FolderFile(
          rel: rel.contains('/')
              ? '${p.dirname(rel.replaceAll('/', p.separator)).replaceAll(p.separator, '/')}/$base'
              : base,
          path: dest.path));
    }
    return _buildBookFromFolder(_newId(), destDir, folderName, copied);
  }

  Book? _buildBookFromFolder(
      String id, String destDir, String folderName, List<FolderFile> items) {
    if (items.isEmpty) return null;
    final absPaths = items.map((e) => e.path).toList();
    // 根目录只有图片（无子目录）→ 平铺漫画书
    final allRootLevel = items.every((e) => !e.rel.contains('/'));
    final allImages = items.every((e) => _imageExts
        .contains(p.extension(e.rel).toLowerCase().replaceFirst('.', '')));
    if (allRootLevel && allImages) {
      absPaths.sort(_naturalCompare);
      return Book(
        id: id,
        title: folderName,
        type: BookType.comic,
        files: absPaths,
      );
    }
    // 含子目录 / PDF → 文件夹书（树结构，子文件夹 = 章节）
    final root = FolderNode(name: folderName, rel: '', isDir: true, children: []);
    for (final f in items) {
      _insertNode(root, f.rel.split('/'), f.path);
    }
    _sortTree(root);
    final cover = _makeCoverSync(absPaths);
    return Book(
      id: id,
      title: folderName,
      type: BookType.folder,
      files: absPaths,
      rootDir: destDir,
      structure: root.children,
      coverPath: cover,
    );
  }

  void _insertNode(FolderNode parent, List<String> segs, String absPath) {
    if (segs.isEmpty) return;
    if (segs.length == 1) {
      final rel = parent.rel.isEmpty ? segs[0] : '${parent.rel}/${segs[0]}';
      parent.children.add(FolderNode(
          name: segs[0], rel: rel, isDir: false, absPath: absPath));
      return;
    }
    final dirName = segs.first;
    FolderNode? dir;
    for (final c in parent.children) {
      if (c.isDir && c.name == dirName) {
        dir = c;
        break;
      }
    }
    if (dir == null) {
      final rel = parent.rel.isEmpty ? dirName : '${parent.rel}/$dirName';
      dir = FolderNode(name: dirName, rel: rel, isDir: true);
      parent.children.add(dir);
    }
    _insertNode(dir, segs.sublist(1), absPath);
  }

  void _sortTree(FolderNode node) {
    node.children.sort((a, b) {
      if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      return _naturalCompareName(a.name, b.name);
    });
    for (final c in node.children) {
      if (c.isDir) _sortTree(c);
    }
  }

  /// 从网址下载单个文件（txt / 图片 / pdf）作为书。
  Future<Book?> importFromUrl(String url) async {
    final uri = Uri.tryParse(url.trim());
    if (uri == null || !(uri.scheme == 'http' || uri.scheme == 'https')) {
      return null;
    }
    final client = HttpClient()..connectionTimeout = const Duration(seconds: 25);
    try {
      final req = await client.getUrl(uri);
      final resp = await req.close();
      if (resp.statusCode != 200) return null;
      final bytes = <int>[];
      await for (final chunk in resp) {
        bytes.addAll(chunk);
      }
      final name = p.basename(uri.path.isEmpty ? 'download' : uri.path);
      if (name.isEmpty || name == '.') return null;
      final id = _newId();
      final dir = Directory(p.join(storage.booksDir.path, id));
      await dir.create(recursive: true);
      final dest = File(p.join(dir.path, name));
      await dest.writeAsBytes(bytes, flush: true);
      final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
      final isImage = _imageExts.contains(ext);
      final isPdf = _pdfExts.contains(ext);
      String? cover;
      if (isImage) {
        final c = await _makeCover(dest.path);
        cover = c?.path;
      }
      return Book(
        id: id,
        title: p.basenameWithoutExtension(name),
        type: isPdf
            ? BookType.pdf
            : (isImage ? BookType.image : BookType.txt),
        files: [dest.path],
        coverPath: cover,
      );
    } finally {
      client.close(force: true);
    }
  }

  Future<File> _copyIntoLibrary(File src, String bookId) async {
    final dir = Directory(p.join(storage.booksDir.path, bookId));
    if (!await dir.exists()) {
      await dir.create(recursive: true);
    }
    var base = p.basename(src.path);
    var dest = File(p.join(dir.path, base));
    var n = 1;
    while (await dest.exists()) {
      base = '${p.basenameWithoutExtension(src.path)}_$n.${p.extension(src.path)}';
      dest = File(p.join(dir.path, base));
      n++;
    }
    await src.copy(dest.path);
    return dest;
  }

  Future<File?> _makeCover(String imagePath) async {
    try {
      final bytes = await File(imagePath).readAsBytes();
      final decoded = img.decodeImage(bytes);
      if (decoded == null) return null;
      final thumb = img.copyResize(decoded, width: 400);
      final out = File(p.join(p.dirname(imagePath), 'cover.jpg'));
      await out.writeAsBytes(img.encodeJpg(thumb, quality: 80), flush: true);
      return out;
    } catch (_) {
      return null;
    }
  }

  String? _makeCoverSync(List<String> paths) {
    for (final f in paths) {
      final ext = p.extension(f).toLowerCase().replaceFirst('.', '');
      if (!_imageExts.contains(ext)) continue;
      try {
        final bytes = File(f).readAsBytesSync();
        final decoded = img.decodeImage(bytes);
        if (decoded == null) continue;
        final thumb = img.copyResize(decoded, width: 400);
        final out = File(p.join(p.dirname(f), 'cover.jpg'));
        out.writeAsBytesSync(img.encodeJpg(thumb, quality: 80));
        return out.path;
      } catch (_) {
        continue;
      }
    }
    return null;
  }

  /// 文件名自然排序：page2 < page10。
  static int _naturalCompare(String a, String b) => _naturalCompareName(
      p.basenameWithoutExtension(a), p.basenameWithoutExtension(b));

  static int _naturalCompareName(String a, String b) {
    final re = RegExp(r'\d+');
    final am = re.allMatches(a).map((m) => int.parse(m.group(0)!)).toList();
    final bm = re.allMatches(b).map((m) => int.parse(m.group(0)!)).toList();
    final n = am.length < bm.length ? am.length : bm.length;
    for (var i = 0; i < n; i++) {
      if (am[i] != bm[i]) return am[i].compareTo(bm[i]);
    }
    return a.compareTo(b);
  }
}

/// 文件夹导入的原始条目（相对路径 + 绝对路径）。
class FolderFile {
  final String rel;
  final String path;
  const FolderFile({required this.rel, required this.path});
}
