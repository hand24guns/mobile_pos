import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class OrderService {
  // ============================================================
  // GET INVOICES — Ambil daftar invoice berdasarkan filter tanggal & store
  //
  // REST API: GET /v1/orders?date_from=Y-m-d&date_to=Y-m-d&store_id=X
  // Fallback: POST /penjualan.php (action: getInvoiceList)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getInvoices({
    int? userId,
    int? organisasiId,
    int? storeId,
    required String dateFrom,
    required String dateTo,
    String? caraBayar,
    String? search,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba RESTful API endpoint terlebih dahulu
    try {
      final response = await dio.get(
        '/v1/orders',
        queryParameters: {
          'date_from': dateFrom,
          'date_to': dateTo,
          if (userId != null && userId > 0) 'user_id': userId,
          if (organisasiId != null && organisasiId > 0)
            'organisasi_id': organisasiId,
          if (storeId != null && storeId > 0) 'store_id': storeId,
          if (caraBayar != null && caraBayar.isNotEmpty)
            'cara_bayar': caraBayar,
          if (search != null && search.isNotEmpty) 'search': search,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback ke endpoint legacy /penjualan.php jika REST belum siap
    if (!restSuccess || responseData == null) {
      try {
        final response = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'getInvoiceList',
            'user_id': userId,
            'organisasi_id': organisasiId,
            'date_from': dateFrom,
            'date_to': dateTo,
            if (storeId != null && storeId > 0) 'store_id': storeId,
          }),
        );
        responseData = response.data;
      } catch (e) {
        // Fallback form-urlencoded
        try {
          final response = await dio.post(
            '/penjualan.php',
            data: {
              'action': 'getInvoiceList',
              'user_id': userId,
              'organisasi_id': organisasiId,
              'date_from': dateFrom,
              'date_to': dateTo,
              if (storeId != null && storeId > 0) 'store_id': storeId,
            },
            options: Options(contentType: Headers.formUrlEncodedContentType),
          );
          responseData = response.data;
        } catch (_) {
          return [];
        }
      }
    }

    final data = _parseResponse(responseData);
    final rawList = data['data'] ?? data['invoices'] ?? data['orders'];
    if (rawList is List) {
      return List<Map<String, dynamic>>.from(
        rawList.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
      );
    }

    return [];
  }

  // ============================================================
  // GET INVOICE DETAIL — Ambil item produk dan keterangan invoice
  //
  // REST API: GET /v1/orders/{invoice_id}
  // Fallback: POST /penjualan.php (action: getInvoiceDetail)
  // ============================================================
  static Future<Map<String, dynamic>> getInvoiceDetail(int invoiceId) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. REST API
    try {
      final response = await dio.get('/v1/orders/$invoiceId');
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback
    if (!restSuccess || responseData == null) {
      try {
        final response = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'getInvoiceDetail',
            'invoice_id': invoiceId,
          }),
        );
        responseData = response.data;
      } catch (e) {
        throw Exception('Gagal mengambil detail invoice: $e');
      }
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    if (!isSuccess && data.containsKey('message')) {
      throw Exception(data['message'] ?? 'Invoice tidak bisa dicetak');
    }

    final payload = (data['data'] is Map<String, dynamic>)
        ? data['data'] as Map<String, dynamic>
        : data;

    final rawItems = payload['items'] ?? data['items'] ?? data['data'];
    final items = (rawItems is List)
        ? List<Map<String, dynamic>>.from(
            rawItems.whereType<Map>().map((e) => Map<String, dynamic>.from(e)),
          )
        : <Map<String, dynamic>>[];

    final keterangan =
        payload['keterangan'] ?? data['keterangan']?.toString() ?? '';

    return {
      'items': items,
      'keterangan': keterangan,
    };
  }

  // ============================================================
  // TRACK PRINT — Tambah counter cetak invoice
  //
  // REST API: POST /v1/orders/{kode}/track-print
  // Fallback: POST /penjualan.php (action: trackPrint)
  // ============================================================
  static Future<int> trackPrint(String kode) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. REST API
    try {
      final response = await dio.post(
        '/v1/orders/$kode/track-print',
        data: {'kode': kode},
      );
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback
    if (!restSuccess || responseData == null) {
      try {
        final response = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'trackPrint',
            'kode': kode,
          }),
        );
        responseData = response.data;
      } catch (_) {
        return 1;
      }
    }

    final data = _parseResponse(responseData);
    if (data['success'] == true || data['success'] == 1) {
      final rawCount = data['count'] ?? data['copy_count'];
      return (rawCount as num?)?.toInt() ?? 1;
    }

    return 1;
  }

  // ============================================================
  // VOID INVOICE — Kirim request pembatalan / void invoice
  //
  // REST API: POST /v1/orders/{id}/cancel
  // Fallback: POST /penjualan.php (action: voidInvoice)
  // ============================================================
  static Future<Map<String, dynamic>> voidInvoice({
    required int invoiceId,
    required String notes,
    int? userId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. REST API
    try {
      final response = await dio.post(
        '/v1/orders/$invoiceId/cancel',
        data: {
          'notes': notes,
          'reason': notes,
          if (userId != null && userId > 0) 'user_id': userId,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback
    if (!restSuccess || responseData == null) {
      try {
        final response = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'voidInvoice',
            'id': invoiceId,
            'notes': notes,
            if (userId != null && userId > 0) 'userID': userId,
          }),
        );
        responseData = response.data;
      } catch (e) {
        return {
          'success': false,
          'message': 'Gagal terhubung ke server: $e',
        };
      }
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    return {
      'success': isSuccess,
      'message': data['message']?.toString() ??
          (isSuccess ? 'Request void berhasil dikirim!' : 'Gagal kirim request void'),
    };
  }

  // ============================================================
  // CHECKOUT ORDER (Proses Bayar / Simpan Penjualan)
  // REST API: POST /v1/orders
  // Fallback: POST /penjualan.php (action: prosesBayar)
  // ============================================================
  static Future<Map<String, dynamic>> checkoutOrder({
    required String number,
    required int caraBayarId,
    required int storeId,
    required int organisasiId,
    required dynamic userId,
    required int salesTipeId,
    int memberId = 0,
    String voucher = '',
    String? returSource,
    required double nominalBayar,
    required String deviceToken,
    String keterangan = '',
    int pendingOrderId = 0,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    final payload = {
      'number': number,
      'cara_bayar_id': caraBayarId,
      'store_id': storeId,
      'organisasi_id': organisasiId,
      'user_id': userId,
      'sales_tipe_id': salesTipeId,
      'member_id': memberId,
      'voucher': voucher,
      if (returSource != null && returSource.isNotEmpty)
        'retur_source': returSource,
      'nominal_bayar': nominalBayar,
      'device_token': deviceToken,
      'keterangan': keterangan,
      'pending_order_id': pendingOrderId,
    };

    // 1. Coba REST API
    try {
      final res = await dio.post('/v1/orders', data: payload);
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
            'action': 'prosesBayar',
            ...payload,
          }),
        );
        responseData = res.data;
      } catch (e) {
        return {'success': false, 'message': 'Gagal memproses pembayaran: $e'};
      }
    }

    return _parseResponse(responseData);
  }

  // ============================================================
  // SEND RECEIPT WHATSAPP
  // REST API: POST /v1/orders/{invoice}/send-whatsapp
  // Fallback: POST /penjualan.php (action: kirimWA)
  // ============================================================
  static Future<bool> sendReceiptWhatsApp({
    required String invoiceNumber,
    required int storeId,
    required int organisasiId,
    required int memberId,
  }) async {
    final dio = ApiService.getDio();
    try {
      // 1. Coba REST API
      try {
        final res = await dio.post(
          '/v1/orders/$invoiceNumber/send-whatsapp',
          data: {
            'store_id': storeId,
            'organisasi_id': organisasiId,
            'member_id': memberId,
          },
        );
        if (res.statusCode == 200) return true;
      } catch (_) {}

      // 2. Fallback legacy
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'kirimWA',
          'number': invoiceNumber,
          'store_id': storeId,
          'organisasi_id': organisasiId,
          'member_id': memberId,
        }),
      );
      final data = _parseResponse(res.data);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
  }

  // ============================================================
  // SEND RECEIPT EMAIL
  // REST API: POST /v1/orders/{invoice}/send-email
  // Fallback: POST /penjualan.php (action: kirimEmail)
  // ============================================================
  static Future<bool> sendReceiptEmail({
    required String invoiceNumber,
    required int storeId,
    required int organisasiId,
    required int memberId,
  }) async {
    final dio = ApiService.getDio();
    try {
      // 1. Coba REST API
      try {
        final res = await dio.post(
          '/v1/orders/$invoiceNumber/send-email',
          data: {
            'store_id': storeId,
            'organisasi_id': organisasiId,
            'member_id': memberId,
          },
        );
        if (res.statusCode == 200) return true;
      } catch (_) {}

      // 2. Fallback legacy
      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'kirimEmail',
          'number': invoiceNumber,
          'store_id': storeId,
          'organisasi_id': organisasiId,
          'member_id': memberId,
        }),
      );
      final data = _parseResponse(res.data);
      return data['success'] == true;
    } catch (_) {
      return false;
    }
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
