import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import '../services/session_service.dart';
import '../services/auth_service.dart';
import '../services/dashboard_service.dart';
import '../utils/printer_helper.dart';
import 'penjualan/penjualan_screen.dart';
import 'invoice_list_screen.dart';
import 'laporan_pembayaran_screen.dart';
import 'login_screen.dart';
import 'printer_screen.dart';
import 'adjustment_screen.dart';
import 'laporan_screen.dart';
import 'pengaturan_screen.dart';
import 'petikes/petikes_screen.dart';
import 'transfer_order/transfer_order_screen.dart';
import '../services/transfer_order_service.dart';

// ─── Palette ────────────────────────────────────────────────
// Warna utama: slate gelap #151F2C. Gradasi dibuat dengan menaikkan
// lightness secara bertahap di hue yang sama (biru-slate), supaya
// header dan tile terasa satu keluarga tanpa kontras yang keras.
const Color _navy = Color(0xFF151F2C); // utama
const Color _navyMid = Color(0xFF1E2B3D); // tengah gradasi / tooltip
const Color _navyLight = Color(0xFF2A3A50); // ujung gradasi header
const Color _navyAccent = Color(0xFF30476A); // ujung gradasi tile menu
const Color _blue = Color(0xFF2563EB); // aksen / CTA
const Color _blueLight = Color(0xFF3B82F6);
const Color _bgGray = Color(0xFFF2F4F8); // latar halaman, netral-dingin
const Color _green = Color(0xFF22C55E);

// ─── Model menu (data-driven supaya grid mudah ditambah) ─────
class _MenuItem {
  final IconData icon;
  final String label;
  final String description;
  final VoidCallback onTap;
  final bool enabled;
  final int badgeCount;

  const _MenuItem({
    required this.icon,
    required this.label,
    required this.description,
    required this.onTap,
    this.enabled = true,
    this.badgeCount = 0,
  });
}

class _MenuGroup {
  final String title;
  final List<_MenuItem> items;

  const _MenuGroup({required this.title, required this.items});
}

class HomeScreen extends ConsumerStatefulWidget {
  const HomeScreen({super.key});

