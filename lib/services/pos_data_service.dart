import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class PosDataService {
  // ============================================================
  // GET NEXT ORDER / INVOICE NUMBER
  // REST API: GET /v1/orders/next-number?store_id=X&device_token=Y
  // Fallback: POST /penjualan.php (action: getNumber)
  // ============================================================
  static Future<String> getNextOrderNumber({
    required int storeId,
    required String deviceToken,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.get('/v1/orders/next-number', queryParameters: {
        'store_id': storeId,
        'device_token': deviceToken,
      });
      if (res.statusCode == 200 && res.data != null) {
        responseData = res.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy
    if (!restSuccess || responseData == null) {
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
    }

    final data = _parseData(responseData);
    final payload = (data['data'] is Map<String, dynamic>)
        ? data['data'] as Map<String, dynamic>
        : data;

    return (payload['number'] ?? payload['invoice_number'] ?? '').toString();
  }

  // ============================================================
  // GET CHANNELS (Sales Types: Dine In, Takeaway, Delivery, etc.)
  // REST API: GET /v1/channels?organisasi_id=X
  // Fallback: POST /penjualan.php (action: getChannels)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getChannels({
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.get('/v1/channels', queryParameters: {
        'organisasi_id': organisasiId,
      });
      if (res.statusCode == 200 && res.data != null) {
        responseData = res.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy
    if (!restSuccess || responseData == null) {
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
  // REST API: GET /v1/payment-methods?organisasi_id=X
  // Fallback: POST /penjualan.php (action: getCaraBayar)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getCaraBayar({
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.get('/v1/payment-methods', queryParameters: {
        'organisasi_id': organisasiId,
      });
      if (res.statusCode == 200 && res.data != null) {
        responseData = res.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy
    if (!restSuccess || responseData == null) {
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
  // REST API: GET /v1/members?keyword=X&organisasi_id=Y
  // Fallback: POST /penjualan.php (action: searchMember)
  // ============================================================
  static Future<List<Map<String, dynamic>>> searchMember({
    required String keyword,
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.get('/v1/members', queryParameters: {
        'keyword': keyword,
        'organisasi_id': organisasiId,
      });
      if (res.statusCode == 200 && res.data != null) {
        responseData = res.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy
    if (!restSuccess || responseData == null) {
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
  // REST API: GET /v1/members/check-hp?hp=X&organisasi_id=Y
  // Fallback: POST /penjualan.php (action: cekHPMember)
  // ============================================================
  static Future<Map<String, dynamic>> checkMemberHp({
    required String hp,
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.get('/v1/members/check-hp', queryParameters: {
        'hp': hp,
        'organisasi_id': organisasiId,
      });
      if (res.statusCode == 200 && res.data != null) {
        responseData = res.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy
    if (!restSuccess || responseData == null) {
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
    }

    return _parseData(responseData);
  }

  // ============================================================
  // INSERT MEMBER BARU
  // REST API: POST /v1/members
  // Fallback: POST /penjualan.php (action: insertMember)
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
    bool restSuccess = false;

    final body = {
      'nama': nama,
      'hp': hp,
      'email': email ?? '',
      'ig': ig ?? '',
      'tgl_lahir': tglLahir ?? '',
      'organisasi_id': organisasiId,
    };

    // 1. Coba REST API
    try {
      final res = await dio.post('/v1/members', data: body);
      if (res.statusCode == 200 && res.data != null) {
        responseData = res.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy
    if (!restSuccess || responseData == null) {
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
