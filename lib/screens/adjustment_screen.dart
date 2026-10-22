import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';
import '../services/adjustment_service.dart';
import '../services/session_service.dart';
import '../services/store_service.dart';

// ─── Palette (samakan dengan home_screen.dart) ─────────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A2F5A);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);

// ── Cache manager khusus gambar produk Adjustment.
// Terpisah dari cache milik penjualan_screen.dart supaya kebijakan
// eviction-nya independen — tapi kalau kamu mau, tinggal reuse
// `productImageCacheManager` yang sudah ada di products.dart.
final CacheManager _adjustmentImageCacheManager = CacheManager(
  Config(
    'adjustmentImageCache',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 300,
  ),
);

class AdjustmentScreen extends ConsumerStatefulWidget {
  const AdjustmentScreen({super.key});

  @override
  ConsumerState<AdjustmentScreen> createState() => _AdjustmentScreenState();
}

class _AdjustmentScreenState extends ConsumerState<AdjustmentScreen> {
  int _userID = 0;
  List<int> _outlets = [];
  List<Map<String, dynamic>> _storeOptions = [];

  int? _storeID;
  int? _organisasiID;
  String _storeName = '';
  String _number = '';
  final DateTime _tanggal = DateTime.now();
  String _tipe = 'count'; // 'count' = Set Total, 'adjust' = Update Selisih

  // ── SKU search — auto-focus untuk barcode scanner, sama seperti
  // penjualan_screen.dart (_skuKeyboardVisible menahan keyboard virtual
  // muncul kecuali user tap manual; scanner fisik tetap bisa inject).
  final _skuController = TextEditingController();
  final _skuFocusNode = FocusNode();
  bool _skuKeyboardVisible = false;

  List<Map<String, dynamic>> _items = [];
  double _totalQty = 0;

  // ── Image grid per kategori — pola identik dengan products.dart /
  // widgets_grid.dart di penjualan_screen.dart
  List<Map<String, dynamic>> _imageCategories = [];
  bool _isLoadingImages = false;

  // Anti-double-tap guard, sama seperti _processingKodes di penjualan
  final Set<String> _processingKodes = {};
  bool _isBusy = false; // guard umum saat insert/refresh berjalan

