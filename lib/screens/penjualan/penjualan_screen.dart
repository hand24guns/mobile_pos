import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:dio/dio.dart';
import '../../providers/penjualan_provider.dart';
import '../../services/api_service.dart';
import '../../services/session_service.dart';
import '../../services/shift_service.dart';
import '../../models/cart_item.dart';
import '../../utils/currency_format.dart';
import '../../utils/currency_input_formatter.dart';
import '../login_screen.dart';
import '../home_screen.dart';
import '../printer_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../utils/printer_helper.dart';
import '../invoice_list_screen.dart';
// ── Widget baru ───────────────────────────────────────────────
import '../../widgets/package_dialog.dart';
import '../../widgets/add_member_sheet.dart';
import 'package:cached_network_image/cached_network_image.dart';
import 'package:flutter_cache_manager/flutter_cache_manager.dart';

// ── File ini dipecah ke beberapa part untuk maintenance ──
part 'shift.dart';
part 'data.dart';
part 'products.dart';
part 'cart.dart';
part 'payment.dart';
part 'pending.dart';
part 'widgets_header.dart';
part 'widgets_grid.dart';
part 'widgets_cart.dart';
part 'widgets_summary.dart';

class PenjualanScreen extends ConsumerStatefulWidget {
  const PenjualanScreen({super.key});

  @override
  ConsumerState<PenjualanScreen> createState() => _PenjualanScreenState();
}

class _PenjualanScreenState extends ConsumerState<PenjualanScreen> {
  final _skuController = TextEditingController();
  final _memberController = TextEditingController();
  final _nominalController = TextEditingController();
  final _keteranganController = TextEditingController(); // keterangan transaksi
  // FocusNode untuk field SKU — dipakai oleh barcode scanner auto-focus
  final _skuFocusNode = FocusNode();

  // Keyboard virtual hanya muncul saat user tap manual ke field SKU.
  // Scanner fisik inject karakter langsung ke focused field tanpa butuh keyboard.
  // Default false → _focusSku() memberi fokus tanpa membuka keyboard.
  bool _skuKeyboardVisible = false;
  String _activeVoucher = '';

  // Track pending order yang sedang di-retrieve (null = transaksi baru)
  int? _activePendingOrderID;
  String _activePendingLabel = '';

  // Untuk inline notes per item: key = item index, value = controller
  final Map<int, TextEditingController> _itemNotesControllers = {};
  // Set of item indices yang sedang expanded (menampilkan input notes)
  final Set<int> _expandedNotes = {};
  // Set of item indices yang nama produknya sedang expanded (tap-to-expand
  // untuk baca nama panjang dengan banyak addon secara penuh)
  final Set<int> _expandedNames = {};

  String _token = '';
  int _userID = 0;
  String _deviceToken = '';
  int _shiftID = 0;
  bool _isLoading = true;

  // ── Error state untuk load awal (_loadMinimalData) ─────────────
  // Dulu error di chain load awal (cekShiftUser/getStores/getNumber/
  // getChannels/dst) ditelan diam-diam oleh try/catch terluar — hasilnya
  // Scaffold tetap dirender "seolah sukses" (isLoading=false) padahal
  // sebagian data gagal ke-load (channel kosong, grid produk kosong,
  // dsb) tanpa ada tanda apa pun ke kasir. Sekarang dibedakan tegas:
  // gagal → tampilkan layar retry, BUKAN Scaffold kosong yang menipu.
  bool _loadError = false;

  // ── Guard: cegah simpan Pending / Bayar saat ada operasi yang
  // sedang mengubah harga/temp_invoice (insert produk, update qty,
  // hapus item, voucher, ganti channel). Mencegah race condition
  // simpan pending dengan harga yang belum sempat ter-update di server
  // (mis. ganti channel lalu langsung pencet Pending sebelum
  // recalculateChannel selesai → harga lama yang ke-save).
  bool _isCartSyncing = false;

  // ── Shift polling ─────────────────────────────────────────────
  Timer? _shiftPollingTimer;
  int _activeStoreID = 0;
  int _activeOrgID = 0;
  String _activeStoreName = '';
  bool _isFnb = false; // true jika jasa_perusahaan == 3 (FnB/resto)

  List<Map<String, dynamic>> _channels = [];
  List<Map<String, dynamic>> _caraBayarList = [];

