import 'prefs_manager.dart';

class ContactSettingsStore {
  static const String _smazKeyPrefix = 'contact_smaz_';
  static const String _favoriteKeyPrefix = 'contact_favorite_';

  Future<bool> loadSmazEnabled(String contactKeyHex) async {
    final prefs = PrefsManager.instance;
    final key = '$_smazKeyPrefix$contactKeyHex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveSmazEnabled(String contactKeyHex, bool enabled) async {
    final prefs = PrefsManager.instance;
    final key = '$_smazKeyPrefix$contactKeyHex';
    await prefs.setBool(key, enabled);
  }

  Future<bool> loadFavorite(String contactKeyHex) async {
    final prefs = PrefsManager.instance;
    final key = '$_favoriteKeyPrefix$contactKeyHex';
    return prefs.getBool(key) ?? false;
  }

  Future<void> saveFavorite(String contactKeyHex, bool isFavorite) async {
    final prefs = PrefsManager.instance;
    final key = '$_favoriteKeyPrefix$contactKeyHex';
    await prefs.setBool(key, isFavorite);
  }

  Future<Set<String>> loadFavoriteContactKeys() async {
    final prefs = PrefsManager.instance;
    final keys = prefs.getKeys();
    final favorites = <String>{};
    for (final key in keys) {
      if (!key.startsWith(_favoriteKeyPrefix)) continue;
      if (prefs.getBool(key) != true) continue;
      favorites.add(key.substring(_favoriteKeyPrefix.length));
    }
    return favorites;
  }
}
