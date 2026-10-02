import 'package:flutter/material.dart';
import '../services/session_service.dart';
import '../services/order_service.dart';
import '../services/store_service.dart';
import '../services/shift_service.dart';
import '../utils/currency_format.dart';
import '../utils/printer_helper.dart';
import 'package:shared_preferences/shared_preferences.dart';

class InvoiceListScreen extends StatefulWidget {
  // Filter awal opsional — dipakai saat masuk dari laporan lain
  // (mis. tap baris "Transaksi" di laporan Channel Terjual), supaya
  // list langsung tampil ter-filter tanpa user perlu set ulang.
  final int? initialChannelId;
  final String? initialChannelName;
  final String? initialCaraBayarName;
  final int? initialStoreId;
  final String? initialStoreName;
  final DateTime? initialDateFrom;
  final DateTime? initialDateTo;

  const InvoiceListScreen({
    super.key,
    this.initialChannelId,
    this.initialChannelName,
    this.initialCaraBayarName,
    this.initialStoreId,
    this.initialStoreName,
    this.initialDateFrom,
    this.initialDateTo,
  });

  @override
  State<InvoiceListScreen> createState() => _InvoiceListScreenState();
}

class _InvoiceListScreenState extends State<InvoiceListScreen> {
  int _userID = 0;
  int _organisasiID = 0;

  // Store aktif shift — HANYA untuk filter invoice & isFnB.
  // TIDAK dipakai sebagai sumber data header struk cetak.
  int _activeStoreID = 0;
  bool _isFnB = false;
  bool _isLoading = true;
  DateTime _dateFrom = DateTime.now();
  DateTime _dateTo = DateTime.now();
  List<Map<String, dynamic>> _invoices = [];

  // ── Filter cara bayar ────────────────────────────────────────
  String? _selectedCaraBayar; // null = semua
  List<String> _caraBayarOptions = [];

  // ── Filter channel ────────────────────────────────────────────
  int? _selectedChannelId; // null = semua
  String? _selectedChannelName;
  List<Map<String, dynamic>> _channelOptions = []; // [{id, nama}]

  // ── Filter outlet/store ─────────────────────────────────────────
  int? _selectedStoreId; // null = semua outlet
  String? _selectedStoreName;
  List<Map<String, dynamic>> _storeOptions = []; // [{id, nama}] — diambil dari getStores

  // ── Filter search (baru) — cari no invoice / customer / kasir ──
  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  // ── Pagination (baru) ────────────────────────────────────────
  int _currentPage = 0; // 0-based
  int _pageSize = 10;
  static const List<int> _pageSizeOptions = [10, 25, 50, 100];

  List<Map<String, dynamic>> get _filteredInvoices {
    final query = _searchQuery.trim().toLowerCase();
    return _invoices.where((inv) {
      final matchCaraBayar = _selectedCaraBayar == null ||
          inv['cara_bayar'] == _selectedCaraBayar;
      final matchChannel = _selectedChannelId == null ||
          inv['channel_id'] == _selectedChannelId;
      final matchStore = _selectedStoreId == null ||
          inv['store_id'] == _selectedStoreId;
      if (!matchCaraBayar || !matchChannel || !matchStore) return false;
      if (query.isEmpty) return true;
      final kode = (inv['kode'] ?? '').toString().toLowerCase();
      final member = (inv['member'] ?? '').toString().toLowerCase();
      final kasir = (inv['kasir'] ?? '').toString().toLowerCase();
      return kode.contains(query) ||
          member.contains(query) ||
          kasir.contains(query);
    }).toList();
  }

  // ── Slice halaman berjalan dari hasil filter ────────────────
  List<Map<String, dynamic>> get _pagedInvoices {
    final filtered = _filteredInvoices;
    final start = _currentPage * _pageSize;
    if (start >= filtered.length) return [];
    final end = (start + _pageSize) > filtered.length
        ? filtered.length
        : start + _pageSize;
    return filtered.sublist(start, end);
  }

  bool get _hasActiveFilter {
    final today = DateTime.now();
    final isDefaultDate = _dateFrom.year == today.year &&
        _dateFrom.month == today.month &&
        _dateFrom.day == today.day &&
        _dateTo.year == today.year &&
        _dateTo.month == today.month &&
        _dateTo.day == today.day;
    return !isDefaultDate ||
        _selectedCaraBayar != null ||
        _selectedChannelId != null ||
        _selectedStoreId != null ||
        _searchQuery.trim().isNotEmpty;
  }

