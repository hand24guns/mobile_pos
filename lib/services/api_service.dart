import 'package:dio/dio.dart';

class ApiService {
  static const String baseUrl = 'https://pos.aibipi.com/api';

  /// Base URL untuk gambar produk.
  /// Otomatis derived dari [baseUrl] → strip '/api' → tambah path gambar.
  /// Jika [baseUrl] diubah (staging/production), URL gambar ikut berubah.
  static String get productImageUrl {
    final origin = baseUrl.endsWith('/api')
        ? baseUrl.substring(0, baseUrl.length - 4)
        : baseUrl;
    return '$origin/dist/img/produk/';
  }

  static Dio getDio({String? token}) {
    final options = BaseOptions(
      baseUrl: baseUrl,
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
