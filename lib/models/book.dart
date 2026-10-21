enum BookType { txt, comic, image, pdf }

class Book {
  final String id;
  String title;
  BookType type;
  List<String> files;
  String? coverPath;
  int pageIndex;
  DateTime addedAt;

  Book({
    required this.id,
    required this.title,
    required this.type,
    required this.files,
    this.coverPath,
    this.pageIndex = 0,
    DateTime? addedAt,
  }) : addedAt = addedAt ?? DateTime.now();

  Map<String, dynamic> toJson() => {
        'id': id,
        'title': title,
        'type': type.name,
        'files': files,
        'cover': coverPath,
        'pageIndex': pageIndex,
        'addedAt': addedAt.toIso8601String(),
      };

  factory Book.fromJson(Map<String, dynamic> j) => Book(
        id: j['id'] as String,
        title: j['title'] as String,
        type: BookType.values.byName(j['type'] as String),
        files: List<String>.from(j['files'] as List),
        coverPath: j['cover'] as String?,
        pageIndex: (j['pageIndex'] as num?)?.toInt() ?? 0,
        addedAt: DateTime.tryParse((j['addedAt'] as String?) ?? '') ?? DateTime.now(),
      );
}