  @override
  void initState() {
    super.initState();
    // Terapkan filter awal (dari laporan Channel Terjual) sebelum load.
    if (widget.initialDateFrom != null) _dateFrom = widget.initialDateFrom!;
    if (widget.initialDateTo != null) _dateTo = widget.initialDateTo!;
    if (widget.initialChannelId != null) {
      _selectedChannelId = widget.initialChannelId;
      _selectedChannelName = widget.initialChannelName;
    }
    if (widget.initialCaraBayarName != null) {
      _selectedCaraBayar = widget.initialCaraBayarName;
    }
    if (widget.initialStoreId != null) {
      _selectedStoreId = widget.initialStoreId;
      _selectedStoreName = widget.initialStoreName;
    }
    _searchCtrl.addListener(() {
      setState(() {
        _searchQuery = _searchCtrl.text;
        _currentPage = 0;
      });
    });
    _loadData();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadData() async {
    try {
      final session = await SessionService.getSession();
      _userID = session['user_id'] ?? 0;

      // 1. Ambil daftar store yang accessible
      final stores = await StoreService.getStores(userId: _userID);
      _storeOptions = stores;

      if (stores.isNotEmpty) {
        // Default ke store pertama
        _activeStoreID =
            int.tryParse(stores.first['id']?.toString() ?? '') ?? 0;

        final orgData = await StoreService.getOrganisasiId(_activeStoreID);
        _organisasiID = orgData['organisasi_id'] ?? 0;
        _isFnB = orgData['is_fnb'] == true;
      }

      // 2. Cek shift aktif user — override activeStoreID & organisasiID
      //    untuk keperluan FILTER INVOICE saja.
      final shiftData = await ShiftService.cekShiftUser(userId: _userID);
      if (shiftData['has_shift'] == true) {
        _activeStoreID = shiftData['store_id'] ?? _activeStoreID;
        _organisasiID = shiftData['organisasi_id'] ?? _organisasiID;
        _isFnB = shiftData['is_fnb'] == true;
      }

      await _loadInvoices();
      if (mounted) setState(() => _isLoading = false);
    } catch (e, stack) {
      debugPrint('ERROR _loadData: $e');
      debugPrint('STACK: $stack');
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadInvoices() async {
    final dateFrom = _dateFrom.toIso8601String().substring(0, 10);
    final dateTo = _dateTo.toIso8601String().substring(0, 10);

    final invoices = await OrderService.getInvoices(
      userId: _userID,
      organisasiId: _organisasiID,
      storeId: _activeStoreID,
      dateFrom: dateFrom,
      dateTo: dateTo,
    );

    if (!mounted) return;

    setState(() {
      _invoices = invoices;
      _currentPage = 0;
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

      // Rebuild unique channel list dari data baru (unik per channel_id)
      final channelMap = <int, String>{};
      for (final inv in _invoices) {
        final id = inv['channel_id'] as int? ?? 0;
        final nama = (inv['sales_tipe'] ?? '').toString().trim();
        if (id > 0 && nama.isNotEmpty) channelMap[id] = nama;
      }
      _channelOptions = channelMap.entries
          .map((e) => {'id': e.key, 'nama': e.value})
          .toList()
        ..sort((a, b) =>
            (a['nama'] as String).compareTo(b['nama'] as String));
      // Reset pilihan kalau sudah tidak ada di list baru
      if (_selectedChannelId != null &&
          !channelMap.containsKey(_selectedChannelId)) {
        _selectedChannelId = null;
        _selectedChannelName = null;
      } else if (_selectedChannelId != null) {
        _selectedChannelName = channelMap[_selectedChannelId];
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
      return await OrderService.trackPrint(kode);
    } catch (_) {
      return 1; // fallback: anggap first print agar tidak crash
    }
  }

  // ── Ambil items + keterangan transaksi dari API ─────────────
  Future<Map<String, dynamic>> _fetchItems(int invoiceId) async {
    return await OrderService.getInvoiceDetail(invoiceId);
  }

  // ── Fetch store data berdasarkan store_id invoice ────────────
  //
  // PENTING: method ini sengaja menerima store_id dari invoice,
  // bukan dari _activeStoreID. Ini memastikan header struk selalu
  // menampilkan nama/alamat/logo store tempat transaksi terjadi,
  // tidak peduli user sedang open shift di store mana.
  Future<Map<String, dynamic>> _fetchStoreData(int storeId) async {
    try {
      return await StoreService.getStoreData(storeId);
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
      final storeName = invoice['store']?.toString() ?? '';
      final storeAddress = storeData['alamat']?.toString() ?? '';
      final storeNpwp = storeData['npwp']?.toString() ?? '';
      final invoiceNote = storeData['invoice_note']?.toString() ?? '';
      final logoFileName = storeData['logo_file_name']?.toString() ?? '';
      final logoUrl = storeData['logo_url']?.toString() ?? '';

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

  Future<void> _requestVoid(Map<String, dynamic> invoice) async {
    final TextEditingController otherCtrl = TextEditingController();
    String? selectedReason;
    String? errorMessage;

    const voidReasons = [
      'Salah Payment',
      'Salah Item',
      'Cancel Order',
      'Salah Channel',
      'Lainnya',
    ];

    final String? chosenReason = await showDialog<String>(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (ctx, setDialogState) => AlertDialog(
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          title: const Row(
            children: [
              Icon(Icons.warning_amber_rounded, color: Colors.red),
              SizedBox(width: 8),
              Text('Request Void',
                  style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'Invoice: ${invoice['kode']}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 12),
                const Text(
                  'Pilih alasan void:',
                  style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                ),
                const SizedBox(height: 4),
                RadioGroup<String>(
                  groupValue: selectedReason,
                  onChanged: (val) {
                    setDialogState(() {
                      selectedReason = val;
                      errorMessage = null;
                    });
                  },
                  child: Column(
                    children: voidReasons.map((reason) {
                      return InkWell(
                        onTap: () {
                          setDialogState(() {
                            selectedReason = reason;
                            errorMessage = null;
                          });
                        },
                        borderRadius: BorderRadius.circular(8),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 2),
                          child: Row(
                            children: [
                              Radio<String>(
                                value: reason,
                                activeColor: Colors.red,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                              ),
                              const SizedBox(width: 4),
                              Expanded(
                                child: Text(
                                  reason,
                                  style: const TextStyle(fontSize: 14),
                                ),
                              ),
                            ],
                          ),
                        ),
                      );
                    }).toList(),
                  ),
                ),
                if (selectedReason == 'Lainnya') ...[
                  const SizedBox(height: 8),
                  TextField(
                    controller: otherCtrl,
                    maxLines: 3,
                    autofocus: true,
                    decoration: const InputDecoration(
                      labelText: 'Keterangan Lainnya',
                      hintText: 'Masukkan keterangan alasan void...',
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                    ),
                    onChanged: (_) {
                      if (errorMessage != null) {
                        setDialogState(() {
                          errorMessage = null;
                        });
                      }
                    },
                  ),
                ],
                if (errorMessage != null) ...[
                  const SizedBox(height: 8),
                  Text(
                    errorMessage!,
                    style: const TextStyle(
                      color: Colors.red,
                      fontSize: 12,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, null),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () {
                if (selectedReason == null) {
                  setDialogState(() {
                    errorMessage = 'Pilih salah satu alasan void';
                  });
                  return;
                }
                if (selectedReason == 'Lainnya') {
                  final text = otherCtrl.text.trim();
                  if (text.isEmpty) {
                    setDialogState(() {
                      errorMessage = 'Keterangan lainnya tidak boleh kosong';
                    });
                    return;
                  }
                  Navigator.pop(ctx, text);
                } else {
                  Navigator.pop(ctx, selectedReason);
                }
              },
              child: const Text('Kirim Request',
                  style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      ),
    );

    otherCtrl.dispose();

    if (chosenReason == null || chosenReason.trim().isEmpty) return;
    final notes = chosenReason.trim();

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final invoiceId = int.tryParse(invoice['id']?.toString() ?? '') ?? 0;
      final res = await OrderService.voidInvoice(
        invoiceId: invoiceId,
        notes: notes,
        userId: _userID,
      );

      if (mounted) Navigator.pop(context);

      if (res['success'] == true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res['message'] ?? 'Request void berhasil dikirim!'),
              backgroundColor: Colors.red,
            ),
          );
        }
        await _loadInvoices(); // refresh list — invoice tetap muncul dgn badge "Request Void"
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
                content: Text(res['message'] ?? 'Gagal kirim request void')),
          );
        }
      }
    } catch (e) {
      if (mounted) Navigator.pop(context);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Error: $e')),
        );
      }
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
      _currentPage = 0;
    });
  }

