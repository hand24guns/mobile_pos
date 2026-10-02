import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

/// Status shift di divisi
enum ShiftStatus {
  /// Belum ada shift aktif → user harus buka shift
  tidakAda,

  /// Shift aktif milik user ini → bisa langsung masuk
  milikSaya,

  /// Shift aktif tapi milik user lain → blokir
  milikOrangLain,
}

class ShiftResult {
  final ShiftStatus status;
  final int shiftID;
  final double modalKasir;
  final String kasirNama; // diisi jika status == milikOrangLain

  const ShiftResult({
    required this.status,
    this.shiftID = 0,
    this.modalKasir = 0,
    this.kasirNama = '',
  });
}

class ShiftService {
  // ============================================================
  // CEK SHIFT AKTIF
  // REST API: GET /v1/shifts/check?store_id=X&organisasi_id=Y&user_id=Z
  // Fallback: POST /penjualan.php (action: cekShift)
  // ============================================================
  static Future<ShiftResult> cekShift({
    String? token,
    required int storeID,
    required int organisasiID,
    required int userID,
  }) async {
    final dio = ApiService.getDio(token: token);
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.get('/v1/shifts/check', queryParameters: {
        'store_id': storeID,
        'organisasi_id': organisasiID,
        'user_id': userID,
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
        final res = await dio.post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'cekShift',
              'store_id': storeID,
              'organisasi_id': organisasiID,
              'user_id': userID,
            }));
        responseData = res.data;
      } catch (_) {
        return const ShiftResult(status: ShiftStatus.tidakAda);
      }
    }

    final data = _parseData(responseData);
    final int statusCode = data['status'] ?? 0;

    switch (statusCode) {
      case 1:
        return ShiftResult(
          status: ShiftStatus.milikSaya,
          shiftID: data['shift_id'] ?? 0,
          modalKasir: (data['modal_kasir'] as num?)?.toDouble() ?? 0,
        );
      case 2:
        return ShiftResult(
          status: ShiftStatus.milikOrangLain,
          shiftID: data['shift_id'] ?? 0,
          kasirNama: data['kasir_nama'] ?? 'User lain',
        );
      default:
        return const ShiftResult(status: ShiftStatus.tidakAda);
    }
  }

  // ============================================================
  // BUKA SHIFT
  // REST API: POST /v1/shifts
  // Fallback: POST /penjualan.php (action: bukaShift)
  // ============================================================
  static Future<int> bukaShift({
    String? token,
    required int storeID,
    required int organisasiID,
    required int userID,
    required double modalKasir,
  }) async {
    final dio = ApiService.getDio(token: token);
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.post('/v1/shifts', data: {
        'store_id': storeID,
        'organisasi_id': organisasiID,
        'user_id': userID,
        'modal_kasir': modalKasir,
      });
      if (res.statusCode == 200 || res.statusCode == 201) {
        responseData = res.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy
    if (!restSuccess || responseData == null) {
      try {
        final res = await dio.post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'bukaShift',
              'store_id': storeID,
              'organisasi_id': organisasiID,
              'user_id': userID,
              'modal_kasir': modalKasir,
            }));
        responseData = res.data;
      } catch (_) {
        return 0;
      }
    }

    final data = _parseData(responseData);
    if (data['success'] == true || data['status'] == 'success') {
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;
      return int.tryParse(payload['shift_id']?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  // ============================================================
  // GET REKAP SHIFT
  // REST API: GET /v1/shifts/{id}/summary
  // Fallback: POST /penjualan.php (action: getRekapShift)
  // ============================================================
  static Future<Map<String, dynamic>> getRekapShift({
    String? token,
    required int shiftID,
    required int storeID,
    required int organisasiID,
  }) async {
    final dio = ApiService.getDio(token: token);
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.get('/v1/shifts/$shiftID/summary', queryParameters: {
        'store_id': storeID,
        'organisasi_id': organisasiID,
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
        final res = await dio.post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'getRekapShift',
              'shift_id': shiftID,
              'store_id': storeID,
              'organisasi_id': organisasiID,
            }));
        responseData = res.data;
      } catch (_) {
        return {};
      }
    }

    final data = _parseData(responseData);
    if (data['success'] == true || data['status'] == 'success') {
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;
      return {
        'open_shift': payload['open_shift'] ?? '',
        'modal_kasir': (payload['modal_kasir'] as num?)?.toDouble() ?? 0,
        'jumlah_invoice': payload['jumlah_invoice'] ?? 0,
        'total_sales': (payload['total_sales'] as num?)?.toDouble() ?? 0,
      };
    }
    return {};
  }

  // ============================================================
  // TUTUP SHIFT
  // REST API: POST /v1/shifts/{id}/close
  // Fallback: POST /penjualan.php (action: tutupShift)
  // ============================================================
  static Future<bool> tutupShift({
    String? token,
    required int shiftID,
    required int storeID,
    required int organisasiID,
    required double totalSales,
    required int jumlahInvoice,
  }) async {
    final dio = ApiService.getDio(token: token);
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.post('/v1/shifts/$shiftID/close', data: {
        'store_id': storeID,
        'organisasi_id': organisasiID,
        'total_sales': totalSales,
        'jumlah_invoice': jumlahInvoice,
      });
      if (res.statusCode == 200 || res.statusCode == 204) {
        responseData = res.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy
    if (!restSuccess || responseData == null) {
      try {
        final res = await dio.post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'tutupShift',
              'shift_id': shiftID,
              'store_id': storeID,
              'organisasi_id': organisasiID,
              'total_sales': totalSales,
              'jumlah_invoice': jumlahInvoice,
            }));
        responseData = res.data;
      } catch (_) {
        return false;
      }
    }

    final data = _parseData(responseData);
    return data['success'] == true || data['status'] == 'success';
  }

  // ============================================================
  // CEK SHIFT USER — Cek apakah user memiliki shift aktif di store manapun
  //
  // REST API: GET /v1/shifts/active?user_id=X
  // Fallback: POST /penjualan.php (action: cekShiftUser)
  // ============================================================
  static Future<Map<String, dynamic>> cekShiftUser({int? userId}) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. REST API
    try {
      final res = await dio.get('/v1/shifts/active', queryParameters: {
        if (userId != null && userId > 0) 'user_id': userId,
      });
      if (res.statusCode == 200 && res.data != null) {
        responseData = res.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback
    if (!restSuccess || responseData == null) {
      try {
        final res = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'cekShiftUser',
            if (userId != null && userId > 0) 'user_id': userId,
          }),
        );
        responseData = res.data;
      } catch (_) {
        return {'has_shift': false};
      }
    }

    Map<String, dynamic> data = {};
    if (responseData is Map<String, dynamic>) {
      data = responseData;
    } else if (responseData is String && responseData.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(responseData);
        if (decoded is Map<String, dynamic>) data = decoded;
      } catch (_) {}
    }

    final payload = (data['data'] is Map<String, dynamic>)
        ? data['data'] as Map<String, dynamic>
        : data;

    final hasShift = payload['has_shift'] == true ||
        payload['has_shift'] == 1 ||
        payload['has_shift'] == '1';

    return {
      'has_shift': hasShift,
      'shift_id': int.tryParse(payload['shift_id']?.toString() ?? '') ?? 0,
      'store_id': int.tryParse(payload['store_id']?.toString() ?? '') ?? 0,
      'store_nama':
          (payload['store_nama'] ?? payload['store_name'] ?? '').toString(),
      'organisasi_id':
          int.tryParse(payload['organisasi_id']?.toString() ?? '') ?? 0,
      'is_fnb': payload['is_fnb'] == 1 ||
          payload['is_fnb'] == true ||
          payload['is_fnb'] == '1',
    };
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
