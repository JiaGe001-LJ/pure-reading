import 'dart:io';
import 'dart:math';

import 'package:file_picker/file_picker.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;

import '../models/book.dart';
import 'storage_service.dart';

class ImportService {
  final StorageService storage;

  ImportService(this.storage);

  static const _imageExts = ['jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'];
  static const _pdfExts = ['pdf'];

  String _newId() =>
      DateTime.now().microsecondsSinceEpoch.toRadixString(36) +
      Random().nextInt(9999).toString();

  /// 导入一个或多个 TXT 文本，每个文件成为一本书。
  Future<List<Book>> pickTextFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: ['txt', 'text'],
      allowMultiple: true,
    );
    if (result == null) return [];
    final books = <Book>[];
    for (final f in result.files) {
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
    return books;
  }

  /// 多选图片作为一个漫画合订本（按文件名自然排序）。
  Future<Book?> pickImagesAsComic() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _imageExts,
      allowMultiple: true,
    );
    if (result == null || result.files.isEmpty) return null;
    final id = _newId();
    final paths = <String>[];
    for (final f in result.files) {
      if (f.path == null) continue;
      final src = File(f.path!);
      final dest = await _copyIntoLibrary(src, id);
      paths.add(dest.path);
    }
    paths.sort(_naturalCompare);
    final cover = await _makeCover(paths.first);
    return Book(
      id: id,
      title: p.basenameWithoutExtension(paths.first),
      type: BookType.comic,
      files: paths,
      coverPath: cover?.path,
    );
  }

  /// 选择整个文件夹导入为漫画：扫描目录（含子目录）内全部图片，
  /// 按路径自然排序作为一本漫画（书名 = 文件夹名）。
  Future<Book?> pickImageFolderAsComic() async {
    final dirPath = await FilePicker.platform.getDirectoryPath();
    if (dirPath == null) return null;
    final root = Directory(dirPath);
    if (!await root.exists()) return null;
    final found = <File>[];
    await for (final e in root.list(recursive: true, followLinks: false)) {
      if (e is File && _imageExts.contains(p.extension(e.path).toLowerCase().replaceFirst('.', ''))) {
        found.add(e);
      }
    }
    if (found.isEmpty) return null;
    final id = _newId();
    final paths = <String>[];
    for (final src in found) {
      final dest = await _copyIntoLibrary(src, id);
      paths.add(dest.path);
    }
    paths.sort(_naturalCompare);
    final cover = await _makeCover(paths.first);
    return Book(
      id: id,
      title: p.basenameWithoutExtension(root.path),
      type: BookType.comic,
      files: paths,
      coverPath: cover?.path,
    );
  }

  /// 导入单个或多个 PDF，每个 PDF 成为一本书。
  Future<List<Book>> pickPdfFiles() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _pdfExts,
      allowMultiple: true,
    );
    if (result == null) return [];
    final books = <Book>[];
    for (final f in result.files) {
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

  /// 导入单张图片。
  Future<Book?> pickSingleImage() async {
    final result = await FilePicker.platform.pickFiles(
      type: FileType.custom,
      allowedExtensions: _imageExts,
      allowMultiple: false,
    );
    if (result == null || result.files.isEmpty) return null;
    final f = result.files.first;
    if (f.path == null) return null;
    final src = File(f.path!);
    final id = _newId();
    final dest = await _copyIntoLibrary(src, id);
    final cover = await _makeCover(dest.path);
    return Book(
      id: id,
      title: p.basenameWithoutExtension(src.path),
      type: BookType.image,
      files: [dest.path],
      coverPath: cover?.path,
    );
  }

  /// 从网址下载单个文件（txt / 图片）作为书。
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

  /// 文件名自然排序：page2 < page10。
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
