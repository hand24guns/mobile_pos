import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../providers/penjualan_provider.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../services/shift_service.dart';
import '../models/cart_item.dart';
import '../utils/currency_format.dart';
import 'login_screen.dart';
import 'printer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../utils/printer_helper.dart';
import 'invoice_list_screen.dart';
// ── Widget baru ───────────────────────────────────────────────
import '../widgets/package_dialog.dart';
import '../widgets/add_member_sheet.dart';

class PenjualanScreen extends ConsumerStatefulWidget {
  const PenjualanScreen({super.key});

  @override
  ConsumerState<PenjualanScreen> createState() => _PenjualanScreenState();
}

class _PenjualanScreenState extends ConsumerState<PenjualanScreen> {
  final _skuController = TextEditingController();
  final _memberController = TextEditingController();
  final _nominalController = TextEditingController();
  final _keteranganController = TextEditingController(); // keterangan transaksi
  String _activeVoucher = '';

  // Untuk inline notes per item: key = item index, value = controller
  final Map<int, TextEditingController> _itemNotesControllers = {};
  // Set of item indices yang sedang expanded (menampilkan input notes)
  final Set<int> _expandedNotes = {};

  String _token = '';
  int _userID = 0;
  String _deviceToken = '';
  int _shiftID = 0;
  bool _isLoading = true;

  // ── Shift polling ─────────────────────────────────────────────
  Timer? _shiftPollingTimer;
  int _activeStoreID = 0;
  int _activeOrgID = 0;
  String _activeStoreName = '';
  bool _isFnb = false; // true jika jasa_perusahaan == 3 (FnB/resto)

  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _caraBayarList = [];

  // ── Product image grid — dikelompokkan per kategori (jenis produk) ──
  // Struktur: [ { 'id': int, 'nama': String, 'produk': [ {kode,nama,hpj,image} ] } ]
  List<Map<String, dynamic>> _imageCategories = [];
  bool _isLoadingImages = false;

  @override
  void initState() {
    super.initState();
    _loadInitialData();
    _startShiftPolling();
  }

  @override
  void dispose() {
    _shiftPollingTimer?.cancel();
    _skuController.dispose();
    _memberController.dispose();
    _nominalController.dispose();
    _keteranganController.dispose();
    for (final c in _itemNotesControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // ============================================================
  // SHIFT POLLING — cek status shift tiap 60 detik
  // ============================================================
  void _startShiftPolling() {
    _shiftPollingTimer?.cancel();
    _shiftPollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkShiftStillActive();
    });
  }

  Future<void> _checkShiftStillActive() async {
    if (_shiftID == 0 || _activeStoreID == 0 || _activeOrgID == 0) return;
    try {
      final result = await ShiftService.cekShift(
        token: _token,
        storeID: _activeStoreID,
        organisasiID: _activeOrgID,
        userID: _userID,
      );
      final stillActive =
          result.status == ShiftStatus.milikSaya && result.shiftID == _shiftID;
      if (!stillActive && mounted) _onShiftForceClosed();
    } catch (_) {
      // Offline/timeout → diam saja
    }
  }

