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
  String _token        = '';
  int    _userID       = 0;
  int    _organisasiID = 0;
  // Store data — dipakai untuk print & WA & email
  // Untuk multi-store, diambil dari store aktif (shift)
  int    _activeStoreID      = 0;
  String _activeStoreName    = '';
  String _activeStoreAddress = '';
  String _activeStoreNpwp    = '';
  String _activeInvoiceNote  = '';
  int    _waEnabled          = 0;
  // Apakah user punya akses > 1 store (untuk tampilkan kolom store di list)
  bool   _isMultiStore = false;
  bool   _isLoading    = true;
  DateTime _dateFrom = DateTime.now().subtract(const Duration(days: 9));
  DateTime _dateTo   = DateTime.now();
  List<Map<String, dynamic>> _invoices = [];

  @override
  void initState() {
    super.initState();
    _loadData();
  }

  Future<void> _loadData() async {
    try {
      final session = await SessionService.getSession();
      _token  = session['token'];
      _userID = session['user_id'];

      final dio = ApiService.getDio(token: _token);

      // Ambil semua store yang bisa diakses user
      final storeRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action':  'getStores',
            'user_id': _userID,
          }));
      final stores =
          List<Map<String, dynamic>>.from(storeRes.data['data']);
      _isMultiStore = stores.length > 1;

      // Ambil organisasiID dari store pertama (semua store milik org yang sama)
      _activeStoreID = int.parse(stores.first['id'].toString());
      final orgRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action':   'getOrganisasiID',
            'store_id': _activeStoreID,
          }));
      _organisasiID =
          int.parse(orgRes.data['organisasi_id'].toString());

      // Cek shift aktif user → untuk tahu store mana yang aktif
      // (dipakai untuk print/WA/email — pakai setting store aktif)
      final shiftRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action':  'cekShiftUser',
            'user_id': _userID,
          }));

      if (shiftRes.data['has_shift'] == true) {
        _activeStoreID   = shiftRes.data['store_id'];
        _activeStoreName = shiftRes.data['store_nama'];
      } else {
        _activeStoreName = stores.first['nama'].toString();
      }

      // Load setting store aktif (untuk print/WA/email)
      final settingRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action':   'getStoreSetting',
            'store_id': _activeStoreID,
          }));
      _activeStoreAddress = settingRes.data['alamat'] ?? '';
      _activeStoreNpwp    = settingRes.data['npwp'] ?? '';
      _activeInvoiceNote  = settingRes.data['invoice_note'] ?? '';
      _waEnabled          = settingRes.data['wa'] ?? 0;

      await _loadInvoices();
      setState(() => _isLoading = false);
    } catch (e, stack) {
      print('ERROR _loadData: $e');
      print('STACK: $stack');
      setState(() => _isLoading = false);
    }
  }

  Future<void> _loadInvoices() async {
    final dio     = ApiService.getDio(token: _token);
    final dateFrom = _dateFrom.toIso8601String().substring(0, 10);
    final dateTo   = _dateTo.toIso8601String().substring(0, 10);

    final res = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action':        'getInvoiceList',
          'user_id':       _userID,
          'organisasi_id': _organisasiID,
          'date_from':     dateFrom,
          'date_to':       dateTo,
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

  Future<void> _printInvoice(Map<String, dynamic> invoice) async {
    try {
      final isConnected = await PrinterHelper.isConnected();
      if (!isConnected) {
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
          return;
        }
        await PrinterHelper.connect(savedMac);
      }

      // Ambil detail items
      final dio = ApiService.getDio(token: _token);
      final detailRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getInvoiceDetail',
            'invoice_id': invoice['id'],
          }));

      final items = List<Map<String, dynamic>>.from(detailRes.data['data']);

      await PrinterHelper.printInvoice(
        storeName:    _activeStoreName,
        storeAddress: _activeStoreAddress,
        npwp:         _activeStoreNpwp,
        invoiceNote:  _activeInvoiceNote,
        invoiceNumber: invoice['kode'],
        tanggal: invoice['tanggal'].toString().length >= 16
            ? invoice['tanggal'].toString().substring(0, 16)
            : invoice['tanggal'].toString(),
        kasir:        invoice['kasir'] ?? '',
        memberNama:   invoice['member'] ?? '',
        items:        items,
        gross:        (invoice['gross'] as num).toDouble(),
        diskon:       (invoice['diskon'] as num).toDouble(),
        total:        (invoice['total'] as num).toDouble(),
        dpp:          0,
        pajak:        0,
        caraBayar:    invoice['cara_bayar'] ?? '',
        nominalBayar: (invoice['bayar'] as num).toDouble(),
        kembalian:    (invoice['kembalian'] as num).toDouble(),
        voucherKode:  invoice['voucher_kode'],
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
            'action':        'kirimWA',
            'number':        invoice['kode'],
            'store_id':      _activeStoreID,
            'organisasi_id': _organisasiID,
            'member_id':     invoice['dim_bp_id'] ?? 0,
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
            'action':        'kirimEmail',
            'number':        invoice['kode'],
            'store_id':      _activeStoreID,
            'organisasi_id': _organisasiID,
            'member_id':     invoice['dim_bp_id'] ?? 0,
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
                                            padding:
                                                const EdgeInsets.symmetric(
                                                    horizontal: 8,
                                                    vertical: 2),
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
                                              color: Colors.grey,
                                              fontSize: 12),
                                        ),
                                        // Baris 4: cara bayar + jam
                                        Text(
                                          '${inv['cara_bayar']?.isNotEmpty == true ? inv['cara_bayar'] : '-'}'
                                          ' • '
                                          '${inv['tanggal'].toString().length >= 16 ? inv['tanggal'].toString().substring(11, 16) : inv['tanggal'].toString()}',
                                          style: const TextStyle(
                                              color: Colors.grey,
                                              fontSize: 12),
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
                                    crossAxisAlignment:
                                        CrossAxisAlignment.end,
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
                                          // Print
                                          IconButton(
                                            icon: const Icon(Icons.print,
                                                color: Color(0xFF1D273B)),
                                            tooltip: 'Print',
                                            onPressed: () =>
                                                _printInvoice(inv),
                                          ),
                                          // WA
                                          if (_waEnabled == 1 &&
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
                                              onPressed: () =>
                                                  _sendEmail(inv),
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
