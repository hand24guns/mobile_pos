import 'package:flutter/material.dart';
import '../../services/report_service.dart';
import '../../services/session_service.dart';
import '../../services/store_service.dart';

// ─── Palette ────────────────────────────────────────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);
const Color _green = Color(0xFF16A34A);
const Color _purple = Color(0xFF7C3AED);

/// Report Item Terjual — rekap qty & netto terjual per produk untuk
/// rentang tanggal, di-sort dari qty terbanyak.
/// - 1 store saja (session): langsung load otomatis (default rentang
///   tanggal: bulan berjalan) saat screen dibuka.
/// - >1 store: begitu dibuka langsung load agregat "Semua Outlet"
///   (store_id 0) tanpa harus pilih dulu. User bisa filter ke 1 store
///   spesifik lewat dropdown, atau balik lagi ke "Semua Outlet" — sama
///   seperti pola di OnhandReportScreen. Setiap ganti pilihan data
///   langsung di-load ulang (tanpa tombol "Proses").
class ItemTerjualReportScreen extends StatefulWidget {
  final List<int> outlets;

  const ItemTerjualReportScreen({super.key, required this.outlets});

  @override
  State<ItemTerjualReportScreen> createState() =>
      _ItemTerjualReportScreenState();
}

class _ItemTerjualReportScreenState extends State<ItemTerjualReportScreen> {
  List<Map<String, dynamic>> _stores = []; // [{id, nama}]
  int? _selectedStore;
  bool _loadingData = false;
  bool _hasLoadedOnce = false;
  List<dynamic> _rows = [];
  Map<String, dynamic> _summary = {};
  String? _error;

  // Penggunaan box/kemasan (tr_invoice_kemasan) — di-load bersamaan
  // dengan item terjual, tapi errornya terpisah supaya kegagalan box
  // tidak menutupi data penjualan.
  List<dynamic> _boxRows = [];
  Map<String, dynamic> _boxSummary = {};
  String? _boxError;

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
    // 1 store: langsung pakai store itu. >1 store: default ke "Semua
    // Outlet" (store_id 0 -> backend agregasikan semua store yang bisa
    // diakses user), sama seperti pola default di OnhandReportScreen.
    _selectedStore = _singleStore ? widget.outlets.first : 0;
    await _loadStores();
    _loadItemTerjual();
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

