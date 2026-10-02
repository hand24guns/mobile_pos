import 'dart:convert';
import 'package:dio/dio.dart';
import 'api_service.dart';

class PettyCashService {
  // ============================================================
  // GET NOMOR DOKUMEN KAS KECIL
  //
  // REST API: GET /v1/petty-cash/number?tipe=masuk|keluar&organisasi_id=X
  // Fallback: POST /penjualan.php (action: getNumberPetikes)
  // ============================================================
  static Future<String?> getPettyCashNumber({
    required String tipe,
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final response = await dio.get(
        '/v1/petty-cash/number',
        queryParameters: {
          'tipe': tipe,
          'organisasi_id': organisasiId,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy /penjualan.php
    if (!restSuccess || responseData == null) {
      try {
        final response = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'getNumberPetikes',
            'tipe': tipe,
            'organisasi_id': organisasiId,
          }),
        );
        responseData = response.data;
      } catch (_) {
        return null;
      }
    }

    final data = _parseResponse(responseData);
    if (data['success'] == true || data['success'] == 1 || data['success'] == 'true') {
      return data['number']?.toString();
    }
    return null;
  }

  // ============================================================
  // GET KATEGORI OPEX
  //
  // REST API: GET /v1/petty-cash/categories?organisasi_id=X
  // Fallback: POST /penjualan.php (action: getOpexPetikes)
  // ============================================================
  static Future<List<Map<String, dynamic>>> getOpexCategories({
    required int organisasiId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final response = await dio.get(
        '/v1/petty-cash/categories',
        queryParameters: {'organisasi_id': organisasiId},
      );
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy /penjualan.php
    if (!restSuccess || responseData == null) {
      try {
        final response = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'getOpexPetikes',
            'organisasi_id': organisasiId,
          }),
        );
        responseData = response.data;
      } catch (_) {
        return [];
      }
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
  // GET MUTASI KAS KECIL
  //
  // REST API: GET /v1/petty-cash?store_id=X&organisasi_id=Y&start_date=Z&end_date=W
  // Fallback: POST /penjualan.php (action: getPetikesList)
  // ============================================================
  static Future<Map<String, dynamic>> getPettyCashList({
    required int storeId,
    required int organisasiId,
    required String startDate,
    required String endDate,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final response = await dio.get(
        '/v1/petty-cash',
        queryParameters: {
          'store_id': storeId,
          'organisasi_id': organisasiId,
          'start_date': startDate,
          'end_date': endDate,
        },
      );
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy /penjualan.php
    if (!restSuccess || responseData == null) {
      try {
        final response = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'getPetikesList',
            'store_id': storeId,
            'organisasi_id': organisasiId,
            'start_date': startDate,
            'end_date': endDate,
          }),
        );
        responseData = response.data;
      } catch (_) {
        return {
          'success': false,
          'message': 'Gagal terhubung ke server',
          'data': <Map<String, dynamic>>[],
          'saldo_total': 0.0,
        };
      }
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    if (isSuccess) {
      final raw = data['data'];
      final List<Map<String, dynamic>> list = [];
      if (raw is List) {
        for (final item in raw) {
          if (item is Map) {
            list.add(Map<String, dynamic>.from(item));
          }
        }
      }

      final double saldoTotal =
          double.tryParse('${data['saldo_total'] ?? 0}') ?? 0.0;

      return {
        'success': true,
        'data': list,
        'saldo_total': saldoTotal,
      };
    }

