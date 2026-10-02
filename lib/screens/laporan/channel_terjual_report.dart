import 'package:flutter/material.dart';
import '../../services/report_service.dart';
import '../../services/session_service.dart';
import '../../services/store_service.dart';
import '../invoice_list_screen.dart';

// ─── Palette ────────────────────────────────────────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);
const Color _green = Color(0xFF16A34A);
const Color _purple = Color(0xFF7C3AED);

/// Report Total Transaksi per Channel (salestipe) — rekap jumlah
/// transaksi (invoice) & total nominal per channel penjualan untuk
/// 1 store atau seluruh store yang bisa diakses user + rentang
/// tanggal, di-sort dari nominal terbesar lalu jumlah transaksi
/// terbanyak (urutan sudah dilakukan di backend).
/// - 1 store saja (session): langsung load otomatis (default rentang
///   tanggal: bulan berjalan) saat screen dibuka.
/// - >1 store: langsung load otomatis dalam mode "Semua Store"
///   (agregasi) saat screen dibuka — user tidak perlu pilih store
///   dulu untuk lihat reportnya. Begitu user memilih store tertentu
///   (atau balik ke "Semua Store") di dropdown, data langsung
///   di-load ulang (tanpa tombol "Proses"), sama seperti pola di
///   OnhandReportScreen / ItemTerjualReportScreen.
class ChannelTerjualReportScreen extends StatefulWidget {
  final List<int> outlets;

  const ChannelTerjualReportScreen({super.key, required this.outlets});

  @override
  State<ChannelTerjualReportScreen> createState() =>
      _ChannelTerjualReportScreenState();
}

