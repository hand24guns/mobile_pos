import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class CartService {
  // ============================================================
  // GET ITEMS IN CART (temp_invoice)
  // RPC: POST /penjualan.php (action: getItems)
  // ============================================================
  static Future<Map<String, dynamic>> getCartItems({
    required String number,
    required String deviceToken,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getItems',
          'number': number,
          'device_token': deviceToken,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'data': []};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // GET CART SUMMARY (gross, diskon, total, dpp, tax)
  // RPC: POST /penjualan.php (action: getSummary)
  // ============================================================
  static Future<Map<String, dynamic>> getCartSummary({
    required String number,
    required int storeId,
    required String deviceToken,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getSummary',
          'number': number,
          'store_id': storeId,
          'device_token': deviceToken,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // INSERT ITEM BIASA
  // RPC: POST /penjualan.php (action: insertItem)
  // ============================================================
  static Future<Map<String, dynamic>> addItem({
    required String number,
    required String sku,
    required int organisasiId,
    required int storeId,
    int memberId = 0,
    String voucher = '',
    required String deviceToken,
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final payload = {
      'number': number,
      'sku': sku,
      'organisasi_id': organisasiId,
      'store_id': storeId,
      'member_id': memberId,
      'voucher': voucher,
      'device_token': deviceToken,
      'salestipe_id': salesTipeId,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'insertItem',
          ...payload,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal terhubung ke server'};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // INSERT PACKAGE
  // RPC: POST /penjualan.php (action: insertPackage)
  // ============================================================
  static Future<Map<String, dynamic>> addPackage({
    required String number,
    required String sku,
    required int organisasiId,
    required int storeId,
    int memberId = 0,
    String voucher = '',
    required String deviceToken,
    required List<Map<String, dynamic>> isianDipilih,
    required List<Map<String, dynamic>> addonDipilih,
    required double addonTotal,
    String keterangan = '',
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final payload = {
      'number': number,
      'sku': sku,
      'organisasi_id': organisasiId,
      'store_id': storeId,
      'member_id': memberId,
      'voucher': voucher,
      'device_token': deviceToken,
      'isian': jsonEncode(isianDipilih),
      'addon': jsonEncode(addonDipilih),
      'addon_harga': addonTotal,
      'keterangan': keterangan,
      'salestipe_id': salesTipeId,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'insertPackage',
          ...payload,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal terhubung ke server'};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // EDIT PACKAGE
  // RPC: POST /penjualan.php (action: editPackage)
  // ============================================================
  static Future<Map<String, dynamic>> editPackage({
    required String number,
    required String sku,
    required String oldPackagesNotes,
    required int organisasiId,
    required int storeId,
    int memberId = 0,
    String voucher = '',
    required String deviceToken,
    required List<Map<String, dynamic>> isianDipilih,
    required List<Map<String, dynamic>> addonDipilih,
    required double addonTotal,
    String keterangan = '',
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final payload = {
      'number': number,
      'sku': sku,
      'old_packages_notes': oldPackagesNotes,
      'organisasi_id': organisasiId,
      'store_id': storeId,
      'member_id': memberId,
      'voucher': voucher,
      'device_token': deviceToken,
      'isian': jsonEncode(isianDipilih),
      'addon': jsonEncode(addonDipilih),
      'addon_harga': addonTotal,
      'keterangan': keterangan,
      'salestipe_id': salesTipeId,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'editPackage',
          ...payload,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal terhubung ke server'};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // DELETE ITEM DARI CART
  // RPC: POST /penjualan.php (action: deleteItem)
  // ============================================================
  static Future<Map<String, dynamic>> deleteItem({
    required int itemId,
    required String number,
    required String deviceToken,
    String voucher = '',
    int memberId = 0,
    required int organisasiId,
    required int storeId,
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'deleteItem',
          'id': itemId,
          'number': number,
          'device_token': deviceToken,
          'voucher': voucher,
          'member_id': memberId,
          'organisasi_id': organisasiId,
          'store_id': storeId,
          'salestipe_id': salesTipeId,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // UPDATE QTY ITEM
  // RPC: POST /penjualan.php (action: updateQty)
  // ============================================================
  static Future<Map<String, dynamic>> updateQty({
    required int itemId,
    required double qty,
    required String number,
    required String deviceToken,
    String voucher = '',
    int memberId = 0,
    required int organisasiId,
    required int storeId,
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'updateQty',
          'id': itemId,
          // kirim int kalau bilangan bulat (PHP membaca (int), hindari "2.0")
          'qty': qty == qty.truncateToDouble() ? qty.toInt() : qty,
          'number': number,
          'device_token': deviceToken,
          'voucher': voucher,
          'member_id': memberId,
          'organisasi_id': organisasiId,
          'store_id': storeId,
          'salestipe_id': salesTipeId,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // UPDATE ITEM NOTES / KETERANGAN
  // RPC: POST /penjualan.php (action: updateItemKeterangan)
  // ============================================================
  static Future<bool> updateItemNotes({
    required int itemId,
    required String number,
    required String deviceToken,
    required String keterangan,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'updateItemKeterangan',
          'id': itemId,
          'number': number,
          'device_token': deviceToken,
          'keterangan': keterangan,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return false;
    }

    final data = _parseData(responseData);
    return data['success'] == true;
  }

  // ============================================================
  // RECALCULATE CART
  // RPC: POST /penjualan.php (action: recalculate)
  // ============================================================
  static Future<Map<String, dynamic>> recalculate({
    required String number,
    required String deviceToken,
    String voucher = '',
    int memberId = 0,
    required int organisasiId,
    required int storeId,
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final payload = {
      'number': number,
      'device_token': deviceToken,
      'voucher': voucher,
      'member_id': memberId,
      'organisasi_id': organisasiId,
      'store_id': storeId,
      'salestipe_id': salesTipeId,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'recalculate',
          ...payload,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // RECALCULATE CHANNEL (ketika channel/sales_type diganti)
  // RPC: POST /penjualan.php (action: recalculateChannel)
  // ============================================================
  static Future<Map<String, dynamic>> recalculateChannel({
    required String number,
    required int salesTipeId,
    required int organisasiId,
    required String deviceToken,
    String voucher = '',
    int memberId = 0,
    required int storeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final payload = {
      'number': number,
      'salestipe_id': salesTipeId,
      'organisasi_id': organisasiId,
      'device_token': deviceToken,
      'voucher': voucher,
      'member_id': memberId,
      'store_id': storeId,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'recalculateChannel',
          ...payload,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // CEK VOUCHER
  // RPC: POST /penjualan.php (action: cekVoucher)
  // ============================================================
  static Future<Map<String, dynamic>> checkVoucher({
    required String code,
    required int organisasiId,
    required int storeId,
    required String number,
    required String deviceToken,
    int memberId = 0,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final payload = {
      'code': code,
      'organisasi_id': organisasiId,
      'store_id': storeId,
      'number': number,
      'device_token': deviceToken,
      'member_id': memberId,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'cekVoucher',
          ...payload,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal cek voucher'};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // RESET DISKON
  // RPC: POST /penjualan.php (action: resetDiskon)
  // ============================================================
  static Future<bool> resetDiscount({
    required String number,
    required String deviceToken,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'resetDiskon',
          'number': number,
          'device_token': deviceToken,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return false;
    }

    final data = _parseData(responseData);
    return data['success'] == true;
  }

  // ============================================================
  // CEK RETUR
  // RPC: POST /penjualan.php (action: cekRetur)
  // ============================================================
  static Future<Map<String, dynamic>> checkReturn({
    required String nomorInvoice,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'cekRetur',
          'nomor_invoice': nomorInvoice,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal cek retur'};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // LOAD RETUR (Muat item retur ke dalam transaksi aktif)
  // RPC: POST /penjualan.php (action: loadRetur)
  // ============================================================
  static Future<Map<String, dynamic>> loadReturn({
    required String nomorInvoice,
    required String number,
    required int organisasiId,
    required int storeId,
    required String deviceToken,
    required int salesTipeId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final payload = {
      'nomor_invoice': nomorInvoice,
      'number': number,
      'organisasi_id': organisasiId,
      'store_id': storeId,
      'device_token': deviceToken,
      'salestipe_id': salesTipeId,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'loadRetur',
          ...payload,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal memuat item retur'};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // SET ITEM FREE
  // RPC: POST /penjualan.php (action: setItemFree)
  // ============================================================
  static Future<Map<String, dynamic>> setItemFree({
    required int itemId,
    required String number,
    required String deviceToken,
    required bool isFree,
    String reason = '',
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final payload = {
      'id': itemId,
      'number': number,
      'device_token': deviceToken,
      'is_free': isFree ? 1 : 0,
      'free_reason': reason,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'setItemFree',
          ...payload,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // INSERT ITEM NEW ROW (tambah baris item baru langsung)
  // RPC: POST /penjualan.php (action: insertItemNewRow)
  // ============================================================
  static Future<Map<String, dynamic>> insertItemNewRow({
    required String number,
    required String sku,
    required int organisasiId,
    required int storeId,
    required String deviceToken,
    required int salesTipeId,
    int qty = 1,
    bool isFree = false,
    String reason = '',
    int memberId = 0,
    String voucher = '',
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    final payload = {
      'number': number,
      'sku': sku,
      'organisasi_id': organisasiId,
      'store_id': storeId,
      'device_token': deviceToken,
      'salestipe_id': salesTipeId,
      'qty': qty,
      'is_free': isFree ? 1 : 0,
      'free_reason': reason,
      'member_id': memberId,
      'voucher': voucher,
    };

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'insertItemNewRow',
          ...payload,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return {'success': false};
    }

    return _parseData(responseData);
  }

  // ============================================================
  // GET CART ITEMS AS IS (Raw temp_invoice rows untuk pending order)
  // RPC: POST /penjualan.php (action: getCartItemsAsIs)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getCartItemsAsIs({
    required String number,
    required String deviceToken,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getCartItemsAsIs',
          'number': number,
          'device_token': deviceToken,
        }),
      );
      responseData = res.data;
    } catch (_) {
      return [];
    }

    final data = _parseData(responseData);
    final raw = data['data'] ?? data['items'] ?? [];
    if (raw is List) {
      return raw
          .whereType<Map>()
          .map((e) => Map<String, dynamic>.from(e))
          .toList();
    }
    return [];
  }

  // ============================================================
  // KEMASAN / BOX (override kasir) — hanya lewat penjualan.php
  // Box dihitung otomatis server saat prosesBayar; 3 endpoint ini
  // hanya untuk melihat hitungan, menyimpan override, dan reset.
  // ============================================================
  static Future<Map<String, dynamic>> _postKemasan(
    Map<String, dynamic> fields,
  ) async {
    try {
      final res = await ApiService.getDio().post(
        '/penjualan.php',
        data: FormData.fromMap(fields),
      );
      final data = _parseData(res.data);
      if (data.isEmpty) {
        return {'success': false, 'message': 'Respons server tidak valid'};
      }
      return data;
    } catch (_) {
      return {'success': false, 'message': 'Gagal terhubung ke server'};
    }
  }

  /// Hitungan box saat ini (cart_kosong / sumber auto|manual / items / opsi).
  static Future<Map<String, dynamic>> getKemasan({
    required String number,
    required int storeId,
    required int organisasiId,
    required String deviceToken,
  }) {
    return _postKemasan({
      'action': 'getKemasan',
      'number': number,
      'store_id': storeId,
      'organisasi_id': organisasiId,
      'device_token': deviceToken,
    });
  }

  /// Simpan override. [items] = [{id, qty}]; list kosong = "tanpa box".
  static Future<Map<String, dynamic>> simpanKemasan({
    required String number,
    required int organisasiId,
    required String deviceToken,
    required List<Map<String, dynamic>> items,
  }) {
    return _postKemasan({
      'action': 'simpanKemasan',
      'number': number,
      'organisasi_id': organisasiId,
      'device_token': deviceToken,
      'items': jsonEncode(items),
    });
  }

  /// Hapus override → kembali ke hitungan otomatis.
  static Future<Map<String, dynamic>> resetKemasan({
    required String number,
    required String deviceToken,
  }) {
    return _postKemasan({
      'action': 'resetKemasan',
      'number': number,
      'device_token': deviceToken,
    });
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
