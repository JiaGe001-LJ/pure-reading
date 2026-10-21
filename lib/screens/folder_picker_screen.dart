import 'dart:io';

import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;

/// 内置文件夹浏览器：不经过系统 DocumentsUI（真机 SAF 权限对话框不稳定），
/// 直接以真实路径列出目录，选择要导入的文件夹。
/// 依赖 Android "所有文件访问权限"（MANAGE_EXTERNAL_STORAGE）。
class FolderPickerScreen extends StatefulWidget {
  const FolderPickerScreen({super.key});

  @override
  State<FolderPickerScreen> createState() => _FolderPickerScreenState();
}

class _FolderPickerScreenState extends State<FolderPickerScreen> {
  static const _imageExts = {'jpg', 'jpeg', 'png', 'webp', 'bmp', 'gif'};
  static const _containerExts = {
    'mobi', 'epub', 'azw', 'azw3', 'zip', 'rar', '7z', 'cbz', 'cbr', 'tar', 'gz',
  };

  Directory _current = Directory('/storage/emulated/0');
  final List<Directory> _stack = [];
  String? _error;

  @override
  void initState() {
    super.initState();
    // 兜底：/storage/emulated/0 不可读时回退到可枚举的外部目录
    if (!_current.existsSync()) {
      final alt = Directory('/sdcard');
      _current = alt.existsSync() ? alt : Directory('/');
    }
  }

  void _enter(Directory d) {
    setState(() {
      _stack.add(_current);
      _current = d;
    });
  }

  void _up() {
    if (_stack.isEmpty) {
      Navigator.of(context).pop();
      return;
    }
    setState(() => _current = _stack.removeLast());
  }

  Future<List<_Entry>> _listEntries() async {
    try {
      final entries = <_Entry>[];
      await for (final e in _current.list(followLinks: false)) {
        final name = p.basename(e.path);
        if (name.startsWith('.')) continue; // 隐藏文件
        if (e is Directory) {
          var count = 0;
          try {
            await for (final c in e.list(followLinks: false)) {
              final cn = p.basename(c.path);
              if (cn.startsWith('.')) continue;
              if (c is Directory) {
                count++;
              } else if (_isBookFile(cn)) {
                count++;
              }
              if (count > 999) break;
            }
          } catch (_) {
            count = -1; // 无权限/不可读
          }
          entries.add(_Entry(name: name, path: e.path, isDir: true, childCount: count));
        } else if (_isBookFile(name)) {
          entries.add(_Entry(name: name, path: e.path, isDir: false));
        }
        // mobi / zip 等容器文件不显示，避免误选
      }
      entries.sort((a, b) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
        return _naturalCompare(a.name, b.name);
      });
      return entries;
    } catch (e) {
      _error = e.toString();
      return [];
    }
  }

  bool _isBookFile(String name) {
    final ext = p.extension(name).toLowerCase().replaceFirst('.', '');
    if (_containerExts.contains(ext)) return false;
    return _imageExts.contains(ext) || ext == 'pdf' || ext == 'txt' || ext == 'text';
  }

  static int _naturalCompare(String a, String b) {
    final re = RegExp(r'\d+');
    final am = re.allMatches(a).map((m) => int.parse(m.group(0)!)).toList();
    final bm = re.allMatches(b).map((m) => int.parse(m.group(0)!)).toList();
    final n = am.length < bm.length ? am.length : bm.length;
    for (var i = 0; i < n; i++) {
      if (am[i] != bm[i]) return am[i].compareTo(bm[i]);
    }
    return a.compareTo(b);
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(
        title: Text(_current.path, maxLines: 1, overflow: TextOverflow.ellipsis),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: _up,
        ),
      ),
      body: _error != null
          ? Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text('无法读取此文件夹：\n$_error\n\n请检查是否已开启"所有文件访问权限"',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: scheme.error)),
              ),
            )
          : FutureBuilder<List<_Entry>>(
              future: _listEntries(),
              builder: (ctx, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Center(child: CircularProgressIndicator());
                }
                final entries = snap.data ?? const [];
                if (entries.isEmpty) {
                  return Center(
                      child: Text('此文件夹内没有可导入的内容',
                          style: TextStyle(color: scheme.outline)));
                }
                return ListView.builder(
                  itemCount: entries.length,
                  itemBuilder: (ctx, i) {
                    final e = entries[i];
                    return ListTile(
                      leading: Icon(
                        e.isDir ? Icons.folder : _iconFor(e.name),
                        color: e.isDir ? scheme.primary : scheme.onSurfaceVariant,
                      ),
                      title: Text(e.name, maxLines: 1, overflow: TextOverflow.ellipsis),
                      subtitle: e.isDir && e.childCount >= 0
                          ? Text(e.childCount == 0 ? '空文件夹' : '内含 ${e.childCount} 个条目')
                          : null,
                      trailing: e.isDir ? const Icon(Icons.chevron_right) : null,
                      onTap: e.isDir
                          ? () => _enter(Directory(e.path))
                          : () {
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                                  content: Text('请选择文件夹，而不是单个文件')));
                            },
                    );
                  },
                );
              },
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: FilledButton.icon(
            icon: const Icon(Icons.download_done),
            label: const Text('导入此文件夹'),
            onPressed: () => Navigator.of(context).pop(_current.path),
          ),
        ),
      ),
    );
  }

  IconData _iconFor(String name) {
    final ext = p.extension(name).toLowerCase();
    if (ext == '.pdf') return Icons.picture_as_pdf_outlined;
    return Icons.image_outlined;
  }
}

class _Entry {
  final String name;
  final String path;
  final bool isDir;
  final int childCount;
  const _Entry({required this.name, required this.path, required this.isDir, this.childCount = 0});
}
