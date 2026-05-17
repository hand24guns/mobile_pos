import 'package:flutter/material.dart';
import '../utils/currency_format.dart';

// ============================================================
// PackageDialog
//
// Dipanggil dari _PenjualanScreenState._insertProduk() ketika
// cekPackage API mengembalikan is_package = true.
//
// Flow:
//   1. User tap produk / enter SKU
//   2. _insertProduk(sku) → POST cekPackage → is_package=true
//   3. showDialog(PackageDialog) → user pilih isian + addon
//   4. Tap "Tambah ke Order" → onConfirm callback
//   5. _doInsertPackage() → POST insertPackage → _refreshFromApi()
// ============================================================

class PackageDialog extends StatefulWidget {
  final String sku;
  final Map<String, dynamic> packageData;

  /// Callback setelah user konfirmasi.
  /// [isianDipilih]  — list of { 'id': int, 'nama': String }
  /// [addonDipilih]  — list of { 'id': int, 'nama': String, 'harga': double }
  /// [addonTotal]    — total harga tambahan addon
  final void Function(
    List<Map<String, dynamic>> isianDipilih,
    List<Map<String, dynamic>> addonDipilih,
    double addonTotal,
  ) onConfirm;

  const PackageDialog({
    super.key,
    required this.sku,
    required this.packageData,
    required this.onConfirm,
  });

  @override
  State<PackageDialog> createState() => _PackageDialogState();
}

class _PackageDialogState extends State<PackageDialog> {
  // Set ID isian yang dipilih (checkbox, bisa banyak)
  final Set<int> _selectedIsian = {};

  // Per grup → item yang dipilih (radio)
  // key = grup string (e.g. 'topping'), value = { id, nama, harga }
  final Map<String, Map<String, dynamic>> _selectedAddon = {};

  bool _showIsianError = false;

  double get _basePrice => _toDouble(widget.packageData['hpj']);

  double get _addonTotal =>
      _selectedAddon.values.fold(0.0, (sum, a) => sum + _toDouble(a['harga']));

  double get _totalHarga => _basePrice + _addonTotal;

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  List get _isianList => (widget.packageData['isian'] as List?) ?? [];

  Map<String, dynamic> get _addonGroups =>
      (widget.packageData['addon_groups'] as Map<String, dynamic>?) ?? {};

  @override
  void initState() {
    super.initState();
    // Default: pilih item pertama tiap grup addon
    _addonGroups.forEach((grup, items) {
      final list = items as List;
      if (list.isNotEmpty) {
        final first = list[0];
        _selectedAddon[grup] = {
          'id': first['m_package_addon_id'],
          'nama': first['nama'],
          'harga': _toDouble(first['harga_tambah']),
        };
      }
    });
  }

  void _onConfirm() {
    // Validasi: minimal 1 isian dipilih
    if (_selectedIsian.isEmpty) {
      setState(() => _showIsianError = true);
      return;
    }

    // Kumpulkan isian yang dipilih
    final isianDipilih = _isianList
        .where((i) => _selectedIsian.contains(i['m_package_isian_id'] as int))
        .map<Map<String, dynamic>>((i) => {
              'id': i['m_package_isian_id'],
              'nama': i['nama'],
            })
        .toList();

    // Kumpulkan addon yang dipilih (hanya yang harga > 0 ditampilkan di nama,
    // tapi semua tetap dikirim ke backend)
    final addonDipilih = _selectedAddon.values
        .map<Map<String, dynamic>>((a) => {
              'id': a['id'],
              'nama': a['nama'],
              'harga': a['harga'],
            })
        .toList();

    Navigator.pop(context);
    widget.onConfirm(isianDipilih, addonDipilih, _addonTotal);
  }

  String _rupiah(double n) => 'Rp ${CurrencyFormat.format(n)}';

