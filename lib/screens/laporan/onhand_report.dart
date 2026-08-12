import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import '../../services/api_service.dart';
import '../../services/session_service.dart';

// ─── Palette ────────────────────────────────────────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);
const Color _green = Color(0xFF16A34A);
const Color _purple = Color(0xFF7C3AED);

/// Report Onhand — versi Flutter dari report/Onhand.php.
/// - 1 store saja (session): langsung load onhand otomatis saat screen dibuka.
/// - >1 store: begitu user memilih store dari dropdown, onhand langsung
///   di-load otomatis (tanpa tombol "Proses").
class OnhandReportScreen extends StatefulWidget {
  final List<int> outlets;

  const OnhandReportScreen({super.key, required this.outlets});

  @override
  State<OnhandReportScreen> createState() => _OnhandReportScreenState();
}

class _OnhandReportScreenState extends State<OnhandReportScreen> {
  List<Map<String, dynamic>> _stores = []; // [{id, nama}]
  int? _selectedStore;
  bool _loadingStores = false;
  bool _loadingData = false;
  bool _hasLoadedOnce = false;
  List<dynamic> _rows = [];
  Map<String, dynamic> _summary = {};
  String? _error;

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
    if (_singleStore) {
      _selectedStore = widget.outlets.first;
    }
    await _loadStores();
    if (_singleStore) {
      _loadOnhand();
    }
  }

  // ============================================================
  // API CALLS
  // ============================================================
  Future<void> _loadStores() async {
    if (!mounted) return;
    setState(() => _loadingStores = true);
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
      // Gagal ambil nama store — dropdown fallback tampilkan ID saja.
    } finally {
      if (mounted) setState(() => _loadingStores = false);
    }
  }

  Future<void> _loadOnhand() async {
    if (_selectedStore == null) return;
    if (!mounted) return;
    setState(() {
      _loadingData = true;
      _error = null;
    });

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
          'action': 'getOnhand',
          'store_id': _selectedStore.toString(),
        },
      ).timeout(const Duration(seconds: 15));

      if (!mounted) return;
      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _rows = data['items'] ?? [];
          _summary = (data['summary'] ?? {}) as Map<String, dynamic>;
          _hasLoadedOnce = true;
        });
      } else {
        setState(() {
          _error = data['message'] ?? 'Gagal memuat data onhand';
        });
      }
    } catch (_) {
      if (mounted) setState(() => _error = 'Gagal terhubung ke server');
    } finally {
      if (mounted) setState(() => _loadingData = false);
    }
  }

  String _storeName(int id) {
    final match = _stores.firstWhere(
      (s) => s['id'].toString() == id.toString(),
      orElse: () => {},
    );
    return (match['nama'] as String?) ?? 'Store $id';
  }

  String _formatNumber(num val) {
    return val.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }

  String _formatCurrency(num val) => 'Rp ${_formatNumber(val)}';

  List<dynamic> get _filteredRows {
    if (_searchQuery.isEmpty) return _rows;
    return _rows.where((r) {
      final item = r as Map<String, dynamic>;
      final kode = (item['kode'] ?? '').toString().toLowerCase();
      final nama = (item['nama'] ?? '').toString().toLowerCase();
      return kode.contains(_searchQuery) || nama.contains(_searchQuery);
    }).toList();
  }

  // ============================================================
  // BUILD
  // ============================================================
  // Ambang batas "compact": tablet 7" landscape yang kepotong navigation
  // bar 3-tombol biasanya menyisakan tinggi < 600px untuk body konten.
  // Di bawah itu, filter bar + 2 card + search bar (masing-masing block
  // penuh) kebanyakan makan tempat, jadi digabung jadi 1 toolbar ringkas.
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
    final totalItem = (_summary['total_item'] as num?)?.toInt() ?? _rows.length;
    final totalOnhand = (_summary['total_onhand'] as num?) ?? 0;
    final totalNominal = (_summary['total_nominal'] as num?) ?? 0;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: [
          _buildCompactStoreField(),
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
              icon: Icons.widgets_outlined,
              color: _green,
              label: 'Onhand',
              value: _formatNumber(totalOnhand),
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
      constraints: const BoxConstraints(minWidth: 150, maxWidth: 230),
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
                      items: widget.outlets
                          .map((id) => DropdownMenuItem(
                                value: id,
                                child: Text(_storeName(id),
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() => _selectedStore = val);
                        if (val != null) _loadOnhand();
                      },
                    ),
                  ),
          ),
        ],
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

  // ── Portrait header: 4 baris ─────────────────────────────────
  // Row 1: Store (dropdown bila akses banyak store)
  // Row 2: Total Item (SKU) + Total Qty berdampingan
  // Row 3: Total Value (Qty x HPJ)
  // Row 4: Search box
  Widget _buildPortraitHeader() {
    final showStats = _hasLoadedOnce && _error == null;
    final totalItem = (_summary['total_item'] as num?)?.toInt() ?? _rows.length;
    final totalOnhand = (_summary['total_onhand'] as num?) ?? 0;
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
          if (showStats) ...[
            const SizedBox(height: 10),
            // Row 2: Total Item (SKU) & Total Qty
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
                    icon: Icons.widgets_outlined,
                    color: _green,
                    label: 'Total Qty',
                    value: _formatNumber(totalOnhand),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            // Row 3: Total Value (Qty x HPJ)
            _HeaderStat(
              icon: Icons.payments_outlined,
              color: _purple,
              label: 'Total Value (Qty × HPJ)',
              value: _formatCurrency(totalNominal),
              fullWidth: true,
            ),
            const SizedBox(height: 10),
            // Row 4: Search box
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
                      items: widget.outlets
                          .map((id) => DropdownMenuItem(
                                value: id,
                                child: Text(_storeName(id),
                                    overflow: TextOverflow.ellipsis),
                              ))
                          .toList(),
                      onChanged: (val) {
                        setState(() => _selectedStore = val);
                        if (val != null) _loadOnhand();
                      },
                    ),
                  ),
          ),
        ],
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
            TextButton(onPressed: _loadOnhand, child: const Text('Coba Lagi')),
          ],
        ),
      );
    }
    if (!_hasLoadedOnce) {
      return Center(
        child: Text(
          widget.outlets.length > 1
              ? 'Pilih store untuk memuat data onhand'
              : 'Memuat data...',
          style: TextStyle(color: Colors.grey[500]),
        ),
      );
    }

    final filtered = _filteredRows;

    if (filtered.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.inventory_2_outlined, size: 40, color: Colors.grey[350]),
            const SizedBox(height: 8),
            Text(
              _rows.isEmpty
                  ? 'Tidak ada data onhand'
                  : 'Tidak ada produk yang cocok',
              style: TextStyle(color: Colors.grey[500]),
            ),
          ],
        ),
      );
    }

    return RefreshIndicator(
      color: _blue,
      onRefresh: _loadOnhand,
      child: Padding(
        padding: EdgeInsets.all(compact ? 8 : 16),
        child: Container(
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(compact ? 8 : 12),
            border: Border.all(color: Colors.grey.shade200),
          ),
          clipBehavior: Clip.antiAlias,
          child: Column(
            children: [
              _buildTableHeader(compact),
              Expanded(
                child: ListView.separated(
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: filtered.length,
                  separatorBuilder: (_, __) =>
                      Divider(height: 1, color: Colors.grey.shade200),
                  itemBuilder: (context, i) => _buildTableRow(
                      filtered[i] as Map<String, dynamic>, i, compact),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // Kolom disederhanakan untuk portrait: No / Produk (nama + kode di
  // bawahnya) / Qty. Lebar No & Qty tetap, Produk mengisi sisa ruang.
  static const double _noColWidth = 28;
  static const double _qtyColWidth = 76;

  Widget _buildTableHeader(bool compact) {
    final style = TextStyle(
      color: Colors.white,
      fontWeight: FontWeight.w600,
      fontSize: compact ? 12.5 : 13.5,
    );
    return Container(
      color: _navy,
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16, vertical: compact ? 10 : 12),
      child: Row(
        children: [
          SizedBox(width: _noColWidth, child: Text('No', style: style)),
          Expanded(child: Text('Produk', style: style)),
          SizedBox(
            width: _qtyColWidth,
            child: Text('Qty', style: style, textAlign: TextAlign.right),
          ),
        ],
      ),
    );
  }

  Widget _buildTableRow(Map<String, dynamic> item, int i, bool compact) {
    final namaGabungan = [
      item['nama'],
      item['warna'],
      item['size'],
    ].where((e) => (e ?? '').toString().isNotEmpty).join(' - ');
    final kode = '${item['kode'] ?? ''}';
    final fontSize = compact ? 12.5 : 14.0;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.symmetric(
          horizontal: compact ? 12 : 16, vertical: compact ? 9 : 12),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          SizedBox(
            width: _noColWidth,
            child: Text('${i + 1}',
                style: TextStyle(fontSize: fontSize, color: Colors.grey[700])),
          ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  namaGabungan,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                      fontSize: fontSize, fontWeight: FontWeight.w500),
                ),
                if (kode.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(
                    kode,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                        fontSize: fontSize - 2, color: Colors.grey[500]),
                  ),
                ],
              ],
            ),
          ),
          SizedBox(
            width: _qtyColWidth,
            child: Text(
              _formatNumber((item['qty'] as num?) ?? 0),
              textAlign: TextAlign.right,
              style: TextStyle(
                  color: _green,
                  fontWeight: FontWeight.w700,
                  fontSize: fontSize),
            ),
          ),
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

// ─── Header stat chip (dipakai di portrait header: row 2 & row 3) ──
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
