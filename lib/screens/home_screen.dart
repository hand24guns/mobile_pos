import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/session_service.dart';
import '../services/api_service.dart';
import '../utils/printer_helper.dart'; // TODO: sesuaikan path ini dengan lokasi printer_helper.dart di project-mu
import 'penjualan/penjualan_screen.dart';
import 'invoice_list_screen.dart';
import 'laporan_pembayaran_screen.dart';
import 'login_screen.dart';
import 'printer_screen.dart';
import 'adjustment_screen.dart';
import 'laporan_screen.dart';
import 'pengaturan_screen.dart';

// ─── Palette ────────────────────────────────────────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A2F5A);
const Color _navyLight = Color(0xFF243B6E);
const Color _blue = Color(0xFF2563EB);
const Color _blueLight = Color(0xFF3B82F6);
const Color _bgGray = Color(0xFFF0F4FA);
const Color _cardWhite = Colors.white;
const Color _green = Color(0xFF22C55E);

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
  bool _sessionLoaded = false;

  // Path menu di m_menu_pos yang mewakili fitur Penyesuaian (sama
  // dengan path yang dipakai sidebar.php versi web).
  static const String _menuPathAdjustment = 'penyesuaian/Adjustment';

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
  }

  Future<void> _loadSession() async {
    final session = await SessionService.getSession();
    if (!mounted) return;
    setState(() {
      _nama = session['nama'] ?? '';
      _username = session['username'] ?? '';
      _outlets = List<int>.from(session['outlets'] ?? []);
      _menus = List<String>.from(session['menus'] ?? []);
      _sessionLoaded = true;
    });
    _loadStats();
  }

  // User tanpa akses store (belum terdaftar di m_user_divisi) tidak
  // boleh masuk ke Penjualan/Penyesuaian — form-nya akan kosong/rusak
  // karena tidak ada store yang bisa dipilih. Sebelum session selesai
  // di-load, anggap dulu enabled (hindari tile kelihatan disabled
  // sekilas lalu berubah begitu data outlet datang).
  bool get _hasStoreAccess => !_sessionLoaded || _outlets.isNotEmpty;

  // Penyesuaian butuh DUA syarat: akses store (sama seperti Penjualan)
  // DAN akses menu "Penyesuaian" dari grup user (m_user_grup ->
  // m_grup_menu -> m_menu_pos), sama seperti yang dicek sidebar.php
  // di versi web.
  bool get _hasAdjustmentAccess =>
      !_sessionLoaded ||
      (_outlets.isNotEmpty && _menus.contains(_menuPathAdjustment));

  void _showNoStoreAccessWarning() {
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        icon: const Icon(Icons.lock_outline_rounded, color: _navy, size: 32),
        title: const Text('Tidak Ada Akses Store'),
        content: const Text(
          'Akun kamu belum memiliki akses ke store manapun. Silakan hubungi admin untuk mendapatkan akses.',
        ),
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

  void _showNoAdjustmentAccessWarning() {
    final reason = _outlets.isEmpty
        ? 'Akun kamu belum memiliki akses ke store manapun.'
        : 'Akun kamu tidak memiliki izin akses menu Penyesuaian.';

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
    if (_outlets.isEmpty) return;
    if (!mounted) return;
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
        body: {'action': 'getDashboard', 'store_ids': _outlets.join(',')},
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        setState(() {
          _invoiceHariIni = data['invoice_count'] ?? 0;
          _totalPenjualan = (data['total_penjualan'] as num?)?.toDouble() ?? 0;
        });
      }
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
      await SessionService.clearSession();
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
        return LaporanScreen(outlets: _outlets);
      case 2:
        return PengaturanScreen(outlets: _outlets);
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
  Widget _buildHomeContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final w = constraints.maxWidth;
        final h = constraints.maxHeight;
        final compact = h < 480;
        final hPad = w >= 800 ? 28.0 : 16.0;
        final vPad = compact ? 12.0 : 20.0;
        final gap = compact ? 10.0 : 16.0;

        return RefreshIndicator(
          color: _blue,
          onRefresh: _loadStats,
          child: SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── Stat Cards ───────────────────────────────
                _buildStatCards(compact: compact, gap: gap, w: w),
                SizedBox(height: compact ? 12 : 20),

                // ── Menu Utama label ────────────────────────
                Row(
                  children: [
                    Text(
                      'Menu Utama',
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
                ),
                SizedBox(height: compact ? 10 : 14),

                // ── Menu Tiles ──────────────────────────────
                // Selalu 2 baris x 2 kolom, baik landscape/tablet maupun
                // portrait/phone: baris atas PENJUALAN + INVOICE,
                // baris bawah PENYESUAIAN STOK + REKAP PEMBAYARAN.
                //
                // PENJUALAN & PENYESUAIAN STOK butuh akses store
                // (m_user_divisi) — kalau user tidak punya outlet sama
                // sekali, tile-nya di-disable (abu-abu) dan tap
                // menampilkan warning, bukan masuk ke form kosong/rusak.
                Row(
                  children: [
                    Expanded(
                      child: _MenuTile(
                        icon: Icons.shopping_cart_rounded,
                        label: 'PENJUALAN',
                        description: 'Kasir & transaksi penjualan produk',
                        compact: compact,
                        enabled: _hasStoreAccess,
                        onTap: _hasStoreAccess
                            ? () => _pushAndRecheckPrinter(
                                  const PenjualanScreen(),
                                )
                            : _showNoStoreAccessWarning,
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _MenuTile(
                        icon: Icons.description_rounded,
                        label: 'INVOICE',
                        description: 'Riwayat transaksi & cetak ulang invoice',
                        compact: compact,
                        onTap: () => _pushAndRecheckPrinter(
                          const InvoiceListScreen(),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: gap),
                Row(
                  children: [
                    Expanded(
                      child: _MenuTile(
                        icon: Icons.inventory_2_rounded,
                        label: 'PENYESUAIAN STOK',
                        description: 'Update selisih & set total stok produk',
                        compact: compact,
                        enabled: _hasAdjustmentAccess,
                        onTap: _hasAdjustmentAccess
                            ? () => Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (_) => const AdjustmentScreen(),
                                  ),
                                )
                            : _showNoAdjustmentAccessWarning,
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _MenuTile(
                        icon: Icons.payments_rounded,
                        label: 'REKAP PEMBAYARAN',
                        description: 'Rekap omset per metode pembayaran',
                        compact: compact,
                        onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                            builder: (_) => const LaporanPembayaranScreen(),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: compact ? 8 : 20),
              ],
            ),
          ),
        );
      },
    );
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
            _BottomNavItem(
              icon: Icons.bar_chart_rounded,
              label: 'Laporan',
              selected: _navIndex == 1,
              onTap: () => setState(() => _navIndex = 1),
            ),
            _BottomNavItem(
              icon: Icons.settings_rounded,
              label: 'Pengaturan',
              selected: _navIndex == 2,
              onTap: () => setState(() => _navIndex = 2),
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
// WIDGET: _MenuTile  (landscape card, dark navy gradient)
// ============================================================
class _MenuTile extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;
  final bool compact;
  final VoidCallback onTap;
  final bool enabled;

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.compact,
    required this.onTap,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final iconBox = compact ? 44.0 : 64.0;
    final pad = compact ? 14.0 : 20.0;

    return Material(
      color: Colors.transparent,
      borderRadius: BorderRadius.circular(16),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Ink(
          decoration: BoxDecoration(
            gradient: enabled
                ? const LinearGradient(
                    colors: [_navy, _navyMid, Color(0xFF1E3A8A)],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  )
                : LinearGradient(
                    colors: [Colors.grey.shade500, Colors.grey.shade600],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: (enabled ? _navy : Colors.grey).withValues(alpha: 0.3),
                blurRadius: 10,
                offset: const Offset(0, 3),
              ),
            ],
          ),
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

  const _BottomNavItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Expanded(
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, color: selected ? _blue : Colors.grey[400], size: 24),
              const SizedBox(height: 4),
              Text(
                label,
                style: TextStyle(
                  color: selected ? _blue : Colors.grey[400],
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

  // Dikirim ke penjualan.php (bukan auth.php) karena di sinilah
  // validateToken() sudah dijalankan dan $userID di-resolve dari
  // token — persis pola yang dipakai semua action lain
  // (CartHandler, MasterHandler, dst). Handler-nya ada di
  // MasterHandler.php, action 'changePassword'.
  Future<void> _submit() async {
    if (!_isValid || _isSaving) return;
    setState(() {
      _isSaving = true;
      _errorText = null;
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
          'action': 'changePassword',
          'password': _passwordCtrl.text,
          'password_confirmation': _rePasswordCtrl.text,
        },
      ).timeout(const Duration(seconds: 10));

      if (!mounted) return;

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        Navigator.pop(context);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Password berhasil diubah')),
        );
      } else {
        setState(() {
          _errorText = data['message'] ?? 'Gagal mengubah password';
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
