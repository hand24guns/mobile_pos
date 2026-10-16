import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class ProductService {
  // ============================================================
  // SEARCH PRODUK (Barcode / Nama / SKU)
  // REST API: GET /v1/products?term=X&organisasi_id=Y&salestipe_id=Z
  // Fallback: POST /penjualan.php (action: searchProduk)
  // ============================================================
  static Future<List<Map<String, dynamic>>> searchProducts({
    required String term,
    required int organisasiId,
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'searchProduk',
          'term': term,
          'organisasi_id': organisasiId,
          'salestipe_id': salesTipeId,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return [];
    }

    final data = _parseData(responseData);
    final raw = data['data'] ?? data['products'] ?? [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // ============================================================
  // CEK PACKAGE (Cek apakah SKU adalah bundle/package & ambil isian/addon)
  // RPC: POST /penjualan.php (action: cekPackage)
  // ============================================================
  static Future<Map<String, dynamic>> checkPackage({
    required String sku,
    required int organisasiId,
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'cekPackage',
          'sku': sku,
          'organisasi_id': organisasiId,
          'salestipe_id': salesTipeId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = res.data;
    } catch (_) {
      return {};
    }

    if (responseData is Map<String, dynamic>) {
      return responseData;
    } else if (responseData is Map) {
      return Map<String, dynamic>.from(responseData);
    } else if (responseData is String && responseData.trim().isNotEmpty) {
      final jsonStart = responseData.indexOf('{');
      if (jsonStart >= 0) {
        try {
          final decoded = jsonDecode(responseData.substring(jsonStart));
          if (decoded is Map) {
            return Map<String, dynamic>.from(decoded);
          }
        } catch (_) {}
      }
    }

    return {};
  }

  // ============================================================
  // GET IMAGE PRODUCTS (Daftar produk berkategori dengan gambar untuk grid)
  // RPC: POST /penjualan.php (action: getImageProducts)
  // ============================================================
  static Future<dynamic> getImageProducts({
    required int organisasiId,
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getImageProducts',
          'organisasi_id': organisasiId,
          'salestipe_id': salesTipeId,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      responseData = res.data;
    } catch (e) {
      rethrow;
    }

    if (responseData is String && responseData.trim().isNotEmpty) {
      final jsonStart = responseData.indexOf('{');
      final arrayStart = responseData.indexOf('[');
      int start = 0;
      if (jsonStart >= 0 && arrayStart >= 0) {
        start = jsonStart < arrayStart ? jsonStart : arrayStart;
      } else if (jsonStart >= 0) {
        start = jsonStart;
      } else if (arrayStart >= 0) {
        start = arrayStart;
      }

      return jsonDecode(responseData.substring(start));
    }

    return responseData;
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