  Future<void> _loadItemTerjual() async {
    if (_selectedStore == null) return;
    if (!mounted) return;
    setState(() {
      _loadingData = true;
      _error = null;
      _boxError = null;
    });

    final start = _formatDate(_startDate);
    final end = _formatDate(_endDate);

    // Box dimuat paralel; kegagalannya ditangani sendiri (tidak throw).
    final boxFuture = _loadBoxTerpakai(start, end);

    try {
      final result = await ReportService.getItemTerjualReport(
        storeId: _selectedStore,
        startDate: start,
        endDate: end,
      );
      await boxFuture;

      if (!mounted) return;
      if (result.success) {
        setState(() {
          _rows = result.items;
          _summary = result.summary;
          _hasLoadedOnce = true;
        });
      } else {
        setState(() {
          _error = result.message ?? 'Gagal memuat data item terjual';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _error = 'Gagal terhubung ke server');
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  Future<void> _loadBoxTerpakai(String start, String end) async {
    try {
      final result = await ReportService.getKemasanTerpakaiReport(
        storeId: _selectedStore,
        startDate: start,
        endDate: end,
      );
      if (!mounted) return;
      setState(() {
        if (result.success) {
          _boxRows = result.items;
          _boxSummary = result.summary;
        } else {
          _boxRows = [];
          _boxSummary = {};
          _boxError = result.message ?? 'Gagal memuat penggunaan box';
        }
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _boxRows = [];
        _boxSummary = {};
        _boxError = 'Gagal terhubung ke server';
      });
    }
  }

  String _storeName(int id) {
    if (id == 0) return 'Semua Outlet';
    final match = _stores.firstWhere(
      (s) => s['id'].toString() == id.toString(),
      orElse: () => {},
    );
    return (match['nama'] as String?) ?? 'Store $id';
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
      if (_selectedStore != null) _loadItemTerjual();
    }
  }

  List<dynamic> _applySearch(List<dynamic> source) {
    if (_searchQuery.isEmpty) return source;
    return source.where((r) {
      final item = r as Map<String, dynamic>;
      final kode = (item['kode'] ?? '').toString().toLowerCase();
      final nama = (item['nama'] ?? '').toString().toLowerCase();
      return kode.contains(_searchQuery) || nama.contains(_searchQuery);
    }).toList();
  }

  List<dynamic> get _filteredRows => _applySearch(_rows);
  List<dynamic> get _filteredBoxRows => _applySearch(_boxRows);

  // ============================================================
  // BUILD
  // ============================================================
  // Ambang batas "compact": tablet 7" landscape yang kepotong navigation
  // bar 3-tombol biasanya menyisakan tinggi < 600px untuk body konten.
  static const double _compactHeightBreakpoint = 600;

  // Ambang batas "split": lebar cukup (tablet / landscape) -> Item
  // Terjual di kiri, Penggunaan Box di kanan. Di bawah itu (portrait)
  // card ditumpuk vertikal dalam 1 scroll view.
  static const double _splitWidthBreakpoint = 720;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, constraints) {
      final compact = constraints.maxHeight < _compactHeightBreakpoint;
      final split = constraints.maxWidth >= _splitWidthBreakpoint;
      return Container(
        color: _bgGray,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (compact) _buildCompactToolbar() else _buildPortraitHeader(),
            Expanded(child: _buildBody(compact: compact, split: split)),
          ],
        ),
      );
    });
  }

  // ── Compact toolbar (height-constrained layout) ─────────────
  Widget _buildCompactToolbar() {
    final showStats = _hasLoadedOnce && _error == null;
    final totalItem = (_summary['total_item'] as num?)?.toInt() ?? _rows.length;
    final totalQty = (_summary['total_qty'] as num?) ?? 0;
    final totalNetto = (_summary['total_netto'] as num?) ?? 0;

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
              icon: Icons.inventory_2_outlined,
              color: _blue,
              label: 'Item',
              value: _formatNumber(totalItem),
            ),
            const SizedBox(width: 8),
            _MiniStat(
              icon: Icons.trending_up_rounded,
              color: _green,
              label: 'Qty',
              value: _formatNumber(totalQty),
            ),
            const SizedBox(width: 8),
            _MiniStat(
              icon: Icons.payments_outlined,
              color: _purple,
              label: 'Netto',
              value: _formatCurrency(totalNetto),
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
                      hint: const Text('Pilih Store',
                          style: TextStyle(fontSize: 13)),
                      style: const TextStyle(
                          fontSize: 13,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600),
                      items: [
                        const DropdownMenuItem(
                          value: 0,
                          child: Text('Semua Outlet',
                              overflow: TextOverflow.ellipsis),
                        ),
                        ...widget.outlets.map((id) => DropdownMenuItem(
                              value: id,
                              child: Text(_storeName(id),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedStore = val);
                        if (val != null) _loadItemTerjual();
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
          hintText: 'Cari produk / kode...',
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
  // Row 3: Total Item (SKU) + Total Qty berdampingan
  // Row 4: Total Netto
  // Row 5: Search box
  Widget _buildPortraitHeader() {
    final showStats = _hasLoadedOnce && _error == null;
    final totalItem = (_summary['total_item'] as num?)?.toInt() ?? _rows.length;
    final totalQty = (_summary['total_qty'] as num?) ?? 0;
    final totalNetto = (_summary['total_netto'] as num?) ?? 0;

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
            // Row 3: Total Item (SKU) & Total Qty
            Row(
              children: [
                Expanded(
                  child: _HeaderStat(
                    icon: Icons.inventory_2_outlined,
                    color: _blue,
                    label: 'Total Item (SKU)',
                    value: _formatNumber(totalItem),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: _HeaderStat(
                    icon: Icons.trending_up_rounded,
                    color: _green,
                    label: 'Total Qty Terjual',
                    value: _formatNumber(totalQty),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Row 4: Total Netto
            _HeaderStat(
              icon: Icons.payments_outlined,
              color: _purple,
              label: 'Total Netto',
              value: _formatCurrency(totalNetto),
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
                      hint: const Text('Pilih Store',
                          style: TextStyle(fontSize: 14)),
                      style: const TextStyle(
                          fontSize: 14,
                          color: Colors.black87,
                          fontWeight: FontWeight.w600),
                      items: [
                        const DropdownMenuItem(
                          value: 0,
                          child: Text('Semua Outlet',
                              overflow: TextOverflow.ellipsis),
                        ),
                        ...widget.outlets.map((id) => DropdownMenuItem(
                              value: id,
                              child: Text(_storeName(id),
                                  overflow: TextOverflow.ellipsis),
                            )),
                      ],
                      onChanged: (val) {
                        setState(() => _selectedStore = val);
                        if (val != null) _loadItemTerjual();
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
          hintText: 'Cari produk / kode...',
          hintStyle: TextStyle(color: Colors.grey[400], fontSize: 14),
          prefixIcon: Icon(Icons.search, size: 20, color: Colors.grey[400]),
          border: InputBorder.none,
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 12),
        ),
      ),
    );
  }

  Widget _buildBody({bool compact = false, bool split = false}) {
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
                onPressed: _loadItemTerjual, child: const Text('Coba Lagi')),
          ],
        ),
      );
    }
    if (!_hasLoadedOnce) {
      return Center(
        child: Text(
          'Memuat data...',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    final salesPanel = _buildPanel(
      title: 'Item Terjual',
      icon: Icons.trending_up_rounded,
      color: _blue,
      subtitle: '${_formatNumber(_rows.length)} item',
      rows: _filteredRows,
      totalRows: _rows.length,
      emptyText: 'Tidak ada item terjual di rentang tanggal ini',
      compact: compact,
      scrollable: split,
      rowBuilder: (item, i) => _buildRowCard(item, i, compact),
    );

    final boxQty = (_boxSummary['total_qty'] as num?) ?? 0;
    final boxPanel = _buildPanel(
      title: 'Penggunaan Box',
      icon: Icons.inventory_2_outlined,
      color: _purple,
      subtitle: '${_formatNumber(boxQty)} box terpakai',
      rows: _filteredBoxRows,
      totalRows: _boxRows.length,
      emptyText: 'Tidak ada penggunaan box di rentang tanggal ini',
      error: _boxError,
      compact: compact,
      scrollable: split,
      rowBuilder: (item, i) => _buildRowCard(
        item,
        i,
        compact,
        valueKey: 'total_hpp',
        qtyLabel: 'box',
        hideZeroValue: true,
      ),
    );

    final pad = compact ? 8.0 : 16.0;

    if (split) {
      // Tablet / landscape: kiri = item terjual, kanan = penggunaan box.
      // Tiap card scroll sendiri; pull-to-refresh ada di dalam masing-masing.
      return Padding(
        padding: EdgeInsets.all(pad),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Expanded(child: salesPanel),
            SizedBox(width: pad),
            Expanded(child: boxPanel),
          ],
        ),
      );
    }

    // Portrait: 1 view, card penjualan di atas, card box di bawahnya.
    return RefreshIndicator(
      color: _blue,
      onRefresh: _loadItemTerjual,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: EdgeInsets.all(pad),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            salesPanel,
            SizedBox(height: pad),
            boxPanel,
          ],
        ),
      ),
    );
  }

  // ── Panel/card: header (judul + ringkasan) + daftar baris ────
  // scrollable = true  -> list scroll sendiri (butuh tinggi terbatas,
  //                       dipakai di mode split).
  // scrollable = false -> list ikut scroll halaman (portrait).
  Widget _buildPanel({
    required String title,
    required IconData icon,
    required Color color,
    required String subtitle,
    required List<dynamic> rows,
    required int totalRows,
    required String emptyText,
    required bool compact,
    required bool scrollable,
    required Widget Function(Map<String, dynamic> item, int index) rowBuilder,
    String? error,
  }) {
    final gap = SizedBox(height: compact ? 6 : 10);

    Widget content;
    if (error != null) {
      content = _panelMessage(Icons.error_outline_rounded, error,
          iconColor: Colors.red[300]);
    } else if (rows.isEmpty) {
      content = _panelMessage(
        Icons.inbox_outlined,
        totalRows == 0 ? emptyText : 'Tidak ada produk yang cocok',
      );
    } else if (scrollable) {
      content = RefreshIndicator(
        color: _blue,
        onRefresh: _loadItemTerjual,
        child: ListView.separated(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: EdgeInsets.all(compact ? 10 : 14),
          itemCount: rows.length,
          separatorBuilder: (_, __) => gap,
          itemBuilder: (context, i) =>
              rowBuilder(rows[i] as Map<String, dynamic>, i),
        ),
      );
    } else {
      content = ListView.separated(
        shrinkWrap: true,
        physics: const NeverScrollableScrollPhysics(),
        padding: const EdgeInsets.all(14),
        itemCount: rows.length,
        separatorBuilder: (_, __) => gap,
        itemBuilder: (context, i) =>
            rowBuilder(rows[i] as Map<String, dynamic>, i),
      );
    }

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(20),
        boxShadow: [
          BoxShadow(
            color: _navy.withValues(alpha: 0.06),
            blurRadius: 16,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        mainAxisSize: scrollable ? MainAxisSize.max : MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: EdgeInsets.fromLTRB(16, compact ? 12 : 16, 16, 12),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(icon, size: 18, color: color),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    title,
                    style: const TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w700,
                        color: _navy),
                  ),
                ),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: color.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    subtitle,
                    style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.w600,
                        color: color),
                  ),
                ),
              ],
            ),
          ),
          Divider(height: 1, color: Colors.grey.shade200),
          if (scrollable) Expanded(child: content) else content,
        ],
      ),
    );
  }

  Widget _panelMessage(IconData icon, String text, {Color? iconColor}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32, horizontal: 16),
      child: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 36, color: iconColor ?? Colors.grey[350]),
            const SizedBox(height: 8),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      ),
    );
  }

  // ── Warna aksen per baris (rotasi), sama seperti pola di
  // LaporanPembayaranScreen / ChannelTerjualReportScreen — biar
  // tampilan tabel konsisten di semua laporan.
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

  // Dipakai untuk baris item terjual (default) dan penggunaan box
  // (valueKey: 'total_hpp', qtyLabel: 'box'). hideZeroValue menyembunyikan
  // nominal kalau 0 (hpp box sering belum diisi).
  Widget _buildRowCard(
    Map<String, dynamic> item,
    int i,
    bool compact, {
    String valueKey = 'netto',
    String qtyLabel = 'qty',
    bool hideZeroValue = false,
  }) {
    final nama = '${item['nama'] ?? ''}';
    final kode = '${item['kode'] ?? ''}';
    final qty = (item['qty'] as num?) ?? 0;
    final netto = (item[valueKey] as num?) ?? 0;
    final showValue = !(hideZeroValue && netto == 0);
    final accent = _rowAccent(i);

    // Baris flat (tanpa shadow) karena sudah berada di dalam card besar.
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFF7F9FD),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.grey.shade200),
      ),
      padding:
          EdgeInsets.symmetric(horizontal: 16, vertical: compact ? 10 : 12),
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
          // Nama + kode produk
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15, color: _navy),
                ),
                if (kode.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    kode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 11.5, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ),
          // Badge qty
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
            decoration: BoxDecoration(
              color: accent.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(20),
            ),
            child: Text(
              '${_formatNumber(qty)} $qtyLabel',
              style: TextStyle(
                  color: accent, fontWeight: FontWeight.w600, fontSize: 11),
            ),
          ),
          if (showValue) ...[
            const SizedBox(width: 10),
            Text(
              _formatCurrency(netto),
              style: const TextStyle(
                  color: _navy, fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ],
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
