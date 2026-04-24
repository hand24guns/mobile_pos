import 'package:dio/dio.dart';
import 'api_service.dart';

class AuthService {
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    try {
      final dio = ApiService.getDio();
      final response = await dio.post(
        '/auth.php',
        data: FormData.fromMap({
          'action': 'login',
          'username': username,
          'password': password,
        }),
      );

      return response.data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal terhubung ke server: $e'
      };
    }
  }
}