  void _onShiftForceClosed() {
    _shiftPollingTimer?.cancel();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Shift Ditutup'),
        content: const Text(
          'Shift kamu telah ditutup dari perangkat lain.\n'
          'Silakan buka shift baru untuk melanjutkan.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              setState(() {
                _shiftID = 0;
                _activeStoreID = 0;
                _activeOrgID = 0;
                _activeStoreName = '';
                _isFnb = false;
                _isLoading = true;
              });
              _loadInitialData();
              _startShiftPolling();
            },
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D273B)),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // LOAD INITIAL DATA
  // ============================================================
  Future<void> _loadInitialData() async {
    try {
      final session = await SessionService.getSession();
      _token = session['token'];
      _userID = session['user_id'];
      _deviceToken = await SessionService.getDeviceToken();

      final dio = ApiService.getDio(token: _token);

      // STEP 1 — Cek shift user aktif
      final shiftUserRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'cekShiftUser',
            'user_id': _userID,
          }));

      int storeID = 0;
      int organisasiID = 0;
      String storeName = '';

      if (shiftUserRes.data['has_shift'] == true) {
        storeID = shiftUserRes.data['store_id'];
        organisasiID = shiftUserRes.data['organisasi_id'];
        storeName = shiftUserRes.data['store_nama'];
        _shiftID = shiftUserRes.data['shift_id'];
        _isFnb = (shiftUserRes.data['is_fnb'] as int? ?? 0) == 1;
      } else {
        // STEP 2 — Pilih store
        final storeRes = await dio.post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'getStores',
              'user_id': _userID,
            }));
        final stores = List<Map<String, dynamic>>.from(storeRes.data['data']);

        Map<String, dynamic>? pickedStore;
        if (stores.length == 1) {
          pickedStore = stores.first;
        } else {
          if (!mounted) return;
          pickedStore = await _showStorePicker(stores);
          if (pickedStore == null) {
            await _logout();
            return;
          }
        }

        storeID = int.parse(pickedStore['id'].toString());
        storeName = pickedStore['nama'].toString();

        final orgRes = await dio.post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'getOrganisasiID',
              'store_id': storeID,
            }));
        organisasiID = int.parse(orgRes.data['organisasi_id'].toString());
        _isFnb = (orgRes.data['is_fnb'] as int? ?? 0) == 1;

        // STEP 3 — Cek shift store
        final shiftRes = await ShiftService.cekShift(
          token: _token,
          storeID: storeID,
          organisasiID: organisasiID,
          userID: _userID,
        );

        if (shiftRes.status == ShiftStatus.milikOrangLain) {
          if (mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => AlertDialog(
                title: const Text('Store Sedang Digunakan'),
                content: Text(
                  'Store $storeName sedang digunakan oleh ${shiftRes.kasirNama}.\n\n'
                  'Silahkan pilih store lain atau minta kasir tersebut menutup shiftnya.',
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D273B)),
                    child:
                        const Text('OK', style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
            _loadInitialData();
            return;
          }
        }

        if (shiftRes.status == ShiftStatus.tidakAda) {
          if (!mounted) return;
          final shiftID = await _showBukaShiftDialog(
            storeID: storeID,
            organisasiID: organisasiID,
          );
          if (shiftID == 0) {
            await _logout();
            return;
          }
          _shiftID = shiftID;
        }
      }

      // STEP 4 — Load number, channels, cara bayar
      final numberRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getNumber',
            'store_id': storeID,
            'organisasi_id': organisasiID,
            'device_token': _deviceToken,
          }));
      final number = numberRes.data['number'];

      final channelRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({'action': 'getChannels'}));
      _channels = List<Map<String, dynamic>>.from(channelRes.data['data']);

      final caraBayarRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({'action': 'getCaraBayar'}));
      _caraBayarList =
          List<Map<String, dynamic>>.from(caraBayarRes.data['data']);

      ref.read(penjualanProvider.notifier).setInitialData(
            number: number,
            storeID: storeID,
            storeName: storeName,
            organisasiID: organisasiID,
            salesTipeID:
                int.parse(_channels.first['dim_salestipe_id'].toString()),
          );

      _activeStoreID = storeID;
      _activeOrgID = organisasiID;
      _activeStoreName = storeName;

      setState(() => _isLoading = false);
      _loadImageProducts();
    } catch (e, st) {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _logout() async {
    await SessionService.clearSession();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  // ============================================================
  // STORE PICKER — Modal Bottom Sheet
  // ============================================================
  Future<Map<String, dynamic>?> _showStorePicker(
      List<Map<String, dynamic>> stores) async {
    Map<String, dynamic>? selected;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.store, color: Color(0xFF1D273B), size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text('Pilih Store',
                          style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1D273B))),
                    ),
                    Text('${stores.length} store',
                        style: TextStyle(
                            fontSize: 12, color: Colors.grey.shade500)),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  shrinkWrap: true,
                  itemCount: stores.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final s = stores[i];
                    final isSelected =
                        selected?['id'].toString() == s['id'].toString();
                    return InkWell(
                      onTap: () => setState(() => selected = s),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 16, vertical: 14),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1D273B)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF1D273B)
                                : Colors.grey.shade200,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.store : Icons.store_outlined,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade500,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(s['nama'].toString(),
                                  style: TextStyle(
                                    color: isSelected
                                        ? Colors.white
                                        : Colors.black87,
                                    fontWeight: isSelected
                                        ? FontWeight.bold
                                        : FontWeight.normal,
                                    fontSize: 15,
                                  )),
                            ),
                            if (isSelected)
                              const Icon(Icons.check_circle,
                                  color: Colors.white, size: 18),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: selected == null
                            ? null
                            : () => Navigator.pop(ctx, selected),
                        style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1D273B)),
                        child: Text(
                          selected == null
                              ? 'Pilih Store'
                              : 'Masuk ke ${selected!['nama']}',
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUKA SHIFT
  // ============================================================
  Future<int> _showBukaShiftDialog({
    required int storeID,
    required int organisasiID,
  }) async {
    final modalController = TextEditingController(text: '0');

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Buka Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Input modal kasir awal:',
                style: TextStyle(color: Colors.grey)),
            const SizedBox(height: 12),
            TextField(
              controller: modalController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Modal Kasir',
                border: OutlineInputBorder(),
                prefixText: 'Rp ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D273B)),
            child:
                const Text('Buka Shift', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return 0;

    final modal = double.tryParse(
          modalController.text.replaceAll(',', '').trim(),
        ) ??
        0;

    final shiftID = await ShiftService.bukaShift(
      token: _token,
      storeID: storeID,
      organisasiID: organisasiID,
      userID: _userID,
      modalKasir: modal,
    );

    if (shiftID == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Gagal buka shift'), backgroundColor: Colors.red),
      );
    }
    return shiftID;
  }

  // ============================================================
  // TUTUP SHIFT
  // ============================================================
  Future<void> _tutupShift() async {
    final state = ref.read(penjualanProvider);

    final rekap = await ShiftService.getRekapShift(
      token: _token,
      shiftID: _shiftID,
      storeID: state.storeID,
      organisasiID: state.organisasiID,
    );

    if (rekap.isEmpty || !mounted) return;

    final openShift = rekap['open_shift'] ?? '';
    final modalKasir = (rekap['modal_kasir'] as num).toDouble();
    final totalSales = (rekap['total_sales'] as num).toDouble();
    final jumlahInv = rekap['jumlah_invoice'] as int;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tutup Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rekapRow('Buka Shift', openShift.toString().substring(0, 16)),
            const Divider(),
            _rekapRow('Modal Kasir', 'Rp ${CurrencyFormat.format(modalKasir)}'),
            _rekapRow('Jumlah Invoice', '$jumlahInv transaksi'),
            _rekapRow('Total Sales', 'Rp ${CurrencyFormat.format(totalSales)}'),
            const Divider(),
            const SizedBox(height: 8),
            const Text('Yakin ingin menutup shift?',
                style: TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Tutup Shift',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final berhasil = await ShiftService.tutupShift(
      token: _token,
      shiftID: _shiftID,
      storeID: state.storeID,
      organisasiID: state.organisasiID,
      totalSales: totalSales,
      jumlahInvoice: jumlahInv,
    );

    if (!mounted) return;

    if (berhasil) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Shift Ditutup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 56),
              const SizedBox(height: 16),
              Text('Total Sales: Rp ${CurrencyFormat.format(totalSales)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
              Text('$jumlahInv transaksi',
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _logout();
              },
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFF1D273B)),
              child:
                  const Text('Selesai', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Gagal menutup shift'), backgroundColor: Colors.red),
      );
    }
  }

  Widget _rekapRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );

  // ============================================================
  // SEARCH PRODUK — cek package dulu sebelum insert
  // ============================================================
  Future<void> _searchProduk(String sku) async {
    if (sku.isEmpty) return;
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'searchProduk',
          'term': sku,
          'organisasi_id': state.organisasiID,
        }));

    final data = List<Map<String, dynamic>>.from(res.data['data']);
    if (data.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Produk "$sku" tidak ditemukan')),
        );
      }
      return;
    }

    if (data.length == 1) {
      await _insertProduk(data.first['kode'] as String);
    } else {
      _showProductPicker(data);
    }
    _skuController.clear();
  }

  // ============================================================
  // INSERT PRODUK — wrap: cek package dulu
  // Pakai ResponseType.plain agar tidak crash jika PHP ada output
  // warning/notice sebelum JSON — bersihkan string lalu parse.
  // ============================================================
  Future<void> _insertProduk(String sku) async {
    final state = ref.read(penjualanProvider);
    final dio   = ApiService.getDio(token: _token);

    Map<String, dynamic> cekData;
    try {
      final rawRes = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action':       'cekPackage',
          'sku':          sku,
          'organisasi_id': state.organisasiID,
        }),
        options: Options(responseType: ResponseType.plain),
      );

      final rawStr = rawRes.data?.toString() ?? '';

      // Buang karakter sebelum '{'  (PHP notice / BOM / whitespace)
      final jsonStart = rawStr.indexOf('{');
      if (jsonStart < 0) {
        // Response tidak valid — fallback insert biasa
        debugPrint('[cekPackage] Response tidak valid (no JSON): $rawStr');
        await _doInsertProduk(sku);
        return;
      }
      final cleanStr = rawStr.substring(jsonStart);
      final decoded = jsonDecode(cleanStr);
      if (decoded is! Map) {
        debugPrint('[cekPackage] JSON bukan Map: $cleanStr');
        await _doInsertProduk(sku);
        return;
      }
      cekData = Map<String, dynamic>.from(decoded);
    } on DioException catch (e) {
      debugPrint('[cekPackage] DioException: ${e.message}');
      await _doInsertProduk(sku);
      return;
    } catch (e) {
      debugPrint('[cekPackage] Exception: $e');
      await _doInsertProduk(sku);
      return;
    }

    // is_package dari PHP bisa berupa bool true atau int 1 (TINYINT MySQL)
    final isPackage = cekData['is_package'] == true || cekData['is_package'] == 1;

    if (isPackage) {
      if (!mounted) return;
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => PackageDialog(
          sku: sku,
          packageData: cekData,
          onConfirm: (isianDipilih, addonDipilih, addonTotal, keterangan) {
            _doInsertPackage(
              sku: sku,
              isianDipilih: isianDipilih,
              addonDipilih: addonDipilih,
              addonTotal: addonTotal,
              keterangan: keterangan,
            );
          },
        ),
      );
    } else {
      await _doInsertProduk(sku);
    }
  }

  /// Insert produk biasa ke temp_invoice
  Future<void> _doInsertProduk(String sku) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'insertItem',
          'number': state.number,
          'sku': sku,
          'organisasi_id': state.organisasiID,
          'store_id': state.storeID,
          'member_id': state.memberID ?? 0,
          'voucher': _activeVoucher,
          'device_token': _deviceToken,
        }));

    if (res.data['success'] == true) {
      _checkVoucherValid(res.data);
      await _refreshFromApi();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data['message'] ?? 'Gagal menambahkan produk'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    _skuController.clear();
  }

  /// Insert produk package ke temp_invoice
  Future<void> _doInsertPackage({
    required String sku,
    required List<Map<String, dynamic>> isianDipilih,
    required List<Map<String, dynamic>> addonDipilih,
    required double addonTotal,
    String keterangan = '',
  }) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'insertPackage',
          'number': state.number,
          'sku': sku,
          'organisasi_id': state.organisasiID,
          'store_id': state.storeID,
          'member_id': state.memberID ?? 0,
          'voucher': _activeVoucher,
          'device_token': _deviceToken,
          'isian': jsonEncode(isianDipilih),
          'addon': jsonEncode(addonDipilih),
          'addon_harga': addonTotal,
          'keterangan': keterangan,
        }));

    if (res.data['success'] == true) {
      _checkVoucherValid(res.data);
      await _refreshFromApi();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content:
                Text(res.data['message'] ?? 'Gagal menambahkan produk package'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================
  // CEK VOUCHER VALID — auto-lepas jika tidak memenuhi syarat
  // ============================================================
  void _checkVoucherValid(Map<String, dynamic> responseData) {
    if (_activeVoucher.isNotEmpty && responseData['voucher_valid'] == false) {
      setState(() => _activeVoucher = '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Voucher dilepas — total belanja tidak memenuhi syarat'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ============================================================
  // REFRESH CART & SUMMARY
  // ============================================================
  Future<void> _refreshFromApi() async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final itemsRes = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'getItems',
          'number': state.number,
          'device_token': _deviceToken,
        }));

    final itemsData = List<Map<String, dynamic>>.from(itemsRes.data['data']);
    final items = itemsData.map((e) => CartItem.fromJson(e)).toList();

    final summaryRes = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'getSummary',
          'number': state.number,
          'store_id': state.storeID,
          'device_token': _deviceToken,
        }));

    final summary = summaryRes.data;
    ref.read(penjualanProvider.notifier).updateItems(items);
    ref.read(penjualanProvider.notifier).updateSummary(
          gross: (summary['gross'] as num).toDouble(),
          diskon: (summary['diskon'] as num).toDouble(),
          total: (summary['total'] as num).toDouble(),
          dpp: (summary['dpp'] as num).toDouble(),
          pajak: (summary['tax'] as num).toDouble(),
        );
  }

  // ============================================================
  // LOAD PRODUK DENGAN IMAGE untuk grid kiri — per kategori
  // ============================================================
  Future<void> _loadImageProducts() async {
    if (_isLoadingImages) return;
    setState(() => _isLoadingImages = true);
    try {
      final state = ref.read(penjualanProvider);
      final dio   = ApiService.getDio(token: _token);

      final rawRes = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action':       'getImageProducts',
          'organisasi_id': state.organisasiID,
        }),
        options: Options(responseType: ResponseType.plain),
      );

      final rawStr = rawRes.data?.toString() ?? '';

      final jsonStart = rawStr.indexOf('{');
      if (jsonStart < 0) {
        return;
      }
      final parsed = jsonDecode(rawStr.substring(jsonStart)) as Map;

      // Backend baru return list of { id, nama, produk: [...] }
      final rawData = parsed['data'];
      if (rawData is List) {
        final categories = rawData
            .map<Map<String, dynamic>>((cat) => {
                  'id': cat['id'] ?? 0,
                  'nama': cat['nama']?.toString() ?? '',
                  'produk': (cat['produk'] as List? ?? [])
                      .map<Map<String, dynamic>>((p) => {
                            'kode': p['kode']?.toString() ?? '',
                            'nama': p['nama']?.toString() ?? '',
                            'hpj': (p['hpj'] as num? ?? 0).toDouble(),
                            'image': p['image']?.toString() ?? '',
                            'is_package': p['is_package'] == true || p['is_package'] == 1,
                          })
                      .where((p) => p['image']!.isNotEmpty)
                      .toList(),
                })
            .where((cat) => (cat['produk'] as List).isNotEmpty)
            .toList();
        if (mounted) setState(() => _imageCategories = categories);
      }
    } catch (e) {
    } finally {
      if (mounted) setState(() => _isLoadingImages = false);
    }
  }

  void _showProductPicker(List<Map<String, dynamic>> products) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView.builder(
        itemCount: products.length,
        itemBuilder: (_, i) {
          final p = products[i];
          return ListTile(
            title: Text(p['nama']),
            subtitle: Text(p['kode']),
            trailing: Text('Rp ${CurrencyFormat.format(p['hpj'])}'),
            onTap: () {
              Navigator.pop(context);
              _insertProduk(p['kode'] as String);
            },
          );
        },
      ),
    );
  }

  // ============================================================
  // REMOVE & UPDATE QTY
  // ============================================================
  Future<void> _removeItem(int index) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);
    final item = state.items[index];

    await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'deleteItem',
          'number': state.number,
          'sku': item.kode,
          'packages_notes': item.packagesNotes ?? '',
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'voucher': _activeVoucher,
          'device_token': _deviceToken,
        }));

    await _refreshFromApi();
  }

  Future<void> _updateQty(int index, int qty) async {
    if (qty <= 0) {
      await _removeItem(index);
      return;
    }
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);
    final item = state.items[index];

    await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'updateQty',
          'number': state.number,
          'sku': item.kode,
          'qty': qty,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'voucher': _activeVoucher,
          'device_token': _deviceToken,
        }));

    await _refreshFromApi();
  }

  Future<void> _updateItemKeterangan(int index, String keterangan) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);
    final item = state.items[index];

    await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'updateItemKeterangan',
          'number': state.number,
          'sku': item.kode,
          'packages_notes': item.packagesNotes ?? '',
          'keterangan': keterangan,
          'device_token': _deviceToken,
        }));

    // Dispose controller lama agar re-init dengan teks terbaru setelah refresh
    _itemNotesControllers[index]?.dispose();
    _itemNotesControllers.remove(index);

    // Refresh state agar keterangan tampil di bawah item
    await _refreshFromApi();
  }

  // ============================================================
  // MEMBER — Add Member Baru (bottom sheet)
  // ============================================================
  void _showAddMemberSheet() {
    final state = ref.read(penjualanProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddMemberSheet(
        token: _token,
        organisasiID: state.organisasiID,
        onSuccess: (memberID, display, nama) async {
          // Set member ke state + field
          _memberController.text = display;
          ref.read(penjualanProvider.notifier).setMember(memberID, nama);

          // Recalculate diskon dengan member baru
          final dio = ApiService.getDio(token: _token);
          await dio.post('/penjualan.php',
              data: FormData.fromMap({
                'action': 'recalculate',
                'number': state.number,
                'store_id': state.storeID,
                'organisasi_id': state.organisasiID,
                'member_id': memberID,
                'voucher': _activeVoucher,
                'device_token': _deviceToken,
              }));

          await _refreshFromApi();

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Member "$nama" berhasil ditambahkan'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
  }

  // ============================================================
  // VOUCHER
  // ============================================================
  void _showVoucherDialog() {
    final voucherController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Input Voucher'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_activeVoucher.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text('Aktif: $_activeVoucher',
                        style: const TextStyle(color: Colors.indigo)),
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _removeVoucher();
                      },
                      child:
                          const Icon(Icons.close, size: 18, color: Colors.red),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: voucherController,
              decoration: const InputDecoration(
                labelText: 'Kode Voucher',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final kode = voucherController.text.trim();
              if (kode.isEmpty) return;
              Navigator.pop(context);
              await _applyVoucher(kode);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyVoucher(String kode) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'cekVoucher',
          'number': state.number,
          'voucher': kode,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'device_token': _deviceToken,
        }));

    if (res.data['success'] == true) {
      setState(() => _activeVoucher = kode);
      await _refreshFromApi();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Voucher $kode berhasil diapply'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data['message'] ?? 'Voucher tidak valid'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _removeVoucher() async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'resetDiskon',
          'number': state.number,
          'device_token': _deviceToken,
        }));

    await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'recalculate',
          'number': state.number,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'voucher': '',
          'device_token': _deviceToken,
        }));

    setState(() => _activeVoucher = '');
    await _refreshFromApi();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voucher dilepas')),
      );
    }
  }

  // ============================================================
  // RETUR
  // ============================================================
  void _showReturDialog() {
    final returController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Retur Penjualan'),
        content: TextField(
          controller: returController,
          decoration: const InputDecoration(
            labelText: 'No. Transaksi Asal',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () async {
              final nomor = returController.text.trim();
              if (nomor.isEmpty) return;
              Navigator.pop(context);
              await _prosesRetur(nomor);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('RETUR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _prosesRetur(String returNumber) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final cekRes = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'cekRetur',
          'retur_number': returNumber,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
        }));

    if (cekRes.data['success'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cekRes.data['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final loadRes = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'loadRetur',
          'retur_number': returNumber,
          'number': state.number,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'device_token': _deviceToken,
        }));

    if (loadRes.data['success'] == true) {
      ref.read(penjualanProvider.notifier).setReturSource(returNumber);
      await _refreshFromApi();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Mode retur aktif — $returNumber'),
            backgroundColor: Colors.orange,
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal load item retur'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================
  // PROSES BAYAR
  // ============================================================
  Future<void> _prosesBayar() async {
    final state = ref.read(penjualanProvider);

    if (state.items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Belum ada produk')));
      return;
    }
    if (state.caraBayarID == 0) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Pilih cara bayar dulu')));
      return;
    }
    if (state.nominalBayar < state.total) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Nominal bayar kurang dari total')));
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Konfirmasi Pembayaran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Total'),
              Text('Rp ${CurrencyFormat.format(state.total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold)),
            ]),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Bayar'),
              Text('Rp ${CurrencyFormat.format(state.nominalBayar)}'),
            ]),
            const Divider(),
            Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
              const Text('Kembalian',
                  style: TextStyle(fontWeight: FontWeight.bold)),
              Text(
                'Rp ${CurrencyFormat.format(state.nominalBayar - state.total)}',
                style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF1D273B)),
              ),
            ]),
          ],
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D273B)),
            child: const Text('Proses', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final session = await SessionService.getSession();
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'prosesBayar',
          'number': state.number,
          'cara_bayar_id': state.caraBayarID,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'user_id': session['user_id'],
          'sales_tipe_id': state.salesTipeID,
          'member_id': state.memberID ?? 0,
          'voucher': _activeVoucher,
          'retur_source': ref.read(penjualanProvider).returSource,
          'nominal_bayar': state.nominalBayar,
          'device_token': _deviceToken,
          'keterangan': _keteranganController.text.trim(),
        }));

    if (mounted) Navigator.pop(context); // tutup loading

    if (res.data['success'] == true) {
      final kembalian = res.data['kembalian'];

      _kirimWADanEmail(
        invoiceNumber: state.number,
        storeID: state.storeID,
        organisasiID: state.organisasiID,
        memberID: state.memberID,
      );

      if (mounted) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            title: const Text('Transaksi Berhasil!'),
            content: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(Icons.check_circle, color: Colors.green, size: 64),
                const SizedBox(height: 16),
                Text(
                  'Kembalian: Rp ${CurrencyFormat.format(kembalian)}',
                  style: const TextStyle(
                      fontSize: 20, fontWeight: FontWeight.bold),
                ),
              ],
            ),
            actions: [
              // ── Tombol Print — adaptif FnB vs non-FnB ───────
              if (_isFnb)
                // FnB: satu tombol → buka bottom sheet pilih
                // Customer / Kitchen / Keduanya
                TextButton.icon(
                  onPressed: () async {
                    final caraBayar = _caraBayarList.firstWhere(
                          (c) =>
                              int.parse(c['dim_carabayar_id'].toString()) ==
                              state.caraBayarID,
                          orElse: () => {'nama': ''},
                        )['nama'] as String? ??
                        '';
                    Navigator.pop(context); // tutup dialog sukses dulu
                    await _showPrintSheet(
                      invoiceNumber: state.number,
                      kembalian: (kembalian as num).toDouble(),
                      caraBayar: caraBayar,
                      currentState: state,
                    );
                    _resetTransaksi();
                  },
                  icon: const Icon(Icons.print, size: 18),
                  label: const Text('Print'),
                )
              else
                // Non-FnB (retail): langsung print customer copy
                TextButton.icon(
                  onPressed: () async {
                    final caraBayar = _caraBayarList.firstWhere(
                          (c) =>
                              int.parse(c['dim_carabayar_id'].toString()) ==
                              state.caraBayarID,
                          orElse: () => {'nama': ''},
                        )['nama'] as String? ??
                        '';
                    await _handlePrint(
                      invoiceNumber: state.number,
                      kembalian: (kembalian as num).toDouble(),
                      caraBayar: caraBayar,
                      currentState: state,
                      isKitchenMode: false,
                    );
                    if (mounted) {
                      Navigator.pop(context);
                      _resetTransaksi();
                    }
                  },
                  icon: const Icon(Icons.receipt_long, size: 18),
                  label: const Text('Print'),
                ),
              ElevatedButton(
                onPressed: () {
                  Navigator.pop(context);
                  _resetTransaksi();
                },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D273B)),
                child: const Text('Selesai',
                    style: TextStyle(color: Colors.white)),
              ),
            ],
          ),
        );
      }
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.data['message'] ?? 'Transaksi gagal')),
        );
      }
    }
  }

  Future<void> _kirimWADanEmail({
    required String invoiceNumber,
    required int storeID,
    required int organisasiID,
    required int? memberID,
  }) async {
    if (memberID == null || memberID == 0) return;
    final dio = ApiService.getDio(token: _token);

    dio
        .post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'kirimWA',
              'number': invoiceNumber,
              'store_id': storeID,
              'organisasi_id': organisasiID,
              'member_id': memberID,
            }))
        .then((_) {}).catchError((_) {});

    dio
        .post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'kirimEmail',
              'number': invoiceNumber,
              'store_id': storeID,
              'organisasi_id': organisasiID,
              'member_id': memberID,
            }))
        .then((_) {}).catchError((_) {});
  }

  Future<void> _resetTransaksi() async {
    final dio = ApiService.getDio(token: _token);
    final currentState = ref.read(penjualanProvider);
    final storeID = currentState.storeID;
    final storeName = currentState.storeName;
    final organisasiID = currentState.organisasiID;

    final numberRes = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'getNumber',
          'store_id': storeID,
          'organisasi_id': organisasiID,
          'device_token': _deviceToken,
        }));
    final newNumber = numberRes.data['number'];

    ref.read(penjualanProvider.notifier).reset();
    ref.read(penjualanProvider.notifier).setInitialData(
          number: newNumber,
          storeID: storeID,
          storeName: storeName,
          organisasiID: organisasiID,
          salesTipeID:
              int.parse(_channels.first['dim_salestipe_id'].toString()),
        );

    setState(() => _activeVoucher = '');
    ref.read(penjualanProvider.notifier).setReturSource('');
    _memberController.clear();
    _nominalController.clear();
    _skuController.clear();
    _keteranganController.clear();
    // Reset item notes
    for (final c in _itemNotesControllers.values) {
      c.dispose();
    }
    _itemNotesControllers.clear();
    _expandedNotes.clear();
  }

  // ============================================================
  // PRINT
  // ============================================================
  //
  // _handlePrint — entry point tunggal untuk semua print.
  //
  // [isKitchenMode] = true  → print 2x (customer + kitchen), untuk FnB.
  //                  false → print 1x (customer only), untuk retail.
  //
  // Dipanggil dari:
  //   • Dialog sukses bayar — tombol "Print" (retail) atau "Print (2x)" (FnB)
  //   • Tombol "Print Kitchen" di dialog sukses bayar
  //   • Invoice list screen (reprint)
  Future<void> _handlePrint({
    required String invoiceNumber,
    required double kembalian,
    required String caraBayar,
    required PenjualanState currentState,
    bool isKitchenMode = false,
  }) async {
    try {
      // ── Pastikan printer terhubung ───────────────────────────
      final connected = await PrinterHelper.isConnected();
      if (!connected) {
        final prefs = await SharedPreferences.getInstance();
        final savedMac = prefs.getString('printer_mac');
        if (savedMac == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Belum ada printer terhubung. Buka pengaturan printer.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        await PrinterHelper.connect(savedMac);
      }

      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);

      // ── Ambil data store ─────────────────────────────────────
      final storeRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getStoreData',
            'store_id': state.storeID,
          }));

      final storeName = storeRes.data['nama'] ?? '';
      final storeAddress = storeRes.data['alamat'] ?? '';
      final storeNpwp = storeRes.data['npwp'] ?? '';
      final invoiceNote = storeRes.data['invoice_note'] ?? '';
      final storeTax = (storeRes.data['tax'] as num? ?? 0).toDouble();
      // isFnb: dibaca dari state yang sudah di-set saat load awal
      // (jasa_perusahaan == 3 di dim_organisasi → FnB/resto)
      final isFnb = _isFnb;

      // ── Siapkan items ────────────────────────────────────────
      final items = currentState.items
          .map((item) => {
                'nama': item.nama,
                'qty': item.qty,
                'hpj': item.hpj,
                'subtotal': item.subtotal,
                'diskon_persen': item.diskonPersen,
                'diskon_nominal': item.diskonNominal,
                'packages_notes': item.packagesNotes ?? '',
              })
          .toList();

      // ── Ambil nama channel ───────────────────────────────────
      final salesTipeNama = _channels
              .firstWhere(
                (c) =>
                    int.parse(c['dim_salestipe_id'].toString()) ==
                    currentState.salesTipeID,
                orElse: () => {'nama': ''},
              )['nama']
              ?.toString() ??
          '';

      final kasirNama =
          (await SessionService.getSession())['nama'] as String? ?? '';
      final tanggal = DateTime.now().toString().substring(0, 16);

      // ── Print berdasarkan mode ───────────────────────────────
      if (isFnb || isKitchenMode) {
        // FnB: print customer struk + kitchen order sekaligus
        final result = await PrinterHelper.printBoth(
          storeName: storeName,
          storeAddress: storeAddress,
          invoiceNumber: invoiceNumber,
          tanggal: tanggal,
          kasir: kasirNama,
          memberNama: currentState.memberNama,
          items: items,
          gross: currentState.gross,
          diskon: currentState.diskon,
          total: currentState.total,
          dpp: currentState.dpp,
          pajak: currentState.pajak,
          caraBayar: caraBayar,
          nominalBayar: currentState.nominalBayar,
          kembalian: kembalian,
          storeTax: storeTax,
          voucherKode: _activeVoucher.isNotEmpty ? _activeVoucher : null,
          npwp: storeNpwp,
          invoiceNote: invoiceNote,
          salesTipe: salesTipeNama.isNotEmpty ? salesTipeNama : null,
        );

        if (mounted) {
          if (result.customer && result.kitchen) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Print berhasil! (Customer + Kitchen)'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (result.customer && !result.kitchen) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Struk customer OK, kitchen print gagal. Coba ulangi.'),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Print gagal'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // Retail: print customer struk saja
        await PrinterHelper.printInvoice(
          storeName: storeName,
          storeAddress: storeAddress,
          npwp: storeNpwp,
          invoiceNote: invoiceNote,
          invoiceNumber: invoiceNumber,
          tanggal: tanggal,
          kasir: kasirNama,
          memberNama: currentState.memberNama,
          items: items,
          gross: currentState.gross,
          diskon: currentState.diskon,
          total: currentState.total,
          dpp: currentState.dpp,
          pajak: currentState.pajak,
          caraBayar: caraBayar,
          nominalBayar: currentState.nominalBayar,
          kembalian: kembalian,
          voucherKode: _activeVoucher.isNotEmpty ? _activeVoucher : null,
          storeTax: storeTax,
          salesTipe: salesTipeNama.isNotEmpty ? salesTipeNama : null,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Print berhasil!'),
                backgroundColor: Colors.green),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal print: $e')));
      }
    }
  }

  // ── Legacy alias — dipakai oleh invoice_list_screen reprint ──
  Future<void> _printInvoice({
    required String invoiceNumber,
    required double kembalian,
    required String caraBayar,
    required PenjualanState currentState,
  }) =>
      _handlePrint(
        invoiceNumber: invoiceNumber,
        kembalian: kembalian,
        caraBayar: caraBayar,
        currentState: currentState,
      );

  // ============================================================
  // PRINT SHEET (FnB) — bottom sheet pilih Customer/Kitchen/Keduanya
  // Dipanggil dari dialog sukses bayar ketika _isFnb == true.
  // Konsisten dengan _showReprintSheet di invoice_list_screen.
  // ============================================================
  Future<void> _showPrintSheet({
    required String invoiceNumber,
    required double kembalian,
    required String caraBayar,
    required PenjualanState currentState,
  }) async {
    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Handle bar
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                child: Text(
                  'Pilih Print — $invoiceNumber',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              const Divider(),
              // Customer copy
              ListTile(
                leading:
                    const Icon(Icons.receipt_long, color: Color(0xFF1D273B)),
                title: const Text('Customer Copy'),
                subtitle: const Text('Struk untuk pelanggan'),
                onTap: () {
                  Navigator.pop(ctx);
                  _handlePrint(
                    invoiceNumber: invoiceNumber,
                    kembalian: kembalian,
                    caraBayar: caraBayar,
                    currentState: currentState,
                    isKitchenMode: false,
                  );
                },
              ),
              // Kitchen copy
              ListTile(
                leading: const Icon(Icons.kitchen, color: Colors.orange),
                title: const Text('Kitchen Copy'),
                subtitle: const Text('Struk untuk dapur'),
                onTap: () {
                  Navigator.pop(ctx);
                  // isKitchenMode=true tapi kita hanya mau kitchen saja.
                  // _handlePrint dengan isKitchenMode=true + isFnb=true
                  // akan masuk ke PrinterHelper.printBoth.
                  // Untuk print kitchen-only kita panggil helper langsung.
                  _printKitchenOnly(
                    invoiceNumber: invoiceNumber,
                    currentState: currentState,
                  );
                },
              ),
              // Keduanya
              ListTile(
                leading: const Icon(Icons.print_rounded, color: Colors.green),
                title: const Text('Customer + Kitchen'),
                subtitle: const Text('Print dua-duanya'),
                onTap: () {
                  Navigator.pop(ctx);
                  _handlePrint(
                    invoiceNumber: invoiceNumber,
                    kembalian: kembalian,
                    caraBayar: caraBayar,
                    currentState: currentState,
                    isKitchenMode: true,
                  );
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Print kitchen-only setelah bayar (tanpa struk customer) ──
  Future<void> _printKitchenOnly({
    required String invoiceNumber,
    required PenjualanState currentState,
  }) async {
    try {
      final connected = await PrinterHelper.isConnected();
      if (!connected) {
        final prefs = await SharedPreferences.getInstance();
        final savedMac = prefs.getString('printer_mac');
        if (savedMac == null) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                    'Belum ada printer terhubung. Buka pengaturan printer.'),
                backgroundColor: Colors.orange,
              ),
            );
          }
          return;
        }
        await PrinterHelper.connect(savedMac);
      }

      final dio = ApiService.getDio(token: _token);
      final storeRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getStoreData',
            'store_id': currentState.storeID,
          }));
      final storeName = storeRes.data['nama'] ?? '';

      final items = currentState.items
          .map((item) => {
                'nama': item.nama,
                'qty': item.qty,
                'hpj': item.hpj,
                'subtotal': item.subtotal,
                'diskon_persen': item.diskonPersen,
                'diskon_nominal': item.diskonNominal,
                'packages_notes': item.packagesNotes ?? '',
              })
          .toList();

      final kasirNama =
          (await SessionService.getSession())['nama'] as String? ?? '';
      final tanggal = DateTime.now().toString().substring(0, 16);

      await PrinterHelper.printKitchen(
        storeName: storeName,
        invoiceNumber: invoiceNumber,
        tanggal: tanggal,
        kasir: kasirNama,
        items: items,
        total: currentState.total,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Print Kitchen berhasil!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Gagal print kitchen: $e')));
      }
    }
  }

  // ============================================================
  // PENDING PAYMENT
  // ============================================================
  Future<void> _showPendingDialog() async {
    final state = ref.read(penjualanProvider);

    if (state.items.isEmpty) {
      ScaffoldMessenger.of(context)
          .showSnackBar(const SnackBar(content: Text('Belum ada produk')));
      return;
    }
    if (state.memberID == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Member harus diisi untuk pending payment')),
      );
      return;
    }

    final labelController = TextEditingController();
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hold Order'),
        content: TextField(
          controller: labelController,
          decoration: const InputDecoration(
            labelText: 'Label / No. Meja (opsional)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Batal')),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final session = await SessionService.getSession();
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'simpanPending',
          'number': state.number,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'user_id': session['user_id'],
          'label': labelController.text.trim(),
          'device_token': _deviceToken,
        }));

    if (res.data['success'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order disimpan sebagai pending'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      await _resetTransaksi();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(res.data['message'] ?? 'Gagal simpan pending')),
        );
      }
    }
  }

  // ============================================================
  // RETRIEVE ORDER
  // ============================================================
  Future<void> _showRetrieveDialog() async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'getPendingOrders',
          'store_id': state.storeID,
        }));

    final orders = List<Map<String, dynamic>>.from(res.data['data']);
    if (orders.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada pending order')),
        );
      }
      return;
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1D273B),
              width: double.infinity,
              child: const Text('Pending Orders',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: orders.length,
                itemBuilder: (_, i) {
                  final order = orders[i];
                  return Card(
                    margin:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    child: ListTile(
                      leading: const Icon(Icons.receipt_long,
                          color: Color(0xFF1D273B)),
                      title: Text(
                        order['label']?.isNotEmpty == true
                            ? order['label']
                            : order['kode'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                          '${order['member']} • ${order['created_date'].toString().substring(0, 16)}'),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          IconButton(
                            icon: const Icon(Icons.play_circle,
                                color: Colors.green),
                            onPressed: () async {
                              Navigator.pop(context);
                              await _retrievePending(
                                int.parse(order['id'].toString()),
                                order['member'],
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final del = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Hapus Order?'),
                                  content: Text(
                                      'Order ${order['label'] ?? order['kode']} akan dihapus.'),
                                  actions: [
                                    TextButton(
                                        onPressed: () =>
                                            Navigator.pop(context, false),
                                        child: const Text('Batal')),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      style: ElevatedButton.styleFrom(
                                          backgroundColor: Colors.red),
                                      child: const Text('Hapus',
                                          style:
                                              TextStyle(color: Colors.white)),
                                    ),
                                  ],
                                ),
                              );
                              if (del == true) {
                                await _deletePending(
                                    int.parse(order['id'].toString()));
                                if (mounted) Navigator.pop(context);
                                await _showRetrieveDialog();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retrievePending(int salesOrderID, String member) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'retrievePending',
          'sales_order_id': salesOrderID,
          'number': state.number,
          'device_token': _deviceToken,
        }));

    if (res.data['success'] == true) {
      _memberController.text = res.data['member'];
      ref.read(penjualanProvider.notifier).setMember(
            int.parse(res.data['member_id'].toString()),
            member,
          );
      await _refreshFromApi();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order berhasil di-retrieve'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  Future<void> _deletePending(int salesOrderID) async {
    final dio = ApiService.getDio(token: _token);
    await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'deletePending',
          'sales_order_id': salesOrderID,
        }));
  }

  // ============================================================
  // RESPONSIVE HELPERS
  // ============================================================
  // Breakpoint berdasarkan lebar layar (dp):
  //   ≥ 800  → tablet 8"+ landscape   → layout normal
  //   720–799 → tablet 8" portrait / 7.5"
  //   600–719 → tablet 7" landscape
  //   < 600  → tablet 7" portrait     → stacked layout
  double get _screenWidth => MediaQuery.of(context).size.width;
  bool get _isSmallTablet => _screenWidth < 800;
  bool get _isTinyTablet  => _screenWidth < 600;

  /// Lebar kolom kanan (cart + summary)
  double get _rightPanelWidth {
    if (_isTinyTablet) return _screenWidth * 0.46;
    if (_isSmallTablet) return _screenWidth * 0.42;
    return _screenWidth * 0.38;
  }

  /// Padding umum untuk container (header, summary)
  EdgeInsets get _panelPadding =>
      EdgeInsets.all(_isTinyTablet ? 8 : _isSmallTablet ? 10 : 12);

  /// Font size label utama (Total, store name, dsb.)
  double get _labelFontSize => _isTinyTablet ? 13 : _isSmallTablet ? 14 : 16;

  /// Tinggi tombol aksi (BAYAR, PENDING)
  double get _buttonHeight => _isTinyTablet ? 40 : _isSmallTablet ? 44 : 48;

  /// Jumlah kolom pada grid gambar produk
  int get _gridColumns {
    if (_isTinyTablet) return 2;
    if (_isSmallTablet) return 3;
    return 4;
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final state = ref.watch(penjualanProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D273B),
        title: const Text('POS Aibipi',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.receipt, color: Colors.white),
            tooltip: 'Invoice List',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InvoiceListScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white),
            tooltip: 'Retrieve Order',
            onPressed: _showRetrieveDialog,
          ),
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrinterScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.lock_clock, color: Colors.orange),
            tooltip: 'Tutup Shift',
            onPressed: _tutupShift,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: _isTinyTablet
          // ── LAYOUT STACKED (tablet 7" portrait < 600dp) ───────────
          ? Column(
              children: [
                _buildHeader(state),
                Expanded(
                  child: _buildImageGrid(),
                ),
                Container(height: 1, color: Colors.grey.shade300),
                SizedBox(
                  height: MediaQuery.of(context).size.height * 0.44,
                  child: Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _checkShiftStillActive,
                          color: const Color(0xFF1D273B),
                          child: _buildCart(state),
                        ),
                      ),
                      Container(height: 1, color: Colors.grey.shade300),
                      _buildSummaryScrollable(state),
                    ],
                  ),
                ),
              ],
            )
          // ── LAYOUT SIDE-BY-SIDE (tablet 7" landscape ke atas) ────
          : Row(
              children: [
                // ── KOLOM KIRI — identitas + product image grid ──
                Expanded(
                  child: Column(
                    children: [
                      _buildHeader(state),
                      Expanded(
                        child: _buildImageGrid(),
                      ),
                    ],
                  ),
                ),
                Container(width: 1, color: Colors.grey.shade300),
                // ── KOLOM KANAN — cart list + summary ────────────
                SizedBox(
                  width: _rightPanelWidth,
                  child: Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _checkShiftStillActive,
                          color: const Color(0xFF1D273B),
                          child: _buildCart(state),
                        ),
                      ),
                      Container(height: 1, color: Colors.grey.shade300),
                      _buildSummaryScrollable(state),
                    ],
                  ),
                ),
              ],
            ),
    );
  }

  // ============================================================
  // HEADER (store info, channel, member, sku search)
  // ============================================================
  Widget _buildHeader(PenjualanState state) {
    return Container(
      color: Colors.white,
      padding: _panelPadding,
      child: Column(
        children: [
          // Row 1: Store + Invoice
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text('Store',
                        style: TextStyle(fontSize: 11, color: Colors.grey)),
                    Text(state.storeName,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text('No. Invoice',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(state.number,
                      style: const TextStyle(fontWeight: FontWeight.bold)),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Channel
          DropdownButtonFormField<int>(
            initialValue: state.salesTipeID,
            decoration: const InputDecoration(
              labelText: 'Channel',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            items: _channels.map((c) {
              return DropdownMenuItem<int>(
                value: int.parse(c['dim_salestipe_id'].toString()),
                child: Text(c['nama']),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                ref.read(penjualanProvider.notifier).setSalesTipe(val);
              }
            },
          ),
          const SizedBox(height: 8),

          // Row 3: Member (search + add baru) + Voucher + Retur
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberController,
                  decoration: InputDecoration(
                    labelText: 'Member (opsional)',
                    border: const OutlineInputBorder(),
                    contentPadding:
                        const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    isDense: true,
                    // ── Ikon di kiri: add member / clear ──────────
                    prefixIcon: state.memberID != null
                        ? IconButton(
                            icon: const Icon(Icons.close,
                                size: 18, color: Colors.red),
                            tooltip: 'Hapus member',
                            onPressed: () {
                              _memberController.clear();
                              ref
                                  .read(penjualanProvider.notifier)
                                  .setMember(null, '');
                            },
                          )
                        : IconButton(
                            icon: const Icon(Icons.person_add,
                                size: 18, color: Color(0xFF1D273B)),
                            tooltip: 'Tambah member baru',
                            onPressed: _showAddMemberSheet,
                          ),
                    // ── Ikon search di kanan ─────────────────────
                    suffixIcon: const Icon(Icons.search, size: 18),
                  ),
                  onSubmitted: (val) async {
                    if (val.isEmpty) return;
                    final dio = ApiService.getDio(token: _token);
                    final res = await dio.post('/penjualan.php',
                        data: FormData.fromMap({
                          'action': 'searchMember',
                          'term': val,
                          'organisasi_id': state.organisasiID,
                        }));
                    final data =
                        List<Map<String, dynamic>>.from(res.data['data']);
                    if (data.isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Member tidak ditemukan')),
                        );
                      }
                      return;
                    }
                    if (mounted) {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => ListView.builder(
                          itemCount: data.length,
                          itemBuilder: (_, i) {
                            final m = data[i];
                            return ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(m['nama']),
                              subtitle: Text(m['telp']),
                              onTap: () {
                                Navigator.pop(context);
                                _memberController.text =
                                    '${m['nama']} - ${m['telp']}';
                                ref.read(penjualanProvider.notifier).setMember(
                                      int.parse(m['dim_bp_id'].toString()),
                                      m['nama'],
                                    );
                              },
                            );
                          },
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Voucher badge jika aktif
              Stack(
                children: [
                  OutlinedButton.icon(
                    onPressed: _showVoucherDialog,
                    icon: const Icon(Icons.confirmation_number_outlined,
                        size: 18),
                    label: const Text('Voucher'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 12, vertical: 12),
                      foregroundColor:
                          _activeVoucher.isNotEmpty ? Colors.indigo : null,
                      side: _activeVoucher.isNotEmpty
                          ? const BorderSide(color: Colors.indigo)
                          : null,
                    ),
                  ),
                  if (_activeVoucher.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.indigo,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showReturDialog,
                icon: const Icon(Icons.assignment_return_outlined, size: 18),
                label: const Text('Retur'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 3.5: Keterangan Transaksi
          TextField(
            controller: _keteranganController,
            decoration: const InputDecoration(
              labelText: 'Keterangan transaksi (opsional)',
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
              prefixIcon: Icon(Icons.notes_outlined, size: 18),
            ),
            maxLines: 1,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 8),

          // Row 4: SKU Search
          TextField(
            controller: _skuController,
            decoration: InputDecoration(
              labelText: 'Cari produk (nama / SKU)',
              border: const OutlineInputBorder(),
              contentPadding:
                  const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _searchProduk(_skuController.text.trim()),
              ),
            ),
            onSubmitted: (val) => _searchProduk(val.trim()),
          ),
        ],
      ),
    );
  }

  // ============================================================
  // PRODUCT IMAGE GRID (kiri bawah)
  // ============================================================
  Widget _buildImageGrid() {
    if (_isLoadingImages) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_imageCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 48, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Tidak ada produk dengan gambar',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    // Selalu pakai DefaultTabController agar tab kategori selalu muncul
    return DefaultTabController(
      length: _imageCategories.length,
      child: Column(
        children: [
          // Tab bar kategori
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF1D273B),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF1D273B),
              labelStyle: TextStyle(
                fontSize: _isTinyTablet ? 11 : 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: _isTinyTablet ? 11 : 13,
              ),
              tabs: _imageCategories
                  .map((cat) => Tab(text: cat['nama']?.toString() ?? ''))
                  .toList(),
            ),
          ),
          // Grid produk per tab
          Expanded(
            child: TabBarView(
              children: _imageCategories.map((cat) {
                final produk = cat['produk'] as List<Map<String, dynamic>>;
                return _buildProductGrid(produk);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Grid produk gambar (dipakai oleh _buildImageGrid)
  Widget _buildProductGrid(List<Map<String, dynamic>> products) {
    return GridView.builder(
      padding: EdgeInsets.all(_isTinyTablet ? 6 : 10),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridColumns,
        mainAxisSpacing: _isTinyTablet ? 6 : 10,
        crossAxisSpacing: _isTinyTablet ? 6 : 10,
        childAspectRatio: 0.72,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final p = products[i];
        final imageUrl = p['image']?.toString() ?? '';
        final nama = p['nama']?.toString() ?? '';
        final kode = p['kode']?.toString() ?? '';
        final hpj = (p['hpj'] as num? ?? 0).toDouble();

        return GestureDetector(
          onTap: () => _insertProduk(kode),
          child: Card(
            elevation: 2,
            clipBehavior: Clip.antiAlias,
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Expanded(
                  child: Image.network(
                    imageUrl,
                    fit: BoxFit.cover,
                    errorBuilder: (_, __, ___) => Container(
                      color: Colors.grey.shade200,
                      child: const Icon(Icons.broken_image,
                          color: Colors.grey, size: 32),
                    ),
                    loadingBuilder: (_, child, progress) {
                      if (progress == null) return child;
                      return Container(
                        color: Colors.grey.shade100,
                        child: const Center(
                            child: CircularProgressIndicator(strokeWidth: 2)),
                      );
                    },
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 6, vertical: 5),
                  color: Colors.white,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        nama,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        'Rp ${CurrencyFormat.format(hpj)}',
                        style: const TextStyle(
                            fontSize: 11,
                            color: Color(0xFF1D273B),
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // CART LIST
  // ============================================================
  Widget _buildCart(PenjualanState state) {
    if (state.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(
            child:
                Text('Belum ada produk', style: TextStyle(color: Colors.grey)),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: state.items.length,
      itemBuilder: (_, i) {
        final item = state.items[i];
        // Tampilkan badge "Package" jika ada packagesNotes
        final isPackage =
            item.packagesNotes != null && item.packagesNotes!.isNotEmpty;

        // Inisialisasi controller notes jika belum ada
        if (!_itemNotesControllers.containsKey(i)) {
          _itemNotesControllers[i] = TextEditingController(
            text: item.keterangan ?? '',
          );
        }
        final notesCtrl = _itemNotesControllers[i]!;
        final isExpanded = _expandedNotes.contains(i);
        final hasNotes = (item.keterangan ?? '').isNotEmpty;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(item.nama,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.bold)),
                              ),
                              if (isPackage)
                                Container(
                                  margin: const EdgeInsets.only(left: 4),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 6, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(color: Colors.blue.shade200),
                                  ),
                                  child: const Text('Package',
                                      style: TextStyle(
                                          fontSize: 10, color: Colors.blue)),
                                ),
                            ],
                          ),
                          Text(item.kode,
                              style: const TextStyle(
                                  fontSize: 12, color: Colors.grey)),
                          Text('Rp ${CurrencyFormat.format(item.hpj)}',
                              style: const TextStyle(fontSize: 12)),
                        ],
                      ),
                    ),
                    // Qty control
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _updateQty(i, item.qty - 1),
                        ),
                        Text('${item.qty}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _updateQty(i, item.qty + 1),
                        ),
                      ],
                    ),
                    // Subtotal + delete + notes toggle
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text('Rp ${CurrencyFormat.format(item.subtotal)}',
                            style: const TextStyle(fontWeight: FontWeight.bold)),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Ikon notes — kuning jika sudah ada notes
                            IconButton(
                              icon: Icon(
                                hasNotes
                                    ? Icons.edit_note
                                    : Icons.add_comment_outlined,
                                size: 20,
                                color: hasNotes
                                    ? Colors.amber.shade700
                                    : Colors.grey,
                              ),
                              tooltip: 'Catatan item',
                              onPressed: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedNotes.remove(i);
                                  } else {
                                    _expandedNotes.add(i);
                                  }
                                });
                              },
                            ),
                            IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red, size: 20),
                              onPressed: () => _removeItem(i),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                // Inline notes input — tampil jika expanded
                if (isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: TextField(
                      controller: notesCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Catatan untuk item ini...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                            horizontal: 10, vertical: 6),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(Icons.check, size: 18,
                              color: Color(0xFF1D273B)),
                          onPressed: () async {
                            final ket = notesCtrl.text.trim();
                            await _updateItemKeterangan(i, ket);
                            setState(() => _expandedNotes.remove(i));
                          },
                        ),
                      ),
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (val) async {
                        await _updateItemKeterangan(i, val.trim());
                        setState(() => _expandedNotes.remove(i));
                      },
                    ),
                  )
                // Tampilkan notes yang sudah tersimpan (collapsed)
                else if (hasNotes)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 2),
                    child: Row(
                      children: [
                        Icon(Icons.notes, size: 13,
                            color: Colors.amber.shade700),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.keterangan ?? '',
                            style: TextStyle(
                                fontSize: 11,
                                color: Colors.amber.shade800,
                                fontStyle: FontStyle.italic),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // SUMMARY SCROLLABLE WRAPPER
  // Membungkus _buildSummary agar tidak ketimpa virtual keyboard.
  // Ketika keyboard muncul, summary otomatis bisa di-scroll ke atas
  // sehingga field Nominal Bayar & tombol BAYAR tetap terlihat.
  // ============================================================
  Widget _buildSummaryScrollable(PenjualanState state) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    return ConstrainedBox(
      // Batasi tinggi maksimum agar tidak overflow saat keyboard tutup,
      // tapi tetap bisa tumbuh saat keyboard terbuka.
      constraints: BoxConstraints(
        maxHeight: MediaQuery.of(context).size.height * 0.55,
      ),
      child: SingleChildScrollView(
        // Padding bawah = tinggi keyboard sehingga konten tidak tertutup
        padding: EdgeInsets.only(bottom: keyboardHeight),
        // Scroll ke bawah otomatis saat keyboard muncul
        reverse: false,
        child: _buildSummary(state),
      ),
    );
  }

  // ============================================================
  // SUMMARY PANEL (kanan)
  // ============================================================
  Widget _buildSummary(PenjualanState state) {
    return Container(
      color: Colors.white,
      padding: _panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Total Pembelian',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: _labelFontSize)),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Gross'),
            Text('Rp ${CurrencyFormat.format(state.gross)}'),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Diskon'),
            Text('Rp ${CurrencyFormat.format(state.diskon)}'),
          ]),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            Text('TOTAL',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: _labelFontSize)),
            Text('Rp ${CurrencyFormat.format(state.total)}',
                style:
                    TextStyle(fontWeight: FontWeight.bold, fontSize: _labelFontSize)),
          ]),
          const Divider(),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('DPP', style: TextStyle(color: Colors.grey)),
            Text('Rp ${CurrencyFormat.format(state.dpp)}',
                style: const TextStyle(color: Colors.grey)),
          ]),
          const SizedBox(height: 4),
          Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [
            const Text('Pajak', style: TextStyle(color: Colors.grey)),
            Text('Rp ${CurrencyFormat.format(state.pajak)}',
                style: const TextStyle(color: Colors.grey)),
          ]),
          const Divider(),

          // Cara Bayar
          DropdownButtonFormField<int>(
            initialValue: state.caraBayarID == 0 ? null : state.caraBayarID,
            decoration: const InputDecoration(
              labelText: 'Cara Bayar',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
            items: _caraBayarList.map((c) {
              return DropdownMenuItem<int>(
                value: int.parse(c['dim_carabayar_id'].toString()),
                child: Text(c['nama']),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                ref.read(penjualanProvider.notifier).setCaraBayar(val);
                final currentTotal = ref.read(penjualanProvider).total;
                _nominalController.text = currentTotal.toStringAsFixed(0);
                ref
                    .read(penjualanProvider.notifier)
                    .setNominalBayar(currentTotal);
              }
            },
          ),
          const SizedBox(height: 8),

          // Nominal Bayar
          TextField(
            controller: _nominalController,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nominal Bayar',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
              prefixText: 'Rp ',
            ),
            onChanged: (val) {
              final nominal = CurrencyFormat.parse(val);
              ref.read(penjualanProvider.notifier).setNominalBayar(nominal);
            },
          ),
          const SizedBox(height: 12),

          // PENDING
          SizedBox(
            width: double.infinity,
            height: _buttonHeight,
            child: ElevatedButton(
              onPressed: state.items.isEmpty ? null : _showPendingDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text(
                _isTinyTablet ? 'PENDING' : 'PENDING PAYMENT',
                style: const TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold),
              ),
            ),
          ),
          const SizedBox(height: 8),

          // BAYAR
          SizedBox(
            width: double.infinity,
            height: _buttonHeight,
            child: ElevatedButton(
              onPressed: state.items.isEmpty ? null : _prosesBayar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D273B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: Text('BAYAR',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: _labelFontSize)),
            ),
          ),
        ],
      ),
    );
  }
}
