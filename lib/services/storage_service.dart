import 'dart:convert';
import 'dart:io';

import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../models/split_config.dart';

class StorageService {
  late Directory documentsDir;
  late Directory booksDir;

  File get _booksFile => File(p.join(documentsDir.path, 'books.json'));
  File get _settingsFile => File(p.join(documentsDir.path, 'settings.json'));

  Future<void> init() async {
    documentsDir = await getApplicationDocumentsDirectory();
    booksDir = Directory(p.join(documentsDir.path, 'books'));
    if (!await booksDir.exists()) {
      await booksDir.create(recursive: true);
    }
  }

  Future<List<Book>> loadBooks() async {
    try {
      if (!await _booksFile.exists()) return [];
      final raw = await _booksFile.readAsString();
      final list = jsonDecode(raw) as List;
      final books = list
          .map((e) => Book.fromJson(e as Map<String, dynamic>))
          .toList();
      books.removeWhere(
          (b) => b.files.isEmpty || !File(b.files.first).existsSync());
      return books;
    } catch (_) {
      return [];
    }
  }

  Future<void> saveBooks(List<Book> books) async {
    final raw =
        jsonEncode(books.map((b) => b.toJson()).toList());
    await _booksFile.writeAsString(raw, flush: true);
  }

  Future<AppSettings> loadSettings() async {
    List<SplitConfig> customs = [];
    String themeName = '';
    double fontSize = 18;
    String fontFamily = '';
    String transitionName = '';
    String activeId = SplitConfig.presetNoneId;
    try {
      if (await _settingsFile.exists()) {
        final raw = await _settingsFile.readAsString();
        final map = jsonDecode(raw) as Map<String, dynamic>;
        themeName = (map['theme'] as String?) ?? '';
        fontSize = (map['fontSize'] as num?)?.toDouble() ?? 18;
        fontFamily = (map['fontFamily'] as String?) ?? '';
        transitionName = (map['pageTransition'] as String?) ?? '';
        activeId = (map['activeSplit'] as String?) ??
            SplitConfig.presetNoneId;
        final customsRaw = map['customSplits'] as List? ?? [];
        customs = customsRaw
            .map((e) => SplitConfig.fromJson(e as Map<String, dynamic>))
            .toList();
      }
    } catch (_) {}
    return AppSettings(
      themePref: ThemePref.values.asNameMap()[themeName] ?? ThemePref.system,
      fontSize: fontSize,
      fontFamily: fontFamily,
      pageTransition: PageTransitionStyle.values.asNameMap()[transitionName] ??
          PageTransitionStyle.horizontal,
      activeSplitConfigId: activeId,
      customSplitConfigs: customs,
    );
  }

  Future<void> saveSettings(AppSettings s) async {
    final map = <String, dynamic>{
      'theme': s.themePref.name,
      'fontSize': s.fontSize,
      'fontFamily': s.fontFamily,
      'pageTransition': s.pageTransition.name,
      'activeSplit': s.activeSplitConfigId,
      'customSplits':
          s.customSplitConfigs.map((c) => c.toJson()).toList(),
    };
    await _settingsFile.writeAsString(jsonEncode(map), flush: true);
  }
}