  // ── WA disconnect banner ──────────────────────────────────────
  // 1 = WA diaktifkan tapi server WA tidak terdaftar/kosong
  int _waDisconnected = 0;
  bool _waBannerDismissed = false;

  // ── Product image grid — dikelompokkan per kategori (jenis produk) ──
  // Struktur: [ { 'id': int, 'nama': String, 'produk': [ {kode,nama,hpj,image} ] } ]
  List<Map<String, dynamic>> _imageCategories = [];
  bool _isLoadingImages = false;
  // true jika load terakhir GAGAL (network/timeout/parse), dibedakan
  // dari _imageCategories.isEmpty yang berarti "memang tidak ada produk
  // bergambar" — supaya UI bisa tampilkan tombol retry, bukan pesan
  // "tidak ada produk" yang menyesatkan saat penyebabnya koneksi putus.
  bool _imageLoadError = false;

  // ── Anti-double-tap guard untuk image grid ────────────────────
  // Kode yang sedang diproses tidak bisa di-tap lagi sampai selesai.
  final Set<String> _processingKodes = {};

  @override
  void initState() {
    super.initState();
    _loadMinimalData().then((_) => _focusSku());
    _startShiftPolling();
  }

  @override
  void dispose() {
    _shiftPollingTimer?.cancel();
    _skuController.dispose();
    _skuFocusNode.dispose();
    _memberController.dispose();
    _nominalController.dispose();
    _keteranganController.dispose();
    for (final c in _itemNotesControllers.values) {
      c.dispose();
    }
    super.dispose();
  }

  // Wrapper agar extension di file part lain bisa panggil setState
  // tanpa kena warning invalid_use_of_protected_member.
  void _setState(VoidCallback fn) => setState(fn);

  // ============================================================
  // GUARD CART MUTATION
  // Bungkus semua operasi yang mengubah harga/temp_invoice (insert
  // produk/package, update qty, hapus item, apply/remove voucher,
  // ganti channel, recalc member) dengan flag _isCartSyncing.
  // Selama flag ini true, tombol Pending & Bayar otomatis ter-disable
  // (lihat widgets_summary.dart) — mencegah kasir menyimpan pending
  // atau bayar dengan harga yang belum sempat ter-update di server.
  //
  // Dio sudah punya connectTimeout & receiveTimeout 10 detik
  // (api_service.dart) jadi flag ini tidak akan gantung selamanya
  // walau network mati total — worst case ±10 detik lalu ter-unlock
  // otomatis via finally, walau request-nya gagal.
  // ============================================================
  Future<void> _runCartMutation(Future<void> Function() action) async {
    if (_isCartSyncing) return; // sudah ada operasi lain berjalan, abaikan
    if (mounted) _setState(() => _isCartSyncing = true);
    try {
      await action();
    } finally {
      if (mounted) _setState(() => _isCartSyncing = false);
    }
  }

