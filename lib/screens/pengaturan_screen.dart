import 'package:flutter/material.dart';
import 'pengaturan/outlet_setting_screen.dart';

// ─── Palette (samain dengan home_screen.dart / laporan_screen.dart) ───
const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);

// Path menu detail Outlet (konfigurasi/MasterStore) — harus match dengan
// nilai di m_menu_detail_pos.path di DB.
const String _pathMasterStore = 'konfigurasi/MasterStore';

enum _SettingType { none, outlet }

/// Halaman Pengaturan: sidebar menu di kiri (icon kotak + label di
/// bawahnya), konten setting di kanan. Default kosong — form baru
/// dirender setelah salah satu menu di sidebar di-tap. Pola sama
/// persis dengan LaporanScreen.
///
/// Menu Outlet ditampilkan hanya jika user punya is_view=1 DAN is_edit=1
/// pada 'konfigurasi/MasterStore' (sesuai flow permission web:
/// Konfigurasi - Master Outlet akses view & edit).
class PengaturanScreen extends StatefulWidget {
  final List<int> outlets;
  final List<String> menus;    // path/link dengan is_view=1 (dari login API)
  final List<String> editable; // path detail menu dengan is_edit=1

  const PengaturanScreen({
    super.key,
    required this.outlets,
    this.menus = const [],
    this.editable = const [],
  });

  @override
  State<PengaturanScreen> createState() => _PengaturanScreenState();
}

class _PengaturanScreenState extends State<PengaturanScreen> {
  _SettingType _selected = _SettingType.none;

  // Outlet: butuh is_view=1 (ada di menus) DAN is_edit=1 (ada di editable).
  // Sebelum session dimuat (menus kosong karena default const []),
  // anggap enabled sementara agar tidak ada flicker.
  bool get _hasOutletAccess =>
      widget.menus.isEmpty ||
      (widget.menus.contains(_pathMasterStore) &&
          widget.editable.contains(_pathMasterStore));

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _buildSidebar(),
        Container(width: 1, color: Colors.grey.shade200),
        Expanded(child: _buildContent()),
      ],
    );
  }

  // ============================================================
  // SIDEBAR
  // ============================================================
  Widget _buildSidebar() {
    return Container(
      width: 84,
      color: Colors.white,
      child: SafeArea(
        top: false,
        bottom: false,
        child: SingleChildScrollView(
          padding: const EdgeInsets.symmetric(vertical: 14),
          child: Column(
            children: [
              // Outlet: tampil hanya jika user punya is_view + is_edit
              if (_hasOutletAccess)
                _SidebarMenuItem(
                  icon: Icons.storefront_rounded,
                  label: 'Outlet',
                  selected: _selected == _SettingType.outlet,
                  onTap: () => setState(() => _selected = _SettingType.outlet),
                ),
              // Menu pengaturan lain nanti ditambahkan di sini.
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // CONTENT
  // ============================================================
  Widget _buildContent() {
    switch (_selected) {
      case _SettingType.outlet:
        return OutletSettingScreen(outlets: widget.outlets);
      case _SettingType.none:
        return _buildEmptyState();
    }
  }

  Widget _buildEmptyState() {
    return Container(
      color: _bgGray,
      alignment: Alignment.center,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.settings_rounded, size: 56, color: Colors.grey[350]),
          const SizedBox(height: 12),
          Text(
            _hasOutletAccess
                ? 'Pilih pengaturan di samping'
                : 'Tidak ada menu pengaturan yang dapat diakses',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WIDGET: _SidebarMenuItem  (identik dengan yang di laporan_screen.dart)
// ============================================================
class _SidebarMenuItem extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool selected;
  final VoidCallback onTap;

  const _SidebarMenuItem({
    required this.icon,
    required this.label,
    required this.selected,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      child: Material(
        color: Colors.transparent,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 52,
                  height: 52,
                  decoration: BoxDecoration(
                    color: selected ? _blue : _bgGray,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: selected ? _blue : Colors.grey.shade200,
                      width: 1.2,
                    ),
                  ),
                  child: Icon(
                    icon,
                    color: selected ? Colors.white : _navy,
                    size: 24,
                  ),
                ),
                const SizedBox(height: 6),
                Text(
                  label,
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: selected ? FontWeight.w700 : FontWeight.w500,
                    color: selected ? _blue : Colors.grey[600],
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
