import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import '../services/session_service.dart';
import '../services/api_service.dart';
import 'penjualan/penjualan_screen.dart';
import 'invoice_list_screen.dart';
import 'laporan_pembayaran_screen.dart';
import 'login_screen.dart';
import 'printer_screen.dart';

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
  final bool _printerConnected = false;
  bool _isLoading = false;
  List<int> _outlets = [];

  @override
  void initState() {
    super.initState();
    _loadSession(); // _loadStats() dipanggil di dalam _loadSession setelah session siap
  }

  Future<void> _loadSession() async {
    final session = await SessionService.getSession();
    if (!mounted) return;
    setState(() {
      _nama = session['nama'] ?? '';
      _username = session['username'] ?? '';
      _outlets = List<int>.from(session['outlets'] ?? []);
    });
    _loadStats();
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
        body: {
          'action': 'getDashboard',
          'store_ids': _outlets.join(','),
        },
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
        return const Center(
            child: Text('Laporan\n(Coming soon)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey)));
      case 2:
        return const Center(
            child: Text('Pengaturan\n(Coming soon)',
                textAlign: TextAlign.center,
                style: TextStyle(fontSize: 18, color: Colors.grey)));
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
                  color: Colors.white.withOpacity(0.15),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                      color: Colors.white.withOpacity(0.3), width: 1.5),
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
                              horizontal: 8, vertical: 2),
                          decoration: BoxDecoration(
                            color: _blueLight.withOpacity(0.35),
                            borderRadius: BorderRadius.circular(20),
                            border:
                                Border.all(color: _blueLight.withOpacity(0.5)),
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
                      Row(
                        children: [
                          const Icon(Icons.person_outline,
                              color: Colors.white54, size: 13),
                          const SizedBox(width: 4),
                          Text(
                            'User: $_username',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: isTablet ? 12 : 11,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              // Action buttons
              _HeaderIconBtn(
                icon: Icons.print_rounded,
                label: 'Printer',
                onTap: () => Navigator.push(context,
                    MaterialPageRoute(builder: (_) => const PrinterScreen())),
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
    return LayoutBuilder(builder: (context, constraints) {
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
              // ── Stat Cards — selalu 1 row ───────────────
              _buildStatCards(compact: compact, gap: gap),
              SizedBox(height: compact ? 12 : 20),

              // ── Menu Utama label ────────────────────────
              Row(children: [
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
                        color: _blue, borderRadius: BorderRadius.circular(2))),
              ]),
              SizedBox(height: compact ? 10 : 14),

              // ── Menu Tiles ──────────────────────────────
              // Landscape / tablet (w >= 600): 1 row, 3 card
              // Portrait / phone  (w <  600): 2 row — PENJUALAN+INVOICE atas, CARA BAYAR bawah
              if (w >= 600) ...[
                Row(
                  children: [
                    Expanded(
                      child: _MenuTile(
                        icon: Icons.shopping_cart_rounded,
                        label: 'PENJUALAN',
                        description: 'Kasir & transaksi penjualan produk',
                        compact: compact,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PenjualanScreen())),
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _MenuTile(
                        icon: Icons.description_rounded,
                        label: 'INVOICE',
                        description: 'Riwayat transaksi & cetak ulang invoice',
                        compact: compact,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const InvoiceListScreen())),
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
                                builder: (_) =>
                                    const LaporanPembayaranScreen())),
                      ),
                    ),
                  ],
                ),
              ] else ...[
                Row(
                  children: [
                    Expanded(
                      child: _MenuTile(
                        icon: Icons.shopping_cart_rounded,
                        label: 'PENJUALAN',
                        description: 'Kasir & transaksi penjualan produk',
                        compact: compact,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const PenjualanScreen())),
                      ),
                    ),
                    SizedBox(width: gap),
                    Expanded(
                      child: _MenuTile(
                        icon: Icons.description_rounded,
                        label: 'INVOICE',
                        description: 'Riwayat transaksi & cetak ulang invoice',
                        compact: compact,
                        onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                                builder: (_) => const InvoiceListScreen())),
                      ),
                    ),
                  ],
                ),
                SizedBox(height: gap),
                _MenuTile(
                  icon: Icons.payments_rounded,
                  label: 'REKAP PEMBAYARAN',
                  description: 'Rekap omset per metode pembayaran hari ini',
                  compact: compact,
                  onTap: () => Navigator.push(
                      context,
                      MaterialPageRoute(
                          builder: (_) => const LaporanPembayaranScreen())),
                ),
              ],
              SizedBox(height: compact ? 8 : 20),
            ],
          ),
        ),
      );
    });
  }

  // ── 3 Stat Cards — selalu 1 row ─────────────────────────
  Widget _buildStatCards({required bool compact, required double gap}) {
    return Row(children: [
      Expanded(
        child: _MiniStatCard(
          icon: Icons.receipt_long_rounded,
          iconBg: const Color(0xFFEFF6FF),
          iconColor: _blue,
          title: 'Invoice Hari Ini',
          value: _isLoading ? '...' : '$_invoiceHariIni Invoice',
          valueColor: _blue,
          compact: compact,
          loading: _isLoading,
        ),
      ),
      SizedBox(width: gap),
      Expanded(
        child: _MiniStatCard(
          icon: Icons.trending_up_rounded,
          iconBg: const Color(0xFFF0FFF4),
          iconColor: _green,
          title: 'Total Penjualan',
          value: _isLoading ? '...' : _formatRupiah(_totalPenjualan),
          valueColor: _navy,
          compact: compact,
          loading: _isLoading,
        ),
      ),
      SizedBox(width: gap),
      Expanded(
        child: _MiniStatCard(
          icon: Icons.print_rounded,
          iconBg: const Color(0xFFF5F3FF),
          iconColor: const Color(0xFF7C3AED),
          title: 'Status Printer',
          value: _printerConnected ? 'Connected ●' : 'Disconnected ○',
          valueColor: _printerConnected ? _green : Colors.red,
          compact: compact,
          loading: false,
        ),
      ),
    ]);
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
            color: Colors.black.withOpacity(0.08),
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
              color: Colors.white.withOpacity(0.12),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white.withOpacity(0.2)),
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

  const _MiniStatCard({
    required this.icon,
    required this.iconBg,
    required this.iconColor,
    required this.title,
    required this.value,
    required this.valueColor,
    required this.compact,
    this.loading = false,
  });

  @override
  Widget build(BuildContext context) {
    final iconSize = compact ? 30.0 : 38.0;
    final pad = compact ? 10.0 : 14.0;

    return Container(
      padding: EdgeInsets.symmetric(horizontal: pad, vertical: pad),
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(12),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withOpacity(0.06),
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
            child: Icon(icon, color: iconColor, size: compact ? 15 : 19),
          ),
          SizedBox(width: compact ? 7 : 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: TextStyle(
                    color: Colors.grey[500],
                    fontSize: compact ? 9 : 10,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
                const SizedBox(height: 2),
                loading
                    ? Container(
                        height: compact ? 11 : 14,
                        width: 60,
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
                          fontSize: compact ? 11 : 14,
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

  const _MenuTile({
    required this.icon,
    required this.label,
    required this.description,
    required this.compact,
    required this.onTap,
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
            gradient: const LinearGradient(
              colors: [_navy, _navyMid, Color(0xFF1E3A8A)],
              begin: Alignment.topLeft,
              end: Alignment.bottomRight,
            ),
            borderRadius: BorderRadius.circular(16),
            boxShadow: [
              BoxShadow(
                color: _navy.withOpacity(0.3),
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
                        color: Colors.white.withOpacity(0.12),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                            color: Colors.white.withOpacity(0.15), width: 1),
                      ),
                      child: Icon(icon,
                          color: Colors.white, size: compact ? 22 : 32),
                    ),
                    const Spacer(),
                    Container(
                      width: compact ? 26 : 32,
                      height: compact ? 26 : 32,
                      decoration: BoxDecoration(
                        color: Colors.white.withOpacity(0.15),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(Icons.arrow_forward_ios_rounded,
                          color: Colors.white, size: 12),
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
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 11,
                    ),
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
                    color: _blue,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        'Buka Sekarang',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: compact ? 10 : 11,
                        ),
                      ),
                      const SizedBox(width: 4),
                      const Icon(Icons.arrow_forward_rounded,
                          color: Colors.white, size: 11),
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
              Icon(
                icon,
                color: selected ? _blue : Colors.grey[400],
                size: 24,
              ),
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