  @override
  Widget build(BuildContext context) {
    return Dialog(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxWidth: 480,
          maxHeight: MediaQuery.of(context).size.height * 0.82,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Header ────────────────────────────────────────
            _buildHeader(),

            // ── Body (scrollable) ─────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    _buildIsianSection(),
                    const Divider(height: 28),
                    if (_addonGroups.isNotEmpty) ...[
                      _buildAddonSection(),
                      const Divider(height: 28),
                    ],
                    _buildPriceSummary(),
                  ],
                ),
              ),
            ),

            // ── Footer ────────────────────────────────────────
            _buildFooter(),
          ],
        ),
      ),
    );
  }

  // ── Header ──────────────────────────────────────────────────
  Widget _buildHeader() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(20, 16, 20, 14),
      decoration: BoxDecoration(
        color: const Color(0xFF1D273B),
        borderRadius: const BorderRadius.vertical(top: Radius.circular(12)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            widget.packageData['nama'] ?? 'Produk Package',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
              fontSize: 16,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            'Harga dasar: ${_rupiah(_basePrice)}',
            style:
                TextStyle(color: Colors.white.withOpacity(0.65), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Isian (Checkbox) ────────────────────────────────────────
  Widget _buildIsianSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Isian',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 6),
            Text('(pilih minimal 1)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _isianList.map<Widget>((item) {
            final id = item['m_package_isian_id'] as int;
            final selected = _selectedIsian.contains(id);
            return GestureDetector(
              onTap: () {
                setState(() {
                  if (selected) {
                    _selectedIsian.remove(id);
                  } else {
                    _selectedIsian.add(id);
                  }
                  _showIsianError = false;
                });
              },
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 140),
                padding:
                    const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                decoration: BoxDecoration(
                  color:
                      selected ? const Color(0xFF1D273B) : Colors.grey.shade100,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: selected
                        ? const Color(0xFF1D273B)
                        : Colors.grey.shade300,
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (selected)
                      const Padding(
                        padding: EdgeInsets.only(right: 4),
                        child: Icon(Icons.check, color: Colors.white, size: 14),
                      ),
                    Text(
                      item['nama'],
                      style: TextStyle(
                        color: selected ? Colors.white : Colors.black87,
                        fontWeight:
                            selected ? FontWeight.bold : FontWeight.normal,
                        fontSize: 13,
                      ),
                    ),
                  ],
                ),
              ),
            );
          }).toList(),
        ),
        // Error hint
        if (_showIsianError)
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Row(
              children: [
                const Icon(Icons.error_outline, color: Colors.red, size: 14),
                const SizedBox(width: 4),
                Text('Pilih minimal 1 isian',
                    style: const TextStyle(color: Colors.red, fontSize: 12)),
              ],
            ),
          ),
      ],
    );
  }

  // ── Addon (Radio per grup) ───────────────────────────────────
  Widget _buildAddonSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: _addonGroups.entries.map((entry) {
        final grup = entry.key;
        final items = entry.value as List;
        if (items.isEmpty) return const SizedBox.shrink();

        final grupLabel =
            (items[0]['grup_label'] as String?) ?? _capitalize(grup);

        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(grupLabel,
                style:
                    const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(height: 10),
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: items.map<Widget>((item) {
                final id = item['m_package_addon_id'] as int;
                final harga = _toDouble(item['harga_tambah']);
                final selected = _selectedAddon[grup]?['id'] == id;

                return GestureDetector(
                  onTap: () {
                    setState(() {
                      _selectedAddon[grup] = {
                        'id': id,
                        'nama': item['nama'],
                        'harga': harga,
                      };
                    });
                  },
                  child: AnimatedContainer(
                    duration: const Duration(milliseconds: 140),
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                    decoration: BoxDecoration(
                      color: selected
                          ? const Color(0xFF1D273B)
                          : Colors.grey.shade100,
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                        color: selected
                            ? const Color(0xFF1D273B)
                            : Colors.grey.shade300,
                      ),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        if (selected)
                          const Padding(
                            padding: EdgeInsets.only(right: 4),
                            child: Icon(Icons.check,
                                color: Colors.white, size: 14),
                          ),
                        Text(
                          item['nama'],
                          style: TextStyle(
                            color: selected ? Colors.white : Colors.black87,
                            fontWeight:
                                selected ? FontWeight.bold : FontWeight.normal,
                            fontSize: 13,
                          ),
                        ),
                        if (harga > 0) ...[
                          const SizedBox(width: 4),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 6, vertical: 2),
                            decoration: BoxDecoration(
                              color: selected
                                  ? Colors.white.withOpacity(0.2)
                                  : Colors.orange.shade100,
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              '+${_rupiah(harga)}',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: selected
                                    ? Colors.white
                                    : Colors.orange.shade800,
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                );
              }).toList(),
            ),
            const SizedBox(height: 14),
          ],
        );
      }).toList(),
    );
  }

  // ── Price Summary ─────────────────────────────────────────────
  Widget _buildPriceSummary() {
    return Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: Colors.grey.shade50,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.grey.shade200),
      ),
      child: Column(
        children: [
          _priceRow('Harga dasar', _rupiah(_basePrice), Colors.black87),
          if (_addonTotal > 0)
            _priceRow('+ Add-on', _rupiah(_addonTotal), Colors.orange.shade700),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15)),
              Text(
                _rupiah(_totalHarga),
                style: const TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 18,
                  color: Colors.green,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _priceRow(String label, String value, Color valueColor) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(label, style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── Footer ────────────────────────────────────────────────────
  Widget _buildFooter() {
    return Container(
      padding: const EdgeInsets.fromLTRB(16, 10, 16, 14),
      decoration: BoxDecoration(
        border: Border(top: BorderSide(color: Colors.grey.shade200)),
      ),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed: () => Navigator.pop(context),
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
              child: const Text('Batal'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed: _onConfirm,
              icon: const Icon(Icons.add_shopping_cart, size: 18),
              label: const Text('Tambah ke Order'),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D273B),
                foregroundColor: Colors.white,
                padding: const EdgeInsets.symmetric(vertical: 12),
                shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(8)),
              ),
            ),
          ),
        ],
      ),
    );
  }

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);
}
