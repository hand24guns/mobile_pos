import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';
import '../services/session_service.dart';
import '../utils/currency_format.dart';
import '../utils/printer_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:font_awesome_flutter/font_awesome_flutter.dart';

class InvoiceListScreen extends StatefulWidget {
  const InvoiceListScreen({super.key});

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  String _token = '';
  int _userID = 0;
  int _organisasiID = 0;

  // Store aktif shift — HANYA untuk filter invoice & isFnB.
  // TIDAK dipakai sebagai sumber data header struk cetak.
  int _activeStoreID = 0;
  bool _isFnB = false;
  bool _isMultiStore = false;
  bool _isLoading = true;
  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  List<Map<String, dynamic>> _invoices = [];

  // ── Filter cara bayar ────────────────────────────────────────
  String? _selectedCaraBayar; // null = semua
  List<String> _caraBayarOptions = [];

  List<Map<String, dynamic>> get _filteredInvoices {
    if (_selectedCaraBayar == null) return _invoices;
    return _invoices
        .where((inv) => inv['cara_bayar'] == _selectedCaraBayar)
        .toList();
  }

  bool get _hasActiveFilter {
    final today = DateTime.now();
    final isDefaultDate = _dateFrom.year == today.year &&
        _dateFrom.month == today.month &&
        _dateFrom.day == today.day &&
        _dateTo.year == today.year &&
        _dateTo.month == today.month &&
        _dateTo.day == today.day;
    return !isDefaultDate || _selectedCaraBayar != null;
  }

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final session = await SessionService.getSession();
      _token = session['token'];
      _userID = session['user_id'];

      final dio = ApiService.getDio(token: _token);

