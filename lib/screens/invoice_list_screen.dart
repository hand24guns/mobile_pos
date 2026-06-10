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
  // Store data — dipakai untuk print & WA & email
  int _activeStoreID = 0;
  String _activeStoreName = '';
  String _activeStoreAddress = '';
  String _activeStoreNpwp = '';
  String _activeInvoiceNote = '';
  String _logoFileName = '';
  String _logoUrl = '';
  bool _isFnB = false; // true jika jasa_perusahaan == 3
  bool _isMultiStore = false;
  bool _isLoading = true;
  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  List<Map<String, dynamic>> _invoices = [];

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

      final storeRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getStores',
            'user_id': _userID,
          }));
      final stores = List<Map<String, dynamic>>.from(storeRes.data['data']);
      _isMultiStore = stores.length > 1;

      _activeStoreID = int.parse(stores.first['id'].toString());

      final orgRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getOrganisasiID',
            'store_id': _activeStoreID,
          }));
      _organisasiID = int.parse(orgRes.data['organisasi_id'].toString());
      _isFnB = (orgRes.data['is_fnb'] == 1);

      // ✅ cekShiftUser DULU — biar _activeStoreID final
      final shiftRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'cekShiftUser',
            'user_id': _userID,
          }));

      if (shiftRes.data['has_shift'] == true) {
        _activeStoreID = shiftRes.data['store_id'];
        _activeStoreName = shiftRes.data['store_nama'];
        _organisasiID = int.parse(shiftRes.data['organisasi_id'].toString());
        _isFnB = (shiftRes.data['is_fnb'] == 1);
      } else {
        _activeStoreName = stores.first['nama'].toString();
      }

      // ✅ getStoreData SETELAH shift resolved — _activeStoreID sudah benar
      final settingRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getStoreData',
            'store_id': _activeStoreID,
          }));
      _activeStoreAddress = settingRes.data['alamat'] ?? '';
      _activeStoreNpwp = settingRes.data['npwp'] ?? '';
      _activeInvoiceNote = settingRes.data['invoice_note'] ?? '';
      _logoFileName = settingRes.data['logo_file_name'] ?? '';
      _logoUrl = settingRes.data['logo_url'] ?? '';

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
  // trackPrint dipanggil sekali di sini untuk mendapat copyCount
  // yang dipakai sebagai ribbon pada kedua jenis struk.
  Future<void> _doPrint(
    Map<String, dynamic> invoice, {
    required bool printCustomer,
    required bool printKitchen,
  }) async {
    try {
      // 1. Pastikan printer terkoneksi
      final connected = await _ensurePrinterConnected();
      if (!connected) return;

      // 2. Ambil items & log print (dapat copyCount) secara paralel
      final results = await Future.wait([
        _fetchItems(invoice['id'] as int),
        _trackPrint(invoice['kode']),
      ]);
      final fetchResult = results[0] as Map<String, dynamic>;
      final items = fetchResult['items'] as List<Map<String, dynamic>>;
      final keteranganTrx = fetchResult['keterangan'] as String;
      // Print dari invoice list SELALU reprint — pastikan ribbon muncul.
      // trackPrint sudah increment di server; kalau first print POS tidak
      // track, offset +1 agar copyCount minimal 2 (ribbon selalu tampil).
      final rawCount = results[1] as int;
      final copyCount = rawCount < 2 ? 2 : rawCount;

      // 3. Siapkan data bersama
      final tanggal = invoice['tanggal'].toString().length >= 16
          ? invoice['tanggal'].toString().substring(0, 16)
          : invoice['tanggal'].toString();

      // Jam transaksi dari created_date (format: "2024-01-15 14:30:00" → "14:30")
      final createdDateRaw = invoice['created_date']?.toString() ?? '';
      final jamTransaksi = createdDateRaw.length >= 16
          ? createdDateRaw.substring(11, 16)
          : (createdDateRaw.length >= 13 ? createdDateRaw.substring(11) : '');

      // 4. Print customer copy
      if (printCustomer) {
        await PrinterHelper.printInvoice(
          storeName: _activeStoreName,
          storeAddress: _activeStoreAddress,
          npwp: _activeStoreNpwp,
          invoiceNote: _activeInvoiceNote,
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
          logoFileName: _logoFileName.isNotEmpty ? _logoFileName : null,
          logoUrl: _logoUrl.isNotEmpty ? _logoUrl : null,
          copyCount: copyCount,
          salesTipe: invoice['sales_tipe'] ?? '',
          jamTransaksi: jamTransaksi.isNotEmpty ? jamTransaksi : null,
        );
      }

      // 5. Jeda singkat sebelum kitchen agar buffer tidak penuh
      if (printCustomer && printKitchen) {
        await Future.delayed(const Duration(milliseconds: 500));
      }

      // 6. Print kitchen copy
      if (printKitchen) {
        await PrinterHelper.printKitchen(
          storeName: _activeStoreName,
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
            'store_id': _activeStoreID,
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
            'store_id': _activeStoreID,
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D273B),
        title: const Text('Invoice List',
            style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold)),
        iconTheme: const IconThemeData(color: Colors.white),
        actions: [
          TextButton.icon(
            onPressed: _pickDateRange,
            icon: const Icon(Icons.date_range, color: Colors.white, size: 18),
            label: Text(
              '${_dateFrom.toIso8601String().substring(0, 10)} s/d ${_dateTo.toIso8601String().substring(0, 10)}',
              style: const TextStyle(color: Colors.white, fontSize: 12),
            ),
          ),
        ],
      ),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _invoices.isEmpty
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
                            '${_invoices.length} transaksi',
                            style: const TextStyle(color: Colors.white70),
                          ),
                          Text(
                            'Total: Rp ${CurrencyFormat.format(_invoices.fold(0.0, (sum, i) => sum + (i['total'] as num).toDouble()))}',
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                    ),
                    // List
                    Expanded(
                      child: ListView.builder(
                        padding: const EdgeInsets.all(8),
                        itemCount: _invoices.length,
                        itemBuilder: (_, i) {
                          final inv = _invoices[i];
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
