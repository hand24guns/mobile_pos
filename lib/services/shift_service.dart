import 'package:dio/dio.dart';
import 'api_service.dart';

/// Status shift di divisi
enum ShiftStatus {
  /// Belum ada shift aktif → user harus buka shift
  tidakAda,

  /// Shift aktif milik user ini → bisa langsung masuk
  milikSaya,

  /// Shift aktif tapi milik user lain → blokir
  milikOrangLain,
}

class ShiftResult {
  final ShiftStatus status;
  final int shiftID;
  final double modalKasir;
  final String kasirNama; // diisi jika status == milikOrangLain

  const ShiftResult({
    required this.status,
    this.shiftID = 0,
    this.modalKasir = 0,
    this.kasirNama = '',
  });
}

class ShiftService {
  // ============================================================
  // CEK SHIFT AKTIF
  // ============================================================
  static Future<ShiftResult> cekShift({
    required String token,
    required int storeID,
    required int organisasiID,
    required int userID,
  }) async {
    final dio = ApiService.getDio(token: token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'cekShift',
          'store_id': storeID,
          'organisasi_id': organisasiID,
          'user_id': userID,
        }));

    final data = res.data;
    final int statusCode = data['status'] ?? 0;

    switch (statusCode) {
      case 1:
        return ShiftResult(
          status: ShiftStatus.milikSaya,
          shiftID: data['shift_id'] ?? 0,
          modalKasir: (data['modal_kasir'] as num?)?.toDouble() ?? 0,
        );
      case 2:
        return ShiftResult(
          status: ShiftStatus.milikOrangLain,
          shiftID: data['shift_id'] ?? 0,
          kasirNama: data['kasir_nama'] ?? 'User lain',
        );
      default:
        return const ShiftResult(status: ShiftStatus.tidakAda);
    }
  }

  // ============================================================
  // BUKA SHIFT
  // ============================================================
  static Future<int> bukaShift({
    required String token,
    required int storeID,
    required int organisasiID,
    required int userID,
    required double modalKasir,
  }) async {
    final dio = ApiService.getDio(token: token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'bukaShift',
          'store_id': storeID,
          'organisasi_id': organisasiID,
          'user_id': userID,
          'modal_kasir': modalKasir,
        }));

    if (res.data['success'] == true) {
      return res.data['shift_id'] as int;
    }
    return 0;
  }

  // ============================================================
  // GET REKAP SHIFT
  // ============================================================
  static Future<Map<String, dynamic>> getRekapShift({
    required String token,
    required int shiftID,
    required int storeID,
    required int organisasiID,
  }) async {
    final dio = ApiService.getDio(token: token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'getRekapShift',
          'shift_id': shiftID,
          'store_id': storeID,
          'organisasi_id': organisasiID,
        }));

    if (res.data['success'] == true) {
      return {
        'open_shift': res.data['open_shift'] ?? '',
        'modal_kasir': (res.data['modal_kasir'] as num?)?.toDouble() ?? 0,
        'jumlah_invoice': res.data['jumlah_invoice'] ?? 0,
        'total_sales': (res.data['total_sales'] as num?)?.toDouble() ?? 0,
      };
    }
    return {};
  }

  // ============================================================
  // TUTUP SHIFT
  // ============================================================
  static Future<bool> tutupShift({
    required String token,
    required int shiftID,
    required int storeID,
    required int organisasiID,
    required double totalSales,
    required int jumlahInvoice,
  }) async {
    final dio = ApiService.getDio(token: token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'tutupShift',
          'shift_id': shiftID,
          'store_id': storeID,
          'organisasi_id': organisasiID,
          'total_sales': totalSales,
          'jumlah_invoice': jumlahInvoice,
        }));

    return res.data['success'] == true;
  }
}
