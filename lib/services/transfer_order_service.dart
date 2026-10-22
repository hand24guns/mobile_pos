import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class TransferOrderService {
  // ============================================================
  // GET LIST TRANSFER ORDER (MASUK & KELUAR)
  // RPC: POST /penjualan.php (action: getIncomingTransferOrders)
  // ============================================================
  static Future<Map<String, dynamic>> getIncomingTransferOrders({
    List<int>? storeIds,
    String? status,
    String? tipe, // 'all', 'in', 'out'
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final map = <String, dynamic>{
        'action': 'getIncomingTransferOrders',
      };
      if (storeIds != null && storeIds.isNotEmpty) {
        map['store_ids'] = storeIds.join(',');
      }
      if (status != null && status.isNotEmpty) {
        map['status'] = status;
      }
      if (tipe != null && tipe.isNotEmpty) {
        map['tipe'] = tipe;
      }

      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap(map),
      );
      responseData = response.data;
    } catch (e) {
      return {
        'success': false,
        'message': 'Gagal memuat data: $e',
        'data': [],
        'pending_count': 0,
      };
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';
    final rawList = data['data'];
    List<Map<String, dynamic>> list = [];
    if (rawList is List) {
      list = rawList.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    return {
      'success': isSuccess,
      'pending_count': int.tryParse(data['pending_count']?.toString() ?? '0') ?? 0,
      'data': list,
      'message': data['message']?.toString() ?? '',
    };
  }

  // ============================================================
  // GET DETAIL TRANSFER ORDER (LIST ITEM)
  // RPC: POST /penjualan.php (action: getTransferOrderDetail)
  // ============================================================
  static Future<Map<String, dynamic>> getTransferOrderDetail({
    int? transferOrderId,
    String? number,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final map = <String, dynamic>{
        'action': 'getTransferOrderDetail',
      };
      if (transferOrderId != null && transferOrderId > 0) {
        map['transfer_order_id'] = transferOrderId;
      }
      if (number != null && number.isNotEmpty) {
        map['number'] = number;
      }

      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap(map),
      );
      responseData = response.data;
    } catch (e) {
      return {'success': false, 'message': 'Gagal memuat detail: $e'};
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';
    if (!isSuccess) {
      return {
        'success': false,
        'message': data['message']?.toString() ?? 'Gagal memuat detail transfer order',
      };
    }

    final headerMap = data['header'] is Map
        ? Map<String, dynamic>.from(data['header'] as Map)
        : <String, dynamic>{};
    final rawItems = data['items'];
    List<Map<String, dynamic>> items = [];
    if (rawItems is List) {
      items = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    return {
      'success': true,
      'header': headerMap,
      'items': items,
    };
  }

  // ============================================================
  // KONFIRMASI TERIMA BARANG TRANSFER ORDER
  // RPC: POST /penjualan.php (action: receiveTransferOrder)
  // ============================================================
  static Future<Map<String, dynamic>> receiveTransferOrder({
    required int transferOrderId,
    String? number,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final map = <String, dynamic>{
        'action': 'receiveTransferOrder',
        'transfer_order_id': transferOrderId,
      };
      if (number != null && number.isNotEmpty) {
        map['number'] = number;
      }

      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap(map),
      );
      responseData = response.data;
    } catch (e) {
      return {'success': false, 'message': 'Koneksi gagal: $e'};
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    return {
      'success': isSuccess,
      'message': data['message']?.toString() ??
          (isSuccess
              ? 'Penerimaan barang berhasil dikonfirmasi'
              : 'Gagal konfirmasi penerimaan'),
    };
  }

  // ============================================================
  // GET PENDING COUNT (UNTUK HOME BADGE & ALERT)
  // RPC: POST /penjualan.php (action: getPendingTransferCount)
  // ============================================================
  static Future<Map<String, dynamic>> getPendingTransferCount({
    List<int>? storeIds,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final map = <String, dynamic>{
        'action': 'getPendingTransferCount',
      };
      if (storeIds != null && storeIds.isNotEmpty) {
        map['store_ids'] = storeIds.join(',');
      }

      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap(map),
      );
      responseData = response.data;
    } catch (_) {
      return {'success': false, 'count': 0, 'data': []};
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';
    final count = int.tryParse(data['count']?.toString() ?? '0') ?? 0;
    final rawItems = data['data'];
    List<Map<String, dynamic>> items = [];
    if (rawItems is List) {
      items = rawItems.map((e) => Map<String, dynamic>.from(e as Map)).toList();
    }

    return {
      'success': isSuccess,
      'count': count,
      'data': items,
    };
  }

  static Map<String, dynamic> _parseResponse(dynamic rawData) {
    if (rawData is Map<String, dynamic>) {
      return rawData;
    } else if (rawData is Map) {
      return Map<String, dynamic>.from(rawData);
    } else if (rawData is String && rawData.trim().isNotEmpty) {
      final jsonStart = rawData.indexOf('{');
      if (jsonStart >= 0) {
        try {
          final decoded = jsonDecode(rawData.substring(jsonStart));
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
    }
    return {};
  }
}
