import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';
import 'session_service.dart';

class DashboardStats {
  final int invoiceCount;
  final double totalPenjualan;
  final List<int> storeIds;

  const DashboardStats({
    this.invoiceCount = 0,
    this.totalPenjualan = 0.0,
    this.storeIds = const [],
  });
}

class DashboardService {
  // ============================================================
  // GET DASHBOARD STATS
  // Mengambil total invoice hari ini dan total nominal penjualan
  // untuk daftar store_ids yang diberikan (atau auto-resolve jika kosong).
  //
  // REST API: GET /v1/dashboard?store_ids=1,2,3
  // Fallback: POST /penjualan.php (action: getDashboard)
  // ============================================================
  static Future<DashboardStats> getStats({
    List<int> storeIds = const [],
  }) async {
    final dio = ApiService.getDio();
    List<int> effectiveStoreIds = List.from(storeIds);

    // Jika storeIds kosong, coba ambil daftar store milik user via getStores
    if (effectiveStoreIds.isEmpty) {
      try {
        final session = await SessionService.getSession();
        final userId = session['user_id'] ?? 0;
        final res = await dio.post(
          '/penjualan.php',
          data: {
            'action': 'getStores',
            'user_id': userId,
          },
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
        final raw = res.data;
        Map<String, dynamic> sData = {};
        if (raw is Map<String, dynamic>) {
          sData = raw;
        } else if (raw is String && raw.isNotEmpty) {
          sData = jsonDecode(raw);
        }
        if (sData['data'] is List) {
          effectiveStoreIds = (sData['data'] as List)
              .map((s) => int.tryParse(s['id']?.toString() ?? '') ?? 0)
              .where((id) => id > 0)
              .toList();
        }
      } catch (_) {}
    }

    final storeIdsStr = effectiveStoreIds.join(',');

    dynamic responseData;
    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getDashboard',
          'store_ids': storeIdsStr,
        }),
      );
      responseData = response.data;
    } catch (_) {
      return DashboardStats(storeIds: effectiveStoreIds);
    }

    // 3. Parse response data (baik Map maupun String JSON)
    Map<String, dynamic> data = {};
    if (responseData is Map<String, dynamic>) {
      data = responseData;
    } else if (responseData is String && responseData.trim().isNotEmpty) {
      try {
        final decoded = jsonDecode(responseData);
        if (decoded is Map<String, dynamic>) {
          data = decoded;
        }
      } catch (_) {}
    }

    final bool isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true' ||
        data['success'] == '1';

    if (isSuccess) {
      final payload = (data['data'] is Map<String, dynamic>)
          ? data['data'] as Map<String, dynamic>
          : data;

      final rawInvoice = payload['invoice_count'] ??
          payload['invoice_hari_ini'] ??
          payload['count'] ??
          data['invoice_count'];

      final int invoiceCount = rawInvoice is int
          ? rawInvoice
          : int.tryParse(rawInvoice?.toString() ?? '') ?? 0;

      final rawTotal = payload['total_penjualan'] ??
          payload['total'] ??
          data['total_penjualan'];

      final double totalPenjualan = rawTotal is num
          ? rawTotal.toDouble()
          : double.tryParse(rawTotal?.toString() ?? '') ?? 0.0;

      return DashboardStats(
        invoiceCount: invoiceCount,
        totalPenjualan: totalPenjualan,
        storeIds: effectiveStoreIds,
      );
    }

    return DashboardStats(storeIds: effectiveStoreIds);
  }
}
