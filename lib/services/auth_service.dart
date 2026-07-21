import 'package:dio/dio.dart';
import 'api_service.dart';
import 'session_service.dart';

class AuthService {
  // ============================================================
  // LOGIN — kirim kredensial, simpan session jika sukses.
  // Mengembalikan map response dari server; pemanggil cukup
  // cek ['success'] == true, tidak perlu urus session secara manual.
  // ============================================================
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    try {
      final dio = ApiService.getDio();
      final response = await dio.post(
        '/auth.php',
        data: FormData.fromMap({
          'action':   'login',
          'username': username,
          'password': password,
        }),
      );

      final data = response.data as Map<String, dynamic>;

      if (data['success'] == true) {
        final outlets = List<int>.from(
          (data['outlets'] as List? ?? []).map((e) => int.tryParse(e.toString()) ?? 0)
        ).where((e) => e > 0).toList();

        final menus = List<String>.from(
          (data['menus'] as List? ?? []).map((e) => e.toString())
        );

        await SessionService.saveSession(
          token:    data['token']    as String,
          userID:   data['user_id'] is int
                      ? data['user_id'] as int
                      : int.tryParse(data['user_id'].toString()) ?? 0,
          nama:     data['nama']     as String? ?? '',
          username: data['username'] as String? ?? '',
          outlets:  outlets,
          menus:    menus,
        );
      }

      return data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal terhubung ke server: $e',
      };
    }
  }
}