  // ── Popup pilih channel ──────────────────────────────────────
  Future<void> _pickChannel() async {
    final picked = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Filter Channel',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1), // -1 = "Semua"
            child: Row(
              children: [
                Icon(Icons.all_inclusive,
                    size: 18,
                    color: _selectedChannelId == null
                        ? const Color(0xFF1D273B)
                        : Colors.grey),
                const SizedBox(width: 10),
                Text('Semua',
                    style: TextStyle(
                        fontWeight: _selectedChannelId == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: _selectedChannelId == null
                            ? const Color(0xFF1D273B)
                            : null)),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._channelOptions.map((ch) {
            final id = ch['id'] as int;
            final nama = ch['nama'] as String;
            final selected = _selectedChannelId == id;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, id),
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined,
                      size: 18,
                      color: selected ? const Color(0xFF1D273B) : Colors.grey),
                  const SizedBox(width: 10),
                  Text(nama,
                      style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: selected ? const Color(0xFF1D273B) : null)),
                  if (selected) ...[
                    const Spacer(),
                    const Icon(Icons.check, size: 16, color: Color(0xFF1D273B)),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );

    if (picked == null) return;
    setState(() {
      if (picked == -1) {
        _selectedChannelId = null;
        _selectedChannelName = null;
      } else {
        _selectedChannelId = picked;
        _selectedChannelName = _channelOptions
            .firstWhere((c) => c['id'] == picked)['nama'] as String;
      }
      _currentPage = 0;
    });
  }

  // ── Popup pilih outlet/store ──────────────────────────────────
  Future<void> _pickStore() async {
    final picked = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Filter Outlet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        children: [
          SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, -1), // -1 = "Semua"
            child: Row(
              children: [
                Icon(Icons.all_inclusive,
                    size: 18,
                    color: _selectedStoreId == null
                        ? const Color(0xFF1D273B)
                        : Colors.grey),
                const SizedBox(width: 10),
                Text('Semua Outlet',
                    style: TextStyle(
                        fontWeight: _selectedStoreId == null
                            ? FontWeight.bold
                            : FontWeight.normal,
                        color: _selectedStoreId == null
                            ? const Color(0xFF1D273B)
                            : null)),
              ],
            ),
          ),
          const Divider(height: 1),
          ..._storeOptions.map((s) {
            final id = int.parse(s['id'].toString());
            final nama = (s['nama'] ?? s['name'] ?? '').toString();
            final selected = _selectedStoreId == id;
            return SimpleDialogOption(
              onPressed: () => Navigator.pop(ctx, id),
              child: Row(
                children: [
                  Icon(Icons.storefront,
                      size: 18,
                      color: selected ? const Color(0xFF1D273B) : Colors.grey),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(nama,
                        style: TextStyle(
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
                            color: selected ? const Color(0xFF1D273B) : null)),
                  ),
                  if (selected) ...[
                    const SizedBox(width: 8),
                    const Icon(Icons.check, size: 16, color: Color(0xFF1D273B)),
                  ],
                ],
              ),
            );
          }),
        ],
      ),
    );

    if (picked == null) return;
    setState(() {
      if (picked == -1) {
        _selectedStoreId = null;
        _selectedStoreName = null;
      } else {
        _selectedStoreId = picked;
        String storeName = '';
        for (final s in _storeOptions) {
          if (int.tryParse(s['id']?.toString() ?? '') == picked) {
            storeName = (s['nama'] ?? s['name'] ?? '').toString();
            break;
          }
        }
        _selectedStoreName = storeName;
      }
      _currentPage = 0;
    });
  }

  // ── Label gabungan "Channel - Cara Bayar" (mis. "TAKEAWAY - EDC") ─
  String _channelCaraBayarLabel(Map<String, dynamic> inv) {
    final channel = (inv['sales_tipe'] ?? '').toString().trim();
    final caraBayar = (inv['cara_bayar'] ?? '').toString().trim();
    if (channel.isEmpty && caraBayar.isEmpty) return '-';
    if (channel.isEmpty) return caraBayar;
    if (caraBayar.isEmpty) return channel;
    return '$channel - $caraBayar';
  }

  String _fmtDate(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  // ── Reset semua filter ke default ───────────────────────────
  void _resetFilter() {
    final today = DateTime.now();
    setState(() {
      _dateFrom = today;
      _dateTo = today;
      _selectedCaraBayar = null;
      _selectedChannelId = null;
      _selectedChannelName = null;
      _selectedStoreId = null;
      _selectedStoreName = null;
      _searchCtrl.clear();
      _searchQuery = '';
      _currentPage = 0;
    });
    _loadInvoices();
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredInvoices;
    final paged = _pagedInvoices;
    final totalSum =
        filtered.fold(0.0, (sum, i) => sum + (i['total'] as num).toDouble());
    final avgTransaksi = filtered.isEmpty ? 0.0 : totalSum / filtered.length;
    final totalPages =
        filtered.isEmpty ? 1 : ((filtered.length - 1) ~/ _pageSize) + 1;
    final showingFrom = filtered.isEmpty ? 0 : _currentPage * _pageSize + 1;
    final showingTo = filtered.isEmpty
        ? 0
        : (_currentPage * _pageSize + paged.length);

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9),
      body: SafeArea(
        child: _isLoading
            ? const Center(child: CircularProgressIndicator())
            : Column(
                children: [
                  // ── Header navy ───────────────────────────────
                  Container(
                    color: const Color(0xFF1D273B),
                    padding: const EdgeInsets.fromLTRB(12, 8, 16, 12),
                    child: Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.arrow_back,
                              color: Colors.white),
                          onPressed: () => Navigator.pop(context),
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text('Invoice List',
                                  style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.bold)),
                              Text('Daftar transaksi penjualan',
                                  style: TextStyle(
                                      color:
                                          Colors.white.withValues(alpha: 0.6),
                                      fontSize: 12)),
                            ],
                          ),
                        ),
                        IconButton(
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          tooltip: 'Refresh',
                          onPressed: _loadInvoices,
                        ),
                      ],
                    ),
                  ),

                  // ── Konten putih ───────────────────────────────
                  Expanded(
                    child: filtered.isEmpty && !_hasActiveFilter
                        ? const Center(
                            child: Text('Tidak ada transaksi',
                                style: TextStyle(color: Colors.grey)))
                        : ListView(
                            padding: const EdgeInsets.all(16),
                            children: [
                              // Stat cards
                              LayoutBuilder(builder: (ctx, constraints) {
                                final isNarrow = constraints.maxWidth < 640;
                                final cards = [
                                  _statCard(
                                    icon: Icons.shopping_cart_outlined,
                                    iconBg: const Color(0xFF1D273B),
                                    label: 'Total Penjualan',
                                    value: 'Rp ${CurrencyFormat.format(totalSum)}',
                                  ),
                                  _statCard(
                                    icon: Icons.assignment_outlined,
                                    iconBg: const Color(0xFF1D273B),
                                    label: 'Total Invoice',
                                    value: '${filtered.length}',
                                    sub: 'Transaksi',
                                  ),
                                  _statCard(
                                    icon: Icons.show_chart,
                                    iconBg: const Color(0xFF1D273B),
                                    label: 'Rata-rata Transaksi',
                                    value: 'Rp ${CurrencyFormat.format(avgTransaksi)}',
                                  ),
                                  _statCard(
                                    icon: Icons.replay_circle_filled_outlined,
                                    iconBg: Colors.red.shade400,
                                    label: 'Refund / Pembatalan',
                                    value: 'Rp 0',
                                    sub: '0 Transaksi',
                                  ),
                                ];
                                if (isNarrow) {
                                  return Column(
                                    children: cards
                                        .map((c) => Padding(
                                              padding: const EdgeInsets.only(
                                                  bottom: 10),
                                              child: c,
                                            ))
                                        .toList(),
                                  );
                                }
                                return Row(
                                  children: cards
                                      .map((c) => Expanded(
                                            child: Padding(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 5),
                                              child: c,
                                            ),
                                          ))
                                      .toList(),
                                );
                              }),
                              const SizedBox(height: 16),

                              // Search & filter row
                              LayoutBuilder(builder: (ctx, constraints) {
                                final isNarrow = constraints.maxWidth < 780;
                                final searchField = _searchField();
                                final dateBtn = _dropdownLikeButton(
                                  icon: Icons.calendar_today,
                                  label:
                                      '${_fmtDate(_dateFrom)} - ${_fmtDate(_dateTo)}',
                                  onTap: _pickDateRange,
                                );
                                final caraBayarBtn = _dropdownLikeButton(
                                  icon: Icons.credit_card,
                                  label: _selectedCaraBayar ?? 'Semua Cara Bayar',
                                  onTap: _caraBayarOptions.isEmpty
                                      ? null
                                      : _pickCaraBayar,
                                );
                                final channelBtn = _dropdownLikeButton(
                                  icon: Icons.storefront_outlined,
                                  label: _selectedChannelName ?? 'Semua Channel',
                                  onTap:
                                      _channelOptions.isEmpty ? null : _pickChannel,
                                );
                                final storeBtn = _dropdownLikeButton(
                                  icon: Icons.store_outlined,
                                  label: _selectedStoreName ?? 'Semua Outlet',
                                  onTap: _storeOptions.length <= 1
                                      ? null
                                      : _pickStore,
                                );
                                final filterBtn = ElevatedButton.icon(
                                  onPressed: _loadInvoices,
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(0xFF1D273B),
                                    foregroundColor: Colors.white,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                  icon: const Icon(Icons.filter_alt_outlined,
                                      size: 16),
                                  label: const Text('Filter'),
                                );
                                final resetBtn = OutlinedButton(
                                  onPressed: _hasActiveFilter ? _resetFilter : null,
                                  style: OutlinedButton.styleFrom(
                                    foregroundColor: const Color(0xFF1D273B),
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 16, vertical: 14),
                                    shape: RoundedRectangleBorder(
                                        borderRadius:
                                            BorderRadius.circular(8)),
                                  ),
                                  child: const Text('Reset'),
                                );

                                if (isNarrow) {
                                  return Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.stretch,
                                    children: [
                                      searchField,
                                      const SizedBox(height: 8),
                                      dateBtn,
                                      const SizedBox(height: 8),
                                      caraBayarBtn,
                                      const SizedBox(height: 8),
                                      channelBtn,
                                      const SizedBox(height: 8),
                                      storeBtn,
                                      const SizedBox(height: 8),
                                      Row(
                                        children: [
                                          Expanded(child: filterBtn),
                                          const SizedBox(width: 8),
                                          Expanded(child: resetBtn),
                                        ],
                                      ),
                                    ],
                                  );
                                }

                                return Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(flex: 3, child: searchField),
                                    const SizedBox(width: 10),
                                    Expanded(flex: 2, child: dateBtn),
                                    const SizedBox(width: 10),
                                    Expanded(flex: 2, child: caraBayarBtn),
                                    const SizedBox(width: 10),
                                    Expanded(flex: 2, child: channelBtn),
                                    const SizedBox(width: 10),
                                    Expanded(flex: 2, child: storeBtn),
                                    const SizedBox(width: 10),
                                    filterBtn,
                                    const SizedBox(width: 8),
                                    resetBtn,
                                  ],
                                );
                              }),

                              // Active filter chips
                              if (_hasActiveFilter) ...[
                                const SizedBox(height: 12),
                                Wrap(
                                  crossAxisAlignment: WrapCrossAlignment.center,
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    const Text('Filter aktif:',
                                        style: TextStyle(
                                            color: Colors.grey, fontSize: 13)),
                                    _filterChip(
                                      'Tanggal: ${_fmtDate(_dateFrom)}'
                                      '${_dateFrom != _dateTo ? ' - ${_fmtDate(_dateTo)}' : ''}',
                                      onRemove: () {
                                        setState(() {
                                          _dateFrom = DateTime.now();
                                          _dateTo = DateTime.now();
                                          _currentPage = 0;
                                        });
                                        _loadInvoices();
                                      },
                                    ),
                                    _filterChip(
                                      'Cara Bayar: ${_selectedCaraBayar ?? 'Semua'}',
                                      onRemove: _selectedCaraBayar == null
                                          ? null
                                          : () => setState(() {
                                                _selectedCaraBayar = null;
                                                _currentPage = 0;
                                              }),
                                    ),
                                    _filterChip(
                                      'Channel: ${_selectedChannelName ?? 'Semua'}',
                                      onRemove: _selectedChannelId == null
                                          ? null
                                          : () => setState(() {
                                                _selectedChannelId = null;
                                                _selectedChannelName = null;
                                                _currentPage = 0;
                                              }),
                                    ),
                                    _filterChip(
                                      'Outlet: ${_selectedStoreName ?? 'Semua'}',
                                      onRemove: _selectedStoreId == null
                                          ? null
                                          : () => setState(() {
                                                _selectedStoreId = null;
                                                _selectedStoreName = null;
                                                _currentPage = 0;
                                              }),
                                    ),
                                    if (_searchQuery.trim().isNotEmpty)
                                      _filterChip(
                                        'Cari: "${_searchQuery.trim()}"',
                                        onRemove: () {
                                          _searchCtrl.clear();
                                        },
                                      ),
                                  ],
                                ),
                              ],

                              const SizedBox(height: 16),

                              // List
                              if (filtered.isEmpty)
                                const Padding(
                                  padding: EdgeInsets.symmetric(vertical: 40),
                                  child: Center(
                                    child: Text('Tidak ada transaksi yang cocok',
                                        style: TextStyle(color: Colors.grey)),
                                  ),
                                )
                              else
                                ...paged.map((inv) => _invoiceRow(inv)),

                              const SizedBox(height: 12),

                              // Pagination
                              if (filtered.isNotEmpty)
                                LayoutBuilder(builder: (ctx, constraints) {
                                  final isNarrow = constraints.maxWidth < 640;
                                  final showingText = Text(
                                    'Menampilkan $showingFrom - $showingTo dari ${filtered.length} transaksi',
                                    style: const TextStyle(
                                        color: Colors.grey, fontSize: 13),
                                  );
                                  final controls = Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      _pageSizeDropdown(),
                                      const SizedBox(width: 8),
                                      IconButton(
                                        icon: const Icon(Icons.chevron_left),
                                        onPressed: _currentPage > 0
                                            ? () => setState(
                                                () => _currentPage--)
                                            : null,
                                      ),
                                      Container(
                                        width: 32,
                                        height: 32,
                                        alignment: Alignment.center,
                                        decoration: BoxDecoration(
                                          color: const Color(0xFF1D273B),
                                          borderRadius:
                                              BorderRadius.circular(6),
                                        ),
                                        child: Text('${_currentPage + 1}',
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold)),
                                      ),
                                      IconButton(
                                        icon: const Icon(Icons.chevron_right),
                                        onPressed:
                                            _currentPage + 1 < totalPages
                                                ? () => setState(
                                                    () => _currentPage++)
                                                : null,
                                      ),
                                    ],
                                  );
                                  if (isNarrow) {
                                    return Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.center,
                                      children: [
                                        showingText,
                                        const SizedBox(height: 8),
                                        controls,
                                      ],
                                    );
                                  }
                                  return Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [showingText, controls],
                                  );
                                }),
                            ],
                          ),
                  ),
                ],
              ),
      ),
    );
  }

  // ── Widget: stat card ─────────────────────────────────────────
  Widget _statCard({
    required IconData icon,
    required Color iconBg,
    required String label,
    required String value,
    String? sub,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Row(
        children: [
          Container(
            width: 44,
            height: 44,
            decoration: BoxDecoration(
              color: iconBg,
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: Colors.white, size: 20),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(label,
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
                const SizedBox(height: 2),
                Text(value,
                    style: const TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1D273B)),
                    overflow: TextOverflow.ellipsis),
                if (sub != null)
                  Text(sub,
                      style: TextStyle(
                          color: Colors.grey.shade500, fontSize: 11)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  // ── Widget: search field ────────────────────────────────────
  Widget _searchField() {
    return TextField(
      controller: _searchCtrl,
      decoration: InputDecoration(
        hintText: 'Cari no invoice / customer / kasir',
        hintStyle: TextStyle(color: Colors.grey.shade400, fontSize: 13),
        prefixIcon: Icon(Icons.search, color: Colors.grey.shade400, size: 20),
        suffixIcon: _searchQuery.isEmpty
            ? null
            : IconButton(
                icon: Icon(Icons.close, color: Colors.grey.shade400, size: 18),
                onPressed: () => _searchCtrl.clear(),
              ),
        filled: true,
        fillColor: Colors.white,
        contentPadding:
            const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        enabledBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: BorderSide(color: Colors.grey.shade300),
        ),
        focusedBorder: OutlineInputBorder(
          borderRadius: BorderRadius.circular(8),
          borderSide: const BorderSide(color: Color(0xFF1D273B)),
        ),
      ),
    );
  }

  // ── Widget: tombol bergaya dropdown (buka dialog picker existing) ──
  Widget _dropdownLikeButton({
    required IconData icon,
    required String label,
    required VoidCallback? onTap,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: onTap == null ? Colors.grey.shade100 : Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(icon, size: 16, color: Colors.grey.shade600),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                label,
                style: TextStyle(fontSize: 13, color: Colors.grey.shade800),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            Icon(Icons.keyboard_arrow_down,
                size: 18, color: Colors.grey.shade500),
          ],
        ),
      ),
    );
  }

  // ── Widget: chip filter aktif ───────────────────────────────
  Widget _filterChip(String label, {VoidCallback? onRemove}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.grey.shade100,
        borderRadius: BorderRadius.circular(20),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label,
              style: TextStyle(color: Colors.grey.shade700, fontSize: 12)),
          if (onRemove != null) ...[
            const SizedBox(width: 6),
            InkWell(
              onTap: onRemove,
              child: Icon(Icons.close, size: 14, color: Colors.grey.shade500),
            ),
          ],
        ],
      ),
    );
  }

  // ── Widget: dropdown jumlah per halaman ─────────────────────
  Widget _pageSizeDropdown() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        border: Border.all(color: Colors.grey.shade300),
        borderRadius: BorderRadius.circular(8),
      ),
      child: DropdownButtonHideUnderline(
        child: DropdownButton<int>(
          value: _pageSize,
          isDense: true,
          items: _pageSizeOptions
              .map((n) => DropdownMenuItem(
                    value: n,
                    child: Text('$n / halaman',
                        style: const TextStyle(fontSize: 13)),
                  ))
              .toList(),
          onChanged: (v) {
            if (v == null) return;
            setState(() {
              _pageSize = v;
              _currentPage = 0;
            });
          },
        ),
      ),
    );
  }

  // ── Widget: satu baris invoice (full width) ─────────────────
  Widget _invoiceRow(Map<String, dynamic> inv) {
    final jam = inv['created_date'] != null &&
            inv['created_date'].toString().length >= 19
        ? inv['created_date'].toString().substring(11, 19)
        : (inv['created_date']?.toString().isNotEmpty == true
            ? inv['created_date'].toString()
            : '-');
    final tanggalRaw = inv['tanggal']?.toString() ?? '';
    String tanggalLabel = '';
    if (tanggalRaw.length >= 10) {
      final parts = tanggalRaw.substring(0, 10).split('-');
      if (parts.length == 3) tanggalLabel = '${parts[2]}/${parts[1]}/${parts[0]}';
    }

    // Invoice yang sedang menunggu approval void — tetap dihitung sebagai
    // transaksi valid, hanya tombol void diganti badge keterangan.
    final isPendingVoid = (inv['status'] ?? '').toString() == 'REQ VO';

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: isPendingVoid ? Colors.orange.withValues(alpha: 0.04) : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isPendingVoid ? Colors.orange.shade200 : Colors.grey.shade200,
        ),
      ),
      child: Row(
        children: [
          // Icon
          Container(
            width: 40,
            height: 40,
            decoration: BoxDecoration(
              color: const Color(0xFF1D273B),
              borderRadius: BorderRadius.circular(8),
            ),
            child: const Icon(Icons.description_outlined,
                color: Colors.white, size: 18),
          ),
          const SizedBox(width: 14),
          // Kode + store
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(inv['kode'] ?? '',
                    style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: Color(0xFF1D273B))),
                const SizedBox(height: 2),
                Text(inv['store'] ?? '',
                    style: TextStyle(
                        color: Colors.grey.shade600, fontSize: 12)),
              ],
            ),
          ),
          // Jam / tanggal
          Expanded(
            flex: 2,
            child: Row(
              children: [
                Icon(Icons.access_time,
                    size: 13, color: Colors.grey.shade400),
                const SizedBox(width: 4),
                Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(jam,
                        style: const TextStyle(
                            fontSize: 12, fontWeight: FontWeight.w600)),
                    if (tanggalLabel.isNotEmpty)
                      Text(tanggalLabel,
                          style: TextStyle(
                              fontSize: 11, color: Colors.grey.shade500)),
                  ],
                ),
              ],
            ),
          ),
          // Channel - cara bayar sebagai badge tunggal + kasir
          Expanded(
            flex: 3,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: Colors.deepPurple.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Text(_channelCaraBayarLabel(inv),
                      style: const TextStyle(
                          fontSize: 11,
                          color: Colors.deepPurple,
                          fontWeight: FontWeight.w600)),
                ),
                if ((inv['kasir'] ?? '').toString().isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 4),
                    child: Text('Kasir: ${inv['kasir']}',
                        style: TextStyle(
                            fontSize: 11, color: Colors.grey.shade500)),
                  ),
              ],
            ),
          ),
          // Total
          Expanded(
            flex: 2,
            child: Text(
              'Rp ${CurrencyFormat.format(inv['total'])}',
              textAlign: TextAlign.right,
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ),
          const SizedBox(width: 10),
          // Print button — dimatikan kalau invoice sedang REQ VO
          _squareIconButton(
            icon: Icons.print_outlined,
            tooltip: isPendingVoid
                ? 'Tidak bisa print — menunggu approval void'
                : (_isFnB ? 'Print Ulang' : 'Print'),
            enabled: !isPendingVoid,
            onPressed: () => _handlePrint(inv),
          ),
          const SizedBox(width: 8),
          // Request Void — disembunyikan & diganti badge kalau sudah REQ VO
          if (isPendingVoid)
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.orange.withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.orange.shade300),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.hourglass_top_rounded,
                      size: 14, color: Colors.orange.shade800),
                  const SizedBox(width: 5),
                  Text(
                    'Request Void',
                    style: TextStyle(
                        fontSize: 11,
                        fontWeight: FontWeight.w600,
                        color: Colors.orange.shade800),
                  ),
                ],
              ),
            )
          else
            _squareIconButton(
              icon: Icons.cancel_outlined,
              tooltip: 'Request Void',
              iconColor: Colors.red,
              onPressed: () => _requestVoid(inv),
            ),
        ],
      ),
    );
  }

  Widget _squareIconButton({
    required IconData icon,
    required String tooltip,
    required VoidCallback onPressed,
    Color iconColor = const Color(0xFF1D273B),
    bool enabled = true,
  }) {
    return Tooltip(
      message: tooltip,
      child: InkWell(
        onTap: enabled ? onPressed : null,
        borderRadius: BorderRadius.circular(8),
        child: Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            border: Border.all(
                color: enabled ? Colors.grey.shade300 : Colors.grey.shade200),
            borderRadius: BorderRadius.circular(8),
            color: enabled ? null : Colors.grey.shade50,
          ),
          child: Icon(icon, size: 18, color: enabled ? iconColor : Colors.grey.shade400),
        ),
      ),
    );
  }

}
