import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';
import 'session_service.dart';

class TrialStatus {
  final String organisasi;
  final String? tglSelesai;
  final bool expired;
  final int? daysRemaining;
  final String whatsappUrl;

  const TrialStatus({
    this.organisasi = '',
    this.tglSelesai,
    this.expired = false,
    this.daysRemaining,
    this.whatsappUrl = '',
  });

  /// Alert tampil jika belum expired dan sisa hari <= 14 (H-14)
  bool get shouldShowAlert =>
      !expired &&
      daysRemaining != null &&
      daysRemaining! >= 0 &&
      daysRemaining! <= 14;

  factory TrialStatus.fromJson(Map<String, dynamic> json) {
    return TrialStatus(
      organisasi: json['organisasi']?.toString() ?? '',
      tglSelesai: json['tglselesai']?.toString(),
      expired: json['expired'] == true ||
          json['expired'] == 1 ||
          json['expired'] == 'true',
      daysRemaining: json['days_remaining'] is num
          ? (json['days_remaining'] as num).toInt()
          : int.tryParse(json['days_remaining']?.toString() ?? ''),
      whatsappUrl: json['whatsapp_url']?.toString() ?? '',
    );
  }
}

class DashboardStats {
  final int invoiceCount;
  final double totalPenjualan;
  final List<int> storeIds;
  final TrialStatus? trialStatus;

  const DashboardStats({
    this.invoiceCount = 0,
    this.totalPenjualan = 0.0,
    this.storeIds = const [],
    this.trialStatus,
  });
}

class DashboardService {
  // ============================================================
  // GET DASHBOARD STATS
  // Mengambil total invoice hari ini, total nominal penjualan,
  // dan status trial organisasi untuk daftar store_ids.
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

      final rawTrial = payload['trial_status'] ?? data['trial_status'];
      TrialStatus? trialStatus;
      if (rawTrial is Map<String, dynamic>) {
        trialStatus = TrialStatus.fromJson(rawTrial);
      }

      return DashboardStats(
        invoiceCount: invoiceCount,
        totalPenjualan: totalPenjualan,
        storeIds: effectiveStoreIds,
        trialStatus: trialStatus,
      );
    }

    return DashboardStats(storeIds: effectiveStoreIds);
  }

  // ============================================================
  // GET TRIAL STATUS LANGSUNG
  // ============================================================
  static Future<TrialStatus?> getTrialStatus() async {
    final dio = ApiService.getDio();
    try {
      final response = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getTrialStatus',
        }),
      );
      final dynamic raw = response.data;
      Map<String, dynamic> data = {};
      if (raw is Map<String, dynamic>) {
        data = raw;
      } else if (raw is String && raw.trim().isNotEmpty) {
        data = jsonDecode(raw);
      }
      final rawTrial = data['trial_status'];
      if (rawTrial is Map<String, dynamic>) {
        return TrialStatus.fromJson(rawTrial);
      }
    } catch (_) {}
    return null;
  }
}
