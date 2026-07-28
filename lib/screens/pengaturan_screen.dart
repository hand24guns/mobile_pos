import 'package:flutter/material.dart';
import 'pengaturan/outlet_setting_screen.dart';

// ─── Palette (samain dengan home_screen.dart / laporan_screen.dart) ───
const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);

enum _SettingType { none, outlet }

/// Halaman Pengaturan: sidebar menu di kiri (icon kotak + label di
/// bawahnya), konten setting di kanan. Default kosong — form baru
/// dirender setelah salah satu menu di sidebar di-tap. Pola sama
/// persis dengan LaporanScreen.
class PengaturanScreen extends StatefulWidget {
  final List<int> outlets;

  const PengaturanScreen({super.key, required this.outlets});

  @override
  State<PengaturanScreen> createState() => _PengaturanScreenState();
}

class _PengaturanScreenState extends State<PengaturanScreen> {
  _SettingType _selected = _SettingType.none;

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
            'Pilih pengaturan di samping',
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
