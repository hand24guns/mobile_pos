import 'package:dio/dio.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'session_service.dart';

class ApiService {
  /// URL default (dipakai kalau user belum pernah setting custom URL).
  static const String defaultBaseUrl = 'https://pos.aibipi.com/api';

  static const String _prefsKey = 'custom_base_url';

  static String _baseUrl = defaultBaseUrl;
  static bool _initialized = false;

  /// URL API yang sedang aktif (default atau hasil custom setting user).
  static String get baseUrl => _baseUrl;

  /// True kalau user sudah pernah set custom URL (bukan default).
  static bool get isCustomBaseUrl => _baseUrl != defaultBaseUrl;

  /// WAJIB dipanggil sekali di awal (main.dart) sebelum widget lain
  /// memakai ApiService.baseUrl atau ApiService.getDio().
  /// Membaca custom URL yang tersimpan (kalau ada) dari local storage.
  static Future<void> init() async {
    if (_initialized) return;
    final prefs = await SharedPreferences.getInstance();
    final saved = prefs.getString(_prefsKey);
    if (saved != null && saved.trim().isNotEmpty) {
      _baseUrl = saved.trim();
    }
    _initialized = true;
  }

  /// Simpan custom base URL. Kirim null / string kosong untuk reset
  /// kembali ke [defaultBaseUrl].
  ///
  /// Kalau URL yang aktif benar-benar berubah (pindah server), session
  /// lama otomatis di-clear (`SessionService.clearSession()`) karena
  /// token dari server sebelumnya tidak akan valid di server baru.
  /// device_token TIDAK ikut terhapus (lihat SessionService).
  static Future<void> setBaseUrl(String? url) async {
    final prefs = await SharedPreferences.getInstance();
    final oldUrl = _baseUrl;

    String newUrl;
    if (url == null || url.trim().isEmpty) {
      await prefs.remove(_prefsKey);
      newUrl = defaultBaseUrl;
    } else {
      var cleaned = url.trim();
      // Buang trailing slash biar konsisten sama format defaultBaseUrl.
      while (cleaned.endsWith('/')) {
        cleaned = cleaned.substring(0, cleaned.length - 1);
      }
      // Kalau user lupa isi skema, asumsikan https.
      if (!cleaned.startsWith('http://') && !cleaned.startsWith('https://')) {
        cleaned = 'https://$cleaned';
      }
      await prefs.setString(_prefsKey, cleaned);
      newUrl = cleaned;
    }

    _baseUrl = newUrl;

    if (newUrl != oldUrl) {
      await SessionService.clearSession();
    }
  }

  /// Base URL untuk gambar produk.
  /// Otomatis derived dari [baseUrl] → strip '/api' → tambah path gambar.
  static String get productImageUrl {
    final origin = _baseUrl.endsWith('/api')
        ? _baseUrl.substring(0, _baseUrl.length - 4)
        : _baseUrl;
    return '$origin/dist/img/produk/';
  }

  static Dio getDio({String? token}) {
    final options = BaseOptions(
      baseUrl: _baseUrl,
      connectTimeout: const Duration(seconds: 10),
      receiveTimeout: const Duration(seconds: 10),
      headers: token != null ? {'Authorization': 'Bearer $token'} : {},
    );

    final dio = Dio(options);

    // Interceptor untuk debug
    dio.interceptors.add(LogInterceptor(
      requestHeader: true,
      responseBody: true,
    ));

    return dio;
  }
}