class _ChannelTerjualReportScreenState
    extends State<ChannelTerjualReportScreen> {
  List<Map<String, dynamic>> _stores = []; // [{id, nama}]
  int? _selectedStore;
  bool _loadingData = false;
  bool _hasLoadedOnce = false;
  List<dynamic> _rows = [];
  Map<String, dynamic> _summary = {};
  String? _error;

  DateTime _startDate = DateTime.now();
  DateTime _endDate = DateTime.now();

  final TextEditingController _searchCtrl = TextEditingController();
  String _searchQuery = '';

  bool get _singleStore => widget.outlets.length == 1;

  @override
  void initState() {
    super.initState();
    _init();
    _searchCtrl.addListener(() {
      setState(() => _searchQuery = _searchCtrl.text.trim().toLowerCase());
    });
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    // Single store: langsung pakai store itu. Multi store: default ke
    // 0 ("Semua Store") supaya laporan agregat langsung tampil tanpa
    // user harus pilih store dulu.
    _selectedStore = _singleStore ? widget.outlets.first : 0;
    await _loadStores();
    _loadChannelTerjual();
  }

  // ============================================================
  // API CALLS
  // ============================================================
  Future<void> _loadStores() async {
    if (!mounted) return;
    try {
      final session = await SessionService.getSession();
      final userId = int.tryParse(session['user_id']?.toString() ?? '');
      final stores = await StoreService.getStores(userId: userId);
      if (!mounted) return;
      setState(() {
        _stores = stores;
      });
    } catch (_) {
      // Gagal ambil nama store — dropdown fallback tampilkan ID saja.
    }
  }

  Future<void> _loadChannelTerjual() async {
    if (_selectedStore == null) return;
    if (!mounted) return;
    setState(() {
      _loadingData = true;
      _error = null;
    });

    try {
      final result = await ReportService.getChannelTerjualReport(
        storeId: _selectedStore,
        startDate: _formatDate(_startDate),
        endDate: _formatDate(_endDate),
      );

      if (!mounted) return;
      if (result.success) {
        setState(() {
          _rows = result.items;
          _summary = result.summary;
          _hasLoadedOnce = true;
        });
      } else {
        setState(() {
          _error = result.message ?? 'Gagal memuat data channel terjual';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal terhubung ke server');
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  String _storeName(int id) {
    if (id == 0) return 'Semua Store';
    final match = _stores.firstWhere(
      (s) => s['id'].toString() == id.toString(),
      orElse: () => {},
    );
    return (match['nama'] as String?) ?? 'Store $id';
  }

  // Opsi "Semua Store" (id 0) selalu ditaruh paling atas, diikuti
  // store satu-satu — dipakai di dropdown compact toolbar & portrait
  // header supaya user multi-outlet bisa balik ke mode agregat kapan
  // saja tanpa harus keluar dari filter.
  List<DropdownMenuItem<int>> _storeDropdownItems() {
    return [
      const DropdownMenuItem(value: 0, child: Text('Semua Store')),
      ...widget.outlets.map((id) => DropdownMenuItem(
            value: id,
            child: Text(_storeName(id), overflow: TextOverflow.ellipsis),
          )),
    ];
  }

  String _twoDigits(int n) => n.toString().padLeft(2, '0');

  String _formatDate(DateTime d) =>
      '${d.year}-${_twoDigits(d.month)}-${_twoDigits(d.day)}';

  String _formatDateShort(DateTime d) =>
      '${_twoDigits(d.day)}/${_twoDigits(d.month)}';

  String _formatNumber(num val) {
    return val.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  String _formatCurrency(num val) => 'Rp ${_formatNumber(val)}';

  Future<void> _pickDateRange() async {
    final picked = await showDateRangePicker(
      context: context,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
      initialDateRange: DateTimeRange(start: _startDate, end: _endDate),
      builder: (context, child) => Theme(
        data: Theme.of(context).copyWith(
          colorScheme: Theme.of(context).colorScheme.copyWith(primary: _blue),
        ),
        child: child!,
      ),
    );
    if (picked != null) {
      setState(() {
        _startDate = picked.start;
        _endDate = picked.end;
      });
      if (_selectedStore != null) _loadChannelTerjual();
    }
  }

  // Hasil dari backend SUDAH terurut (nominal terbesar → jumlah
  // transaksi terbanyak); search hanya menyaring tanpa mengubah urutan.
  List<dynamic> get _filteredRows {
    if (_searchQuery.isEmpty) return _rows;
    return _rows.where((r) {
      final item = r as Map<String, dynamic>;
      final channel = (item['channel'] ?? '').toString().toLowerCase();
      return channel.contains(_searchQuery);
    }).toList();
  }

  // ============================================================
  // BUILD
  // ============================================================
  // Ambang batas "compact": tablet 7" landscape yang kepotong navigation
  // bar 3-tombol biasanya menyisakan tinggi < 600px untuk body konten.
  static const double _compactHeightBreakpoint = 600;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < _compactHeightBreakpoint;
      return Container(
        color: _bgGray,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) _buildCompactToolbar() else _buildPortraitHeader(),
            Expanded(child: _buildBody(compact: compact)),
          ],
        ),
      );
    });
  }

  // ── Compact toolbar (height-constrained layout) ─────────────
  Widget _buildCompactToolbar() {
    final showStats = _hasLoadedOnce && _error == null;
    final totalChannel =
        (_summary['total_channel'] as num?)?.toInt() ?? _rows.length;
    final totalTransaksi = (_summary['total_transaksi'] as num?) ?? 0;
    final totalNominal = (_summary['total_nominal'] as num?) ?? 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _buildCompactStoreField(),
          const SizedBox(width: 8),
          _buildCompactDateField(),
          if (_loadingData) ...[
            const SizedBox(width: 10),
            const SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: _blue),
            ),
          ],
          if (showStats) ...[
            const SizedBox(width: 12),
            _MiniStat(
              icon: Icons.storefront_outlined,
              color: _blue,
              label: 'Channel',
              value: _formatNumber(totalChannel),
            ),
            const SizedBox(width: 8),
            _MiniStat(
              icon: Icons.receipt_long_outlined,
              color: _green,
              label: 'Transaksi',
              value: _formatNumber(totalTransaksi),
            ),
            const SizedBox(width: 8),
            _MiniStat(
              icon: Icons.payments_outlined,
              color: _purple,
              label: 'Nominal',
              value: _formatCurrency(totalNominal),
            ),
          ],
          const SizedBox(width: 12),
          Expanded(child: _buildCompactSearchField()),
        ],
      ),
    );
  }

  Widget _buildCompactStoreField() {
    return Container(
      height: 40,
      constraints: const BoxConstraints(minWidth: 130, maxWidth: 200),
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: _singleStore ? _bgGray : Colors.white,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, size: 16, color: Colors.grey[600]),
          const SizedBox(width: 6),
          Expanded(
            child: _singleStore
                ? Text(
                    widget.outlets.isNotEmpty
                        ? _storeName(widget.outlets.first)
                        : '-',
                    style: const TextStyle(
                        fontSize: 13, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      isDense: true,
                      value: _selectedStore,
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600),
                      items: _storeDropdownItems(),
                      onChanged: (val) {
                        setState(() => _selectedStore = val);
                        _loadChannelTerjual();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildCompactDateField() {
    return InkWell(
      onTap: _pickDateRange,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(8),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.date_range_rounded, size: 16, color: Colors.grey[600]),
            const SizedBox(width: 6),
            Text(
              '${_formatDateShort(_startDate)} - ${_formatDateShort(_endDate)}',
              style: const TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildCompactSearchField() {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: _bgGray,
        borderRadius: BorderRadius.circular(8),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(fontSize: 13),
        decoration: InputDecoration(
          hintText: 'Cari channel...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 13),
          prefixIcon: Icon(Icons.search, size: 18, color: Colors.grey[400]),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
        ),
      ),
    );
  }

  // ── Portrait header: 5 baris ─────────────────────────────────
  // Row 1: Store (dropdown bila akses banyak store)
  // Row 2: Rentang tanggal
  // Row 3: Total Channel + Total Transaksi berdampingan
  // Row 4: Total Nominal
  // Row 5: Search box
  Widget _buildPortraitHeader() {
    final showStats = _hasLoadedOnce && _error == null;
    final totalChannel =
        (_summary['total_channel'] as num?)?.toInt() ?? _rows.length;
    final totalTransaksi = (_summary['total_transaksi'] as num?) ?? 0;
    final totalNominal = (_summary['total_nominal'] as num?) ?? 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // Row 1: Store
          Row(
            children: [
              Expanded(child: _buildStoreField()),
              if (_loadingData) ...[
                const SizedBox(width: 10),
                const SizedBox(
                  width: 18,
                  height: 18,
                  child:
                      CircularProgressIndicator(strokeWidth: 2, color: _blue),
                ),
              ],
            ],
          ),
          const SizedBox(height: 10),
          // Row 2: Rentang tanggal
          _buildDateField(),
          if (showStats) ...[
            const SizedBox(height: 10),
            // Row 3: Total Channel & Total Transaksi
            Row(
              children: [
                Expanded(
                  child: _HeaderStat(
                    icon: Icons.storefront_outlined,
                    color: _blue,
                    label: 'Total Channel',
                    value: _formatNumber(totalChannel),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeaderStat(
                    icon: Icons.receipt_long_outlined,
                    color: _green,
                    label: 'Total Transaksi',
                    value: _formatNumber(totalTransaksi),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Row 4: Total Nominal
            _HeaderStat(
              icon: Icons.payments_outlined,
              color: _purple,
              label: 'Total Nominal',
              value: _formatCurrency(totalNominal),
              fullWidth: true,
            ),
            const SizedBox(height: 10),
            // Row 5: Search box
            _buildSearchField(),
          ],
        ],
      ),
    );
  }

  Widget _buildStoreField() {
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: 12),
      decoration: BoxDecoration(
        color: _singleStore ? _bgGray : Colors.white,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: Row(
        children: [
          Icon(Icons.storefront_outlined, size: 18, color: Colors.grey[600]),
          const SizedBox(width: 8),
          Expanded(
            child: _singleStore
                ? Text(
                    widget.outlets.isNotEmpty
                        ? _storeName(widget.outlets.first)
                        : '-',
                    style: const TextStyle(
                        fontSize: 14, fontWeight: FontWeight.w600),
                    overflow: TextOverflow.ellipsis,
                  )
                : DropdownButtonHideUnderline(
                    child: DropdownButton<int>(
                      isExpanded: true,
                      isDense: true,
                      value: _selectedStore,
                      style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600),
                      items: _storeDropdownItems(),
                      onChanged: (val) {
                        setState(() => _selectedStore = val);
                        _loadChannelTerjual();
                      },
                    ),
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildDateField() {
    return InkWell(
      onTap: _pickDateRange,
      borderRadius: BorderRadius.circular(10),
      child: Container(
        height: 44,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: Colors.grey.shade300),
        ),
        child: Row(
          children: [
            Icon(Icons.date_range_rounded, size: 18, color: Colors.grey[600]),
            const SizedBox(width: 8),
            Text(
              '${_formatDate(_startDate)}  s/d  ${_formatDate(_endDate)}',
              style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
            ),
            const Spacer(),
            Icon(Icons.arrow_drop_down_rounded, color: Colors.grey[500]),
          ],
        ),
      ),
    );
  }

  Widget _buildSearchField() {
    return Container(
      height: 44,
      decoration: BoxDecoration(
        color: _bgGray,
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: TextField(
        controller: _searchCtrl,
        style: const TextStyle(fontSize: 14),
        decoration: InputDecoration(
          hintText: 'Cari channel...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[400]),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildBody({bool compact = false}) {
    if (_loadingData && !_hasLoadedOnce) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }
    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded, size: 40, color: Colors.red[300]),
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            TextButton(
                onPressed: _loadChannelTerjual, child: const Text('Coba Lagi')),
          ],
        ),
      );
    }
    if (!_hasLoadedOnce) {
      // Baik single maupun multi store sekarang langsung di-load saat
      // screen dibuka (multi store default ke mode "Semua Store"),
      // jadi state ini hanya transisi singkat sebelum data pertama masuk.
      return Center(
        child: Text('Memuat data...', style: TextStyle(color: Colors.grey[500])),
      );
    }

    final filtered = _filteredRows;

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.pie_chart_rounded, size: 40, color: Colors.grey[350]),
            const SizedBox(height: 8),
            Text(
              _rows.isEmpty
                  ? 'Tidak ada transaksi di rentang tanggal ini'
                  : 'Tidak ada channel yang cocok',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _blue,
      onRefresh: _loadChannelTerjual,
      child: ListView.separated(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(compact ? 8 : 16),
        itemCount: filtered.length,
        separatorBuilder: (_, __) => SizedBox(height: compact ? 6 : 10),
        itemBuilder: (context, i) =>
            _buildRowCard(filtered[i] as Map<String, dynamic>, i, compact),
      ),
    );
  }

  // ── Warna aksen per baris (rotasi), sama seperti pola di
  // LaporanPembayaranScreen — biar tampilan tabel konsisten di semua
  // laporan.
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

  Widget _buildRowCard(Map<String, dynamic> item, int i, bool compact) {
    final channel = '${item['channel'] ?? ''}';
    final channelId = (item['dim_salestipe_id'] as num?)?.toInt();
    final jumlahTransaksi = (item['jumlah_transaksi'] as num?) ?? 0;
    final totalNominal = (item['total_nominal'] as num?) ?? 0;
    final accent = _rowAccent(i);

    return GestureDetector(
      onTap: () => _openInvoiceList(channelId: channelId, channel: channel),
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
        padding: EdgeInsets.symmetric(
            horizontal: 16, vertical: compact ? 10 : 12),
        child: Row(
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
                      color: accent, fontWeight: FontWeight.bold, fontSize: 12),
                ),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Text(
                channel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    fontWeight: FontWeight.bold, fontSize: 15, color: _navy),
              ),
            ),
            // Badge jumlah transaksi
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
              decoration: BoxDecoration(
                color: accent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Text(
                '${_formatNumber(jumlahTransaksi)} transaksi',
                style: TextStyle(
                    color: accent, fontWeight: FontWeight.w600, fontSize: 11),
              ),
            ),
            const SizedBox(width: 10),
            Text(
              _formatCurrency(totalNominal),
              style: const TextStyle(
                  color: _navy, fontWeight: FontWeight.bold, fontSize: 14),
            ),
            const SizedBox(width: 4),
            Icon(Icons.chevron_right_rounded, size: 18, color: Colors.grey[350]),
          ],
        ),
      ),
    );
  }

  // Drill-down: buka Invoice List sudah ter-filter ke channel ini +
  // rentang tanggal yang sedang dipakai di laporan ini, supaya jumlah
  // transaksi yang tampil konsisten dengan angka di baris yang di-tap.
  void _openInvoiceList({required int? channelId, required String channel}) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => InvoiceListScreen(
          initialChannelId: channelId,
          initialChannelName: channel,
          initialDateFrom: _startDate,
          initialDateTo: _endDate,
        ),
      ),
    );
  }
}

// ─── Mini stat chip (dipakai di compact toolbar) ────────────
class _MiniStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;

  const _MiniStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 6),
          Text(value,
              style: const TextStyle(
                  fontWeight: FontWeight.w700, fontSize: 13, color: _navy)),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(fontSize: 11, color: Colors.grey[600])),
        ],
      ),
    );
  }
}

// ─── Header stat chip (dipakai di portrait header) ──
class _HeaderStat extends StatelessWidget {
  final IconData icon;
  final Color color;
  final String label;
  final String value;
  final bool fullWidth;

  const _HeaderStat({
    required this.icon,
    required this.color,
    required this.label,
    required this.value,
    this.fullWidth = false,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: fullWidth ? double.infinity : null,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 8),
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10.5, color: Colors.grey[600]),
                ),
                const SizedBox(height: 2),
                Text(
                  value,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700, color: _navy),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
