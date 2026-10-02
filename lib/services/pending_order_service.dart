import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class PendingOrderService {
  // ============================================================
  // SIMPAN / UPDATE PENDING ORDER
  // REST API: POST /v1/pending-orders
  // Fallback: POST /penjualan.php (action: simpanPending)
  // ============================================================
  static Future<Map<String, dynamic>> savePending({
    required String number,
    required int storeId,
    required int organisasiId,
    int memberId = 0,
    required dynamic userId,
    String label = '',
    required String deviceToken,
    required int salesTipeId,
    String keterangan = '',
    int? pendingOrderId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    final payload = {
      'number': number,
      'store_id': storeId,
      'organisasi_id': organisasiId,
      'member_id': memberId,
      'user_id': userId,
      'label': label,
      'device_token': deviceToken,
      'salestipe_id': salesTipeId,
      'keterangan': keterangan,
      if (pendingOrderId != null) 'pending_order_id': pendingOrderId,
    };

    // 1. Coba REST API
    try {
      final res = pendingOrderId != null
          ? await dio.put('/v1/pending-orders/$pendingOrderId', data: payload)
          : await dio.post('/v1/pending-orders', data: payload);
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
        final res = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'simpanPending',
            ...payload,
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
  // GET DAFTAR PENDING ORDERS
  // REST API: GET /v1/pending-orders?store_id=X
  // Fallback: POST /penjualan.php (action: getPendingOrders)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getPendingOrders({
    required int storeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.get('/v1/pending-orders', queryParameters: {
        'store_id': storeId,
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
            'action': 'getPendingOrders',
            'store_id': storeId,
          }),
        );
        responseData = res.data;
      } catch (_) {
        return [];
      }
    }

    final data = _parseData(responseData);
    final raw = data['data'] ?? data['orders'] ?? [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // ============================================================
  // RETRIEVE PENDING ORDER
  // REST API: POST /v1/pending-orders/{id}/retrieve
  // Fallback: POST /penjualan.php (action: retrievePending)
  // ============================================================
  static Future<Map<String, dynamic>> retrievePending({
    required int salesOrderId,
    required String number,
    required String deviceToken,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    final payload = {
      'sales_order_id': salesOrderId,
      'number': number,
      'device_token': deviceToken,
    };

    // 1. Coba REST API
    try {
      final res =
          await dio.post('/v1/pending-orders/$salesOrderId/retrieve', data: payload);
      if (res.statusCode == 200) {
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
            'action': 'retrievePending',
            ...payload,
          }),
        );
        responseData = res.data;
      } catch (e) {
        return {'success': false, 'message': 'Gagal retrieve order: $e'};
      }
    }

    return _parseData(responseData);
  }

  // ============================================================
  // DELETE / VOID PENDING ORDER
  // REST API: DELETE /v1/pending-orders/{id}
  // Fallback: POST /penjualan.php (action: deletePending)
  // ============================================================
  static Future<bool> deletePending({
    required int salesOrderId,
    required dynamic userId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.delete('/v1/pending-orders/$salesOrderId', data: {
        'user_id': userId,
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
        final res = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'deletePending',
            'sales_order_id': salesOrderId,
            'user_id': userId,
          }),
        );
        responseData = res.data;
      } catch (_) {
        return false;
      }
    }

    final data = _parseData(responseData);
    return data['success'] == true;
  }

  // ============================================================
  // GET PENDING ORDER ITEMS
  // REST API: GET /v1/pending-orders/{id}/items
  // Fallback: POST /penjualan.php (action: getPendingOrderItems)
  // ============================================================
  static Future<Map<String, dynamic>> getPendingOrderItems({
    required int salesOrderId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final res = await dio.get('/v1/pending-orders/$salesOrderId/items');
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
            'action': 'getPendingOrderItems',
            'sales_order_id': salesOrderId,
          }),
        );
        responseData = res.data;
      } catch (_) {
        return {'success': false, 'items': []};
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
