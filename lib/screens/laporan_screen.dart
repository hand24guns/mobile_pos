import 'package:flutter/material.dart';
import 'laporan/onhand_report.dart';

// ─── Palette (samain dengan home_screen.dart) ──────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);

enum _ReportType { none, onhand }

/// Halaman Laporan: sidebar menu report di kiri (icon kotak + label di
/// bawahnya), konten report di kanan. Default kosong — report baru
/// dirender setelah salah satu menu di sidebar di-tap.
class LaporanScreen extends StatefulWidget {
  final List<int> outlets;

  const LaporanScreen({super.key, required this.outlets});

  @override
  State<LaporanScreen> createState() => _LaporanScreenState();
}

class _LaporanScreenState extends State<LaporanScreen> {
  _ReportType _selected = _ReportType.none;

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
                icon: Icons.inventory_2_rounded,
                label: 'Onhand',
                selected: _selected == _ReportType.onhand,
                onTap: () => setState(() => _selected = _ReportType.onhand),
              ),
              // Menu report lain nanti ditambahkan di sini, mengikuti
              // pola m_submenu kategori 'Inventory' di versi web
              // (Onhand.php).
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
      case _ReportType.onhand:
        return OnhandReportScreen(outlets: widget.outlets);
      case _ReportType.none:
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
          Icon(Icons.bar_chart_rounded, size: 56, color: Colors.grey[350]),
          const SizedBox(height: 12),
          Text(
            'Pilih laporan di samping',
            style: TextStyle(color: Colors.grey[500], fontSize: 14),
          ),
        ],
      ),
    );
  }
}

// ============================================================
// WIDGET: _SidebarMenuItem  (icon kotak + label di bawah)
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
