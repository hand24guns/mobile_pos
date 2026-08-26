import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/session_service.dart';
import '../services/api_service.dart';
import 'invoice_list_screen.dart';

// ─── Palette (sama dengan home_screen) ──────────────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A2F5A);
const Color _navyLight = Color(0xFF243B6E);
const Color _blue = Color(0xFF2563EB);
const Color _green = Color(0xFF22C55E);
const Color _bgGray = Color(0xFFF0F4FA);

class LaporanPembayaranScreen extends ConsumerStatefulWidget {
  const LaporanPembayaranScreen({super.key});

  @override
  ConsumerState<LaporanPembayaranScreen> createState() =>
      _LaporanPembayaranScreenState();
}

class _LaporanPembayaranScreenState
    extends ConsumerState<LaporanPembayaranScreen> {
  bool _isLoading = false;
  List<int> _outlets = [];

  // Filter outlet — 1 store dipilih sekaligus, sama seperti pola di
  // menu Laporan (OnhandReportScreen/ItemTerjualReportScreen/dst).
  List<Map<String, dynamic>> _stores = []; // [{id, nama}]
  int? _selectedStore;

  bool get _singleStore => _outlets.length <= 1;

  // Filter state
  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  // Data
  List<Map<String, dynamic>> _rows = [];
  int _totalFreq = 0;
  double _totalAmount = 0;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  Future<void> _loadSession() async {
    final session = await SessionService.getSession();
    if (!mounted) return;
    setState(() {
      _outlets = List<int>.from(session['outlets'] ?? []);
      _selectedStore = _outlets.isNotEmpty ? _outlets.first : null;
    });
    await _loadStores();
    _fetchData();
  }

  Future<void> _loadStores() async {
    try {
      final session = await SessionService.getSession();
      final token = session['token'] ?? '';
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/penjualan.php'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'action': 'getStores',
          'user_id': (session['user_id'] ?? '').toString(),
        },
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final raw = (data['stores'] ?? data['data'] ?? []) as List<dynamic>;
        setState(() {
          _stores = raw.map((e) {
            final m = e as Map<String, dynamic>;
            return {
              'id': m['id'] ?? m['dim_divisi_id'] ?? m['store_id'],
              'nama': m['nama'] ?? m['store_name'] ?? m['name'],
            };
          }).toList();
        });
      }
    } catch (_) {
      // Gagal ambil nama store — chip fallback tampilkan ID saja.
    }
  }

  String _storeName(int id) {
    final match = _stores.firstWhere(
      (s) => s['id'].toString() == id.toString(),
      orElse: () => {},
    );
    return (match['nama'] as String?) ?? 'Store $id';
  }

  Future<void> _pickStore() async {
    final picked = await showDialog<int?>(
      context: context,
      builder: (ctx) => SimpleDialog(
        title: const Text('Pilih Outlet',
            style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold)),
        children: _stores.map((s) {
          final id = s['id'] as int;
          final nama = s['nama'] as String;
          final selected = _selectedStore == id;
          return SimpleDialogOption(
            onPressed: () => Navigator.pop(ctx, id),
            child: Row(
              children: [
                Icon(Icons.storefront_outlined,
                    size: 18, color: selected ? _blue : Colors.grey),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(nama,
                      style: TextStyle(
                          fontWeight:
                              selected ? FontWeight.bold : FontWeight.normal,
                          color: selected ? _blue : null)),
                ),
                if (selected)
                  const Icon(Icons.check, size: 16, color: _blue),
              ],
            ),
          );
        }).toList(),
      ),
    );

    if (picked == null || picked == _selectedStore) return;
    setState(() => _selectedStore = picked);
    _fetchData();
  }

  Future<void> _fetchData() async {
    if (_selectedStore == null) return;
    setState(() => _isLoading = true);

    try {
      final session = await SessionService.getSession();
      final token = session['token'] ?? '';

      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/penjualan.php'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'action': 'getLaporanPembayaran',
          'store_ids': _selectedStore.toString(),
          'start_date': _fmtDate(_startDate),
          'end_date': _fmtDate(_endDate),
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final List rows = data['rows'] ?? [];
        int freq = 0;
        double amt = 0;
        for (final r in rows) {
          freq += _parseNum(r['jumlah']).toInt();
          amt += _parseNum(r['total']);
        }
        final sorted = List<Map<String, dynamic>>.from(rows)
          ..sort(
              (a, b) => _parseNum(b['total']).compareTo(_parseNum(a['total'])));
        setState(() {
          _rows = sorted;
          _totalFreq = freq;
          _totalAmount = amt;
        });
      } else {
        _rows = [];
        _totalFreq = 0;
        _totalAmount = 0;
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memuat data: $e'),
            backgroundColor: Colors.red[700],
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // PHP mengembalikan angka sebagai String di JSON — helper ini handle keduanya
  double _parseNum(dynamic v) {
    if (v == null) return 0;
    if (v is num) return v.toDouble();
    return double.tryParse(v.toString()) ?? 0;
  }

  String _fmtDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _fmtDateDisplay(DateTime d) =>
      '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';

  String _formatRupiah(double val) {
    if (val == 0) return 'Rp 0';
    final parts = val.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    return 'Rp $parts';
  }

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (ctx, child) => Theme(
        data: Theme.of(ctx).copyWith(
          colorScheme: const ColorScheme.light(
            primary: _blue,
            onPrimary: Colors.white,
          ),
        ),
        child: child!,
      ),
    );
    if (picked == null) return;
    setState(() {
      _startDate = picked.start;
      _endDate = picked.end;
    });
    _fetchData();
  }

  // ── Color per payment type ───────────────────────────────
  Color _rowAccent(int index) {
    const colors = [
      Color(0xFF2563EB),
      Color(0xFF22C55E),
      Color(0xFFF59E0B),
      Color(0xFFEC4899),
      Color(0xFF7C3AED),
      Color(0xFF06B6D4),
      Color(0xFFEF4444),
    ];
    return colors[index % colors.length];
  }

  // Drill-down: buka Invoice List sudah ter-filter ke cara bayar ini +
  // rentang tanggal yang sedang dipakai di laporan ini, supaya jumlah
  // transaksi yang tampil konsisten dengan angka di baris yang di-tap.
  void _openInvoiceList({required String caraBayar}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceListScreen(
          initialCaraBayarName: caraBayar,
          initialDateFrom: _startDate,
          initialDateTo: _endDate,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGray,
      body: Column(
        children: [
          _buildHeader(),
          _buildFilterBar(),
          Expanded(child: _buildBody()),
          _buildFooter(),
        ],
      ),
    );
  }

  // ── Header ───────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      decoration: const BoxDecoration(
        gradient: LinearGradient(
          colors: [_navy, _navyMid, _navyLight],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              GestureDetector(
                onTap: () => Navigator.pop(context),
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.arrow_back_ios_new_rounded,
                      color: Colors.white, size: 18),
                ),
              ),
              const SizedBox(width: 14),
              const Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Laporan Cara Bayar',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: 17,
                      ),
                    ),
                    SizedBox(height: 2),
                    Text(
                      'Rekap omset per metode pembayaran',
                      style: TextStyle(color: Colors.white60, fontSize: 12),
                    ),
                  ],
                ),
              ),
              // Refresh
              GestureDetector(
                onTap: _fetchData,
                child: Container(
                  width: 40,
                  height: 40,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(10),
                    border:
                        Border.all(color: Colors.white.withValues(alpha: 0.2)),
                  ),
                  child: const Icon(Icons.refresh_rounded,
                      color: Colors.white, size: 20),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Filter outlet & tanggal — 1 baris ────────────────────
  Widget _buildFilterBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Row(
        children: [
          const Icon(Icons.storefront_rounded, size: 16, color: _blue),
          const SizedBox(width: 6),
          Expanded(
            child: _singleStore
                ? Text(
                    _outlets.isNotEmpty ? _storeName(_outlets.first) : '-',
                    style: const TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: _navy),
                    overflow: TextOverflow.ellipsis,
                  )
                : _StoreChip(
                    label: _selectedStore != null
                        ? _storeName(_selectedStore!)
                        : 'Pilih Outlet',
                    onTap: _pickStore,
                  ),
          ),
          const SizedBox(width: 10),
          const Icon(Icons.calendar_today_rounded, size: 16, color: _blue),
          const SizedBox(width: 6),
          Expanded(
            child: _DateChip(
              label:
                  '${_fmtDateDisplay(_startDate)} – ${_fmtDateDisplay(_endDate)}',
              onTap: _pickDateRange,
            ),
          ),
        ],
      ),
    );
  }

  // ── Body ─────────────────────────────────────────────────
  Widget _buildBody() {
    if (_isLoading) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }

    if (_rows.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.credit_card_off_rounded,
                size: 64, color: Colors.grey[300]),
            const SizedBox(height: 12),
            Text('Tidak ada data',
                style: TextStyle(color: Colors.grey[400], fontSize: 15)),
            const SizedBox(height: 4),
            Text('Coba ubah periode tanggal',
                style: TextStyle(color: Colors.grey[400], fontSize: 12)),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _blue,
      onRefresh: _fetchData,
      child: ListView.separated(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 16),
        itemCount: _rows.length,
        separatorBuilder: (_, __) => const SizedBox(height: 10),
        itemBuilder: (ctx, i) {
          final r = _rows[i];
          final nama = r['nama']?.toString() ?? '-';
          final jumlah = _parseNum(r['jumlah']).toInt();
          final total = _parseNum(r['total']);
          final accent = _rowAccent(i);

          return GestureDetector(
            onTap: () => _openInvoiceList(caraBayar: nama),
            child: Container(
              decoration: BoxDecoration(
                color: Colors.white,
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.05),
                    blurRadius: 8,
                    offset: const Offset(0, 2),
                  ),
                ],
              ),
              child: Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        // Nomor
                        Container(
                          width: 28,
                          height: 28,
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.12),
                            shape: BoxShape.circle,
                          ),
                          child: Center(
                            child: Text(
                              '${i + 1}',
                              style: TextStyle(
                                color: accent,
                                fontWeight: FontWeight.bold,
                                fontSize: 12,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Expanded(
                          child: Text(
                            nama,
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15,
                              color: _navy,
                            ),
                          ),
                        ),
                        // Frekuensi badge
                        Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: accent.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(20),
                          ),
                          child: Text(
                            '$jumlah transaksi',
                            style: TextStyle(
                              color: accent,
                              fontWeight: FontWeight.w600,
                              fontSize: 11,
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        Text(
                          _formatRupiah(total),
                          style: const TextStyle(
                            color: _navy,
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                        ),
                        const SizedBox(width: 4),
                        Icon(Icons.chevron_right_rounded,
                            size: 18, color: Colors.grey[350]),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          );
        },
      ),
    );
  }

  // ── Footer total ─────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 10,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      padding: EdgeInsets.fromLTRB(
          20, 14, 20, MediaQuery.of(context).padding.bottom + 14),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Total Transaksi',
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  '$_totalFreq transaksi',
                  style: const TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Container(
            width: 1,
            height: 36,
            color: Colors.grey[200],
            margin: const EdgeInsets.symmetric(horizontal: 16),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('Total Omset',
                    style: TextStyle(color: Colors.grey, fontSize: 11)),
                const SizedBox(height: 2),
                Text(
                  _formatRupiah(_totalAmount),
                  style: const TextStyle(
                    color: _blue,
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ── Helper widget: store chip ────────────────────────────────
class _StoreChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _StoreChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.storefront_outlined, size: 14, color: _blue),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            const Icon(Icons.arrow_drop_down_rounded, size: 16, color: _blue),
          ],
        ),
      ),
    );
  }
}

// ── Helper widget: date chip ─────────────────────────────────
class _DateChip extends StatelessWidget {
  final String label;
  final VoidCallback onTap;

  const _DateChip({required this.label, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
        decoration: BoxDecoration(
          color: const Color(0xFFEFF6FF),
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: const Color(0xFFBFDBFE)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.calendar_month_rounded, size: 14, color: _blue),
            const SizedBox(width: 5),
            Flexible(
              child: Text(
                label,
                style: const TextStyle(
                  color: _blue,
                  fontWeight: FontWeight.w600,
                  fontSize: 12,
                ),
                overflow: TextOverflow.ellipsis,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
