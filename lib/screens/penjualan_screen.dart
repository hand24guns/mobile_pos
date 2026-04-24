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

class PenjualanScreen extends ConsumerStatefulWidget {
  const PenjualanScreen({super.key});

  @override
  ConsumerState<PenjualanScreen> createState() => _PenjualanScreenState();
}

class _PenjualanScreenState extends ConsumerState<PenjualanScreen> {
  final _skuController = TextEditingController();
  final _memberController = TextEditingController();
  final _nominalController = TextEditingController();
  String _activeVoucher = '';

  String _token = '';
  int _userID = 0;
  String _deviceToken = '';
  int _shiftID = 0;
  bool _isLoading = true;

  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _caraBayarList = [];

  @override
  void initState() {
    super.initState();
    _loadInitialData();
  }

  Future<void> _loadInitialData() async {
    try {
      final session = await SessionService.getSession();
      _token       = session['token'];
      _userID      = session['user_id'];
      _deviceToken = await SessionService.getDeviceToken();

      final dio = ApiService.getDio(token: _token);

      // ============================================================
      // STEP 1 — Cek apakah user sudah punya shift aktif (store manapun)
      // Jika ya → bypass store picker, langsung pakai store dari shift
      // ============================================================
      final shiftUserRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action':  'cekShiftUser',
            'user_id': _userID,
          }));

      int    storeID      = 0;
      int    organisasiID = 0;
      String storeName    = '';

      if (shiftUserRes.data['has_shift'] == true) {
        // Sudah ada shift aktif milik user ini → langsung masuk
        storeID      = shiftUserRes.data['store_id'];
        organisasiID = shiftUserRes.data['organisasi_id'];
        storeName    = shiftUserRes.data['store_nama'];
        _shiftID     = shiftUserRes.data['shift_id'];

      } else {
        // ============================================================
        // STEP 2 — Belum ada shift → load stores → tampil picker
        // ============================================================
        final storeRes = await dio.post('/penjualan.php',
            data: FormData.fromMap({
              'action':  'getStores',
              'user_id': _userID,
            }));
        final stores =
            List<Map<String, dynamic>>.from(storeRes.data['data']);

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

        storeID   = int.parse(pickedStore['id'].toString());
        storeName = pickedStore['nama'].toString();

        final orgRes = await dio.post('/penjualan.php',
            data: FormData.fromMap({
              'action':   'getOrganisasiID',
              'store_id': storeID,
            }));
        organisasiID =
            int.parse(orgRes.data['organisasi_id'].toString());

        // ============================================================
        // STEP 3 — Cek shift di store yang dipilih
        // ============================================================
        final shiftRes = await ShiftService.cekShift(
          token:        _token,
          storeID:      storeID,
          organisasiID: organisasiID,
          userID:       _userID,
        );

        if (shiftRes.status == ShiftStatus.milikOrangLain) {
          // Store sedang dipakai user lain → warning → reload (pilih store lain)
          if (mounted) {
            await showDialog(
              context: context,
              barrierDismissible: false,
              builder: (_) => AlertDialog(
                title: const Text('Store Sedang Digunakan'),
                content: Text(
                  'Store $storeName sedang digunakan oleh ${shiftRes.kasirNama}.\n\nSilahkan pilih store lain atau minta kasir tersebut menutup shiftnya.',
                ),
                actions: [
                  ElevatedButton(
                    onPressed: () => Navigator.pop(context),
                    style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D273B)),
                    child: const Text('OK',
                        style: TextStyle(color: Colors.white)),
                  ),
                ],
              ),
            );
            // Restart alur dari awal
            _loadInitialData();
            return;
          }
        }

        if (shiftRes.status == ShiftStatus.tidakAda) {
          // Store kosong → buka shift baru
          if (!mounted) return;
          final shiftID = await _showBukaShiftDialog(
            storeID:      storeID,
            organisasiID: organisasiID,
          );
          if (shiftID == 0) {
            await _logout();
            return;
          }
          _shiftID = shiftID;
        }
        // milikSaya tidak mungkin terjadi di sini karena STEP 1 sudah handle
      }

      // ============================================================
      // STEP 4 — Load number, channels, cara bayar → masuk PenjualanScreen
      // ============================================================
      final numberRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action':        'getNumber',
            'store_id':      storeID,
            'organisasi_id': organisasiID,
            'device_token':  _deviceToken,
          }));
      final number = numberRes.data['number'];

      final channelRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({'action': 'getChannels'}));
      _channels =
          List<Map<String, dynamic>>.from(channelRes.data['data']);

      final caraBayarRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({'action': 'getCaraBayar'}));
      _caraBayarList =
          List<Map<String, dynamic>>.from(caraBayarRes.data['data']);

      ref.read(penjualanProvider.notifier).setInitialData(
            number:       number,
            storeID:      storeID,
            storeName:    storeName,
            organisasiID: organisasiID,
            salesTipeID:
                int.parse(_channels.first['dim_salestipe_id'].toString()),
          );

      setState(() => _isLoading = false);

    } catch (e, stackTrace) {
      print('ERROR: $e');
      print('STACK: $stackTrace');
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
  // STORE PICKER — Modal Bottom Sheet, scrollable, support list panjang
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
      builder: (_) {
        return StatefulBuilder(
          builder: (ctx, setState) {
            return Container(
              // max 75% tinggi layar supaya tidak full screen
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
                  // Handle bar
                  Container(
                    margin: const EdgeInsets.only(top: 12),
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: Colors.grey.shade300,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),

                  // Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                    child: Row(
                      children: [
                        const Icon(Icons.store,
                            color: Color(0xFF1D273B), size: 22),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'Pilih Store',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                              color: Color(0xFF1D273B),
                            ),
                          ),
                        ),
                        Text(
                          '${stores.length} store',
                          style: TextStyle(
                              fontSize: 12, color: Colors.grey.shade500),
                        ),
                      ],
                    ),
                  ),

                  const Divider(height: 1),

                  // List store — scrollable
                  Flexible(
                    child: ListView.separated(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      shrinkWrap: true,
                      itemCount: stores.length,
                      separatorBuilder: (_, __) =>
                          const SizedBox(height: 6),
                      itemBuilder: (_, i) {
                        final s = stores[i];
                        final isSelected = selected?['id'].toString() ==
                            s['id'].toString();
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
                                  isSelected
                                      ? Icons.store
                                      : Icons.store_outlined,
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.grey.shade500,
                                  size: 20,
                                ),
                                const SizedBox(width: 12),
                                Expanded(
                                  child: Text(
                                    s['nama'].toString(),
                                    style: TextStyle(
                                      color: isSelected
                                          ? Colors.white
                                          : Colors.black87,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      fontSize: 15,
                                    ),
                                  ),
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

                  // Footer buttons
                  const Divider(height: 1),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
                    child: Row(
                      children: [
                        Expanded(
                          child: OutlinedButton(
                            onPressed: () => Navigator.pop(ctx, null),
                            style: OutlinedButton.styleFrom(
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              side: const BorderSide(
                                  color: Color(0xFF1D273B)),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: const Text('Batal',
                                style:
                                    TextStyle(color: Color(0xFF1D273B))),
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
                              backgroundColor: const Color(0xFF1D273B),
                              disabledBackgroundColor:
                                  Colors.grey.shade300,
                              padding:
                                  const EdgeInsets.symmetric(vertical: 14),
                              shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8)),
                            ),
                            child: Text(
                              selected == null
                                  ? 'Pilih Store Dulu'
                                  : 'Masuk ke ${selected!['nama']}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // BUKA SHIFT — modal input modal kasir
  // Return shift_id jika berhasil, 0 jika user cancel
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
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D273B)),
            child: const Text('Buka Shift',
                style: TextStyle(color: Colors.white)),
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
      token:        _token,
      storeID:      storeID,
      organisasiID: organisasiID,
      userID:       _userID,
      modalKasir:   modal,
    );

    if (shiftID == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal buka shift'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return shiftID;
  }

  // ============================================================
  // TUTUP SHIFT — ambil rekap dulu lalu konfirmasi
  // ============================================================
  Future<void> _tutupShift() async {
    final state = ref.read(penjualanProvider);

    final rekap = await ShiftService.getRekapShift(
      token:        _token,
      shiftID:      _shiftID,
      storeID:      state.storeID,
      organisasiID: state.organisasiID,
    );

    if (rekap.isEmpty || !mounted) return;

    final openShift  = rekap['open_shift'] ?? '';
    final modalKasir = (rekap['modal_kasir'] as num).toDouble();
    final totalSales = (rekap['total_sales'] as num).toDouble();
    final jumlahInv  = rekap['jumlah_invoice'] as int;

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
            child: const Text('Batal'),
          ),
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
      token:         _token,
      shiftID:       _shiftID,
      storeID:       state.storeID,
      organisasiID:  state.organisasiID,
      totalSales:    totalSales,
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
              child: const Text('Selesai',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal menutup shift'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _rekapRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey)),
          Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
        ],
      ),
    );
  }

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

    // Jika hanya 1 hasil langsung tambah ke cart
    if (data.length == 1) {
      _addToCart(data.first);
    } else {
      // Tampilkan pilihan
      _showProductPicker(data);
    }
    _skuController.clear();
  }

  Future<void> _addToCart(Map<String, dynamic> produk) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    // Insert ke temp_invoice via API
    await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action':        'insertItem',
          'number':        state.number,
          'sku':           produk['kode'],
          'organisasi_id': state.organisasiID,
          'store_id':      state.storeID,
          'member_id':     state.memberID ?? 0,
          'voucher':       _activeVoucher,
          'device_token':  _deviceToken,
        }));

    // Refresh items + summary dari API
    await _refreshFromApi();
    _skuController.clear();
  }

  Future<void> _refreshFromApi() async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final itemsRes = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action':       'getItems',
          'number':       state.number,
          'device_token': _deviceToken,
        }));

    final itemsData = List<Map<String, dynamic>>.from(itemsRes.data['data']);
    final items = itemsData.map((e) => CartItem.fromJson(e)).toList();

    final summaryRes = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action':       'getSummary',
          'number':       state.number,
          'store_id':     state.storeID,
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
              _addToCart(p);
            },
          );
        },
      ),
    );
  }

  Future<void> _removeItem(int index) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);
    final item = state.items[index];

    await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action':        'deleteItem',
          'number':        state.number,
          'sku':           item.kode,
          'store_id':      state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id':     state.memberID ?? 0,
          'voucher':       _activeVoucher,
          'device_token':  _deviceToken,
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
          'action':        'updateQty',
          'number':        state.number,
          'sku':           item.kode,
          'qty':           qty,
          'store_id':      state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id':     state.memberID ?? 0,
          'voucher':       _activeVoucher,
          'device_token':  _deviceToken,
        }));

    await _refreshFromApi();
  }

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
                    )
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
            child: const Text('Batal'),
          ),
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
          'action':        'cekVoucher',
          'number':        state.number,
          'voucher':       kode,
          'store_id':      state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id':     state.memberID ?? 0,
          'device_token':  _deviceToken,
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
          'action':       'resetDiskon',
          'number':       state.number,
          'device_token': _deviceToken,
        }));

    await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action':        'recalculate',
          'number':        state.number,
          'store_id':      state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id':     state.memberID ?? 0,
          'voucher':       '',
          'device_token':  _deviceToken,
        }));

    setState(() => _activeVoucher = '');
    await _refreshFromApi();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Voucher dilepas')),
      );
    }
  }

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
            child: const Text('Batal'),
          ),
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

    // Cek nomor retur
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
          'action':        'loadRetur',
          'retur_number':  returNumber,
          'number':        state.number,
          'store_id':      state.storeID,
          'organisasi_id': state.organisasiID,
          'device_token':  _deviceToken,
        }));

    if (loadRes.data['success'] == true) {
      // Simpan retur source ke provider
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

  Future<void> _prosesBayar() async {
    final state = ref.read(penjualanProvider);

    // Validasi
    if (state.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada produk')),
      );
      return;
    }

    if (state.caraBayarID == 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Pilih cara bayar dulu')),
      );
      return;
    }

    if (state.nominalBayar < state.total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal bayar kurang dari total')),
      );
      return;
    }

    // Konfirmasi
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Konfirmasi Pembayaran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total'),
                Text('Rp ${CurrencyFormat.format(state.total)}',
                    style: const TextStyle(fontWeight: FontWeight.bold)),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bayar'),
                Text('Rp ${CurrencyFormat.format(state.nominalBayar)}'),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Kembalian',
                    style: TextStyle(fontWeight: FontWeight.bold)),
                Text(
                  'Rp ${CurrencyFormat.format(state.nominalBayar - state.total)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 18,
                      color: Color(0xFF1D273B)),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D273B),
            ),
            child: const Text('Proses', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    // Loading
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    final session = await SessionService.getSession();
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action':        'prosesBayar',
          'number':        state.number,
          'cara_bayar_id': state.caraBayarID,
          'store_id':      state.storeID,
          'organisasi_id': state.organisasiID,
          'user_id':       session['user_id'],
          'sales_tipe_id': state.salesTipeID,
          'member_id':     state.memberID ?? 0,
          'voucher':       _activeVoucher,
          'retur_source':  ref.read(penjualanProvider).returSource,
          'nominal_bayar': state.nominalBayar,
          'device_token':  _deviceToken,
        }));

    if (mounted) Navigator.pop(context); // tutup loading

    if (res.data['success'] == true) {
      final kembalian = res.data['kembalian'];

      // Kirim WA & Email di background
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
              TextButton.icon(
                onPressed: () async {
                  await _printInvoice(
                    invoiceNumber: state.number,
                    kembalian: (kembalian as num).toDouble(),
                    caraBayar: _caraBayarList.firstWhere(
                      (c) =>
                          int.parse(c['dim_carabayar_id'].toString()) ==
                          state.caraBayarID,
                      orElse: () => {'nama': ''},
                    )['nama'],
                    currentState: state,
                  );
                },
                icon: const Icon(Icons.print),
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

    // Kirim WA di background
    dio
        .post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'kirimWA',
              'number': invoiceNumber,
              'store_id': storeID,
              'organisasi_id': organisasiID,
              'member_id': memberID,
            }))
        .then((res) {
      print('WA: ${res.data}');
    }).catchError((e) {
      print('WA error: $e');
    });

    // Kirim Email di background
    dio
        .post('/penjualan.php',
            data: FormData.fromMap({
              'action': 'kirimEmail',
              'number': invoiceNumber,
              'store_id': storeID,
              'organisasi_id': organisasiID,
              'member_id': memberID,
            }))
        .then((res) {
      print('Email: ${res.data}');
    }).catchError((e) {
      print('Email error: $e');
    });
  }

  Future<void> _resetTransaksi() async {
    final dio = ApiService.getDio(token: _token);

    // Simpan data store dulu sebelum reset
    final currentState = ref.read(penjualanProvider);
    final storeID = currentState.storeID;
    final storeName = currentState.storeName;
    final organisasiID = currentState.organisasiID;

    final numberRes = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action':        'getNumber',
          'store_id':      storeID,
          'organisasi_id': organisasiID,
          'device_token':  _deviceToken,
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
  }

  Future<void> _printInvoice({
    required String invoiceNumber,
    required double kembalian,
    required String caraBayar,
    required PenjualanState currentState,
  }) async {
    try {
      final isConnected = await PrinterHelper.isConnected();
      if (!isConnected) {
        // Coba connect ke printer tersimpan
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

      // Ambil data store
      final storeRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getStoreData',
            'store_id': state.storeID,
          }));

      final storeName = storeRes.data['nama'] ?? '';
      final storeAddress = storeRes.data['alamat'] ?? '';
      final storeNpwp = storeRes.data['npwp'] ?? '';
      final invoiceNote = storeRes.data['invoice_note'] ?? '';

      // Ambil items dari currentState (bukan state yang sudah reset)
      final items = currentState.items
          .map((item) => {
                'nama': item.nama,
                'qty': item.qty,
                'hpj': item.hpj,
                'subtotal': item.subtotal,
                'diskon_persen': item.diskonPersen,
                'diskon_nominal': item.diskonNominal,
              })
          .toList();

      await PrinterHelper.printInvoice(
        storeName: storeName,
        storeAddress: storeAddress,
        npwp: storeNpwp,
        invoiceNote: invoiceNote,
        invoiceNumber: invoiceNumber,
        tanggal: DateTime.now().toString().substring(0, 16),
        kasir: (await SessionService.getSession())['nama'] ?? '',
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
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Print berhasil!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal print: $e')),
        );
      }
    }
  }

  Future<void> _showPendingDialog() async {
    final state = ref.read(penjualanProvider);

    if (state.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada produk')),
      );
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
            child: const Text('Batal'),
          ),
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
          'action':        'simpanPending',
          'number':        state.number,
          'store_id':      state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id':     state.memberID ?? 0,
          'user_id':       session['user_id'],
          'label':         labelController.text.trim(),
          'device_token':  _deviceToken,
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
                          // Retrieve
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
                          // Delete
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
                                      child: const Text('Batal'),
                                    ),
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
          'action':         'retrievePending',
          'sales_order_id': salesOrderID,
          'number':         state.number,
          'device_token':   _deviceToken,
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

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final state = ref.watch(penjualanProvider);

    return Scaffold(
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
      body: Row(
        children: [
          // KOLOM KIRI (60%)
          Expanded(
            flex: 6,
            child: Column(
              children: [
                _buildHeader(state),
                Expanded(child: _buildCart(state)),
              ],
            ),
          ),
          // DIVIDER
          Container(width: 1, color: Colors.grey.shade300),
          // KOLOM KANAN (40%)
          SizedBox(
            width: MediaQuery.of(context).size.width * 0.38,
            child: _buildSummary(state),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader(PenjualanState state) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
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
          // Row 3: Member + Voucher + Retur
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
                    suffixIcon: state.memberID != null
                        ? IconButton(
                            icon: const Icon(Icons.close, size: 18),
                            onPressed: () {
                              _memberController.clear();
                              ref
                                  .read(penjualanProvider.notifier)
                                  .setMember(null, '');
                            },
                          )
                        : const Icon(Icons.search, size: 18),
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
              OutlinedButton.icon(
                onPressed: () => _showVoucherDialog(),
                icon: const Icon(Icons.confirmation_number_outlined, size: 18),
                label: const Text('Voucher'),
                style: OutlinedButton.styleFrom(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
                ),
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: () => _showReturDialog(),
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

  Widget _buildCart(PenjualanState state) {
    if (state.items.isEmpty) {
      return const Center(
        child: Text('Belum ada produk', style: TextStyle(color: Colors.grey)),
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: state.items.length,
      itemBuilder: (_, i) {
        final item = state.items[i];
        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Row(
              children: [
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(item.nama,
                          style: const TextStyle(fontWeight: FontWeight.bold)),
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
                // Subtotal
                Column(
                  crossAxisAlignment: CrossAxisAlignment.end,
                  children: [
                    Text('Rp ${CurrencyFormat.format(item.subtotal)}',
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    IconButton(
                      icon:
                          const Icon(Icons.delete, color: Colors.red, size: 20),
                      onPressed: () => _removeItem(i),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildSummary(PenjualanState state) {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const Text('Total Pembelian',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          const Divider(),
          // Gross
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Gross'),
              Text('Rp ${CurrencyFormat.format(state.gross)}'),
            ],
          ),
          const SizedBox(height: 4),
          // Diskon
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Diskon'),
              Text('Rp ${CurrencyFormat.format(state.diskon)}'),
            ],
          ),
          const Divider(),
          // Total
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('TOTAL',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              Text('Rp ${CurrencyFormat.format(state.total)}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 16)),
            ],
          ),
          const Divider(),
          // DPP & Pajak
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('DPP', style: TextStyle(color: Colors.grey)),
              Text('Rp ${CurrencyFormat.format(state.dpp)}',
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Pajak', style: TextStyle(color: Colors.grey)),
              Text('Rp ${CurrencyFormat.format(state.pajak)}',
                  style: const TextStyle(color: Colors.grey)),
            ],
          ),
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
          const Spacer(),
          // PENDING dulu
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: state.items.isEmpty ? null : _showPendingDialog,
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.red,
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('PENDING PAYMENT',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ),
          const SizedBox(height: 8),
          // BAYAR paling bawah
          SizedBox(
            width: double.infinity,
            height: 48,
            child: ElevatedButton(
              onPressed: state.items.isEmpty ? null : _prosesBayar,
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D273B),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('BAYAR',
                  style: TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 16)),
            ),
          ),
        ],
      ),
    );
  }
}
