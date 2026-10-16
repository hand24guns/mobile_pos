import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class PosDataService {
  // ============================================================
  // GET NEXT ORDER / INVOICE NUMBER
  // RPC: POST /penjualan.php (action: getNumber)
  // ============================================================
  static Future<String> getNextOrderNumber({
    required int storeId,
    required String deviceToken,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getNumber',
          'store_id': storeId,
          'device_token': deviceToken,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return '';
    }

    final data = _parseData(responseData);
    final payload = (data['data'] is Map<String, dynamic>)
        ? data['data'] as Map<String, dynamic>
        : data;

    return (payload['number'] ?? payload['invoice_number'] ?? '').toString();
  }

  // ============================================================
  // GET CHANNELS (Sales Types: Dine In, Takeaway, Delivery, etc.)
  // RPC: POST /penjualan.php (action: getChannels)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getChannels({
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getChannels',
          'organisasi_id': organisasiId,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return [];
    }

    final data = _parseData(responseData);
    final raw = data['data'] ?? data['channels'] ?? [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // ============================================================
  // GET CARA BAYAR (Payment Methods: Cash, EDC, QRIS, Transfer, etc.)
  // RPC: POST /penjualan.php (action: getCaraBayar)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getCaraBayar({
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getCaraBayar',
          'organisasi_id': organisasiId,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return [];
    }

    final data = _parseData(responseData);
    final raw = data['data'] ?? data['payment_methods'] ?? [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // ============================================================
  // SEARCH MEMBER / CUSTOMER
  // RPC: POST /penjualan.php (action: searchMember)
  // ============================================================
  static Future<List<Map<String, dynamic>>> searchMember({
    required String keyword,
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'searchMember',
          'keyword': keyword,
          'organisasi_id': organisasiId,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return [];
    }

    final data = _parseData(responseData);
    final raw = data['data'] ?? data['members'] ?? [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // ============================================================
  // CEK HP MEMBER
  // RPC: POST /penjualan.php (action: cekHPMember)
  // ============================================================
  static Future<Map<String, dynamic>> checkMemberHp({
    required String hp,
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'cekHPMember',
          'hp': hp,
          'organisasi_id': organisasiId,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal terhubung ke server'};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // INSERT MEMBER BARU
  // RPC: POST /penjualan.php (action: insertMember)
  // ============================================================
  static Future<Map<String, dynamic>> createMember({
    required String nama,
    required String hp,
    String? email,
    String? ig,
    String? tglLahir,
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final body = {
      'nama': nama,
      'hp': hp,
      'email': email ?? '',
      'ig': ig ?? '',
      'tgl_lahir': tglLahir ?? '',
      'organisasi_id': organisasiId,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'insertMember',
          ...body,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal terhubung ke server'};
    }

    return _parseData(responseData);
  }

  static Map<String, dynamic> _parseData(dynamic rawData) {
    if (rawData is Map<String, dynamic>) {
      return rawData;
    } else if (rawData is Map) {
      return Map<String, dynamic>.from(rawData);
    } else if (rawData is String && rawData.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(rawData);
        if (decoded is Map) {
          return Map<String, dynamic>.from(decoded);
        }
      } catch (_) {}
    }
    return {};
  }
}
