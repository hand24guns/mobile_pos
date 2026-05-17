import 'package:dio/dio.dart';

class ApiService {
  static const String baseUrl = 'https://pos.aibipi.com/api';

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
