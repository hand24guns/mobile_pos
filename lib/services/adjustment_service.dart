import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class AdjustmentService {
  // ============================================================
  // GET NOMOR DOKUMEN ADJUSTMENT
  // RPC: POST /penjualan.php (action: getNumberAdjustment)
  // ============================================================
  static Future<String?> getAdjustmentNumber(int storeId) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getNumberAdjustment',
          'store_id': storeId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = response.data;
    } catch (_) {
      return null;
    }

    final data = _parseResponse(responseData);
    if (data['success'] == true || data['success'] == 1 || data['success'] == 'true') {
      return data['number']?.toString();
    }
    return null;
  }

  // ============================================================
  // SEARCH PRODUK ADJUSTMENT
  // RPC: POST /penjualan.php (action: searchProdukAdjustment)
  // ============================================================
  static Future<List<Map<String, dynamic>>> searchProducts({
    required int organisasiId,
    required String term,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'searchProdukAdjustment',
          'organisasi_id': organisasiId,
          'term': term,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = response.data;
    } catch (_) {
      return [];
    }

    final data = _parseResponse(responseData);
    if (data['success'] == true || data['success'] == 1 || data['success'] == 'true') {
      final raw = data['data'];
      if (raw is List) {
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return [];
  }

  // ============================================================
  // GET PRODUK DENGAN IMAGE (GRID ADJUSTMENT)
  // RPC: POST /penjualan.php (action: getImageProductsAdjustment)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getImageProducts({
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getImageProductsAdjustment',
          'organisasi_id': organisasiId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = response.data;
    } catch (_) {
      return [];
    }

    final data = _parseResponse(responseData);
    if (data['success'] == true || data['success'] == 1 || data['success'] == 'true') {
      final raw = data['data'];
      if (raw is List) {
        return raw
            .map<Map<String, dynamic>>((cat) => {
                  'id': cat['id'] ?? 0,
                  'nama': cat['nama']?.toString() ?? '',
                  'produk': (cat['produk'] as List? ?? [])
                      .map<Map<String, dynamic>>((p) => {
                            'kode': p['kode']?.toString() ?? '',
                            'nama': p['nama']?.toString() ?? '',
                            'image': p['image']?.toString() ?? '',
                          })
                      .where((p) => (p['image'] as String).isNotEmpty)
                      .toList(),
                })
            .where((cat) => (cat['produk'] as List).isNotEmpty)
            .toList();
      }
    }
    return [];
  }

  // ============================================================
  // INSERT ITEM ADJUSTMENT (TEMP)
  // RPC: POST /penjualan.php (action: insertItemAdjustment)
  // ============================================================
  static Future<Map<String, dynamic>> insertItem({
    required String number,
    required String kode,
    int qty = 1,
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'insertItemAdjustment',
          'number': number,
          'kode': kode,
          'qty': qty,
          'organisasi_id': organisasiId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = response.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal terhubung ke server'};
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    return {
      'success': isSuccess,
      'message': data['message']?.toString() ?? (isSuccess ? null : 'Gagal menambahkan produk'),
    };
  }

  // ============================================================
  // GET ITEMS ADJUSTMENT (TEMP)
  // RPC: POST /penjualan.php (action: getListAdjustment)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getItems({
    required String number,
    required int organisasiId,
  }) async {
    if (number.isEmpty) return [];

    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getListAdjustment',
          'number': number,
          'organisasi_id': organisasiId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = response.data;
    } catch (_) {
      return [];
    }

    final data = _parseResponse(responseData);
    if (data['success'] == true || data['success'] == 1 || data['success'] == 'true') {
      final raw = data['data'];
      if (raw is List) {
        return raw.map((e) => Map<String, dynamic>.from(e as Map)).toList();
      }
    }
    return [];
  }

  // ============================================================
  // GET TOTAL QTY ADJUSTMENT (TEMP)
  // RPC: POST /penjualan.php (action: getTotalQtyAdjustment)
  // ============================================================
  static Future<int> getTotalQty({
    required String number,
    required int organisasiId,
  }) async {
    if (number.isEmpty) return 0;

    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getTotalQtyAdjustment',
          'number': number,
          'organisasi_id': organisasiId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = response.data;
    } catch (_) {
      return 0;
    }

    final data = _parseResponse(responseData);
    if (data['success'] == true || data['success'] == 1 || data['success'] == 'true') {
      return int.tryParse(data['total_qty']?.toString() ?? '') ?? 0;
    }
    return 0;
  }

  // ============================================================
  // UPDATE QTY ITEM
  // RPC: POST /penjualan.php (action: updateQtyAdjustment)
  // ============================================================
  static Future<bool> updateQty({
    required String number,
    required String kode,
    required int qty,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'updateQtyAdjustment',
          'number': number,
          'kode': kode,
          'qty': qty,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = response.data;
    } catch (_) {
      return false;
    }

    final data = _parseResponse(responseData);
    return data['success'] == true || data['success'] == 1 || data['success'] == 'true';
  }

  // ============================================================
  // DELETE ITEM ADJUSTMENT
  // RPC: POST /penjualan.php (action: deleteItemAdjustment)
  // ============================================================
  static Future<bool> deleteItem({
    required String number,
    required String kode,
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'deleteItemAdjustment',
          'number': number,
          'kode': kode,
          'organisasi_id': organisasiId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = response.data;
    } catch (_) {
      return false;
    }

    final data = _parseResponse(responseData);
    return data['success'] == true || data['success'] == 1 || data['success'] == 'true';
  }

  // ============================================================
  // SIMPAN TRANSAKSI ADJUSTMENT
  // RPC: POST /penjualan.php (action: simpanAdjustment)
  // ============================================================
  static Future<Map<String, dynamic>> submitAdjustment({
    required int storeId,
    required int organisasiId,
    required String tanggal,
    required String number,
    required String tipe,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'simpanAdjustment',
          'store_id': storeId,
          'organisasi_id': organisasiId,
          'tanggal': tanggal,
          'number': number,
          'tipe': tipe,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = response.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal terhubung ke server'};
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    return {
      'success': isSuccess,
      'message': data['message']?.toString() ?? (isSuccess ? null : 'Gagal menyimpan transaksi'),
    };
  }

  // ── Helper parsing response (JSON atau string JSON dengan prefix) ──
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