    return {
      'success': false,
      'message': data['message']?.toString() ?? 'Gagal memuat data kas kecil',
      'data': <Map<String, dynamic>>[],
      'saldo_total': 0.0,
    };
  }

  // ============================================================
  // GET DETAIL JURNAL & FOTO NOTA KAS KECIL
  //
  // REST API: GET /v1/petty-cash/{payment_id}/journal
  // Fallback: POST /penjualan.php (action: getJurnal)
  // ============================================================
  static Future<Map<String, dynamic>> getJournalDetail({
    required int paymentId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final response = await dio.get('/v1/petty-cash/$paymentId/journal');
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy /penjualan.php
    if (!restSuccess || responseData == null) {
      try {
        final response = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'getJurnal',
            'payment_id': paymentId,
          }),
        );
        responseData = response.data;
      } catch (_) {
        return {'success': false, 'message': 'Gagal terhubung ke server'};
      }
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    if (isSuccess) {
      final rawDetil = data['detil'];
      final List<Map<String, dynamic>> detil = [];
      if (rawDetil is List) {
        for (final d in rawDetil) {
          if (d is Map) {
            detil.add(Map<String, dynamic>.from(d));
          }
        }
      }

      final rawImages = data['images'];
      final List<String> images = [];
      if (rawImages is List) {
        for (final img in rawImages) {
          if (img != null) images.add(img.toString());
        }
      }

      return {
        'success': true,
        'detil': detil,
        'total_debit': (data['total_debit'] as num?)?.toDouble() ?? 0.0,
        'total_kredit': (data['total_kredit'] as num?)?.toDouble() ?? 0.0,
        'images': images,
      };
    }

    return {
      'success': false,
      'message': data['message']?.toString() ?? 'Gagal memuat detail jurnal',
    };
  }

  // ============================================================
  // VOID TRANSAKSI KAS KECIL
  //
  // REST API: POST /v1/petty-cash/{payment_id}/void
  // Fallback: POST /penjualan.php (action: voidPetikes)
  // ============================================================
  static Future<Map<String, dynamic>> voidPettyCash({
    required int paymentId,
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    // 1. Coba REST API
    try {
      final response = await dio.post('/v1/petty-cash/$paymentId/void');
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy /penjualan.php
    if (!restSuccess || responseData == null) {
      try {
        final response = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'voidPetikes',
            'payment_id': paymentId,
          }),
        );
        responseData = response.data;
      } catch (_) {
        return {'success': false, 'message': 'Gagal terhubung ke server'};
      }
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    return {
      'success': isSuccess,
      'message': data['message']?.toString() ??
          (isSuccess ? 'Transaksi berhasil di-void' : 'Gagal void transaksi'),
    };
  }

  // ============================================================
  // SUBMIT TRANSAKSI KAS KECIL (DENGAN UPLOAD FOTO)
  //
  // REST API: POST /v1/petty-cash
  // Fallback: POST /penjualan.php (action: simpanPetikes)
  // ============================================================
  static Future<Map<String, dynamic>> submitPettyCash({
    required int storeId,
    required int organisasiId,
    required String tipe,
    required String tanggal,
    required String number,
    required String keterangan,
    required List<int> kategori,
    required List<String> deskripsi,
    required List<String> nominal,
    List<String> imagePaths = const [],
  }) async {
    final dio = ApiService.getDio();
    dynamic responseData;
    bool restSuccess = false;

    Future<FormData> buildFormData({bool isLegacy = false}) async {
      final formMap = <String, dynamic>{
        if (isLegacy) 'action': 'simpanPetikes',
        'store_id': storeId,
        'organisasi_id': organisasiId,
        'tipe': tipe,
        'tanggal': tanggal,
        'number': number,
        'keterangan': keterangan,
      };

      for (int i = 0; i < deskripsi.length; i++) {
        formMap['kategori[$i]'] = kategori[i];
        formMap['deskripsi[$i]'] = deskripsi[i];
        formMap['nominal[$i]'] = nominal[i];
      }

      final formData = FormData.fromMap(formMap);

      for (int i = 0; i < imagePaths.length; i++) {
        final path = imagePaths[i];
        final filename = path.split(RegExp(r'[\\/]')).last;
        formData.files.add(
          MapEntry(
            'images[]',
            await MultipartFile.fromFile(path, filename: filename),
          ),
        );
      }

      return formData;
    }

    // 1. Coba REST API
    try {
      final formData = await buildFormData(isLegacy: false);
      final response = await dio.post(
        '/v1/petty-cash',
        data: formData,
      );
      if (response.statusCode == 200 && response.data != null) {
        responseData = response.data;
        restSuccess = true;
      }
    } catch (_) {
      restSuccess = false;
    }

    // 2. Fallback legacy /penjualan.php
    if (!restSuccess || responseData == null) {
      try {
        final legacyFormData = await buildFormData(isLegacy: true);
        final response = await dio.post(
          '/penjualan.php',
          data: legacyFormData,
        );
        responseData = response.data;
      } catch (_) {
        return {'success': false, 'message': 'Gagal terhubung ke server'};
      }
    }

    final data = _parseResponse(responseData);
    final isSuccess = data['success'] == true ||
        data['success'] == 1 ||
        data['success'] == 'true';

    return {
      'success': isSuccess,
      'message': data['message']?.toString() ??
          (isSuccess ? 'Petty cash berhasil disimpan' : 'Gagal menyimpan transaksi'),
    };
  }

  // ── Helper parsing response ────────────────────────────────
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
