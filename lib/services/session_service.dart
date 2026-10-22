import 'dart:convert';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SessionService {
  static const String _keyToken       = 'token';
  static const String _keyUserID      = 'user_id';
  static const String _keyNama        = 'nama';
  static const String _keyUsername    = 'username';
  static const String _keyOutlets     = 'outlets'; // CSV: "1,2,3"
  static const String _keyMenus       = 'menus';   // JSON array of menu path/link with is_view=1
  static const String _keyEditable    = 'editable'; // JSON array of menu detail path with is_edit=1
  static const String _keyDeviceToken = 'device_token';

  // Token disimpan terpisah lewat flutter_secure_storage (Android
  // Keystore / iOS Keychain, terenkripsi) — bukan SharedPreferences
  // yang plaintext. Field lain (nama, username, outlets, menus,
  // device_token) tidak sensitif dan tetap di SharedPreferences.
  static const FlutterSecureStorage _secureStorage = FlutterSecureStorage();

  // ============================================================
  // DEVICE TOKEN — generate sekali saat pertama kali install,
  // simpan permanen di shared_preferences.
  // Scope: per device (shared antar sesi login).
  // ============================================================
  static Future<String> getDeviceToken() async {
    final prefs = await SharedPreferences.getInstance();
    String? token = prefs.getString(_keyDeviceToken);
    if (token == null || token.isEmpty) {
      token = const Uuid().v4();
      await prefs.setString(_keyDeviceToken, token);
    }
    return token;
  }

  // ============================================================
  // SAVE SESSION — dipanggil setelah login sukses.
  // outlets = list of dim_divisi_id yang bisa diakses user ini.
  // ============================================================
  static Future<void> saveSession({
    required String token,
    required int userID,
    required String nama,
    required String username,
    required List<int> outlets,
    List<String> menus = const [],
    List<String> editable = const [],
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.write(key: _keyToken, value: token);
    await prefs.setInt(_keyUserID,      userID);
    await prefs.setString(_keyNama,     nama);
    await prefs.setString(_keyUsername, username);
    await prefs.setString(_keyOutlets,  outlets.join(','));
    await prefs.setString(_keyMenus,    jsonEncode(menus));
    await prefs.setString(_keyEditable, jsonEncode(editable));
  }

  // ============================================================
  // GET SESSION — returns semua field termasuk outlets as List<int>
  // ============================================================
  static Future<Map<String, dynamic>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    final raw = prefs.getString(_keyOutlets) ?? '';
    return {
      'token':    await _secureStorage.read(key: _keyToken) ?? '',
      'user_id':  prefs.getInt(_keyUserID)      ?? 0,
      'nama':     prefs.getString(_keyNama)     ?? '',
      'username': prefs.getString(_keyUsername) ?? '',
      'outlets':  _parseOutlets(raw),
      'menus':    _parseMenus(prefs.getString(_keyMenus) ?? ''),
      'editable': _parseMenus(prefs.getString(_keyEditable) ?? ''),
    };
  }

  // ============================================================
  // GET OUTLETS — shortcut kalau hanya butuh list store ID
  // ============================================================
  static Future<List<int>> getOutlets() async {
    final prefs = await SharedPreferences.getInstance();
    return _parseOutlets(prefs.getString(_keyOutlets) ?? '');
  }

  // Ambil token
  static Future<String?> getToken() async {
    return _secureStorage.read(key: _keyToken);
  }

  // Cek apakah sudah login
  static Future<bool> isLoggedIn() async {
    final token = await _secureStorage.read(key: _keyToken);
    return token != null && token.isNotEmpty;
  }

  // ============================================================
  // CLEAR SESSION — device_token TIDAK dihapus
  // supaya cart isolasi tetap konsisten meski user ganti akun
  // ============================================================
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await _secureStorage.delete(key: _keyToken);
    await prefs.remove(_keyUserID);
    await prefs.remove(_keyNama);
    await prefs.remove(_keyUsername);
    await prefs.remove(_keyOutlets);
    await prefs.remove(_keyMenus);
    await prefs.remove(_keyEditable);
  }

  // ── Helper private ─────────────────────────────────────────
  static List<int> _parseOutlets(String raw) {
    if (raw.isEmpty) return [];
    return raw
        .split(',')
        .map((e) => int.tryParse(e.trim()) ?? 0)
        .where((e) => e > 0)
        .toList();
  }

  static List<String> _parseMenus(String raw) {
    if (raw.isEmpty) return [];
    try {
      final decoded = jsonDecode(raw);
      if (decoded is List) return decoded.map((e) => e.toString()).toList();
    } catch (_) {}
    return [];
  }
}
