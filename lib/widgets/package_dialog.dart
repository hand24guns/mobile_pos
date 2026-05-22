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
//
// Struktur addon_groups dari API:
//   {
//     "extra": {
//       "tipe_pilihan": "single" | "multiple",
//       "items": [ { m_package_addon_id, nama, harga_tambah, grup, grup_label } ]
//     }
//   }
//
// Addon tipe 'single'   → radio: pilih tepat 1 item per grup
// Addon tipe 'multiple' → checkbox: bisa pilih beberapa item per grup
//
// State:
//   _selectedSingle   Map<grupKey, addonId>   — satu pilihan per grup single
//   _selectedMultiple Set<int>                — kumpulan id addon multiple
// ============================================================

class PackageDialog extends StatefulWidget {
  final String sku;
  final Map<String, dynamic> packageData;

  /// Callback setelah user konfirmasi.
  /// [isianDipilih]  — list of { 'id': int, 'nama': String }
  /// [addonDipilih]  — list of { 'id': int, 'nama': String, 'harga': double }
  /// [addonTotal]    — total harga tambahan addon
  /// [keterangan]    — catatan/notes untuk item ini (bisa kosong)
  final void Function(
    List<Map<String, dynamic>> isianDipilih,
    List<Map<String, dynamic>> addonDipilih,
    double addonTotal,
    String keterangan,
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
  // ── Isian (checkbox, tidak mandatory) ──
  final Set<int> _selectedIsian = {};

  // ── Addon single: satu pilihan per grup (key = grupKey string) ──
  final Map<String, int> _selectedSingle = {};

  // ── Addon multiple: set id addon yang dicentang ──
  final Set<int> _selectedMultiple = {};

  // ── Cache addon groups ── dihitung sekali di initState supaya
  //    grupKey konsisten antar rebuild dan tidak bergantung pada
  //    SHOW COLUMNS runtime (baca langsung dari packageData sekali)
  late final Map<String, dynamic> _cachedAddonGroups;

  final TextEditingController _keteranganCtrl = TextEditingController();

  @override
  void initState() {
    super.initState();
    _cachedAddonGroups = _parseAddonGroups();
  }

  // ── Helpers ─────────────────────────────────────────────────

  double get _basePrice => _toDouble(widget.packageData['hpj']);

  double get _addonTotal {
    double total = 0;
    _cachedAddonGroups.forEach((grupKey, grupData) {
      final items = (grupData['items'] as List?) ?? [];
      final tipe  = (grupData['tipe_pilihan'] as String?) ?? 'multiple';

      if (tipe == 'single') {
        final selectedId = _selectedSingle[grupKey];
        if (selectedId != null) {
          final dynamic item = items.cast<dynamic>().firstWhere(
            (i) => i['m_package_addon_id'] == selectedId,
            orElse: () => null,
          );
          if (item != null) total += _toDouble(item['harga_tambah']);
        }
      } else {
        for (final item in items) {
          final id = item['m_package_addon_id'] as int;
          if (_selectedMultiple.contains(id)) {
            total += _toDouble(item['harga_tambah']);
          }
        }
      }
    });
    return total;
  }

  double get _totalHarga => _basePrice + _addonTotal;

  double _toDouble(dynamic val) {
    if (val == null) return 0.0;
    if (val is num) return val.toDouble();
    return double.tryParse(val.toString()) ?? 0.0;
  }

  List get _isianList => (widget.packageData['isian'] as List?) ?? [];

  Map<String, dynamic> _parseAddonGroups() {
    final raw = widget.packageData['addon_groups'];
    if (raw == null) return {};
    if (raw is! Map) return {};

    // Normalise: setiap value bisa berupa:
    // A) Map dengan { tipe_pilihan, grup_label, items: [...] }  ← format baru (benar)
    // B) List langsung [ {...}, {...} ]                          ← format lama (legacy)
    final result = <String, dynamic>{};
    (raw as Map).forEach((key, value) {
      if (value is Map) {
        // Format A — sudah benar, pastikan 'items' ada
        result[key.toString()] = {
          'tipe_pilihan': value['tipe_pilihan']?.toString() ?? 'multiple',
          'grup_label':   value['grup_label']?.toString() ?? key.toString(),
          'items':        (value['items'] as List?)
                              ?.map((e) => Map<String, dynamic>.from(e as Map))
                              .toList() ?? [],
        };
      } else if (value is List) {
        // Format B — legacy List langsung [{m_package_addon_id, nama, tipe_pilihan, ...}]
        // Baca tipe_pilihan dari item pertama jika ada, default multiple
        final legacyItems = value
            .map<Map<String, dynamic>>((e) => Map<String, dynamic>.from(e as Map))
            .toList();
        final tipeDariItem = legacyItems.isNotEmpty
            ? (legacyItems.first['tipe_pilihan']?.toString() ?? 'multiple')
            : 'multiple';
        result[key.toString()] = {
          'tipe_pilihan': tipeDariItem,
          'grup_label':   key.toString(),
          'items':        legacyItems,
        };
      }
    });
    return result;
  }

  bool get _hasIsian => _isianList.isNotEmpty;
  bool get _hasAddon => _cachedAddonGroups.isNotEmpty;

  /// Kumpulkan semua addon yang dipilih (single + multiple) untuk dikirim ke API
  List<Map<String, dynamic>> get _addonDipilih {
    final result = <Map<String, dynamic>>[];
    _cachedAddonGroups.forEach((grupKey, grupData) {
      final items = (grupData['items'] as List?) ?? [];
      final tipe  = (grupData['tipe_pilihan'] as String?) ?? 'multiple';

      if (tipe == 'single') {
        final selectedId = _selectedSingle[grupKey];
        if (selectedId != null) {
          final dynamic item = items.cast<dynamic>().firstWhere(
            (i) => i['m_package_addon_id'] == selectedId,
            orElse: () => null,
          );
          if (item != null) {
            result.add({
              'id':    selectedId,
              'nama':  item['nama'],
              'harga': _toDouble(item['harga_tambah']),
            });
          }
        }
      } else {
        for (final item in items) {
          final id = item['m_package_addon_id'] as int;
          if (_selectedMultiple.contains(id)) {
            result.add({
              'id':    id,
              'nama':  item['nama'],
              'harga': _toDouble(item['harga_tambah']),
            });
          }
        }
      }
    });
    return result;
  }

  @override
  void dispose() {
    _keteranganCtrl.dispose();
    super.dispose();
  }

  void _onConfirm() {
    final isianDipilih = _isianList
        .where((i) => _selectedIsian.contains(i['m_package_isian_id'] as int))
        .map<Map<String, dynamic>>((i) => {
              'id':   i['m_package_isian_id'],
              'nama': i['nama'],
            })
        .toList();

    final keterangan = _keteranganCtrl.text.trim();

    Navigator.pop(context);
    widget.onConfirm(isianDipilih, _addonDipilih, _addonTotal, keterangan);
  }

  String _rupiah(double n) => 'Rp ${CurrencyFormat.format(n)}';

  String _capitalize(String s) =>
      s.isEmpty ? s : s[0].toUpperCase() + s.substring(1);

  // ── BUILD ────────────────────────────────────────────────────

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
            _buildHeader(),
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (_hasIsian) ...[
                      _buildIsianSection(),
                      if (_hasAddon) const Divider(height: 28),
                    ],
                    if (_hasAddon) ...[
                      _buildAddonSection(),
                      const Divider(height: 28),
                    ],
                    _buildPriceSummary(),
                    const SizedBox(height: 16),
                    _buildKeteranganInput(),
                  ],
                ),
              ),
            ),
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
      decoration: const BoxDecoration(
        color: Color(0xFF1D273B),
        borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
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
            style: TextStyle(
                color: Colors.white.withOpacity(0.65), fontSize: 12),
          ),
        ],
      ),
    );
  }

  // ── Isian (Checkbox, tidak mandatory) ───────────────────────
  Widget _buildIsianSection() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Text('Isian',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
            const SizedBox(width: 6),
            Text('(opsional)',
                style: TextStyle(fontSize: 11, color: Colors.grey.shade500)),
          ],
        ),
        const SizedBox(height: 10),
        Wrap(
          spacing: 8,
          runSpacing: 8,
          children: _isianList.map<Widget>((item) {
            final id       = item['m_package_isian_id'] as int;
            final selected = _selectedIsian.contains(id);
            return GestureDetector(
              onTap: () => setState(() {
                selected ? _selectedIsian.remove(id) : _selectedIsian.add(id);
              }),
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
      ],
    );
  }

  // ── Addon Section — dispatch per tipe ────────────────────────
  Widget _buildAddonSection() {
    if (_cachedAddonGroups.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Add-on',
            style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
        const SizedBox(height: 10),
        ..._cachedAddonGroups.entries.map((entry) {
          final grupKey  = entry.key;
          final grupData = entry.value as Map<String, dynamic>;
          final items    = (grupData['items'] as List?) ?? [];
          final tipe     = (grupData['tipe_pilihan'] as String?) ?? 'multiple';

          if (items.isEmpty) return const SizedBox.shrink();

          // Ambil grup_label dari grupData (level grup) dulu,
          // fallback ke items[0] untuk backward compat, lalu ke capitalize
          final grupLabel =
              (grupData['grup_label'] as String?)?.isNotEmpty == true
                  ? grupData['grup_label'] as String
                  : (items.isNotEmpty
                      ? (items[0]['grup_label'] as String?) ?? _capitalize(grupKey)
                      : _capitalize(grupKey));

          return _buildAddonGrup(
            grupKey:   grupKey,
            grupLabel: grupLabel,
            items:     items,
            tipe:      tipe,
          );
        }),
      ],
    );
  }

  /// Satu grup addon — label + badge tipe + chip items
  Widget _buildAddonGrup({
    required String grupKey,
    required String grupLabel,
    required List items,
    required String tipe,
  }) {
    final isSingle = tipe == 'single';

    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // ── Sub-label + badge tipe ──
          Row(
            children: [
              Text(
                grupLabel,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: Colors.grey.shade700,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(
                  color: isSingle
                      ? const Color(0xFFDBEAFE) // biru-lt
                      : const Color(0xFFDCFCE7), // hijau-lt
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Text(
                  isSingle ? 'Pilih Satu' : 'Bisa Beberapa',
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: isSingle
                        ? const Color(0xFF1D4ED8)
                        : const Color(0xFF15803D),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // ── Chip items ──
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: items.map<Widget>((item) {
              final id    = item['m_package_addon_id'] as int;
              final harga = _toDouble(item['harga_tambah']);
              final selected = isSingle
                  ? _selectedSingle[grupKey] == id
                  : _selectedMultiple.contains(id);

              return GestureDetector(
                onTap: () => setState(() {
                  if (isSingle) {
                    // Radio behavior: timpa pilihan grup ini, bersihkan dari multiple
                    _selectedSingle[grupKey] = id;
                    _selectedMultiple.remove(id); // guard cross-contamination
                  } else {
                    // Checkbox behavior: toggle, pastikan tidak ada di single
                    _selectedSingle.removeWhere((_, v) => v == id); // guard
                    _selectedMultiple.contains(id)
                        ? _selectedMultiple.remove(id)
                        : _selectedMultiple.add(id);
                  }
                }),
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
                      // ── Icon indicator: radio dot (single) vs checkmark (multiple) ──
                      if (isSingle) ...[
                        AnimatedContainer(
                          duration: const Duration(milliseconds: 140),
                          width: 14,
                          height: 14,
                          margin: const EdgeInsets.only(right: 5),
                          decoration: BoxDecoration(
                            shape: BoxShape.circle,
                            border: Border.all(
                              color: selected
                                  ? Colors.white
                                  : Colors.grey.shade400,
                              width: 2,
                            ),
                          ),
                          child: selected
                              ? Center(
                                  child: Container(
                                    width: 6,
                                    height: 6,
                                    decoration: const BoxDecoration(
                                      shape: BoxShape.circle,
                                      color: Colors.white,
                                    ),
                                  ),
                                )
                              : null,
                        ),
                      ] else ...[
                        if (selected)
                          const Padding(
                            padding: EdgeInsets.only(right: 5),
                            child: Icon(Icons.check,
                                color: Colors.white, size: 14),
                          ),
                      ],

                      // ── Nama addon ──
                      Text(
                        item['nama'],
                        style: TextStyle(
                          color: selected ? Colors.white : Colors.black87,
                          fontWeight: selected
                              ? FontWeight.bold
                              : FontWeight.normal,
                          fontSize: 13,
                        ),
                      ),

                      // ── Badge harga tambah ──
                      if (harga > 0) ...[
                        const SizedBox(width: 5),
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
        ],
      ),
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
            _priceRow(
                '+ Add-on', _rupiah(_addonTotal), Colors.orange.shade700),
          const Divider(height: 16),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Total',
                  style: TextStyle(
                      fontWeight: FontWeight.bold, fontSize: 15)),
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
          Text(label,
              style: const TextStyle(color: Colors.grey, fontSize: 13)),
          Text(value,
              style: TextStyle(
                  color: valueColor,
                  fontSize: 13,
                  fontWeight: FontWeight.w500)),
        ],
      ),
    );
  }

  // ── Keterangan / Notes ────────────────────────────────────────
  Widget _buildKeteranganInput() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            const Icon(Icons.notes_outlined, size: 15, color: Colors.grey),
            const SizedBox(width: 5),
            Text(
              'Catatan item (opsional)',
              style: TextStyle(
                fontWeight: FontWeight.bold,
                fontSize: 13,
                color: Colors.grey.shade700,
              ),
            ),
          ],
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _keteranganCtrl,
          decoration: InputDecoration(
            hintText: 'Contoh: tanpa es, level pedas 2, dll.',
            hintStyle:
                TextStyle(color: Colors.grey.shade400, fontSize: 13),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(8),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
            isDense: true,
          ),
          maxLines: 2,
          textInputAction: TextInputAction.done,
          style: const TextStyle(fontSize: 13),
        ),
      ],
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
}
