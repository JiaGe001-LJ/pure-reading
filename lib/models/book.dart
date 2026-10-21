enum BookType { txt, comic, image, pdf, folder }

/// 文件夹书的目录树节点（子文件夹 = 章节）。
class FolderNode {
  final String name;
  final String rel; // 相对书库根目录的路径，如 "第1章/01.jpg"
  final bool isDir;
  final String? absPath; // 文件节点的绝对路径；目录节点为 null
  final List<FolderNode> children;

  FolderNode({
    required this.name,
    required this.rel,
    required this.isDir,
    this.absPath,
    List<FolderNode>? children,
  }) : children = children ?? [];

  Map<String, dynamic> toJson() => {
        'name': name,
        'rel': rel,
        'isDir': isDir,
        'absPath': absPath,
        'children': children.map((c) => c.toJson()).toList(),
      };

  factory FolderNode.fromJson(Map<String, dynamic> j) => FolderNode(
        name: j['name'] as String,
        rel: j['rel'] as String,
        isDir: (j['isDir'] as bool?) ?? false,
        absPath: j['absPath'] as String?,
        children: List<FolderNode>.from(
            ((j['children'] as List?) ?? const []).map((c) => FolderNode.fromJson(c as Map<String, dynamic>))),
      );
}

class Book {
  final String id;
  String title;
  BookType type;
  List<String> files;
  String? coverPath;
  int pageIndex;
  DateTime addedAt;
  List<int> bookmarks;
  String? rootDir; // folder 书：书库内根目录绝对路径
  List<FolderNode>? structure; // folder 书：目录树

  Book({
    required this.id,
    required this.title,
    required this.type,
    required this.files,
    this.coverPath,
    this.pageIndex = 0,
    this.bookmarks = const [],
    this.rootDir,
    this.structure,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.name,
        'files': files,
        'cover': coverPath,
        'pageIndex': pageIndex,
        'bookmarks': bookmarks,
        'addedAt': addedAt.toIso8601String(),
        'rootDir': rootDir,
        'structure': structure?.map((n) => n.toJson()).toList(),
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        type: BookType.values.byName(j['type'] as String),
        files: List<String>.from(j['files'] as List),
        coverPath: j['cover'] as String?,
        pageIndex: (j['pageIndex'] as num?)?.toInt() ?? 0,
        bookmarks: List<int>.from((j['bookmarks'] as List?) ?? const []),
        rootDir: j['rootDir'] as String?,
        structure: (j['structure'] as List?)
            ?.map((n) => FolderNode.fromJson(n as Map<String, dynamic>))
            .toList(),
        addedAt: DateTime.tryParse((j['addedAt'] as String?) ?? '') ?? DateTime.now(),
      );
}