  bool _loadingInit = true;
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _loadSession();
  }

  @override
  void dispose() {
    _skuController.dispose();
    _skuFocusNode.dispose();
    super.dispose();
  }

  // ============================================================
  // FOKUS SKU — tanpa keyboard (untuk scanner), dipanggil setelah
  // insert produk / pilih store, sama seperti _focusSku() di penjualan
  // ============================================================
  void _focusSku() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      setState(() => _skuKeyboardVisible = false);
      _skuFocusNode.requestFocus();
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  void _focusSkuWithKeyboard() {
    setState(() => _skuKeyboardVisible = true);
    _skuFocusNode.requestFocus();
  }

  // ============================================================
  // SESSION & STORE
  // ============================================================
  Future<void> _loadSession() async {
    final session = await SessionService.getSession();
    if (!mounted) return;
    setState(() {
      _userID = session['user_id'] ?? 0;
      _outlets = List<int>.from(session['outlets'] ?? []);
    });

    try {
      final stores = await StoreService.getStores(userId: _userID);
      _storeOptions = stores;
    } catch (_) {}

    if (!mounted) return;
    setState(() => _loadingInit = false);

    if (_outlets.length == 1) {
      final match = _storeOptions.firstWhere(
        (s) => int.parse(s['id'].toString()) == _outlets.first,
        orElse: () => {'id': _outlets.first, 'nama': ''},
      );
      _selectStore(_outlets.first, match['nama']?.toString() ?? '');
    }
  }

  Future<void> _selectStore(int storeID, String storeName) async {
    setState(() {
      _storeID = storeID;
      _storeName = storeName;
      _number = '';
      _items = [];
      _totalQty = 0;
      _imageCategories = [];
    });

    try {
      final orgData = await StoreService.getOrganisasiId(storeID);
      if (orgData['organisasi_id'] != null && (orgData['organisasi_id'] as int) > 0) {
        _organisasiID = orgData['organisasi_id'] as int;
      }
    } catch (e) {
      debugPrint('[getOrganisasiId] error: $e');
      if (mounted) _showError('Gagal memuat data organisasi outlet');
    }

    try {
      final number = await AdjustmentService.getAdjustmentNumber(storeID);
      if (number != null && mounted) {
        setState(() => _number = number);
      }
    } catch (e) {
      debugPrint('[getAdjustmentNumber] error: $e');
      if (mounted) _showError('Gagal mengambil nomor dokumen');
    }

    _loadImageProducts();
    _focusSku();
  }

  // ============================================================
  // SKU SEARCH — mirror _searchProduk di products.dart:
  // 1 hasil → langsung insert, banyak hasil → bottom sheet picker
  // ============================================================
  Future<void> _onSkuSubmitted(String value) async {
    final term = value.trim();
    if (term.isEmpty) return;

    if (_storeID == null || _organisasiID == null) {
      _showError('Silahkan pilih outlet sebelum input produk');
      setState(() => _skuController.clear());
      return;
    }

    try {
      final data = await AdjustmentService.searchProducts(
        organisasiId: _organisasiID!,
        term: term,
      );

      if (data.isEmpty) {
        _showError('Produk "$term" tidak ditemukan');
      } else if (data.length == 1) {
        await _insertProduk(data.first['kode'].toString());
      } else {
        _showProductPicker(data);
      }
    } catch (_) {
      _showError('Terjadi kesalahan sistem');
    }

    setState(() => _skuController.clear());
  }

  void _showProductPicker(List<Map<String, dynamic>> products) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView.builder(
        itemCount: products.length,
        itemBuilder: (_, i) {
          final p = products[i];
          return ListTile(
            title: Text(p['nama'].toString()),
            subtitle: Text(p['kode'].toString()),
            onTap: () {
              Navigator.pop(context);
              _insertProduk(p['kode'].toString());
            },
          );
        },
      ),
    );
  }

  // ============================================================
  // INSERT PRODUK — dipakai baik oleh SKU search maupun tap gambar
  // di grid, sama seperti _insertProduk di products.dart
  // ============================================================
  Future<void> _insertProduk(String kode) async {
    if (_storeID == null || _organisasiID == null) {
      _showError('Silahkan pilih outlet sebelum input produk');
      return;
    }
    if (_processingKodes.contains(kode)) return;

    setState(() {
      _processingKodes.add(kode);
      _isBusy = true;
    });

    try {
      final res = await AdjustmentService.insertItem(
        number: _number,
        kode: kode,
        qty: 1,
        organisasiId: _organisasiID!,
      );

      if (res['success'] == true) {
        await _refreshList();
        await _refreshTotal();
      } else {
        _showError(res['message'] ?? 'Gagal menambahkan produk');
      }
    } catch (_) {
      _showError('Terjadi kesalahan sistem');
    } finally {
      if (mounted) {
        setState(() {
          _processingKodes.remove(kode);
          _isBusy = false;
        });
      }
    }

    _focusSku();
  }

  // ============================================================
  // LIST & TOTAL
  // ============================================================
  Future<void> _refreshList() async {
    if (_number.isEmpty || _organisasiID == null) return;
    try {
      final items = await AdjustmentService.getItems(
        number: _number,
        organisasiId: _organisasiID!,
      );
      if (mounted) {
        setState(() => _items = items);
      }
    } catch (_) {}
  }

  Future<void> _refreshTotal() async {
    if (_number.isEmpty || _organisasiID == null) return;
    try {
      final total = await AdjustmentService.getTotalQty(
        number: _number,
        organisasiId: _organisasiID!,
      );
      if (mounted) {
        setState(() => _totalQty = total);
      }
    } catch (_) {}
  }

  Future<void> _updateQty(String kode, double qty) async {
    try {
      final ok = await AdjustmentService.updateQty(
        number: _number,
        kode: kode,
        qty: qty,
      );
      if (ok) {
        await _refreshTotal();
      } else {
        _showError('Update Qty gagal');
        await _refreshList();
      }
    } catch (_) {
      _showError('Terjadi kesalahan sistem');
    }
  }

  Future<void> _deleteItem(String kode) async {
    if (_organisasiID == null) return;
    try {
      final ok = await AdjustmentService.deleteItem(
        number: _number,
        kode: kode,
        organisasiId: _organisasiID!,
      );
      if (ok) {
        await _refreshList();
        await _refreshTotal();
      } else {
        _showError('Gagal menghapus data');
      }
    } catch (_) {
      _showError('Terjadi kesalahan sistem');
    }
  }

  // ============================================================
  // LOAD PRODUK DENGAN IMAGE — reuse action getImageProducts yang
  // sudah ada di MasterHandler.php (dipakai juga oleh penjualan),
  // salestipe_id dikosongkan karena Adjustment tidak punya channel/harga.
  // ============================================================
  Future<void> _loadImageProducts() async {
    if (_isLoadingImages || _organisasiID == null) return;
    setState(() => _isLoadingImages = true);
    try {
      final categories = await AdjustmentService.getImageProducts(
        organisasiId: _organisasiID!,
      );
      if (mounted) setState(() => _imageCategories = categories);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _isLoadingImages = false);
    }
  }

  // ============================================================
  // SIMPAN
  // ============================================================
  Future<void> _simpan() async {
    if (_storeID == null || _organisasiID == null) {
      _showError('Outlet belum dipilih');
      return;
    }
    if (_items.isEmpty) {
      _showError('Produk belum diinput');
      return;
    }

    setState(() => _saving = true);
    try {
      final res = await AdjustmentService.submitAdjustment(
        storeId: _storeID!,
        organisasiId: _organisasiID!,
        tanggal: _formatDate(_tanggal),
        number: _number,
        tipe: _tipe,
      );

      if (!mounted) return;

      if (res['success'] == true) {
        await showDialog(
          context: context,
          builder: (_) => AlertDialog(
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Text('Berhasil'),
            content: const Text(
                'Pengajuan penyesuaian stok berhasil, menunggu approval'),
            actions: [
              TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('OK')),
            ],
          ),
        );
        if (mounted) Navigator.pop(context);
      } else {
        _showError(res['message'] ?? 'Gagal menyimpan transaksi');
      }
    } catch (_) {
      _showError('Terjadi kesalahan sistem');
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  // ============================================================
  // HELPERS
  // ============================================================
  String _formatDate(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  String _formatQty(num q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toString();

  void _showError(String message) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(message), backgroundColor: Colors.red),
    );
  }

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    final isLandscape =
        MediaQuery.of(context).orientation == Orientation.landscape;

    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Penyesuaian Stok'),
      ),
      body: _loadingInit
          ? const Center(child: CircularProgressIndicator(color: _blue))
          : Column(
              children: [
                _buildHeaderCard(),
                Expanded(
                  child: isLandscape ? _buildSideBySide() : _buildStacked(),
                ),
                _buildFooter(),
              ],
            ),
    );
  }

  // ── Landscape: grid gambar kiri, list kanan (mirror layout web) ──
  Widget _buildSideBySide() {
    return Row(
      children: [
        Expanded(flex: 6, child: _buildImageGrid()),
        Container(width: 1, color: Colors.grey.shade300),
        Expanded(flex: 4, child: _buildItemList()),
      ],
    );
  }

  // ── Portrait: stacked, sama seperti _buildStackedLayout di
  // penjualan_screen.dart — grid gambar & list ditampilkan bersamaan
  // (bukan tab), grid dibatasi maksimal 2 row supaya list adjustment
  // tetap kebagian ruang (minimal 2 row) alih-alih ke-squeeze ke 0/1 row.
  Widget _buildStacked() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final gridMaxHeight = _stackedImageGridMaxHeight(constraints.maxWidth);
        return Column(
          children: [
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: gridMaxHeight),
              child: _buildImageGrid(),
            ),
            Container(height: 1, color: Colors.grey.shade300),
            Expanded(child: _buildItemList()),
          ],
        );
      },
    );
  }

  // ── Hitung tinggi maksimal grid gambar untuk persis 2 row, mirror
  // formula cell-size di _buildProductGrid (4 kolom, cell square + 1
  // baris nama) ditambah tinggi TabBar kategori di atasnya.
  double _stackedImageGridMaxHeight(double maxWidth) {
    const columns = 4;
    const spacing = 8.0;
    const categoryTabBarHeight = 48.0;
    final cellWidth = (maxWidth - spacing * (columns + 1)) / columns;
    final cellHeight = cellWidth + 32; // gambar square + 1 baris nama
    final twoRowsHeight = cellHeight * 2 + spacing * 3; // top+mid+bottom gap
    return categoryTabBarHeight + twoRowsHeight;
  }

  // ── Header: outlet, tanggal, no. dokumen, tipe, SKU search ──
  Widget _buildHeaderCard() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Baris 1: Store | No. Dokumen ──
          Row(
            children: [
              Expanded(
                child: _outlets.length <= 1
                    ? _readOnlyField(
                        'Store', _storeName.isEmpty ? '-' : _storeName)
                    : DropdownButtonFormField<int>(
                        initialValue: _storeID,
                        decoration: const InputDecoration(
                          labelText: 'Store',
                          isDense: true,
                          border: OutlineInputBorder(),
                        ),
                        items: _storeOptions
                            .map((s) => DropdownMenuItem<int>(
                                  value: int.parse(s['id'].toString()),
                                  child: Text(s['nama']),
                                ))
                            .toList(),
                        onChanged: (val) {
                          if (val == null) return;
                          final match = _storeOptions.firstWhere(
                              (s) => int.parse(s['id'].toString()) == val);
                          _selectStore(val, match['nama'].toString());
                        },
                      ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _readOnlyField(
                    'No. Dokumen', _number.isEmpty ? '-' : _number),
              ),
            ],
          ),
          const SizedBox(height: 10),

          // ── Baris 2: Tanggal | Tipe Adjustment | SKU Search ──
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                flex: 2,
                child: _readOnlyField('Tanggal', _formatDate(_tanggal)),
              ),
              const SizedBox(width: 10),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  initialValue: _tipe,
                  decoration: const InputDecoration(
                    labelText: 'Tipe Adjustment',
                    isDense: true,
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'count', child: Text('Set Total')),
                    DropdownMenuItem(
                        value: 'adjust', child: Text('Update Selisih')),
                  ],
                  onChanged: (val) {
                    if (val != null) setState(() => _tipe = val);
                  },
                ),
              ),
              const SizedBox(width: 10),
              // SKU search — auto-focus barcode scanner, keyboard hanya
              // muncul kalau user tap manual (sama seperti penjualan)
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _skuController,
                  focusNode: _skuFocusNode,
                  keyboardType: _skuKeyboardVisible
                      ? TextInputType.text
                      : TextInputType.none,
                  onTap: _focusSkuWithKeyboard,
                  decoration: const InputDecoration(
                    hintText: 'Cari produk / SKU',
                    isDense: true,
                    border: OutlineInputBorder(),
                    prefixIcon: Icon(Icons.qr_code_scanner, size: 20),
                  ),
                  onSubmitted: (val) {
                    _onSkuSubmitted(val);
                    setState(() => _skuKeyboardVisible = false);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _readOnlyField(String label, String value) {
    return InputDecorator(
      decoration: InputDecoration(
        labelText: label,
        isDense: true,
        filled: true,
        fillColor: Colors.grey.shade100,
        border: const OutlineInputBorder(),
      ),
      child: Text(value,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(color: Colors.black87)),
    );
  }

  // ── Image grid per kategori (sama pola dengan widgets_grid.dart) ──
  Widget _buildImageGrid() {
    if (_isLoadingImages) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_imageCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.image_not_supported_outlined,
                size: 40, color: Colors.grey.shade400),
            const SizedBox(height: 8),
            Text('Tidak ada produk dengan gambar',
                style: TextStyle(color: Colors.grey.shade500)),
          ],
        ),
      );
    }

    return DefaultTabController(
      length: _imageCategories.length,
      child: Column(
        children: [
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: _navy,
              unselectedLabelColor: Colors.grey,
              indicatorColor: _navy,
              labelStyle:
                  const TextStyle(fontSize: 12, fontWeight: FontWeight.w600),
              tabs: _imageCategories
                  .map((cat) => Tab(text: cat['nama']?.toString() ?? ''))
                  .toList(),
            ),
          ),
          Expanded(
            child: TabBarView(
              children: _imageCategories.map((cat) {
                return _buildProductGrid(
                    cat['produk'] as List<Map<String, dynamic>>);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildProductGrid(List<Map<String, dynamic>> products) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const columns = 4;
        const spacing = 8.0;
        final cellWidth =
            (constraints.maxWidth - spacing * (columns + 1)) / columns;
        final cellHeight = cellWidth + 32; // gambar square + 1 baris nama
        final childAspectRatio = cellWidth / cellHeight;

        return GridView.builder(
          padding: const EdgeInsets.all(spacing),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: products.length,
          itemBuilder: (_, i) {
            final p = products[i];
            final kode = p['kode']?.toString() ?? '';
            final nama = p['nama']?.toString() ?? '';
            final imageUrl = p['image']?.toString() ?? '';
            final isProcessing = _processingKodes.contains(kode) || _isBusy;

            return GestureDetector(
              onTap: isProcessing ? null : () => _insertProduk(kode),
              child: Opacity(
                opacity: isProcessing ? 0.55 : 1.0,
                child: Card(
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(8)),
                  child: Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          AspectRatio(
                            aspectRatio: 1,
                            child: _AdjustmentImageTile(imageUrl: imageUrl),
                          ),
                          Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 4, vertical: 4),
                            child: Text(
                              nama,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                  fontSize: 10, fontWeight: FontWeight.w600),
                            ),
                          ),
                        ],
                      ),
                      if (isProcessing)
                        const Positioned.fill(
                          child: Center(
                            child: CircularProgressIndicator(
                                strokeWidth: 2, color: _navy),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ── List item adjustment ──
  Widget _buildItemList() {
    if (_items.isEmpty) {
      return const Center(
          child: Text('Belum ada produk diinput',
              style: TextStyle(color: Colors.grey)));
    }

    return ListView.separated(
      padding: const EdgeInsets.all(10),
      itemCount: _items.length,
      separatorBuilder: (_, __) => const SizedBox(height: 6),
      itemBuilder: (_, i) {
        final item = _items[i];
        final qty = double.tryParse(item['qty']?.toString() ?? '') ?? 0.0;
        final uom = item['uom']?.toString() ?? '';
        return _AdjustmentItemRow(
          index: i + 1,
          kode: item['kode']?.toString() ?? '',
          nama: item['nama']?.toString() ?? '',
          qty: qty,
          uom: uom,
          onQtyChanged: (newQty) =>
              _updateQty(item['kode']?.toString() ?? '', newQty),
          onDelete: () => _deleteItem(item['kode']?.toString() ?? ''),
        );
      },
    );
  }

  // ── Footer: total qty + tombol simpan ──
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
              color: Colors.black.withValues(alpha: 0.06),
              blurRadius: 8,
              offset: const Offset(0, -2))
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text('TOTAL QTY',
                      style: TextStyle(fontSize: 11, color: Colors.grey)),
                  Text(_formatQty(_totalQty),
                      style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                          color: _navyMid)),
                ],
              ),
            ),
            ElevatedButton.icon(
              onPressed: _saving ? null : _simpan,
              style: ElevatedButton.styleFrom(
                backgroundColor: _navy,
                foregroundColor: Colors.white,
                padding:
                    const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
              ),
              icon: _saving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined),
              label: const Text('Simpan'),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET: tile gambar produk — cache + auto-retry, sama pola
// dengan _ProductImageTile di widgets_grid.dart
// ============================================================
class _AdjustmentImageTile extends StatefulWidget {
  final String imageUrl;
  const _AdjustmentImageTile({required this.imageUrl});

  @override
  State<_AdjustmentImageTile> createState() => _AdjustmentImageTileState();
}

class _AdjustmentImageTileState extends State<_AdjustmentImageTile> {
  int _attempt = 0;
  static const int _maxAutoRetry = 2;

  void _scheduleRetry() {
    if (_attempt >= _maxAutoRetry) return;
    Future.delayed(Duration(seconds: 2 * (_attempt + 1)), () {
      if (!mounted) return;
      if (!kIsWeb) {
        _adjustmentImageCacheManager.removeFile(widget.imageUrl);
      }
      setState(() => _attempt++);
    });
  }

  @override
  Widget build(BuildContext context) {
    if (kIsWeb) {
      return Image.network(
        widget.imageUrl,
        fit: BoxFit.cover,
        errorBuilder: (_, __, ___) {
          _scheduleRetry();
          final stillTrying = _attempt < _maxAutoRetry;
          return Container(
            color: Colors.grey.shade200,
            child: Icon(stillTrying ? Icons.wifi_off_rounded : Icons.broken_image,
                color: Colors.grey, size: 22),
          );
        },
        loadingBuilder: (_, child, progress) {
          if (progress == null) return child;
          return Container(
            color: Colors.grey.shade100,
            child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
          );
        },
      );
    }

    return CachedNetworkImage(
      key: ValueKey('${widget.imageUrl}_$_attempt'),
      imageUrl: widget.imageUrl,
      cacheManager: _adjustmentImageCacheManager,
      fit: BoxFit.cover,
      fadeInDuration: const Duration(milliseconds: 200),
      placeholder: (_, __) => Container(
        color: Colors.grey.shade100,
        child: const Center(child: CircularProgressIndicator(strokeWidth: 2)),
      ),
      errorWidget: (_, __, ___) {
        _scheduleRetry();
        final stillTrying = _attempt < _maxAutoRetry;
        return Container(
          color: Colors.grey.shade200,
          child: Icon(stillTrying ? Icons.wifi_off_rounded : Icons.broken_image,
              color: Colors.grey, size: 22),
        );
      },
    );
  }
}

// ============================================================
// WIDGET: baris item produk (qty editable + uom + delete)
// ============================================================
class _AdjustmentItemRow extends StatefulWidget {
  final int index;
  final String kode;
  final String nama;
  final double qty;
  final String uom;
  final ValueChanged<double> onQtyChanged;
  final VoidCallback onDelete;

  const _AdjustmentItemRow({
    required this.index,
    required this.kode,
    required this.nama,
    required this.qty,
    required this.uom,
    required this.onQtyChanged,
    required this.onDelete,
  });

  @override
  State<_AdjustmentItemRow> createState() => _AdjustmentItemRowState();
}

class _AdjustmentItemRowState extends State<_AdjustmentItemRow> {
  late final TextEditingController _qtyController;
  Timer? _debounce;

  static String _formatVal(num q) =>
      q % 1 == 0 ? q.toInt().toString() : q.toString();

  @override
  void initState() {
    super.initState();
    _qtyController = TextEditingController(text: _formatVal(widget.qty));
  }

  @override
  void didUpdateWidget(covariant _AdjustmentItemRow oldWidget) {
    super.didUpdateWidget(oldWidget);
    final currentParsed =
        double.tryParse(_qtyController.text.replaceAll(',', '.'));
    if (oldWidget.qty != widget.qty && currentParsed != widget.qty) {
      _qtyController.text = _formatVal(widget.qty);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _qtyController.dispose();
    super.dispose();
  }

  void _onChanged(String val) {
    final normalized = val.replaceAll(',', '.').trim();
    final qty = double.tryParse(normalized);
    if (qty == null) return;
    _debounce?.cancel();
    _debounce = Timer(
        const Duration(milliseconds: 500), () => widget.onQtyChanged(qty));
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(8),
        boxShadow: [
          BoxShadow(color: Colors.black.withValues(alpha: 0.04), blurRadius: 4)
        ],
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  widget.nama,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontWeight: FontWeight.w600, fontSize: 12),
                ),
                Text(
                  widget.kode,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 10, color: Colors.grey.shade600),
                ),
              ],
            ),
          ),
          const SizedBox(width: 6),
          SizedBox(
            width: 64,
            child: TextField(
              controller: _qtyController,
              keyboardType: const TextInputType.numberWithOptions(decimal: true),
              inputFormatters: [
                FilteringTextInputFormatter.allow(RegExp(r'^\d*[\.,]?\d*')),
              ],
              textAlign: TextAlign.center,
              style: const TextStyle(fontSize: 13),
              decoration: const InputDecoration(
                isDense: true,
                contentPadding:
                    EdgeInsets.symmetric(vertical: 6, horizontal: 4),
                border: OutlineInputBorder(),
              ),
              onChanged: _onChanged,
            ),
          ),
          if (widget.uom.isNotEmpty) ...[
            const SizedBox(width: 6),
            Text(
              widget.uom,
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.w600,
                color: Colors.grey.shade700,
              ),
            ),
          ],
          IconButton(
            icon: const Icon(Icons.delete_outline, color: Colors.red, size: 18),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            onPressed: widget.onDelete,
          ),
        ],
      ),
    );
  }
}