  @override
  ConsumerState<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends ConsumerState<HomeScreen> {
  String _nama = '';
  String _username = '';
  int _navIndex = 0;

  // Dashboard stats
  int _invoiceHariIni = 0;
  double _totalPenjualan = 0;
  bool _printerConnected = false;
  bool _isLoading = false;
  List<int> _outlets = [];
  List<String> _menus = [];
  List<String> _editable = []; // path menu detail yang user punya is_edit=1
  bool _sessionLoaded = false;

  // Perpindahan Stok (Transfer Order) alert & badge
  int _pendingTransferCount = 0;
  String _firstPendingKode = '';
  String _firstPendingPengirim = '';
  bool _alertDismissed = false;

  // ── Path menu (sesuai kolom `path` di m_menu_pos / m_menu_detail_pos
  //    dan kolom `link` di m_submenu) ─────────────────────────────────
  //
  // Penjualan → m_menu_pos.path = 'Penjualan'
  static const String _menuPathPenjualan = 'Penjualan';
  // Penyesuaian Stok → m_menu_pos.path = 'penyesuaian/Adjustment'
  static const String _menuPathAdjustment = 'penyesuaian/Adjustment';
  // Kas Kecil → m_menu_pos.path = 'petikes/Kas'
  static const String _menuPathKasKecil = 'petikes/Kas';
  // Mutasi Barang (Perpindahan Item) → m_menu_pos.path = 'rolling/TransferOrder'
  static const String _menuPathTransferOrder = 'rolling/TransferOrder';
  // Invoice List → m_submenu.link = 'PenjualanList' (tab Laporan - Penjualan)
  static const String _menuPathInvoice = 'PenjualanList';
  // Rekap Pembayaran → m_submenu.link = 'Pembayaran' (tab Laporan - Pembayaran - Cara Bayar)
  static const String _menuPathRekapBayar = 'Pembayaran';
  // Laporan (bottom nav) → m_menu_detail_pos.path = 'report/PenjualanDetil'
  //   Cukup cek salah satu entry Laporan. Jika ada akses ke submenu laporan
  //   apapun, tombol Laporan di nav sudah aktif.
  static const String _menuPathLaporan = 'report/PenjualanDetil';

  // ── Tooltip "Ubah Password" di header ─────────────────────
  // LayerLink menghubungkan posisi tooltip (OverlayEntry) dengan
  // posisi baris username di header, supaya tooltip muncul persis
  // di bawah nama user terlepas dari ukuran layar.
  final LayerLink _userInfoLink = LayerLink();
  OverlayEntry? _passwordTooltipEntry;

  @override
  void initState() {
    super.initState();
    _loadSession(); // _loadStats() dipanggil di dalam _loadSession setelah session siap
    _checkPrinterStatus(); // cek sekali saat home screen pertama kali dibuka
  }

  @override
  void dispose() {
    _removePasswordTooltip();
    super.dispose();
  }

  // ── Tooltip "Ubah Password" ───────────────────────────────
  // Tap 1x di baris username -> muncul tooltip kecil "Ubah Password".
  // Tap lagi di tooltip itu -> tooltip hilang & dialog ubah password terbuka.
  // Tap di luar tooltip -> tooltip hilang begitu saja.
  void _toggleUserTooltip() {
    if (_passwordTooltipEntry != null) {
      _removePasswordTooltip();
      return;
    }
    final overlay = Overlay.of(context);
    _passwordTooltipEntry = OverlayEntry(
      builder: (_) => Stack(
        children: [
          // Barrier transparan supaya tap di luar tooltip menutupnya
          Positioned.fill(
            child: GestureDetector(
              behavior: HitTestBehavior.translucent,
              onTap: _removePasswordTooltip,
            ),
          ),
          CompositedTransformFollower(
            link: _userInfoLink,
            showWhenUnlinked: false,
            offset: const Offset(0, 22),
            child: Material(
              color: Colors.transparent,
              child: GestureDetector(
                onTap: () {
                  _removePasswordTooltip();
                  _openChangePasswordDialog();
                },
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  decoration: BoxDecoration(
                    color: _navyMid,
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                    ),
                    boxShadow: const [
                      BoxShadow(
                        color: Colors.black38,
                        blurRadius: 10,
                        offset: Offset(0, 4),
                      ),
                    ],
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.lock_reset_rounded,
                        color: Colors.white,
                        size: 16,
                      ),
                      SizedBox(width: 6),
                      Text(
                        'Ubah Password',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 13,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
    overlay.insert(_passwordTooltipEntry!);
  }

  void _removePasswordTooltip() {
    _passwordTooltipEntry?.remove();
    _passwordTooltipEntry = null;
  }

  void _openChangePasswordDialog() {
    showDialog(
      context: context,
      builder: (_) => _ChangePasswordDialog(
        nama: _nama.isNotEmpty ? _nama : _username,
      ),
    );
  }

  // ── Cek status koneksi printer & update card ─────────────────
  // Dipanggil saat home screen pertama dibuka, dan setiap kali user
  // kembali dari modul lain (lihat _pushAndRecheckPrinter). Tidak
  // polling terus-menerus karena card status printer memang cuma
  // terlihat di home screen.
  Future<void> _checkPrinterStatus() async {
    try {
      final connected = await PrinterHelper.isConnected();
      if (!mounted) return;
      if (connected != _printerConnected) {
        setState(() => _printerConnected = connected);
      }
    } catch (_) {
      // Gagal cek (mis. bluetooth adapter error) — anggap disconnected
      if (!mounted) return;
      if (_printerConnected) {
        setState(() => _printerConnected = false);
      }
    }
  }

  // ── Push ke modul lain, lalu re-check status printer saat balik ──
  // Menggantikan Navigator.push biasa untuk semua tile/tombol yang
  // bisa mempengaruhi status printer (Penjualan, Invoice, Printer
  // settings, dll) — begitu route di atasnya di-pop, kita langsung
  // cek ulang PrinterHelper.isConnected() supaya card update tanpa
  // perlu polling berkala.
  Future<void> _pushAndRecheckPrinter(Widget screen) async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => screen));
    if (!mounted) return;
    _checkPrinterStatus();
    _loadStats();
  }

  Future<void> _loadSession() async {
    final session = await SessionService.getSession();
    if (!mounted) return;
    setState(() {
      _nama = session['nama'] ?? '';
      _username = session['username'] ?? '';
      _outlets = List<int>.from(session['outlets'] ?? []);
      _menus = List<String>.from(session['menus'] ?? []);
      _editable = List<String>.from(session['editable'] ?? []);
      _sessionLoaded = true;
    });
    _loadStats();
  }

  // ── Hak akses ────────────────────────────────────────────
  // Sebelum session selesai di-load, anggap semua menu enabled
  // (hindari tile kelihatan disabled sekilas lalu berubah begitu
  // data permission dari sesi datang).

  // Cek apakah path/link ada di _menus (is_view=1).
  bool _hasViewAccess(String menuPath) =>
      !_sessionLoaded || _menus.contains(menuPath);

  // Menu yang butuh STORE + VIEW permission (Penjualan, Penyesuaian,
  // Kas Kecil, Transfer Order): outlet tidak boleh kosong DAN
  // path/link harus ada di _menus.
  bool _hasMenuAccess(String menuPath) =>
      !_sessionLoaded || (_outlets.isNotEmpty && _menus.contains(menuPath));

  // Menu yang hanya butuh VIEW permission tanpa cek outlet:
  // Invoice, Rekap Pembayaran, Laporan (bottom nav).
  bool _hasViewOnlyAccess(String menuPath) => _hasViewAccess(menuPath);

  bool get _hasPenjualanAccess => _hasMenuAccess(_menuPathPenjualan);
  bool get _hasInvoiceAccess => _hasViewOnlyAccess(_menuPathInvoice);
  bool get _hasRekapBayarAccess => _hasViewOnlyAccess(_menuPathRekapBayar);
  bool get _hasAdjustmentAccess => _hasMenuAccess(_menuPathAdjustment);
  bool get _hasKasKecilAccess => _hasMenuAccess(_menuPathKasKecil);
  bool get _hasTransferAccess => _hasMenuAccess(_menuPathTransferOrder);
  bool get _hasLaporanAccess =>
      !_sessionLoaded ||
      _menus.contains('laporan') ||
      _menus.contains('Laporan') ||
      _menus.contains(_menuPathLaporan);

  // Warning generik untuk menu yang membutuhkan izin akses.
  void _showNoMenuAccessWarning(String menuName, {bool storeBound = false}) {
    final reason = (storeBound && _outlets.isEmpty)
        ? 'Akun kamu belum memiliki akses ke store manapun.'
        : 'Akun kamu tidak memiliki izin akses menu $menuName.';

    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.lock_outline_rounded, color: _navy, size: 32),
        title: const Text('Tidak Ada Akses'),
        content: Text('$reason Silakan hubungi admin untuk mendapatkan akses.'),
        actions: [
          ElevatedButton(
            onPressed: () => Navigator.pop(context),
            style: ElevatedButton.styleFrom(backgroundColor: _navy),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  Future<void> _loadStats() async {
    if (!mounted) return;
    setState(() => _isLoading = true);

    try {
      final stats = await DashboardService.getStats(storeIds: _outlets);

      if (!mounted) return;

      setState(() {
        if (_outlets.isEmpty && stats.storeIds.isNotEmpty) {
          _outlets = stats.storeIds;
        }
        _invoiceHariIni = stats.invoiceCount;
        _totalPenjualan = stats.totalPenjualan;
      });

      // Ambil jumlah dokumen transfer order masuk (barang datang)
      try {
        final transferRes = await TransferOrderService.getPendingTransferCount(
          storeIds: _outlets,
        );
        if (mounted && transferRes['success'] == true) {
          setState(() {
            _pendingTransferCount = transferRes['count'] ?? 0;
            final items = transferRes['data'] as List?;
            if (items != null && items.isNotEmpty) {
              _firstPendingKode = items[0]['kode']?.toString() ?? '';
              _firstPendingPengirim =
                  items[0]['toko_pengirim']?.toString() ?? '';
            } else {
              _firstPendingKode = '';
              _firstPendingPengirim = '';
            }
          });
        }
      } catch (_) {}
    } catch (_) {
      // Gagal fetch — biarkan nilai 0, user bisa pull-to-refresh
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _greeting() {
    final hour = DateTime.now().hour;
    if (hour < 11) return 'Selamat Pagi';
    if (hour < 15) return 'Selamat Siang';
    if (hour < 18) return 'Selamat Sore';
    return 'Selamat Malam';
  }

  Future<void> _logout() async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Keluar'),
        content: const Text('Yakin ingin keluar dari aplikasi?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: _navy),
            child: const Text('Keluar', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirm == true && mounted) {
      await AuthService.logout();
      if (!mounted) return;
      Navigator.pushAndRemoveUntil(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
        (_) => false,
      );
    }
  }

  // ── Pages for bottom nav ─────────────────────────────────
  Widget _buildBody() {
    switch (_navIndex) {
      case 1:
        // Laporan: guard di sini kalau-kalau _navIndex sempat ke-set 1 sebelumnya
        return _hasLaporanAccess
            ? LaporanScreen(outlets: _outlets)
            : _buildHomeContent();
      case 2:
        // Kas Kecil: guard di sini kalau-kalau _navIndex sempat ke-set 2 sebelumnya
        return _hasKasKecilAccess
            ? KasKecilScreen(outlets: _outlets)
            : _buildHomeContent();
      case 3:
        // Pengaturan: pass menus & editable untuk permission check Outlet
        return PengaturanScreen(
          outlets: _outlets,
          menus: _menus,
          editable: _editable,
        );
      default:
        return _buildHomeContent();
    }
  }

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.of(context).size.width;
    final isTablet = screenWidth >= 600;

    return Scaffold(
      backgroundColor: _bgGray,
      body: Column(
        children: [
          _buildHeader(isTablet),
          Expanded(child: _buildBody()),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  // ============================================================
  // HEADER
  // ============================================================
  Widget _buildHeader(bool isTablet) {
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
          padding: EdgeInsets.symmetric(
            horizontal: isTablet ? 28.0 : 20.0,
            vertical: isTablet ? 20.0 : 16.0,
          ),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              // Logo
              Container(
                width: isTablet ? 64 : 54,
                height: isTablet ? 64 : 54,
                decoration: BoxDecoration(
                  color: Colors.white.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: Colors.white.withValues(alpha: 0.3),
                    width: 1.5,
                  ),
                ),
                clipBehavior: Clip.antiAlias,
                child: Image.asset(
                  'assets/icon/app_icon.png',
                  fit: BoxFit.cover,
                  errorBuilder: (_, __, ___) => Center(
                    child: Text(
                      'A',
                      style: TextStyle(
                        color: Colors.white,
                        fontWeight: FontWeight.bold,
                        fontSize: isTablet ? 28 : 24,
                      ),
                    ),
                  ),
                ),
              ),
              const SizedBox(width: 14),
              // Greeting + info
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Row(
                      children: [
                        Flexible(
                          child: Text(
                            '${_greeting()}, ${_nama.isNotEmpty ? _nama : _username} 👋',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: isTablet ? 20 : 16,
                            ),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Text(
                          'AIBIPI POS',
                          style: TextStyle(
                            color: Colors.white70,
                            fontSize: isTablet ? 13 : 12,
                            letterSpacing: 0.5,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: _blueLight.withValues(alpha: 0.35),
                            borderRadius: BorderRadius.circular(20),
                            border: Border.all(
                              color: _blueLight.withValues(alpha: 0.5),
                            ),
                          ),
                          child: Text(
                            'Mobile',
                            style: TextStyle(
                              color: Colors.white,
                              fontSize: isTablet ? 11 : 10,
                              fontWeight: FontWeight.w600,
                            ),
                          ),
                        ),
                      ],
                    ),
                    if (_username.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      CompositedTransformTarget(
                        link: _userInfoLink,
                        child: GestureDetector(
                          behavior: HitTestBehavior.opaque,
                          onTap: _toggleUserTooltip,
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              const Icon(
                                Icons.person_outline,
                                color: Colors.white54,
                                size: 13,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'User: $_username',
                                style: TextStyle(
                                  color: Colors.white54,
                                  fontSize: isTablet ? 12 : 11,
                                  decoration: TextDecoration.underline,
                                  decorationColor: Colors.white38,
                                  decorationStyle: TextDecorationStyle.dotted,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              // Action buttons
              _HeaderIconBtn(
                icon: Icons.print_rounded,
                label: 'Printer',
                onTap: () => _pushAndRecheckPrinter(const PrinterScreen()),
                isTablet: isTablet,
              ),
              const SizedBox(width: 8),
              _HeaderIconBtn(
                icon: Icons.logout_rounded,
                label: 'Logout',
                onTap: _logout,
                isTablet: isTablet,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // HOME CONTENT
  // ============================================================

  // Daftar menu dikelompokkan per fungsi. Menambah menu baru cukup
  // menambah _MenuItem di sini — grid yang mengatur kolom & baris.
  //
  // Setiap card aktif (enabled) hanya jika user punya is_view=1 untuk
  // path/link menu yang sesuai (disimpan di _menus saat login):
  //   • Penjualan        → path 'Penjualan'   + akses outlet
  //   • Invoice          → link 'PenjualanList'     (submenu tab)
  //   • Rekap Pembayaran → link 'Pembayaran'        (submenu tab)
  //   • Penyesuaian Stok → path 'penyesuaian/Adjustment' + outlet
  //   • Perpindahan Produk → path 'rolling/TransferOrder'  + outlet
  // Setting Printer tidak dibatasi permission (selalu aktif).
  List<_MenuGroup> _menuGroups() {
    return [
      _MenuGroup(
        title: 'Transaksi',
        items: [
          // Penjualan: is_view=1 di 'Penjualan' + akses outlet
          _MenuItem(
            icon: Icons.shopping_cart_rounded,
            label: 'PENJUALAN',
            description: 'Kasir & transaksi penjualan produk',
            enabled: _hasPenjualanAccess,
            onTap: _hasPenjualanAccess
                ? () => _pushAndRecheckPrinter(const PenjualanScreen())
                : () => _showNoMenuAccessWarning('Penjualan', storeBound: true),
          ),
          // Invoice: submenu 'PenjualanList' is_view=1
          // (Laporan - Penjualan - tab Invoice List)
          _MenuItem(
            icon: Icons.description_rounded,
            label: 'INVOICE',
            description: 'Riwayat transaksi & cetak ulang invoice',
            enabled: _hasInvoiceAccess,
            onTap: _hasInvoiceAccess
                ? () => _pushAndRecheckPrinter(const InvoiceListScreen())
                : () => _showNoMenuAccessWarning('Invoice'),
          ),
          // Rekap Pembayaran: submenu 'Pembayaran' is_view=1
          // (Laporan - Pembayaran - submenu Cara Bayar)
          _MenuItem(
            icon: Icons.payments_rounded,
            label: 'REKAP PEMBAYARAN',
            description: 'Rekap omset per metode pembayaran',
            enabled: _hasRekapBayarAccess,
            onTap: _hasRekapBayarAccess
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const LaporanPembayaranScreen(),
                      ),
                    )
                : () => _showNoMenuAccessWarning('Rekap Pembayaran'),
          ),
        ],
      ),
      _MenuGroup(
        title: 'Stok dan Gudang',
        items: [
          // Penyesuaian Stok: 'penyesuaian/Adjustment' is_view=1 + outlet
          _MenuItem(
            icon: Icons.inventory_2_rounded,
            label: 'PENYESUAIAN STOK',
            description: 'Pengajuan penyesuaian stok',
            enabled: _hasAdjustmentAccess,
            onTap: _hasAdjustmentAccess
                ? () => Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (_) => const AdjustmentScreen(),
                      ),
                    )
                : () => _showNoMenuAccessWarning('Penyesuaian Stok',
                    storeBound: true),
          ),
          // Perpindahan Item (Mutasi Barang): 'rolling/TransferOrder' is_view=1 + outlet
          _MenuItem(
            icon: Icons.local_shipping_rounded,
            label: 'TRANSFER ITEM',
            description: 'Terima barang gudang pusat & transfer antar toko',
            badgeCount: _pendingTransferCount,
            enabled: _hasTransferAccess,
            onTap: _hasTransferAccess
                ? () => _pushAndRecheckPrinter(
                      TransferOrderScreen(outlets: _outlets),
                    )
                : () =>
                    _showNoMenuAccessWarning('Transfer Item', storeBound: true),
          ),
        ],
      ),
    ];
  }

  Widget _buildHomeContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final compact = h < 480;
        final hPad = w >= 800 ? 28.0 : 16.0;
        final vPad = compact ? 12.0 : 20.0;
        final gap = compact ? 10.0 : 16.0;

        // Tablet / layar lebar: 3 kolom, tile horizontal (ringkas).
        // HP / layar sempit: 2 kolom, tile vertikal seperti sebelumnya.
        final isWide = w >= 600;
        final columns = isWide ? 3 : 2;

        return RefreshIndicator(
          color: _blue,
          onRefresh: _loadStats,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Alert Dokumen Barang Datang (seperti di web alert-center) ──
                if (_pendingTransferCount > 0 && !_alertDismissed) ...[
                  _buildPendingTransferAlert(compact),
                  SizedBox(height: compact ? 10 : 16),
                ],

                // ── Stat Cards ───────────────────────────────
                _buildStatCards(compact: compact, gap: gap, w: w),
                SizedBox(height: compact ? 12 : 20),

                // ── Grup menu ───────────────────────────────
                for (final group in _menuGroups()) ...[
                  _buildGroupTitle(group.title, compact),
                  SizedBox(height: compact ? 10 : 14),
                  _buildMenuGrid(
                    items: group.items,
                    columns: columns,
                    horizontal: isWide,
                    compact: compact,
                    gap: gap,
                  ),
                  SizedBox(height: compact ? 12 : 20),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildPendingTransferAlert(bool compact) {
    final title = _pendingTransferCount == 1 && _firstPendingKode.isNotEmpty
        ? 'Pengiriman Barang Masuk ($_firstPendingKode)'
        : 'Ada $_pendingTransferCount Pengiriman Barang Masuk';

    final message = _pendingTransferCount == 1 &&
            _firstPendingPengirim.isNotEmpty
        ? 'Ada pengiriman barang dari $_firstPendingPengirim yang harus dikonfirmasi penerimaannya.'
        : 'Terdapat $_pendingTransferCount dokumen pengiriman barang masuk yang menunggu konfirmasi di toko Anda.';

    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFFEFF6FF),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: const Color(0xFFBFDBFE), width: 1.2),
        boxShadow: [
          BoxShadow(
            color: _blue.withValues(alpha: 0.05),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 12 : 16,
        vertical: compact ? 10 : 12,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: _blue.withValues(alpha: 0.12),
              shape: BoxShape.circle,
            ),
            child: const Icon(
              Icons.local_shipping_rounded,
              color: _blue,
              size: 20,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        title,
                        style: const TextStyle(
                          fontSize: 13,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1E3A8A),
                        ),
                      ),
                    ),
                    InkWell(
                      onTap: () => setState(() => _alertDismissed = true),
                      borderRadius: BorderRadius.circular(12),
                      child: const Padding(
                        padding: EdgeInsets.all(2.0),
                        child: Icon(Icons.close_rounded,
                            size: 16, color: Colors.blueGrey),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 3),
                Text(
                  message,
                  style: const TextStyle(
                    fontSize: 12,
                    color: Color(0xFF1E40AF),
                  ),
                ),
                const SizedBox(height: 8),
                InkWell(
                  onTap: () => _pushAndRecheckPrinter(
                    TransferOrderScreen(outlets: _outlets),
                  ),
                  child: const Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Konfirmasi Penerimaan',
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: _blue,
                        ),
                      ),
                      SizedBox(width: 4),
                      Icon(Icons.arrow_forward_rounded, size: 14, color: _blue),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildGroupTitle(String title, bool compact) {
    return Row(
      children: [
        Text(
          title,
          style: TextStyle(
            color: _navy,
            fontWeight: FontWeight.bold,
            fontSize: compact ? 13 : 16,
          ),
        ),
        const SizedBox(width: 8),
        Container(
          width: 28,
          height: 3,
          decoration: BoxDecoration(
            color: _blue,
            borderRadius: BorderRadius.circular(2),
          ),
        ),
      ],
    );
  }

  // Grid sederhana berbasis Row: item dipecah per [columns]. Di layar
  // lebar, sisa slot di baris terakhir diisi ruang kosong supaya lebar
  // tile tetap 1/columns. Di HP, tile tunggal di baris terakhir
  // melebar penuh.
  Widget _buildMenuGrid({
    required List<_MenuItem> items,
    required int columns,
    required bool horizontal,
    required bool compact,
    required double gap,
  }) {
    final rows = <Widget>[];

    for (var i = 0; i < items.length; i += columns) {
      final end = (i + columns < items.length) ? i + columns : items.length;
      final chunk = items.sublist(i, end);
      final cells = <Widget>[];

      for (var j = 0; j < columns; j++) {
        final hasItem = j < chunk.length;
        if (!hasItem && !horizontal) break;
        if (j > 0) cells.add(SizedBox(width: gap));

        if (hasItem) {
          final item = chunk[j];
          cells.add(
            Expanded(
              child: _MenuTile(
                icon: item.icon,
                label: item.label,
                description: item.description,
                compact: compact,
                horizontal: horizontal,
                enabled: item.enabled,
                badgeCount: item.badgeCount,
                onTap: item.onTap,
              ),
            ),
          );
        } else {
          cells.add(const Expanded(child: SizedBox.shrink()));
        }
      }

      if (rows.isNotEmpty) rows.add(SizedBox(height: gap));
      rows.add(Row(children: cells));
    }

    return Column(children: rows);
  }

  // ── Stat Cards ───────────────────────────────────────────
  // Tablet / layar lebar (w >= 600): 1 row, 3 card sejajar.
  // HP / layar sempit  (w <  600): row 1 = 1 card besar (Total
  // Penjualan), row 2 = 2 card kecil (Invoice Hari Ini & Status Printer).
  Widget _buildStatCards({
    required bool compact,
    required double gap,
    required double w,
  }) {
    final totalPenjualanCard = _MiniStatCard(
      icon: Icons.trending_up_rounded,
      iconBg: const Color(0xFFF0FFF4),
      iconColor: _green,
      title: 'Total Penjualan',
      value: _isLoading ? '...' : _formatRupiah(_totalPenjualan),
      valueColor: _navy,
      compact: compact,
      loading: _isLoading,
    );

    final invoiceCard = _MiniStatCard(
      icon: Icons.receipt_long_rounded,
      iconBg: const Color(0xFFEFF6FF),
      iconColor: _blue,
      title: 'Invoice Hari Ini',
      value: _isLoading ? '...' : '$_invoiceHariIni Invoice',
      valueColor: _blue,
      compact: compact,
      loading: _isLoading,
    );

    final printerCard = _MiniStatCard(
      icon: Icons.print_rounded,
      iconBg: const Color(0xFFF5F3FF),
      iconColor: const Color(0xFF7C3AED),
      title: 'Status Printer',
      value: _printerConnected ? 'Connected ●' : 'Disconnected ○',
      valueColor: _printerConnected ? _green : Colors.red,
      compact: compact,
      loading: false,
    );

    if (w < 600) {
      // ── Layar sempit (HP): 1 card besar + 2 card kecil ──
      return Column(
        children: [
          _MiniStatCard(
            icon: Icons.trending_up_rounded,
            iconBg: const Color(0xFFF0FFF4),
            iconColor: _green,
            title: 'Total Penjualan',
            value: _isLoading ? '...' : _formatRupiah(_totalPenjualan),
            valueColor: _navy,
            compact: compact,
            loading: _isLoading,
            large: true,
          ),
          SizedBox(height: gap),
          Row(
            children: [
              Expanded(child: invoiceCard),
              SizedBox(width: gap),
              Expanded(child: printerCard),
            ],
          ),
        ],
      );
    }

    // ── Layar lebar (tablet): 3 card sejajar 1 row ──
    return Row(
      children: [
        Expanded(child: invoiceCard),
        SizedBox(width: gap),
        Expanded(child: totalPenjualanCard),
        SizedBox(width: gap),
        Expanded(child: printerCard),
      ],
    );
  }

  String _formatRupiah(double val) {
    if (val == 0) return 'Rp 0';
    final parts = val.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
    return 'Rp $parts';
  }

  // ── Bottom Nav ────────────────────────────────────────────
  Widget _buildBottomNav() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.08),
            blurRadius: 12,
            offset: const Offset(0, -2),
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Row(
          children: [
            _BottomNavItem(
              icon: Icons.home_rounded,
              label: 'Beranda',
              selected: _navIndex == 0,
              onTap: () => setState(() => _navIndex = 0),
            ),
            // Laporan: aktif jika user punya is_view=1 pada salah satu
            // menu detail Laporan (mis. 'report/PenjualanDetil').
            _BottomNavItem(
              icon: Icons.bar_chart_rounded,
              label: 'Laporan',
              selected: _hasLaporanAccess && _navIndex == 1,
              enabled: _hasLaporanAccess,
              onTap: _hasLaporanAccess
                  ? () => setState(() => _navIndex = 1)
                  : () => _showNoMenuAccessWarning('Laporan'),
            ),
            // Kas Kecil: aktif jika 'petikes/Kas' is_view=1 + outlet
            _BottomNavItem(
              icon: Icons.wallet_outlined,
              label: 'Kas Kecil',
              selected: _hasKasKecilAccess && _navIndex == 2,
              enabled: _hasKasKecilAccess,
              onTap: _hasKasKecilAccess
                  ? () => setState(() => _navIndex = 2)
                  : () =>
                      _showNoMenuAccessWarning('Kas Kecil', storeBound: true),
            ),
            _BottomNavItem(
              icon: Icons.settings_rounded,
              label: 'Pengaturan',
              selected: _navIndex == 3,
              onTap: () => setState(() => _navIndex = 3),
            ),
          ],
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET: _HeaderIconBtn
// ============================================================
class _HeaderIconBtn extends StatelessWidget {
  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final bool isTablet;

  const _HeaderIconBtn({
    required this.icon,
    required this.label,
    required this.onTap,
    required this.isTablet,
  });

  @override
  Widget build(BuildContext context) {
    final size = isTablet ? 52.0 : 46.0;
    return GestureDetector(
      onTap: onTap,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: size,
            height: size,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
            ),
            child: Icon(icon, color: Colors.white, size: isTablet ? 24 : 22),
          ),
          const SizedBox(height: 4),
          Text(
            label,
            style: TextStyle(
              color: Colors.white70,
              fontSize: isTablet ? 11 : 10,
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WIDGET: _MiniStatCard  (compact horizontal layout)
// ============================================================
class _MiniStatCard extends StatelessWidget {
  final IconData icon;
  final Color iconBg;
  final Color iconColor;
  final String title;
  final String value;
  final Color valueColor;
  final bool compact;
  final bool loading;
  final bool large;

  const _MiniStatCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.valueColor,
    required this.compact,
    this.loading = false,
    this.large = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = large ? 46.0 : (compact ? 30.0 : 38.0);
    final pad = large ? 16.0 : (compact ? 10.0 : 14.0);

    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Row(
        children: [
          Container(
            width: iconSize,
            height: iconSize,
            decoration: BoxDecoration(
              color: iconBg,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
              icon,
              color: iconColor,
              size: large ? 24 : (compact ? 15 : 19),
            ),
          ),
          SizedBox(width: large ? 14 : (compact ? 7 : 10)),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: large ? 12 : (compact ? 9 : 10),
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                SizedBox(height: large ? 4 : 2),
                loading
                    ? Container(
                        height: large ? 18 : (compact ? 11 : 14),
                        width: large ? 100 : 60,
                        decoration: BoxDecoration(
                          color: Colors.grey[200],
                          borderRadius: BorderRadius.circular(4),
                        ),
                      )
                    : Text(
                        value,
                        style: TextStyle(
                          color: valueColor,
                          fontWeight: FontWeight.bold,
                          fontSize: large ? 20 : (compact ? 11 : 14),
                        ),
                        overflow: TextOverflow.ellipsis,
                        maxLines: 1,
                      ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WIDGET: _MenuTile
// ============================================================
// Dua varian:
//  - horizontal == true  : kartu ringkas (ikon kiri, teks kanan) untuk
//                          tablet / layar lebar, tinggi tetap.
//  - horizontal == false : kartu vertikal dengan tombol CTA untuk HP.
// Saat enabled == false, tile jadi abu-abu + gembok dan tetap bisa
// di-tap (onTap dipakai untuk menampilkan warning akses).
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool compact;
  final bool horizontal;
  final VoidCallback onTap;
  final bool enabled;
  final int badgeCount;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.compact,
    required this.onTap,
    this.horizontal = false,
    this.enabled = true,
    this.badgeCount = 0,
  });

  BoxDecoration _decoration(double radius) {
    return BoxDecoration(
      gradient: enabled
          ? const LinearGradient(
              colors: [_navy, _navyMid, _navyAccent],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            )
          : LinearGradient(
              colors: [Colors.grey.shade500, Colors.grey.shade600],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
      borderRadius: BorderRadius.circular(radius),
      boxShadow: [
        BoxShadow(
          color: (enabled ? _navy : Colors.grey).withValues(alpha: 0.3),
          blurRadius: 10,
          offset: const Offset(0, 3),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    return horizontal ? _buildHorizontal() : _buildVertical();
  }

  // ── Varian horizontal (tablet) ───────────────────────────
  Widget _buildHorizontal() {
    final iconBox = compact ? 38.0 : 48.0;
    final pad = compact ? 10.0 : 14.0;
    final height = compact ? 62.0 : 88.0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(14),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(14),
        child: Ink(
          height: height,
          decoration: _decoration(14),
          child: Padding(
            padding: EdgeInsets.symmetric(horizontal: pad),
            child: Row(
              children: [
                Container(
                  width: iconBox,
                  height: iconBox,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: Colors.white.withValues(alpha: 0.15),
                      width: 1,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: Colors.white,
                    size: compact ? 20 : 26,
                  ),
                ),
                SizedBox(width: compact ? 10 : 12),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        label,
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: compact ? 12 : 14,
                          letterSpacing: 0.3,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (!compact) ...[
                        const SizedBox(height: 3),
                        Text(
                          enabled ? description : 'Tidak ada akses',
                          style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 11,
                          ),
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ],
                  ),
                ),
                const SizedBox(width: 8),
                if (badgeCount > 0) ...[
                  Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                    decoration: BoxDecoration(
                      color: const Color(0xFFEF4444),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: Colors.white, width: 1),
                    ),
                    child: Text(
                      '$badgeCount',
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  const SizedBox(width: 6),
                ],
                Container(
                  width: compact ? 24 : 28,
                  height: compact ? 24 : 28,
                  decoration: BoxDecoration(
                    color: Colors.white.withValues(alpha: 0.15),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    enabled
                        ? Icons.arrow_forward_ios_rounded
                        : Icons.lock_outline_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ── Varian vertikal (HP) ─────────────────────────────────
  Widget _buildVertical() {
    final iconBox = compact ? 44.0 : 64.0;
    final pad = compact ? 14.0 : 20.0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: _decoration(16),
          child: Padding(
            padding: EdgeInsets.all(pad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top row: Icon + arrow
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      width: iconBox,
                      height: iconBox,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.15),
                          width: 1,
                        ),
                      ),
                      child: Icon(
                        icon,
                        color: Colors.white,
                        size: compact ? 22 : 32,
                      ),
                    ),
                    const Spacer(),
                    if (badgeCount > 0) ...[
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 3),
                        decoration: BoxDecoration(
                          color: const Color(0xFFEF4444),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white, width: 1.2),
                        ),
                        child: Text(
                          '$badgeCount Baru',
                          style: const TextStyle(
                            color: Colors.white,
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      const SizedBox(width: 6),
                    ],
                    Container(
                      width: compact ? 26 : 32,
                      height: compact ? 26 : 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.15),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        enabled
                            ? Icons.arrow_forward_ios_rounded
                            : Icons.lock_outline_rounded,
                        color: Colors.white,
                        size: 12,
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 8 : 12),
                // Label
                Text(
                  label,
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: compact ? 14 : 18,
                    letterSpacing: 0.3,
                  ),
                ),
                if (!compact) ...[
                  const SizedBox(height: 4),
                  Text(
                    description,
                    style: const TextStyle(color: Colors.white70, fontSize: 11),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
                SizedBox(height: compact ? 10 : 16),
                // CTA button
                Container(
                  padding: EdgeInsets.symmetric(
                    horizontal: compact ? 10 : 14,
                    vertical: compact ? 6 : 8,
                  ),
                  decoration: BoxDecoration(
                    color:
                        enabled ? _blue : Colors.white.withValues(alpha: 0.25),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        enabled ? 'Buka Sekarang' : 'Tidak Ada Akses',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: compact ? 10 : 11,
                        ),
                      ),
                      const SizedBox(width: 4),
                      Icon(
                        enabled
                            ? Icons.arrow_forward_rounded
                            : Icons.lock_outline_rounded,
                        color: Colors.white,
                        size: 11,
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET: _BottomNavItem
// ============================================================
class _BottomNavItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;
  final bool enabled;

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
    this.enabled = true,
  });

  // Icon default tab ini memang sudah abu-abu saat tidak terpilih,
  // jadi "abu-abu biasa" tidak cukup untuk menandakan disabled. Saat
  // enabled == false, icon digambar lebih pudar DAN dicoret diagonal
  // (mirip tanda "no entry" tapi versi garis saja) supaya beda kentara
  // dari state "sekedar belum dipilih".
  Widget _buildIcon() {
    if (!enabled) {
      return SizedBox(
        width: 24,
        height: 24,
        child: Stack(
          alignment: Alignment.center,
          children: [
            Icon(icon, color: Colors.grey.shade300, size: 24),
            Transform.rotate(
              angle: -0.7854, // -45 derajat
              child: Container(
                width: 26,
                height: 2,
                decoration: BoxDecoration(
                  color: Colors.grey.shade500,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ),
      );
    }
    return Icon(icon, color: selected ? _blue : Colors.grey[400], size: 24);
  }

  @override
  Widget build(BuildContext context) {
    final labelColor =
        !enabled ? Colors.grey.shade300 : (selected ? _blue : Colors.grey[400]);

    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              _buildIcon(),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: labelColor,
                  fontSize: 11,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

// ============================================================
// WIDGET: _ChangePasswordDialog
// ============================================================
// Popup ubah password: nama (info saja), password baru (dengan
// toggle mata/masking), dan ulangi password. Tombol "Simpan" baru
// aktif kalau password & ulangi password terisi, sama persis, dan
// memenuhi panjang minimal.
class _ChangePasswordDialog extends StatefulWidget {
  final String nama;

  const _ChangePasswordDialog({required this.nama});

  @override
  State<_ChangePasswordDialog> createState() => _ChangePasswordDialogState();
}

class _ChangePasswordDialogState extends State<_ChangePasswordDialog> {
  final _passwordCtrl = TextEditingController();
  final _rePasswordCtrl = TextEditingController();

  bool _obscurePassword = true;
  bool _obscureRePassword = true;
  bool _isSaving = false;
  String? _errorText;

  bool get _passwordsMatch =>
      _rePasswordCtrl.text.isEmpty ||
      _passwordCtrl.text == _rePasswordCtrl.text;

  bool get _isValid {
    final p = _passwordCtrl.text;
    final rp = _rePasswordCtrl.text;
    return p.isNotEmpty && p == rp;
  }

  @override
  void dispose() {
    _passwordCtrl.dispose();
    _rePasswordCtrl.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _errorText = null;
    });

    try {
      final result = await AuthService.changePassword(
        password: _passwordCtrl.text,
        passwordConfirmation: _rePasswordCtrl.text,
      );

      if (!mounted) return;

      if (result['success'] == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(result['message'] ?? 'Password berhasil diubah'),
          ),
        );
      } else {
        setState(() {
          _errorText = result['message'] ?? 'Gagal mengubah password';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorText = 'Gagal terhubung ke server');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      title: const Text('Ubah Password'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Nama user — info saja, tidak bisa diedit
            Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 10,
              ),
              decoration: BoxDecoration(
                color: Colors.grey[100],
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: Colors.grey.shade300),
              ),
              child: Row(
                children: [
                  const Icon(
                    Icons.person_outline,
                    size: 18,
                    color: Colors.grey,
                  ),
                  const SizedBox(width: 8),
                  Flexible(
                    child: Text(
                      widget.nama,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 14),

            // Password baru
            TextField(
              controller: _passwordCtrl,
              obscureText: _obscurePassword,
              autofocus: true,
              decoration: InputDecoration(
                labelText: 'Password Baru',
                border: const OutlineInputBorder(),
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscurePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () =>
                      setState(() => _obscurePassword = !_obscurePassword),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),
            const SizedBox(height: 12),

            // Ulangi password
            TextField(
              controller: _rePasswordCtrl,
              obscureText: _obscureRePassword,
              decoration: InputDecoration(
                labelText: 'Ulangi Password',
                border: const OutlineInputBorder(),
                errorText: _passwordsMatch ? null : 'Password tidak sama',
                suffixIcon: IconButton(
                  icon: Icon(
                    _obscureRePassword
                        ? Icons.visibility_off_outlined
                        : Icons.visibility_outlined,
                  ),
                  onPressed: () => setState(
                    () => _obscureRePassword = !_obscureRePassword,
                  ),
                ),
              ),
              onChanged: (_) => setState(() {}),
            ),

            if (_errorText != null) ...[
              const SizedBox(height: 10),
              Text(
                _errorText!,
                style: const TextStyle(color: Colors.red, fontSize: 12),
              ),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: _isSaving ? null : () => Navigator.pop(context),
          child: const Text('Batal'),
        ),
        ElevatedButton(
          onPressed: (_isValid && !_isSaving) ? _submit : null,
          style: ElevatedButton.styleFrom(backgroundColor: _navy),
          child: _isSaving
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: Colors.white,
                  ),
                )
              : const Text('Simpan', style: TextStyle(color: Colors.white)),
        ),
      ],
    );
  }
}
