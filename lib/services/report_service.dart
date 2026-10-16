import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class PaymentReportResult {
  final List<Map<String, dynamic>> rows;
  final int totalFrequency;
  final double totalAmount;

  const PaymentReportResult({
    this.rows = const [],
    this.totalFrequency = 0,
    this.totalAmount = 0.0,
  });
}

class OnhandReportResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> summary;

  const OnhandReportResult({
    this.success = false,
    this.message,
    this.items = const [],
    this.summary = const {},
  });
}

class ItemTerjualReportResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> summary;

  const ItemTerjualReportResult({
    this.success = false,
    this.message,
    this.items = const [],
    this.summary = const {},
  });
}

class ChannelTerjualReportResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> summary;

  const ChannelTerjualReportResult({
    this.success = false,
    this.message,
    this.items = const [],
    this.summary = const {},
  });
}

class KemasanTerpakaiReportResult {
  final bool success;
  final String? message;
  final List<Map<String, dynamic>> items;
  final Map<String, dynamic> summary;

  const KemasanTerpakaiReportResult({
    this.success = false,
    this.message,
    this.items = const [],
    this.summary = const {},
  });
}

class ReportService {
  // ============================================================
  // GET ONHAND REPORT — Laporan stok produk onhand per store / agregasi
  // RPC: POST /penjualan.php (action: getOnhand)
  // ============================================================
  static Future<OnhandReportResult> getOnhandReport({int? storeId}) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getOnhand',
          'store_id': (storeId ?? 0).toString(),
        }),
      );
      responseData = response.data;
    } catch (_) {
      return const OnhandReportResult(
        success: false,
        message: 'Gagal terhubung ke server',
      );
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    if (isSuccess) {
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;

      final rawItems = payload['items'] ?? payload['data'] ?? [];
      final List<Map<String, dynamic>> items = [];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            items.add(Map<String, dynamic>.from(item));
          }
        }
      }

      final summary = (payload['summary'] is Map)
          ? Map<String, dynamic>.from(payload['summary'])
          : <String, dynamic>{};

      return OnhandReportResult(
        success: true,
        items: items,
        summary: summary,
      );
    }

    return OnhandReportResult(
      success: false,
      message: data['message']?.toString() ?? 'Gagal memuat data onhand',
    );
  }

  // ============================================================
  // GET ITEM TERJUAL REPORT — Rekap item terjual per rentang tanggal
  // RPC: POST /penjualan.php (action: getItemTerjual)
  // ============================================================
  static Future<ItemTerjualReportResult> getItemTerjualReport({
    int? storeId,
    required String startDate,
    required String endDate,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getItemTerjual',
          'store_id': (storeId ?? 0).toString(),
          'start_date': startDate,
          'end_date': endDate,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return const ItemTerjualReportResult(
        success: false,
        message: 'Gagal terhubung ke server',
      );
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    if (isSuccess) {
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;

      final rawItems = payload['items'] ?? payload['data'] ?? [];
      final List<Map<String, dynamic>> items = [];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            items.add(Map<String, dynamic>.from(item));
          }
        }
      }

      final summary = (payload['summary'] is Map)
          ? Map<String, dynamic>.from(payload['summary'])
          : <String, dynamic>{};

      return ItemTerjualReportResult(
        success: true,
        items: items,
        summary: summary,
      );
    }

    return ItemTerjualReportResult(
      success: false,
      message: data['message']?.toString() ?? 'Gagal memuat data item terjual',
    );
  }

  // ============================================================
  // GET CHANNEL TERJUAL REPORT — Rekap transaksi & nominal per channel
  // RPC: POST /penjualan.php (action: getChannelTerjual)
  // ============================================================
  static Future<ChannelTerjualReportResult> getChannelTerjualReport({
    int? storeId,
    required String startDate,
    required String endDate,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getChannelTerjual',
          'store_id': (storeId ?? 0).toString(),
          'start_date': startDate,
          'end_date': endDate,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return const ChannelTerjualReportResult(
        success: false,
        message: 'Gagal terhubung ke server',
      );
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    if (isSuccess) {
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;

      final rawItems = payload['items'] ?? payload['data'] ?? [];
      final List<Map<String, dynamic>> items = [];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            items.add(Map<String, dynamic>.from(item));
          }
        }
      }

      final summary = (payload['summary'] is Map)
          ? Map<String, dynamic>.from(payload['summary'])
          : <String, dynamic>{};

      return ChannelTerjualReportResult(
        success: true,
        items: items,
        summary: summary,
      );
    }

    return ChannelTerjualReportResult(
      success: false,
      message: data['message']?.toString() ?? 'Gagal memuat data channel terjual',
    );
  }

  // ============================================================
  // GET KEMASAN TERPAKAI REPORT — Rekap penggunaan box/kemasan
  // (tr_invoice_kemasan) per rentang tanggal
  // RPC: POST /penjualan.php (action: getKemasanTerpakai)
  // ============================================================
  static Future<KemasanTerpakaiReportResult> getKemasanTerpakaiReport({
    int? storeId,
    required String startDate,
    required String endDate,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getKemasanTerpakai',
          'store_id': (storeId ?? 0).toString(),
          'start_date': startDate,
          'end_date': endDate,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return const KemasanTerpakaiReportResult(
        success: false,
        message: 'Gagal terhubung ke server',
      );
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    if (isSuccess) {
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;

      final rawItems = payload['items'] ?? payload['data'] ?? [];
      final List<Map<String, dynamic>> items = [];
      if (rawItems is List) {
        for (final item in rawItems) {
          if (item is Map) {
            items.add(Map<String, dynamic>.from(item));
          }
        }
      }

      final summary = (payload['summary'] is Map)
          ? Map<String, dynamic>.from(payload['summary'])
          : <String, dynamic>{};

      return KemasanTerpakaiReportResult(
        success: true,
        items: items,
        summary: summary,
      );
    }

    return KemasanTerpakaiReportResult(
      success: false,
      message:
          data['message']?.toString() ?? 'Gagal memuat penggunaan box',
    );
  }

  // ============================================================
  // GET PAYMENT REPORT — Rekap pembayaran per metode transaksi
  // RPC: POST /penjualan.php (action: getLaporanPembayaran)
  // ============================================================
  static Future<PaymentReportResult> getPaymentReport({
    String? storeIds,
    int? storeId,
    required String startDate,
    required String endDate,
  }) async {
    final targetStoreIds = (storeIds != null && storeIds.isNotEmpty)
        ? storeIds
        : (storeId != null ? storeId.toString() : '');

    if (targetStoreIds.isEmpty) {
      return const PaymentReportResult();
    }

    final dio = ApiService.getDio();
    dynamic responseData;

    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getLaporanPembayaran',
          'store_ids': targetStoreIds,
          'start_date': startDate,
          'end_date': endDate,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return const PaymentReportResult();
    }

    // 3. Parse response data (baik Map maupun String JSON)
    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    if (isSuccess) {
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;

      final dynamic rawRows =
          payload['rows'] ?? payload['data'] ?? data['rows'];
      final List<Map<String, dynamic>> rowsList = [];
      int freq = 0;
      double amt = 0.0;

      if (rawRows is List) {
        for (final item in rawRows) {
          if (item is Map) {
            final m = Map<String, dynamic>.from(item);
            final nama =
                (m['nama'] ?? m['cara_bayar'] ?? m['payment_method'] ?? '-')
                    .toString();
            final jumlah =
                _parseNum(m['jumlah'] ?? m['qty'] ?? m['frequency']).toInt();
            final total = _parseNum(m['total'] ?? m['amount']);

            freq += jumlah;
            amt += total;

            rowsList.add({
              'nama': nama,
              'jumlah': jumlah,
              'total': total,
            });
          }
        }
      }

      // Urutkan terbesar berdasarkan total nominal transaksi
      rowsList.sort(
          (a, b) => _parseNum(b['total']).compareTo(_parseNum(a['total'])));

      return PaymentReportResult(
        rows: rowsList,
        totalFrequency: payload['total_frequency'] != null
            ? _parseNum(payload['total_frequency']).toInt()
            : freq,
        totalAmount: payload['total_amount'] != null
            ? _parseNum(payload['total_amount'])
            : amt,
      );
    }

    return const PaymentReportResult();
  }

  // ── Helper parsing angka & response ────────────────────────
  static double _parseNum(dynamic v) {
    if (v == null) return 0.0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0.0;
  }

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