      // 1. Ambil daftar store yang accessible
      final storeRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getStores',
            'user_id': _userID,
          }));
      final stores = List<Map<String, dynamic>>.from(storeRes.data['data']);
      _isMultiStore = stores.length > 1;

      // Default ke store pertama
      _activeStoreID = int.parse(stores.first['id'].toString());

      final orgRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getOrganisasiID',
            'store_id': _activeStoreID,
          }));
      _organisasiID = int.parse(orgRes.data['organisasi_id'].toString());
      _isFnB = (orgRes.data['is_fnb'] == 1);

      // 2. Cek shift aktif user — override activeStoreID & organisasiID
      //    untuk keperluan FILTER INVOICE saja.
      //    Data header struk (nama, alamat, logo, dll) TIDAK diambil di sini;
      //    akan di-fetch per-invoice saat user menekan tombol print.
      final shiftRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'cekShiftUser',
            'user_id': _userID,
          }));

      if (shiftRes.data['has_shift'] == true) {
        _activeStoreID = shiftRes.data['store_id'];
        _organisasiID = int.parse(shiftRes.data['organisasi_id'].toString());
        _isFnB = (shiftRes.data['is_fnb'] == 1);
      }

      await _loadInvoices();
      setState(() => _isLoading = false);
    } catch (e, stack) {
      print('ERROR _loadData: $e');
      print('STACK: $stack');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadInvoices() async {
    final dio = ApiService.getDio(token: _token);
    final dateFrom = _dateFrom.toIso8601String().substring(0, 10);
    final dateTo = _dateTo.toIso8601String().substring(0, 10);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'getInvoiceList',
          'user_id': _userID,
          'organisasi_id': _organisasiID,
          'date_from': dateFrom,
          'date_to': dateTo,
        }));

    setState(() {
      _invoices = List<Map<String, dynamic>>.from(res.data['data']);
      // Rebuild unique cara_bayar list dari data baru
      final options = _invoices
          .map((inv) => (inv['cara_bayar'] ?? '').toString().trim())
          .where((v) => v.isNotEmpty)
          .toSet()
          .toList()
        ..sort();
      _caraBayarOptions = options;
      // Reset pilihan kalau sudah tidak ada di list baru
      if (_selectedCaraBayar != null &&
          !_caraBayarOptions.contains(_selectedCaraBayar)) {
        _selectedCaraBayar = null;
      }
    });
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2024),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(
        start: _dateFrom,
        end: _dateTo,
      ),
      builder: (context, child) => Theme(
        data: ThemeData(
          colorScheme: const ColorScheme.light(
            primary: Color(0xFF1D273B),
          ),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _dateFrom = picked.start;
        _dateTo = picked.end;
      });
      await _loadInvoices();
    }
  }

  // ── Pastikan printer terkoneksi ──────────────────────────────
  Future<bool> _ensurePrinterConnected() async {
    final isConn = await PrinterHelper.isConnected();
    if (isConn) return true;

    final prefs = await SharedPreferences.getInstance();
    final savedMac = prefs.getString('printer_mac');
    if (savedMac == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Belum ada printer. Buka Pengaturan Printer.'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }
    return await PrinterHelper.connect(savedMac);
  }

  // ── Hit API trackPrint → kembalikan copyCount ────────────────
  Future<int> _trackPrint(String kode) async {
    try {
      final dio = ApiService.getDio(token: _token);
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'trackPrint',
            'kode': kode,
          }));
      if (res.data['success'] == true) {
        return (res.data['count'] as num).toInt();
      }
    } catch (_) {}
    return 1; // fallback: anggap first print agar tidak crash
  }

  // ── Ambil items + keterangan transaksi dari API ─────────────
  Future<Map<String, dynamic>> _fetchItems(int invoiceId) async {
    final dio = ApiService.getDio(token: _token);
    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'getInvoiceDetail',
          'invoice_id': invoiceId,
        }));
    return {
      'items': List<Map<String, dynamic>>.from(res.data['data']),
      'keterangan': res.data['keterangan'] ?? '',
    };
  }

  // ── Fetch store data berdasarkan store_id invoice ────────────
  //
  // PENTING: method ini sengaja menerima store_id dari invoice,
  // bukan dari _activeStoreID. Ini memastikan header struk selalu
  // menampilkan nama/alamat/logo store tempat transaksi terjadi,
  // tidak peduli user sedang open shift di store mana.
  Future<Map<String, dynamic>> _fetchStoreData(int storeId) async {
    try {
      final dio = ApiService.getDio(token: _token);
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getStoreData',
            'store_id': storeId,
          }));
      return Map<String, dynamic>.from(res.data);
    } catch (_) {
      return {};
    }
  }

  // ── ENTRY POINT print dari list ──────────────────────────────
  //
  // Untuk FnB → tampilkan bottom sheet pilih Customer/Kitchen/Keduanya
  // Untuk non-FnB → langsung print customer
  Future<void> _handlePrint(Map<String, dynamic> invoice) async {
    if (_isFnB) {
      await _showReprintSheet(invoice);
    } else {
      await _doPrint(invoice, printCustomer: true, printKitchen: false);
    }
  }

  // ── Bottom sheet pilihan reprint untuk FnB ───────────────────
  Future<void> _showReprintSheet(Map<String, dynamic> invoice) async {
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
                  'Print Ulang — ${invoice['kode']}',
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15),
                ),
              ),
              const Divider(),
              // Pilihan
              ListTile(
                leading:
                    const Icon(Icons.receipt_long, color: Color(0xFF1D273B)),
                title: const Text('Customer Copy'),
                subtitle: const Text('Struk untuk pelanggan'),
                onTap: () {
                  Navigator.pop(ctx);
                  _doPrint(invoice, printCustomer: true, printKitchen: false);
                },
              ),
              ListTile(
                leading: const Icon(Icons.kitchen, color: Colors.orange),
                title: const Text('Kitchen Copy'),
                subtitle: const Text('Struk untuk dapur'),
                onTap: () {
                  Navigator.pop(ctx);
                  _doPrint(invoice, printCustomer: false, printKitchen: true);
                },
              ),
              ListTile(
                leading: const Icon(Icons.print_rounded, color: Colors.green),
                title: const Text('Customer + Kitchen'),
                subtitle: const Text('Print dua-duanya'),
                onTap: () {
                  Navigator.pop(ctx);
                  _doPrint(invoice, printCustomer: true, printKitchen: true);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Eksekusi print sesungguhnya ──────────────────────────────
  //
  // [printCustomer] — cetak customer copy
  // [printKitchen]  — cetak kitchen copy
  //
  // FIX BUG: store data (nama, alamat, logo, npwp, dll) di-fetch
  // berdasarkan store_id yang ada di dalam data invoice itu sendiri,
  // bukan dari _activeStoreID (yang bisa ter-override oleh shift user
  // di store berbeda). Dengan begitu struk selalu menampilkan outlet
  // yang benar meskipun user sedang open shift di outlet lain.
  Future<void> _doPrint(
    Map<String, dynamic> invoice, {
    required bool printCustomer,
    required bool printKitchen,
  }) async {
    try {
      // 1. Pastikan printer terkoneksi
      final connected = await _ensurePrinterConnected();
      if (!connected) return;

      // 2. Ambil store_id dari invoice — ini yang BENAR untuk header struk
      final invoiceStoreId = invoice['store_id'] as int? ?? _activeStoreID;

      // 3. Fetch items, copyCount, dan store data secara paralel
      final results = await Future.wait([
        _fetchItems(invoice['id'] as int),
        _trackPrint(invoice['kode']),
        _fetchStoreData(invoiceStoreId),
      ]);

      final fetchResult = results[0] as Map<String, dynamic>;
      final items = fetchResult['items'] as List<Map<String, dynamic>>;
      final keteranganTrx = fetchResult['keterangan'] as String;

      // Print dari invoice list SELALU reprint — pastikan ribbon muncul.
      // trackPrint sudah increment di server; kalau first print POS tidak
      // track, offset +1 agar copyCount minimal 2 (ribbon selalu tampil).
      final rawCount = results[1] as int;
      final copyCount = rawCount < 2 ? 2 : rawCount;

      // 4. Store data dari invoice — BUKAN dari shift user
      final storeData = results[2] as Map<String, dynamic>;
      final storeName    = invoice['store']?.toString() ?? '';
      final storeAddress = storeData['alamat']?.toString() ?? '';
      final storeNpwp    = storeData['npwp']?.toString() ?? '';
      final invoiceNote  = storeData['invoice_note']?.toString() ?? '';
      final logoFileName = storeData['logo_file_name']?.toString() ?? '';
      final logoUrl      = storeData['logo_url']?.toString() ?? '';

      // 5. Waktu transaksi
      final tanggal = invoice['tanggal'].toString().length >= 16
          ? invoice['tanggal'].toString().substring(0, 16)
          : invoice['tanggal'].toString();

      final createdDateRaw = invoice['created_date']?.toString() ?? '';
      final jamTransaksi = createdDateRaw.length >= 16
          ? createdDateRaw.substring(11, 16)
          : (createdDateRaw.length >= 13 ? createdDateRaw.substring(11) : '');

      // 6. Print customer copy
      if (printCustomer) {
        await PrinterHelper.printInvoice(
          storeName: storeName,
          storeAddress: storeAddress,
          npwp: storeNpwp,
          invoiceNote: invoiceNote,
          invoiceNumber: invoice['kode'],
          tanggal: tanggal,
          kasir: invoice['kasir'] ?? '',
          memberNama: invoice['member'] ?? '',
          items: items,
          gross: (invoice['gross'] as num).toDouble(),
          diskon: (invoice['diskon'] as num).toDouble(),
          total: (invoice['total'] as num).toDouble(),
          dpp: 0,
          pajak: 0,
          caraBayar: invoice['cara_bayar'] ?? '',
          nominalBayar: (invoice['bayar'] as num).toDouble(),
          kembalian: (invoice['kembalian'] as num).toDouble(),
          voucherKode: invoice['voucher_kode'],
          keterangan: keteranganTrx,
          logoFileName: logoFileName.isNotEmpty ? logoFileName : null,
          logoUrl: logoUrl.isNotEmpty ? logoUrl : null,
          copyCount: copyCount,
          salesTipe: invoice['sales_tipe'] ?? '',
          jamTransaksi: jamTransaksi.isNotEmpty ? jamTransaksi : null,
        );
      }

      // 7. Jeda singkat sebelum kitchen agar buffer tidak penuh
      if (printCustomer && printKitchen) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 8. Print kitchen copy
      if (printKitchen) {
        await PrinterHelper.printKitchen(
          storeName: storeName,
          invoiceNumber: invoice['kode'],
          tanggal: tanggal,
          kasir: invoice['kasir'] ?? '',
          items: items,
          memberNama: invoice['member'] ?? '',
          total: (invoice['total'] as num).toDouble(),
          keterangan: keteranganTrx,
          copyCount: copyCount,
          salesTipe: invoice['sales_tipe'] ?? '',
          jamTransaksi: jamTransaksi.isNotEmpty ? jamTransaksi : null,
        );
      }

      if (mounted) {
        final label = printCustomer && printKitchen
            ? 'Customer + Kitchen'
            : printCustomer
                ? 'Customer'
                : 'Kitchen';
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Print $label berhasil!'),
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

  Future<void> _sendWA(Map<String, dynamic> invoice) async {
    final telp = invoice['member_telp'] ?? '';
    if (telp.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member tidak punya nomor WA')),
      );
      return;
    }

    final dio = ApiService.getDio(token: _token);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'kirimWA',
            'number': invoice['kode'],
            'store_id': invoice['store_id'] ?? _activeStoreID,
            'organisasi_id': _organisasiID,
            'member_id': invoice['dim_bp_id'] ?? 0,
          }));

      if (mounted) Navigator.pop(context);

      if (res.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('WA berhasil dikirim!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.data['message'] ?? 'Gagal kirim WA')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _sendEmail(Map<String, dynamic> invoice) async {
    final email = invoice['member_email'] ?? '';
    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Member tidak punya email')),
      );
      return;
    }

    final dio = ApiService.getDio(token: _token);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'kirimEmail',
            'number': invoice['kode'],
            'store_id': invoice['store_id'] ?? _activeStoreID,
            'organisasi_id': _organisasiID,
            'member_id': invoice['dim_bp_id'] ?? 0,
          }));

      if (mounted) Navigator.pop(context);

      if (res.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Email berhasil dikirim!'),
            backgroundColor: Colors.green,
          ),
        );
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text(res.data['message'] ?? 'Gagal kirim email')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  Future<void> _requestVoid(Map<String, dynamic> invoice) async {
    final TextEditingController notesCtrl = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('Request Void', style: TextStyle(fontSize: 16)),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Invoice: ${invoice['kode']}',
              style: const TextStyle(fontWeight: FontWeight.bold),
            ),
            const SizedBox(height: 12),
            const Text('Masukkan alasan void:', style: TextStyle(fontSize: 13)),
            const SizedBox(height: 8),
            TextField(
              controller: notesCtrl,
              maxLines: 3,
              decoration: const InputDecoration(
                hintText: 'Contoh: transaksi dobel, salah input, dll.',
                border: OutlineInputBorder(),
                contentPadding:
                    EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            onPressed: () {
              if (notesCtrl.text.trim().isEmpty) return;
              Navigator.pop(ctx, true);
            },
            child: const Text('Kirim Request',
                style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;
    final notes = notesCtrl.text.trim();
    if (notes.isEmpty) return;

    final dio = ApiService.getDio(token: _token);

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'voidInvoice',
            'id': invoice['id'],
            'notes': notes,
            'userID': _userID,
          }));

      if (mounted) Navigator.pop(context);

      if (res.data['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Request void berhasil dikirim!'),
            backgroundColor: Colors.red,
          ),
        );
        await _loadInvoices(); // refresh list — invoice REQ VO tidak muncul lagi
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text(res.data['message'] ?? 'Gagal kirim request void')),
        );
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Error: $e')),
      );
    }
  }

  // ── Popup pilih cara bayar ───────────────────────────────────
  Future<void> _pickCaraBayar() async {
    final picked = await showDialog<String?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Filter Cara Bayar',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, ''),
            child: Row(
              children: [
                Icon(Icons.all_inclusive,
                    size: 18,
                    color: _selectedCaraBayar == null
                        ? const Color(0xFF1D273B)
                        : Colors.grey),
                const SizedBox(width: 10),
                Text('Semua',
                    style: TextStyle(
                        fontWeight: _selectedCaraBayar == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: _selectedCaraBayar == null
                            ? const Color(0xFF1D273B)
                            : null)),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._caraBayarOptions.map((cb) => SimpleDialogOption(
                onPressed: () => Navigator.pop(ctx, cb),
                child: Row(
                  children: [
                    Icon(Icons.payment,
                        size: 18,
                        color: _selectedCaraBayar == cb
                            ? const Color(0xFF1D273B)
                            : Colors.grey),
                    const SizedBox(width: 10),
                    Text(cb,
                        style: TextStyle(
                            fontWeight: _selectedCaraBayar == cb
                                ? FontWeight.bold
                                : FontWeight.normal,
                            color: _selectedCaraBayar == cb
                                ? const Color(0xFF1D273B)
                                : null)),
                    if (_selectedCaraBayar == cb) ...[
                      const Spacer(),
                      const Icon(Icons.check,
                          size: 16, color: Color(0xFF1D273B)),
                    ],
                  ],
                ),
              )),
        ],
      ),
    );

    if (picked == null) return;
    setState(() {
      _selectedCaraBayar = picked.isEmpty ? null : picked;
    });
  }

  // ── Reset semua filter ke default ───────────────────────────
  void _resetFilter() {
    final today = DateTime.now();
    setState(() {
      _dateFrom = today;
      _dateTo = today;
      _selectedCaraBayar = null;
    });
    _loadInvoices();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D273B),
        title: const Text('Invoice List',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          // Filter cara bayar
          TextButton.icon(
            onPressed: _caraBayarOptions.isEmpty ? null : _pickCaraBayar,
            icon: Icon(
              Icons.payment,
              color: _selectedCaraBayar != null ? Colors.amber : Colors.white,
              size: 18,
            ),
            label: Text(
              _selectedCaraBayar ?? 'Cara Bayar',
              style: TextStyle(
                color: _selectedCaraBayar != null ? Colors.amber : Colors.white,
                fontSize: 12,
              ),
            ),
          ),
          // Filter tanggal
          TextButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range, color: Colors.white, size: 18),
            label: Text(
              '${_dateFrom.toIso8601String().substring(0, 10)} s/d ${_dateTo.toIso8601String().substring(0, 10)}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
          // Reset — hanya muncul kalau ada filter aktif
          if (_hasActiveFilter)
            IconButton(
              icon: const Icon(Icons.refresh, color: Colors.amber),
              tooltip: 'Reset Filter',
              onPressed: _resetFilter,
            ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _filteredInvoices.isEmpty
              ? const Center(
                  child: Text('Tidak ada transaksi',
                      style: TextStyle(color: Colors.grey)))
              : Column(
                  children: [
                    // Summary bar
                    Container(
                      color: const Color(0xFF1D273B),
                      padding: const EdgeInsets.symmetric(
                          horizontal: 16, vertical: 8),
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            '${_filteredInvoices.length} transaksi',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 8, vertical: 2),
                                decoration: BoxDecoration(
                                  color: Colors.white.withOpacity(0.15),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Text(
                                  'Invoice: ${_filteredInvoices.length}',
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12),
                                ),
                              ),
                              const SizedBox(width: 10),
                              Text(
                                'Total: Rp ${CurrencyFormat.format(_filteredInvoices.fold(0.0, (sum, i) => sum + (i['total'] as num).toDouble()))}',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _filteredInvoices.length,
                        itemBuilder: (_, i) {
                          final inv = _filteredInvoices[i];
                          return Card(
                            child: Padding(
                              padding: const EdgeInsets.all(12),
                              child: Row(
                                children: [
                                  // Info
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        // Baris 1: kode invoice
                                        Text(inv['kode'],
                                            style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 14)),
                                        const SizedBox(height: 4),
                                        // Baris 2: store badge (hanya muncul kalau multi-store)
                                        if (_isMultiStore)
                                          Container(
                                            margin: const EdgeInsets.only(
                                                bottom: 4),
                                            padding: const EdgeInsets.symmetric(
                                                horizontal: 8, vertical: 2),
                                            decoration: BoxDecoration(
                                              color: const Color(0xFF1D273B)
                                                  .withOpacity(0.08),
                                              borderRadius:
                                                  BorderRadius.circular(4),
                                            ),
                                            child: Text(
                                              inv['store'] ?? '',
                                              style: const TextStyle(
                                                fontSize: 11,
                                                color: Color(0xFF1D273B),
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ),
                                        // Baris 3: member
                                        Text(
                                          inv['member']?.isNotEmpty == true
                                              ? inv['member']
                                              : 'Tanpa Member',
                                          style: const TextStyle(
                                              color: Colors.grey, fontSize: 12),
                                        ),
                                        // Baris 4: cara bayar + jam
                                        Text(
                                          '${inv['cara_bayar']?.isNotEmpty == true ? inv['cara_bayar'] : '-'}'
                                          ' • '
                                          '${inv['tanggal'].toString().length >= 16 ? inv['tanggal'].toString().substring(11, 16) : inv['tanggal'].toString()}',
                                          style: const TextStyle(
                                              color: Colors.grey, fontSize: 12),
                                        ),
                                        // Baris 5: kasir
                                        if ((inv['kasir'] ?? '').isNotEmpty)
                                          Text(
                                            'Kasir: ${inv['kasir']}',
                                            style: const TextStyle(
                                                color: Colors.grey,
                                                fontSize: 11),
                                          ),
                                      ],
                                    ),
                                  ),
                                  // Total + actions
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Text(
                                        'Rp ${CurrencyFormat.format(inv['total'])}',
                                        style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 14),
                                      ),
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          // Print — _handlePrint menangani FnB vs non-FnB
                                          IconButton(
                                            icon: const Icon(Icons.print,
                                                color: Color(0xFF1D273B)),
                                            tooltip: _isFnB
                                                ? 'Print Ulang'
                                                : 'Print',
                                            onPressed: () => _handlePrint(inv),
                                          ),
                                          // WA
                                          if ((inv['store_wa'] == 1) &&
                                              (inv['member_telp'] ?? '')
                                                  .isNotEmpty)
                                            IconButton(
                                              icon: const FaIcon(
                                                  FontAwesomeIcons.whatsapp,
                                                  color: Colors.green),
                                              tooltip: 'Kirim WA',
                                              onPressed: () => _sendWA(inv),
                                            ),
                                          // Email
                                          if ((inv['member_email'] ?? '')
                                              .isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.email,
                                                  color: Colors.orange),
                                              tooltip: 'Kirim Email',
                                              onPressed: () => _sendEmail(inv),
                                            ),
                                          // Request Void
                                          IconButton(
                                            icon: const Icon(
                                                Icons.cancel_outlined,
                                                color: Colors.red),
                                            tooltip: 'Request Void',
                                            onPressed: () => _requestVoid(inv),
                                          ),
                                        ],
                                      ),
                                    ],
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
    );
  }
}
