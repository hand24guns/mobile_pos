import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';

class SessionService {
  static const String _keyToken      = 'token';
  static const String _keyUserID     = 'user_id';
  static const String _keyNama       = 'nama';
  static const String _keyUsername   = 'username';
  static const String _keyDeviceToken = 'device_token';

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

  // Simpan session setelah login
  static Future<void> saveSession({
    required String token,
    required int userID,
    required String nama,
    required String username,
  }) async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setString(_keyToken, token);
    await prefs.setInt(_keyUserID, userID);
    await prefs.setString(_keyNama, nama);
    await prefs.setString(_keyUsername, username);
  }

  // Ambil token
  static Future<String?> getToken() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken);
  }

  // Ambil semua data session
  static Future<Map<String, dynamic>> getSession() async {
    final prefs = await SharedPreferences.getInstance();
    return {
      'token':    prefs.getString(_keyToken) ?? '',
      'user_id':  prefs.getInt(_keyUserID) ?? 0,
      'nama':     prefs.getString(_keyNama) ?? '',
      'username': prefs.getString(_keyUsername) ?? '',
    };
  }

  // Cek apakah sudah login
  static Future<bool> isLoggedIn() async {
    final prefs = await SharedPreferences.getInstance();
    return prefs.getString(_keyToken) != null;
  }

  // Hapus session saat logout — device_token TIDAK dihapus
  // supaya cart isolasi tetap konsisten meski user ganti akun
  static Future<void> clearSession() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_keyToken);
    await prefs.remove(_keyUserID);
    await prefs.remove(_keyNama);
    await prefs.remove(_keyUsername);
  }
}