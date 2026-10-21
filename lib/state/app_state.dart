import 'package:flutter/foundation.dart';

import '../models/app_settings.dart';
import '../models/book.dart';
import '../models/split_config.dart';
import '../services/storage_service.dart';

class AppState extends ChangeNotifier {
  final storage = StorageService();
  late AppSettings settings;
  List<Book> books = [];

  Future<void> init() async {
    await storage.init();
    settings = await storage.loadSettings();
    books = await storage.loadBooks();
  }

  List<SplitConfig> get allSplitConfigs =>
      [...SplitConfig.presets, ...settings.customSplitConfigs];

  SplitConfig get activeSplitConfig {
    for (final c in allSplitConfigs) {
      if (c.id == settings.activeSplitConfigId) return c;
    }
    return SplitConfig.presets.first;
  }

  Future<void> setThemePref(ThemePref v) async {
    settings.themePref = v;
    notifyListeners();
    await storage.saveSettings(settings);
  }

  Future<void> setFontSize(double v) async {
    settings.fontSize = v.clamp(12.0, 32.0);
    notifyListeners();
    await storage.saveSettings(settings);
  }

  Future<void> setFontFamily(String v) async {
    settings.fontFamily = v;
    notifyListeners();
    await storage.saveSettings(settings);
  }

  Future<void> setPageTransition(PageTransitionStyle v) async {
    settings.pageTransition = v;
    notifyListeners();
    await storage.saveSettings(settings);
  }

  Future<void> setActiveSplitConfig(String id) async {
    settings.activeSplitConfigId = id;
    notifyListeners();
    await storage.saveSettings(settings);
  }

  Future<void> addSplitConfig(SplitConfig c) async {
    settings.customSplitConfigs.add(c);
    notifyListeners();
    await storage.saveSettings(settings);
  }

  Future<void> removeSplitConfig(String id) async {
    settings.customSplitConfigs.removeWhere((c) => c.id == id);
    if (settings.activeSplitConfigId == id) {
      settings.activeSplitConfigId = SplitConfig.presetNoneId;
    }
    notifyListeners();
    await storage.saveSettings(settings);
  }

  Future<void> addBooks(List<Book> newBooks) async {
    books.addAll(newBooks);
    notifyListeners();
    await storage.saveBooks(books);
  }

  Future<void> removeBook(String id) async {
    books.removeWhere((b) => b.id == id);
    notifyListeners();
    await storage.saveBooks(books);
  }

  Future<void> saveBooks() async {
    notifyListeners();
    await storage.saveBooks(books);
  }
}
