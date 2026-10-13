import 'package:dio/dio.dart';
import 'api_service.dart';
import 'session_service.dart';

class AuthService {
  // ============================================================
  // LOGIN — kirim kredensial ke RESTful endpoint /v1/auth/login,
  // simpan session jika sukses.
  // Format body: JSON (application/json) {'username': ..., 'password': ...}
  //
  // Mendukung standard response REST API:
  // {
  //   "success": true,
  //   "message": "Login berhasil",
  //   "data": {
  //     "token": "...",
  //     "user_id": 1,
  //     "nama": "Kasir 1",
  //     "username": "kasir1",
  //     "outlets": [1, 2],
  //     "menus": [...]
  //   }
  // }
  // ============================================================
  static Future<Map<String, dynamic>> login(
      String username, String password) async {
    try {
      final dio = ApiService.getDio();
      Response response;
      try {
        // Panggilan RESTful API standar: POST /v1/auth/login dengan body JSON
        response = await dio.post(
          '/v1/auth/login',
          data: {
            'username': username,
            'password': password,
          },
        );
      } on DioException catch (dioErr) {
        final is404 = dioErr.response?.statusCode == 404;
        final isBlockedOrOffline =
            dioErr.type == DioExceptionType.connectionError;
        if (is404 || isBlockedOrOffline) {
          response = await dio.post(
            '/auth.php',
            data: FormData.fromMap({
              'action': 'login',
              'username': username,
              'password': password,
            }),
          );
        } else {
          rethrow;
        }
      }

      final dynamic rawData = response.data;
      final Map<String, dynamic> responseData =
          rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};

      final bool isSuccess = responseData['success'] == true;

      if (isSuccess) {
        // Mengambil payload baik dari format REST ('data': { ... })
        // maupun format flat/legacy di root responseData
        final payload = (responseData['data'] is Map<String, dynamic>)
            ? responseData['data'] as Map<String, dynamic>
            : responseData;

        final rawToken = payload['token'] ?? responseData['token'];
        final token = rawToken?.toString() ?? '';

        final rawUserId =
            payload['user_id'] ?? payload['id'] ?? responseData['user_id'];
        final userId = rawUserId is int
            ? rawUserId
            : int.tryParse(rawUserId?.toString() ?? '') ?? 0;

        final nama =
            (payload['nama'] ?? payload['name'] ?? responseData['nama'] ?? '')
                .toString();

        final usernameVal =
            (payload['username'] ?? responseData['username'] ?? username)
                .toString();

        final dynamic rawOutlets = payload['outlets'] ??
            payload['stores'] ??
            payload['divisi'] ??
            payload['user']?['outlets'] ??
            responseData['outlets'] ??
            responseData['stores'] ??
            responseData['divisi'];

        List<int> outlets = [];
        if (rawOutlets is List) {
          outlets = rawOutlets
              .map((e) {
                if (e is int) return e;
                if (e is num) return e.toInt();
                if (e is Map) {
                  final id = e['id'] ??
                      e['dim_divisi_id'] ??
                      e['store_id'] ??
                      e['outlet_id'];
                  return int.tryParse(id?.toString() ?? '') ?? 0;
                }
                return int.tryParse(e.toString().trim()) ?? 0;
              })
              .where((e) => e > 0)
              .toList();
        } else if (rawOutlets is String && rawOutlets.trim().isNotEmpty) {
          outlets = rawOutlets
              .split(',')
              .map((e) => int.tryParse(e.trim()) ?? 0)
              .where((e) => e > 0)
              .toList();
        }

        final rawMenus = payload['menus'] ?? responseData['menus'];
        final menus = List<String>.from(
            (rawMenus as List? ?? []).map((e) => e.toString()));

        await SessionService.saveSession(
          token: token,
          userID: userId,
          nama: nama,
          username: usernameVal,
          outlets: outlets,
          menus: menus,
        );
      }

      return responseData;
    } on DioException catch (e) {
      // Menangkap pesan eror yang dikirim oleh backend PHP (seperti status 401/400)
      if (e.response != null && e.response?.data is Map<String, dynamic>) {
        return e.response!.data as Map<String, dynamic>;
      }
      return _handleDioError(e);
    } catch (e) {
      return {
        'success': false,
        'message': 'Terjadi kesalahan sistem: $e',
      };
    }
  }

  // ============================================================
  // LOGOUT — panggil endpoint logout REST (opsional) & hapus sesi lokal
  // ============================================================
  static Future<void> logout() async {
    try {
      final dio = ApiService.getDio();
      await dio.post('/v1/auth/logout');
    } catch (_) {
      // Abaikan kegagalan jaringan saat logout agar sesi lokal tetap bersih
    } finally {
      await SessionService.clearSession();
    }
  }

  // ============================================================
  // CHANGE PASSWORD — ubah password kasir / user yang sedang login
  //
  // REST API: POST /v1/auth/change-password
  // Body JSON: {"password": ..., "password_confirmation": ...}
  // ============================================================
  static Future<Map<String, dynamic>> changePassword({
    required String password,
    required String passwordConfirmation,
  }) async {
    try {
      final dio = ApiService.getDio();

      Response response;
      try {
        // Panggilan RESTful standar: POST /v1/auth/change-password
        response = await dio.post(
          '/v1/auth/change-password',
          data: {
            'password': password,
            'password_confirmation': passwordConfirmation,
          },
        );
      } on DioException catch (dioErr) {
        final is404 = dioErr.response?.statusCode == 404;
        final isBlockedOrOffline =
            dioErr.type == DioExceptionType.connectionError;
        if (is404 || isBlockedOrOffline) {
          response = await dio.post(
            '/penjualan.php',
            data: FormData.fromMap({
              'action': 'changePassword',
              'password': password,
              'password_confirmation': passwordConfirmation,
            }),
          );
        } else {
          rethrow;
        }
      }

      final dynamic rawData = response.data;
      final Map<String, dynamic> responseData =
          rawData is Map<String, dynamic> ? rawData : <String, dynamic>{};

      return responseData;
    } on DioException catch (e) {
      return _handleDioError(e);
    } catch (e) {
      return {
        'success': false,
        'message': 'Terjadi kesalahan sistem: $e',
      };
    }
  }

  // ── Helper penanganan error Dio & HTTP Status Codes ────────
  static Map<String, dynamic> _handleDioError(DioException e) {
    if (e.response != null) {
      final status = e.response?.statusCode;
      final data = e.response?.data;

      if (data is Map<String, dynamic>) {
        String message = data['message']?.toString() ?? '';

        // Ekstraksi pesan validasi dari field 'errors': {"field": ["pesan"]}
        if (message.isEmpty && data['errors'] is Map) {
          final errors = data['errors'] as Map;
          if (errors.isNotEmpty) {
            final firstVal = errors.values.first;
            if (firstVal is List && firstVal.isNotEmpty) {
              message = firstVal.first.toString();
            } else {
              message = firstVal.toString();
            }
          }
        }

        if (message.isEmpty) {
          if (status == 401) {
            message = 'Username atau password salah.';
          } else if (status == 422) {
            message = 'Data login yang dikirim tidak valid.';
          } else if (status != null && status >= 500) {
            message = 'Terjadi gangguan pada server ($status).';
          } else {
            message = 'Terjadi kesalahan pada server ($status).';
          }
        }

        return {
          'success': false,
          'message': message,
          'errors': data['errors'],
          'status_code': status,
        };
      }

      if (status == 401) {
        return {
          'success': false,
          'message': 'Username atau password salah.',
          'status_code': 401,
        };
      }

      return {
        'success': false,
        'message': 'Server merespon dengan status $status.',
        'status_code': status,
      };
    }

    switch (e.type) {
      case DioExceptionType.connectionTimeout:
      case DioExceptionType.sendTimeout:
      case DioExceptionType.receiveTimeout:
        return {
          'success': false,
          'message':
              'Batas waktu koneksi habis (timeout). Silakan periksa jaringan Anda.',
        };
      case DioExceptionType.connectionError:
        return {
          'success': false,
          'message':
              'Gagal terhubung ke server. Periksa koneksi internet atau pengaturan URL server.',
        };
      case DioExceptionType.cancel:
        return {
          'success': false,
          'message': 'Permintaan login dibatalkan.',
        };
      default:
        return {
          'success': false,
          'message': e.message ?? 'Terjadi kesalahan koneksi ke server.',
        };
    }
  }
}
