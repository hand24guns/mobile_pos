import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class StoreService {
  // ============================================================
  // GET STORES — Ambil daftar outlet/store yang dapat diakses user
  // RPC: POST /penjualan.php (action: getStores)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getStores({int? userId}) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getStores',
          if (userId != null && userId > 0) 'user_id': userId,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return [];
    }

    final data = _parseResponse(responseData);
    final rawList = data['data'] ?? data['stores'];
    if (rawList is List) {
      return List<Map<String, dynamic>>.from(
        rawList.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
    }

    return [];
  }

  // ============================================================
  // GET ORGANISASI ID — Ambil ID organisasi & status FnB suatu store
  // RPC: POST /penjualan.php (action: getOrganisasiID)
  // ============================================================
  static Future<Map<String, dynamic>> getOrganisasiId(int storeId) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getOrganisasiID',
          'store_id': storeId,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return {'organisasi_id': 0, 'is_fnb': false};
    }

    final data = _parseResponse(responseData);
    final payload = (data['data'] is Map<String, dynamic>)
        ? data['data'] as Map<String, dynamic>
        : data;

    final rawOrgId = payload['organisasi_id'] ?? data['organisasi_id'];
    final organisasiId = int.tryParse(rawOrgId?.toString() ?? '') ?? 0;
    final rawIsFnb = payload['is_fnb'] ?? data['is_fnb'];
    final bool isFnb = rawIsFnb == 1 || rawIsFnb == true || rawIsFnb == '1';

    return {
      'organisasi_id': organisasiId,
      'is_fnb': isFnb,
    };
  }

  // ============================================================
  // GET STORE DATA — Ambil detail profil store (nama, alamat, logo, dll)
  // RPC: POST /penjualan.php (action: getStoreData)
  // ============================================================
  static Future<Map<String, dynamic>> getStoreData(int storeId) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getStoreData',
          'store_id': storeId,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return {};
    }

    final data = _parseResponse(responseData);
    if (data['data'] is Map<String, dynamic>) {
      return data['data'] as Map<String, dynamic>;
    }
    return data;
  }

  // ============================================================
  // GET OUTLET SETTINGS — Ambil setting lengkap outlet yang dapat diakses user
  // RPC: POST /penjualan.php (action: getOutletSetting)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getOutletSettings({int? userId}) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getOutletSetting',
          if (userId != null && userId > 0) 'user_id': userId,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return [];
    }

    final data = _parseResponse(responseData);
    final rawList = data['stores'] ?? data['data'];
    if (rawList is List) {
      return List<Map<String, dynamic>>.from(
        rawList.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
    }

    return [];
  }

  // ============================================================
  // UPDATE OUTLET SETTING — Update setting outlet (No HP, Alamat, NPWP, WA, Tax, Note)
  // RPC: POST /penjualan.php (action: updateOutletSetting)
  // ============================================================
  static Future<Map<String, dynamic>> updateOutletSetting({
    required int storeId,
    required String telp,
    required String alamat,
    required String npwp,
    required bool wa,
    required double tax,
    required String note,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'updateOutletSetting',
          'store_id': storeId.toString(),
          'telp': telp,
          'alamat': alamat,
          'npwp': npwp,
          'wa': wa ? '1' : '0',
          'tax': tax.toString(),
          'note': note,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal menyimpan data outlet'};
    }

    return _parseResponse(responseData);
  }

  // ── Helper parsing response JSON / Map ─────────────────────
  static Map<String, dynamic> _parseResponse(dynamic rawData) {
    if (rawData is Map<String, dynamic>) {
      return rawData;
    } else if (rawData is String && rawData.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map<String, dynamic>) {
          return decoded;
        }
      } catch (_) {}
    }
    return {};
  }
}
