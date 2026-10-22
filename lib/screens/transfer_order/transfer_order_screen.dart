import 'package:flutter/material.dart';
import '../../services/transfer_order_service.dart';
import 'transfer_order_detail_screen.dart';

const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF4F6F9);
const Color _cardBorder = Color(0xFFE2E8F0);
const Color _green = Color(0xFF10B981);

class TransferOrderScreen extends StatefulWidget {
  final List<int> outlets;

  const TransferOrderScreen({super.key, this.outlets = const []});

  @override
  State<TransferOrderScreen> createState() => _TransferOrderScreenState();
}

class _TransferOrderScreenState extends State<TransferOrderScreen> {
  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _allOrders = [];
  String _selectedFilter = 'all'; // 'all', 'DR' (menunggu), 'CO' (selesai)
  String _searchQuery = '';
  int _pendingCount = 0;
  final TextEditingController _searchCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _loadOrders();
  }

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadOrders() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final res = await TransferOrderService.getIncomingTransferOrders(
        storeIds: widget.outlets,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        final list = List<Map<String, dynamic>>.from(res['data'] ?? []);
        setState(() {
          _allOrders = list;
          _pendingCount = res['pending_count'] ?? 0;
          _isLoading = false;
        });
      } else {
        setState(() {
          _errorMessage = res['message'] ?? 'Gagal memuat data transfer order';
          _isLoading = false;
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _errorMessage = 'Terjadi kesalahan: $e';
        _isLoading = false;
      });
    }
  }

  List<Map<String, dynamic>> get _filteredOrders {
    var list = _allOrders;

    if (_selectedFilter == 'in') {
      list = list.where((o) => o['is_masuk'] == true).toList();
    } else if (_selectedFilter == 'out') {
      list = list.where((o) => o['is_keluar'] == true).toList();
    } else if (_selectedFilter == 'DR') {
      list = list.where((o) => o['status'] == 'DR').toList();
    } else if (_selectedFilter == 'CO') {
      list = list.where((o) => o['status'] == 'CO').toList();
    }

    final q = _searchQuery.trim().toLowerCase();
    if (q.isNotEmpty) {
      list = list.where((o) {
        final kode = (o['kode'] ?? '').toString().toLowerCase();
        final asal = (o['toko_pengirim'] ?? '').toString().toLowerCase();
        final tujuan = (o['toko_penerima'] ?? '').toString().toLowerCase();
        return kode.contains(q) || asal.contains(q) || tujuan.contains(q);
      }).toList();
    }

    return list;
  }

  Future<void> _handleConfirmReceive(Map<String, dynamic> order) async {
    final toId = order['id'];
    final kode = order['kode'] ?? '';
    final asal = order['toko_pengirim'] ?? '';
    final tujuan = order['toko_penerima'] ?? '';

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.inventory_rounded, color: _green, size: 24),
            SizedBox(width: 8),
            Text(
              'Konfirmasi Penerimaan',
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'Apakah Anda yakin ingin menerima Transfer Order $kode?',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: const Color(0xFFF1F5F9),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Dari: $asal',
                      style: const TextStyle(fontSize: 13, color: Colors.black87)),
                  const SizedBox(height: 4),
                  Text('Ke: $tujuan',
                      style: const TextStyle(fontSize: 13, color: Colors.black87)),
                ],
              ),
            ),
            const SizedBox(height: 12),
            const Text(
              'Status akan diubah menjadi Complete dan stok otomatis masuk ke inventori toko.',
              style: TextStyle(
                fontSize: 12,
                color: _green,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal', style: TextStyle(color: Colors.grey)),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: _green,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(8),
              ),
            ),
            child: const Text('Ya, Terima Barang'),
          ),
        ],
      ),
    );

    if (confirm != true) return;
    if (!mounted) return;

    // Tampilkan loading snackbar
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Row(
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
            ),
            SizedBox(width: 12),
            Text('Sedang memproses konfirmasi...'),
          ],
        ),
        duration: Duration(seconds: 15),
      ),
    );

    try {
      final res = await TransferOrderService.receiveTransferOrder(
        transferOrderId: toId,
        number: kode,
      );

      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();

      if (res['success'] == true) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Barang berhasil diterima!'),
            backgroundColor: _green,
          ),
        );
        _loadOrders();
      } else {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res['message'] ?? 'Gagal memproses penerimaan'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).hideCurrentSnackBar();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Terjadi error: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _openDetail(Map<String, dynamic> order) async {
    final toId = order['id'];
    final kode = order['kode'] ?? '';

    final didChange = await Navigator.push<bool>(
      context,
      MaterialPageRoute(
        builder: (_) => TransferOrderDetailScreen(
          transferOrderId: toId,
          kode: kode,
        ),
      ),
    );

    if (didChange == true) {
      _loadOrders();
    }
  }

  @override
  Widget build(BuildContext context) {
    final filtered = _filteredOrders;

    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text(
          'Perpindahan Stok',
          style: TextStyle(fontWeight: FontWeight.bold),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'Muat Ulang',
            onPressed: _isLoading ? null : _loadOrders,
          ),
        ],
      ),
      body: Column(
        children: [
          // ── FILTER TABS (Semua / Menunggu Diterima / Selesai) ────
          _buildFilterTabs(),

          // ── SEARCH BAR ──────────────────────────────────────────
          _buildSearchBar(),

          // ── BODY CONTENT / TABEL DOKUMEN ─────────────────────────
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator(color: _blue))
                : _errorMessage != null
                    ? Center(
                        child: Padding(
                          padding: const EdgeInsets.all(24),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(Icons.error_outline_rounded,
                                  size: 48, color: Colors.red),
                              const SizedBox(height: 12),
                              Text(_errorMessage!, textAlign: TextAlign.center),
                              const SizedBox(height: 16),
                              ElevatedButton(
                                onPressed: _loadOrders,
                                style: ElevatedButton.styleFrom(
                                  backgroundColor: _navy,
                                ),
                                child: const Text('Coba Lagi',
                                    style: TextStyle(color: Colors.white)),
                              ),
                            ],
                          ),
                        ),
                      )
                    : RefreshIndicator(
                        color: _blue,
                        onRefresh: _loadOrders,
                        child: filtered.isEmpty
                            ? ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                children: [
                                  SizedBox(
                                    height: MediaQuery.of(context).size.height * 0.4,
                                    child: Center(
                                      child: Column(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Icon(
                                            Icons.inventory_2_outlined,
                                            size: 54,
                                            color: Colors.grey[400],
                                          ),
                                          const SizedBox(height: 12),
                                          Text(
                                            'Tidak ada dokumen transfer order',
                                            style: TextStyle(
                                              fontSize: 15,
                                              color: Colors.grey[600],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              )
                            : ListView(
                                physics: const AlwaysScrollableScrollPhysics(),
                                padding: const EdgeInsets.all(16),
                                children: [
                                  _buildTableCard(filtered),
                                ],
                              ),
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterTabs() {
    final countMasuk = _allOrders.where((o) => o['is_masuk'] == true).length;
    final countKeluar = _allOrders.where((o) => o['is_keluar'] == true).length;
    final countComplete = _allOrders.where((o) => o['status'] == 'CO').length;

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            _buildTabChip('all', 'Semua Transfer', count: _allOrders.length),
            const SizedBox(width: 8),
            _buildTabChip(
              'in',
              'Barang Masuk (Datang)',
              count: countMasuk,
              badgeColor: _pendingCount > 0 ? Colors.red : null,
            ),
            const SizedBox(width: 8),
            _buildTabChip(
              'out',
              'Barang Keluar',
              count: countKeluar,
            ),
            const SizedBox(width: 8),
            _buildTabChip(
              'DR',
              'Menunggu Diterima',
              count: _pendingCount,
              badgeColor: Colors.red,
            ),
            const SizedBox(width: 8),
            _buildTabChip(
              'CO',
              'Selesai (Complete)',
              count: countComplete,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTabChip(String key, String label,
      {int count = 0, Color? badgeColor}) {
    final isSelected = _selectedFilter == key;

    return GestureDetector(
      onTap: () {
        setState(() => _selectedFilter = key);
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected ? _blue.withValues(alpha: 0.12) : const Color(0xFFF1F5F9),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: isSelected ? _blue : Colors.transparent,
            width: 1.2,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                color: isSelected ? _blue : const Color(0xFF334155),
              ),
            ),
            if (count > 0) ...[
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                decoration: BoxDecoration(
                  color: isSelected
                      ? (badgeColor ?? _blue)
                      : (badgeColor ?? Colors.grey[500]),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  '$count',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildSearchBar() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
      child: TextField(
        controller: _searchCtrl,
        onChanged: (val) => setState(() => _searchQuery = val),
        decoration: InputDecoration(
          hintText: 'Cari nomor dokumen / toko pengirim...',
          hintStyle: TextStyle(fontSize: 13, color: Colors.grey[400]),
          prefixIcon: const Icon(Icons.search, size: 20, color: Colors.grey),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear, size: 18),
                  onPressed: () {
                    _searchCtrl.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: const Color(0xFFF8FAFC),
          isDense: true,
          contentPadding: const EdgeInsets.symmetric(vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _cardBorder),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _cardBorder),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(10),
            borderSide: const BorderSide(color: _blue, width: 1.5),
          ),
        ),
      ),
    );
  }

  Widget _buildTableCard(List<Map<String, dynamic>> orders) {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: _cardBorder),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.03),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: ClipRRect(
        borderRadius: BorderRadius.circular(12),
        child: SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minWidth: 950),
            child: DataTable(
              headingRowColor: WidgetStateProperty.all(const Color(0xFFF8FAFC)),
              horizontalMargin: 16,
              columnSpacing: 20,
              dataRowMinHeight: 52,
              dataRowMaxHeight: 64,
              columns: const [
                DataColumn(
                  label: Text('No.', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                DataColumn(
                  label: Text('Nomor Dokumen',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                DataColumn(
                  label: Text('Toko Pengirim',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                DataColumn(
                  label: Text('Toko Penerima',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                DataColumn(
                  label: Text('Tanggal',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                DataColumn(
                  label: Text('Total Qty',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                DataColumn(
                  label: Text('Tipe',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                DataColumn(
                  label: Text('Status',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                DataColumn(
                  label: Text('Action',
                      style: TextStyle(fontWeight: FontWeight.bold)),
                ),
              ],
              rows: orders.asMap().entries.map((entry) {
                final index = entry.key;
                final order = entry.value;
                final isDraft = order['status'] == 'DR';
                final canConfirm = (order['can_confirm'] == true && isDraft);
                final isMasuk = order['is_masuk'] == true;

                return DataRow(
                  cells: [
                    DataCell(Text('${index + 1}.')),
                    DataCell(
                      InkWell(
                        onTap: () => _openDetail(order),
                        child: Text(
                          order['kode'] ?? '-',
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            color: _blue,
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Text(
                        order['toko_pengirim'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    DataCell(
                      Text(
                        order['toko_penerima'] ?? '-',
                        style: const TextStyle(fontWeight: FontWeight.w500),
                      ),
                    ),
                    DataCell(Text(order['tanggal'] ?? '-')),
                    DataCell(
                      Text(
                        '${order['qty'] ?? 0}',
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    // Tipe (Masuk / Keluar / Internal)
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isMasuk
                              ? const Color(0xFFDCFCE7)
                              : const Color(0xFFEFF6FF),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          order['tipe'] ?? (isMasuk ? 'Masuk' : 'Keluar'),
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isMasuk
                                ? const Color(0xFF15803D)
                                : const Color(0xFF1D4ED8),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: isDraft
                              ? const Color(0xFFE0F2FE)
                              : const Color(0xFFDCFCE7),
                          borderRadius: BorderRadius.circular(6),
                        ),
                        child: Text(
                          isDraft ? 'Draft' : 'Complete',
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            color: isDraft
                                ? const Color(0xFF0369A1)
                                : const Color(0xFF15803D),
                          ),
                        ),
                      ),
                    ),
                    DataCell(
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // ── BUTTON VIEW (DENGAN TOOLTIP) ──────
                          Tooltip(
                            message: 'Lihat Detail Item',
                            child: InkWell(
                              onTap: () => _openDetail(order),
                              borderRadius: BorderRadius.circular(8),
                              child: Container(
                                padding: const EdgeInsets.all(6),
                                decoration: BoxDecoration(
                                  color: _blue.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.visibility_outlined,
                                  size: 18,
                                  color: _blue,
                                ),
                              ),
                            ),
                          ),

                          // ── BUTTON KONFIRMASI TERIMA (HANYA UNTUK BARANG MASUK YANG DRAFT) ──
                          // Barang keluar (IRK) TIDAK ada tombol confirm, hanya view saja.
                          if (canConfirm) ...[
                            const SizedBox(width: 8),
                            Tooltip(
                              message: 'Konfirmasi Terima',
                              child: InkWell(
                                onTap: () => _handleConfirmReceive(order),
                                borderRadius: BorderRadius.circular(8),
                                child: Container(
                                  padding: const EdgeInsets.all(6),
                                  decoration: BoxDecoration(
                                    color: _green.withValues(alpha: 0.12),
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: const Icon(
                                    Icons.check_circle_outline_rounded,
                                    size: 18,
                                    color: _green,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ],
                );
              }).toList(),
            ),
          ),
        ),
      ),
    );
  }
}
