import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../models/models.dart';
import '../theme.dart';

class AppState extends ChangeNotifier {
  static const _storage = FlutterSecureStorage();
  static const _panelsKey = 'panels_v1';
  static const maxPanels = 5;

  late SharedPreferences _prefs;
  List<PanelConfig> _panels = [];
  Locale locale = const Locale('fa');
  ThemeMode themeMode = ThemeMode.dark;
  AppStyle style = AppStyle.aurora;

  List<PanelConfig> get panels => List.unmodifiable(_panels);

  bool get canAddPanel => _panels.length < maxPanels;

  PanelConfig? panelById(String id) => _panels.where((p) => p.id == id).firstOrNull;

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    locale = Locale(_prefs.getString('lang') ?? 'fa');
    themeMode = ThemeMode.values.firstWhere(
        (m) => m.name == _prefs.getString('theme'),
        orElse: () => ThemeMode.dark);
    style = AppStyle.values.firstWhere((v) => v.name == _prefs.getString('style'),
        orElse: () => AppStyle.aurora);
    try {
      final raw = await _storage.read(key: _panelsKey);
      if (raw != null) {
        _panels = (jsonDecode(raw) as List)
            .map((e) => PanelConfig.fromJson(Map<String, dynamic>.from(e as Map)))
            .toList();
      }
    } catch (_) {
      _panels = [];
    }
  }

  Future<void> _save() => _storage.write(
      key: _panelsKey, value: jsonEncode(_panels.map((p) => p.toJson()).toList()));

  Future<void> upsert(PanelConfig p) async {
    final i = _panels.indexWhere((e) => e.id == p.id);
    if (i >= 0) {
      _panels[i] = p;
    } else {
      if (!canAddPanel) throw StateError('Maximum of $maxPanels panels reached');
      _panels.add(p);
    }
    notifyListeners();
    await _save();
  }

  Future<void> remove(String id) async {
    _panels.removeWhere((e) => e.id == id);
    notifyListeners();
    await _save();
  }

  Future<void> reorder(int oldIndex, int newIndex) async {
    if (newIndex > oldIndex) newIndex--;
    final p = _panels.removeAt(oldIndex);
    _panels.insert(newIndex, p);
    notifyListeners();
    await _save();
  }

  void setLocale(String code) {
    locale = Locale(code);
    _prefs.setString('lang', code);
    notifyListeners();
  }

  void setTheme(ThemeMode mode) {
    themeMode = mode;
    _prefs.setString('theme', mode.name);
    notifyListeners();
  }

  void setStyle(AppStyle v) {
    style = v;
    _prefs.setString('style', v.name);
    notifyListeners();
  }
}