  // Fokus ke field SKU TANPA membuka virtual keyboard.
  // Dipakai setelah insert produk, retrieve pending, reset transaksi, dsb.
  // Scanner fisik tidak butuh keyboard — inject langsung ke focused field.
  void _focusSku() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      // Sembunyikan keyboard dulu kalau sedang terbuka
      _setState(() => _skuKeyboardVisible = false);
      _skuFocusNode.requestFocus();
      // Pastikan keyboard benar-benar tersembunyi
      SystemChannels.textInput.invokeMethod('TextInput.hide');
    });
  }

  // Fokus ke field SKU DAN buka keyboard — dipanggil saat user tap manual.
  void _focusSkuWithKeyboard() {
    _setState(() => _skuKeyboardVisible = true);
    _skuFocusNode.requestFocus();
  }

  // RESPONSIVE HELPERS
  // ============================================================
  // Breakpoint berdasarkan lebar layar (dp):
  //   ≥ 800  → tablet 8"+ landscape   → layout normal
  //   720–799 → tablet 8" portrait / 7.5"
  //   600–719 → tablet 7" landscape
  //   < 600  → tablet 7" portrait     → stacked layout
  double get _screenWidth => MediaQuery.of(context).size.width;
  bool get _isLandscape =>
      MediaQuery.of(context).orientation == Orientation.landscape;

  // _bodyHeight diisi oleh LayoutBuilder (constraints.maxHeight) pada
  // _buildSideBySideLayout / _buildStackedLayout.
  // Nilainya = tinggi setelah SafeArea + AppBar sudah dikurangi —
  // termasuk 3-button navbar (48dp) yang juga sudah dipotong SafeArea.
  // Default 480 agar helpers tidak crash sebelum LayoutBuilder pertama kali build.
  double _bodyHeight = 480;

  // Tiny: body < 500dp landscape (7" dengan 3-btn nav body ~390-530dp)
  bool get _isTinyTablet =>
      _isLandscape ? _bodyHeight < 500 : _screenWidth < 600;

  // Small: body < 620dp landscape (7–8" semua nav type)
  bool get _isSmallTablet =>
      _isLandscape ? _bodyHeight < 620 : _screenWidth < 900;

  // Compact header: aktif di semua tablet 7" landscape (body ≤ 620dp),
  // termasuk gesture nav (~560-600dp) DAN 3-button nav (~390-530dp).
  // Threshold 620 aman untuk 8"+ (body ≥ 650dp) yang tidak perlu compact.
  bool get _isCompactHeader => _isLandscape && _bodyHeight < 620;

  // Tiny header (1 baris): aktif di 7" landscape semua nav type.
  // Hanya store+channel+sku dalam 1 Row sehingga grid dapat ≥300dp
  // ruang dan muat minimal 2 baris produk.
  // Threshold 520 menangkap DPR=1 (body~472dp) dan DPR=1.5 (body~272dp).
  bool get _isHeaderTiny => _isLandscape && _bodyHeight < 520;

  /// Lebar kolom kanan (cart + summary)
  double get _rightPanelWidth {
    if (_isTinyTablet) return _screenWidth * 0.42;
    if (_isSmallTablet) return _screenWidth * 0.40;
    return _screenWidth * 0.36;
  }

  /// Padding umum untuk container (header, summary)
  EdgeInsets get _panelPadding => EdgeInsets.all(
        _isTinyTablet
            ? 6
            : _isSmallTablet
                ? 8
                : 12,
      );

  /// Padding ringkas untuk mode compact
  EdgeInsets get _compactPadding =>
      const EdgeInsets.symmetric(horizontal: 8, vertical: 4);

  /// Font size label utama (Total, store name, dsb.)
  double get _labelFontSize => _isTinyTablet
      ? 12
      : _isSmallTablet
          ? 13
          : 15;

  /// Font size sekunder (kode, harga, grey text)
  double get _smallFontSize => _isTinyTablet ? 10 : 11;

  /// Tinggi tombol aksi (BAYAR, PENDING)
  double get _buttonHeight => _isTinyTablet
      ? 34
      : _isSmallTablet
          ? 38
          : 44;

  /// Jumlah kolom pada grid gambar produk — selalu 4 kolom
  int get _gridColumns => 4;

  // ============================================================
  // BUILD
  // ============================================================
  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    // Load awal gagal total (mis. koneksi putus di tengah chain
    // cekShiftUser/getStores/getNumber/getChannels/dst) — jangan
    // render Scaffold transaksi dengan data yang setengah-setengah,
    // tampilkan layar retry yang jelas.
    if (_loadError) {
      return Scaffold(
        backgroundColor: const Color(0xFFF5F5F5),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.wifi_off_rounded, size: 56, color: Colors.grey.shade400),
                const SizedBox(height: 16),
                const Text(
                  'Gagal memuat data transaksi.\nPeriksa koneksi internet Anda.',
                  textAlign: TextAlign.center,
                  style: TextStyle(fontSize: 15, color: Colors.black87),
                ),
                const SizedBox(height: 20),
                ElevatedButton.icon(
                  onPressed: _retryLoadMinimalData,
                  icon: const Icon(Icons.refresh),
                  label: const Text('Coba Lagi'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D273B),
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 8),
                TextButton(
                  onPressed: _goToHome,
                  child: const Text('Kembali ke Home'),
                ),
              ],
            ),
          ),
        ),
      );
    }

    final state = ref.watch(penjualanProvider);

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: const Color(0xFFF5F5F5),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1D273B),
        title: const Text(
          'POS Aibipi',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
        centerTitle: true,
        actions: [
          IconButton(
            icon: const Icon(Icons.home_outlined, color: Colors.white),
            tooltip: 'Home',
            onPressed: () => Navigator.pushReplacement(
              context,
              MaterialPageRoute(builder: (_) => const HomeScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.receipt, color: Colors.white),
            tooltip: 'Invoice List',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const InvoiceListScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.folder_open, color: Colors.white),
            tooltip: 'Retrieve Order',
            onPressed: _showRetrieveDialog,
          ),
          IconButton(
            icon: const Icon(Icons.print, color: Colors.white),
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(builder: (_) => const PrinterScreen()),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.lock_clock, color: Colors.orange),
            tooltip: 'Tutup Shift',
            onPressed: _tutupShift,
          ),
          IconButton(
            icon: const Icon(Icons.logout, color: Colors.white),
            onPressed: _logout,
          ),
        ],
      ),
      body: SafeArea(
        // SafeArea memastikan konten tidak tertutup navbar/status bar
        // di semua orientasi dan semua jenis navigation (3-button maupun gesture)
        child: Column(
          children: [
            // ── Banner WA disconnect — hanya muncul kalau WA aktif
            // tapi server WA belum dikonfigurasi, dan belum di-dismiss
            if (_waDisconnected == 1 && !_waBannerDismissed)
              MaterialBanner(
                backgroundColor: const Color(0xFFFFF3CD),
                leading: const Icon(
                  Icons.warning_amber_rounded,
                  color: Color(0xFF856404),
                ),
                content: const Text(
                  'Server WA tidak tersambung. Atur di menu Pengaturan.',
                  style: TextStyle(color: Color(0xFF856404), fontSize: 13),
                ),
                actions: [
                  TextButton(
                    onPressed: () => setState(() => _waBannerDismissed = true),
                    child: const Text(
                      'Tutup',
                      style: TextStyle(color: Color(0xFF856404)),
                    ),
                  ),
                ],
              ),
            // ── Layout utama ─────────────────────────────────────
            Expanded(
              child: _isLandscape
                  // ── LAYOUT SIDE-BY-SIDE (landscape) ─────────────────
                  ? _buildSideBySideLayout(state)
                  // ── LAYOUT STACKED (portrait) ────────────────────────
                  : _buildStackedLayout(state),
            ),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // HEADER (store info, channel, member, sku search)
  // Mode compact: aktif di landscape kecil/sedang — field di susun
  // horizontal 2-kolom agar tinggi header ≤ ~140dp
  // ============================================================
}

// ============================================================
// _BukaShiftButton — tombol dengan loading state sendiri
// Dipakai di dalam _showBukaShiftSheet (bottom sheet).
// ============================================================
class _BukaShiftButton extends StatefulWidget {
  final String token;
  final int storeID;
  final int organisasiID;
  final int userID;
  final TextEditingController modalController;
  final void Function(int shiftID) onSuccess;

  const _BukaShiftButton({
    required this.token,
    required this.storeID,
    required this.organisasiID,
    required this.userID,
    required this.modalController,
    required this.onSuccess,
  });

  @override
  State<_BukaShiftButton> createState() => _BukaShiftButtonState();
}

class _BukaShiftButtonState extends State<_BukaShiftButton> {
  bool _isLoading = false;

  @override
  Widget build(BuildContext context) {
    return ElevatedButton(
      onPressed: _isLoading ? null : _handleTap,
      style: ElevatedButton.styleFrom(
        backgroundColor: const Color(0xFF1D273B),
        minimumSize: const Size.fromHeight(48),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      ),
      child: _isLoading
          ? const SizedBox(
              height: 20,
              width: 20,
              child: CircularProgressIndicator(
                color: Colors.white,
                strokeWidth: 2,
              ),
            )
          : const Text(
              'Buka Shift',
              style: TextStyle(
                color: Colors.white,
                fontWeight: FontWeight.bold,
                fontSize: 15,
              ),
            ),
    );
  }

  Future<void> _handleTap() async {
    setState(() => _isLoading = true);

    final modal = _parseModalKasir(widget.modalController.text);

    final shiftID = await ShiftService.bukaShift(
      token: widget.token,
      storeID: widget.storeID,
      organisasiID: widget.organisasiID,
      userID: widget.userID,
      modalKasir: modal,
    );

    if (!mounted) return;

    if (shiftID == 0) {
      setState(() => _isLoading = false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal buka shift'),
          backgroundColor: Colors.red,
        ),
      );
    } else {
      widget.onSuccess(shiftID);
    }
  }
}
