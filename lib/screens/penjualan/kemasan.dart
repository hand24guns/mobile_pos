// Fitur Kemasan / Box — override pemakaian box oleh kasir (opsional).
// Box dihitung otomatis oleh server saat prosesBayar; bagian ini hanya untuk
// melihat hitungan, menyimpan override, dan reset ke hitungan otomatis.
// Box TIDAK pernah masuk cart/struk/omzet, dan TIDAK pernah memblokir pembayaran.
part of 'penjualan_screen.dart';

extension PenjualanKemasanX on _PenjualanScreenState {
  // ============================================================
  // STATE HELPERS
  // ============================================================

  /// Bersihkan semua state box di sisi klien (override + indikator).
  /// Dipanggil: setelah retrieve pending, load retur, transaksi sukses,
  /// simpan pending, dan saat cart kosong.
  void _clearKemasanState() {
    if (!mounted) return;
    if (!_kemasanOverrideActive && _kemasanSummary.isEmpty) return;
    _setState(() {
      _kemasanOverrideActive = false;
      _kemasanSummary = '';
    });
  }

  /// Dipanggil di tempat yang sama dengan _checkVoucherValid(res).
  /// Server mengirim kemasan_reset: true kalau override dihapus karena
  /// isi cart berubah.
  void _checkKemasanReset(Map<String, dynamic> res) {
    if (res['kemasan_reset'] != true) return;
    final hadOverride = _kemasanOverrideActive;
    _clearKemasanState();
    if (hadOverride && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pilihan box direset karena item berubah'),
          backgroundColor: Colors.orange,
        ),
      );
    }
  }

  // ============================================================
  // INDIKATOR di header: "Box: 1x Box 12 pcs (diubah)  [Reset]"
  // ============================================================
  Widget _buildKemasanIndicator() {
    if (!_kemasanOverrideActive || _kemasanSummary.isEmpty) {
      return const SizedBox.shrink();
    }
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Row(
        children: [
          Icon(Icons.inventory_2_outlined,
              size: 14, color: Colors.deepOrange.shade700),
          const SizedBox(width: 4),
          Expanded(
            child: Text(
              'Box: $_kemasanSummary (diubah)',
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 12,
                color: Colors.deepOrange.shade700,
              ),
            ),
          ),
          InkWell(
            onTap: _resetKemasanFromIndicator,
            child: const Padding(
              padding: EdgeInsets.symmetric(horizontal: 6, vertical: 2),
              child: Text(
                'Reset',
                style: TextStyle(
                  fontSize: 12,
                  color: Colors.indigo,
                  fontWeight: FontWeight.bold,
                  decoration: TextDecoration.underline,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  /// Tombol "Box" di header. [compact] = hanya ikon (hemat ruang).
  Widget _buildKemasanButton({
    required double iconSize,
    required double hPad,
    required double vPad,
    bool shrink = false,
  }) {
    final active = _kemasanOverrideActive;
    final inRetur = ref.read(penjualanProvider).returSource.isNotEmpty;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        Tooltip(
          message: 'Box / Kemasan',
          child: OutlinedButton(
            onPressed: _showKemasanSheet,
            style: OutlinedButton.styleFrom(
              padding: EdgeInsets.symmetric(horizontal: hPad, vertical: vPad),
              minimumSize: shrink ? Size.zero : null,
              tapTargetSize:
                  shrink ? MaterialTapTargetSize.shrinkWrap : null,
              foregroundColor: inRetur
                  ? Colors.grey
                  : (active ? Colors.deepOrange.shade700 : null),
              side: active && !inRetur
                  ? BorderSide(color: Colors.deepOrange.shade700)
                  : null,
            ),
            child: Icon(Icons.inventory_2_outlined, size: iconSize + 2),
          ),
        ),
        if (active && !inRetur)
          Positioned(
            right: 0,
            top: 0,
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: Colors.deepOrange.shade700,
                shape: BoxShape.circle,
              ),
            ),
          ),
      ],
    );
  }

  // ============================================================
  // RESET dari indikator
  // ============================================================
  Future<void> _resetKemasanFromIndicator() async {
    final state = ref.read(penjualanProvider);
    final res = await CartService.resetKemasan(
      number: state.number,
      deviceToken: _deviceToken,
    );
    if (res['success'] == true) {
      _clearKemasanState();
    } else if (mounted) {
      _showKemasanError(res['message']?.toString() ?? 'Gagal reset box');
    }
  }

  void _showKemasanError(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  // ============================================================
  // BOTTOM SHEET "Box / Kemasan"
  // ============================================================
  Future<void> _showKemasanSheet() async {
    final state = ref.read(penjualanProvider);

    // Mode retur: pemakaian box tidak dihitung, jangan panggil getKemasan.
    if (state.returSource.isNotEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pemakaian box tidak dihitung pada transaksi retur'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (state.items.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada produk')),
      );
      return;
    }

    if (_kemasanLoading) return;
    _setState(() => _kemasanLoading = true);
    Map<String, dynamic> res;
    try {
      res = await CartService.getKemasan(
        number: state.number,
        storeId: state.storeID,
        organisasiId: state.organisasiID,
        deviceToken: _deviceToken,
      );
    } finally {
      if (mounted) _setState(() => _kemasanLoading = false);
    }
    if (!mounted) return;

    if (res['success'] != true) {
      _showKemasanError(res['message']?.toString() ?? 'Gagal memuat data box');
      return;
    }
    if (res['cart_kosong'] == true) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Belum ada produk')),
      );
      return;
    }

    final sumber = (res['sumber'] ?? 'auto').toString();
    final opsi = (res['opsi'] is List)
        ? (res['opsi'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];
    final items = (res['items'] is List)
        ? (res['items'] as List)
            .whereType<Map>()
            .map((e) => Map<String, dynamic>.from(e))
            .toList()
        : <Map<String, dynamic>>[];

    // Sinkronkan flag override dengan kondisi server
    if ((sumber == 'manual') != _kemasanOverrideActive) {
      _setState(() {
        _kemasanOverrideActive = sumber == 'manual';
        if (!_kemasanOverrideActive) _kemasanSummary = '';
      });
    }

    int asInt(dynamic v) => int.tryParse(v?.toString() ?? '') ?? 0;

    // Baris awal: {id: int?, qty: int}
    final rows = <Map<String, int?>>[
      for (final it in items)
        {
          'id': asInt(it['kemasan_produk_id']),
          'qty': asInt(it['qty']) < 1 ? 1 : asInt(it['qty']),
        },
    ];

    Map<int, int> normalize(List<Map<String, int?>> list) {
      final out = <int, int>{};
      for (final r in list) {
        final id = r['id'] ?? 0;
        final q = r['qty'] ?? 0;
        if (id > 0 && q > 0) out[id] = (out[id] ?? 0) + q;
      }
      return out;
    }

    final original = normalize(rows);
    String namaBox(int id) {
      final o = opsi.firstWhere(
        (e) => asInt(e['id']) == id,
        orElse: () => <String, dynamic>{},
      );
      return (o['nama'] ?? 'Box $id').toString();
    }

    String ringkas(Map<int, int> m) => m.isEmpty
        ? 'tanpa box'
        : m.entries.map((e) => '${e.value}x ${namaBox(e.key)}').join(', ');

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (sheetCtx) {
        bool saving = false;
        return StatefulBuilder(
          builder: (ctx, setSheet) {
            Future<void> simpan() async {
              final merged = normalize(rows);

              // Hitungan otomatis & tidak diubah → cukup tutup
              if (sumber == 'auto' && _mapEquals(merged, original)) {
                Navigator.of(sheetCtx).pop();
                return;
              }

              setSheet(() => saving = true);
              final r = await CartService.simpanKemasan(
                number: state.number,
                organisasiId: state.organisasiID,
                deviceToken: _deviceToken,
                items: [
                  for (final e in merged.entries)
                    {'id': e.key, 'qty': e.value},
                ],
              );
              if (!mounted) return;

              if (r['success'] == true) {
                _setState(() {
                  _kemasanOverrideActive = true;
                  _kemasanSummary = ringkas(merged);
                });
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              } else {
                setSheet(() => saving = false);
                _showKemasanError(
                  r['message']?.toString() ?? 'Gagal menyimpan pilihan box',
                );
              }
            }

            Future<void> resetOtomatis() async {
              setSheet(() => saving = true);
              final r = await CartService.resetKemasan(
                number: state.number,
                deviceToken: _deviceToken,
              );
              if (!mounted) return;
              if (r['success'] == true) {
                _clearKemasanState();
                if (sheetCtx.mounted) Navigator.of(sheetCtx).pop();
              } else {
                setSheet(() => saving = false);
                _showKemasanError(
                  r['message']?.toString() ?? 'Gagal reset box',
                );
              }
            }

            Widget buildRow(int i) {
              final row = rows[i];
              final selId = row['id'];
              // Hanya box aktif; non-aktif hanya jika sedang terpilih di baris ini
              final choices = opsi.where((o) {
                final active = asInt(o['isactive']) == 1;
                return active || asInt(o['id']) == selId;
              }).toList();

              return Padding(
                padding: const EdgeInsets.only(bottom: 8),
                child: Row(
                  children: [
                    Expanded(
                      child: DropdownButtonFormField<int>(
                        key: ObjectKey(row),
                        isExpanded: true,
                        initialValue: (selId != null &&
                                choices.any((o) => asInt(o['id']) == selId))
                            ? selId
                            : null,
                        hint: const Text('Pilih box'),
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                          contentPadding: EdgeInsets.symmetric(
                              horizontal: 10, vertical: 10),
                        ),
                        items: [
                          for (final o in choices)
                            DropdownMenuItem<int>(
                              value: asInt(o['id']),
                              child: Text(
                                '${o['nama']} (stok ${asInt(o['stok'])})',
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                        ],
                        onChanged: saving
                            ? null
                            : (v) => setSheet(() => rows[i]['id'] = v),
                      ),
                    ),
                    const SizedBox(width: 6),
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline),
                      visualDensity: VisualDensity.compact,
                      onPressed: saving || (row['qty'] ?? 1) <= 1
                          ? null
                          : () => setSheet(
                              () => rows[i]['qty'] = (row['qty'] ?? 1) - 1),
                    ),
                    SizedBox(
                      width: 28,
                      child: Text(
                        '${row['qty']}',
                        textAlign: TextAlign.center,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline),
                      visualDensity: VisualDensity.compact,
                      onPressed: saving
                          ? null
                          : () => setSheet(
                              () => rows[i]['qty'] = (row['qty'] ?? 1) + 1),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_outline, color: Colors.red),
                      visualDensity: VisualDensity.compact,
                      onPressed:
                          saving ? null : () => setSheet(() => rows.removeAt(i)),
                    ),
                  ],
                ),
              );
            }

            return SafeArea(
              child: Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  0,
                  16,
                  16 + MediaQuery.of(ctx).viewInsets.bottom,
                ),
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Row(
                        children: [
                          const Expanded(
                            child: Text(
                              'Box / Kemasan',
                              style: TextStyle(
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: sumber == 'manual'
                                  ? Colors.deepOrange.shade50
                                  : Colors.grey.shade200,
                              borderRadius: BorderRadius.circular(10),
                            ),
                            child: Text(
                              sumber == 'manual' ? 'Diubah kasir' : 'Otomatis',
                              style: const TextStyle(fontSize: 11),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 10),
                      if (rows.isEmpty)
                        const Padding(
                          padding: EdgeInsets.symmetric(vertical: 12),
                          child: Text(
                            'Tanpa box',
                            textAlign: TextAlign.center,
                            style: TextStyle(color: Colors.grey),
                          ),
                        )
                      else
                        for (var i = 0; i < rows.length; i++) buildRow(i),
                      Align(
                        alignment: Alignment.centerLeft,
                        child: TextButton.icon(
                          onPressed: saving
                              ? null
                              : () => setSheet(
                                  () => rows.add({'id': null, 'qty': 1})),
                          icon: const Icon(Icons.add, size: 18),
                          label: const Text('Tambah box'),
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          Expanded(
                            child: OutlinedButton(
                              onPressed: saving ? null : resetOtomatis,
                              child: const Text('Reset otomatis'),
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: ElevatedButton(
                              onPressed: saving ? null : simpan,
                              style: ElevatedButton.styleFrom(
                                backgroundColor: const Color(0xFF1D273B),
                                foregroundColor: Colors.white,
                              ),
                              child: saving
                                  ? const SizedBox(
                                      height: 16,
                                      width: 16,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Text('Simpan'),
                            ),
                          ),
                        ],
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

  bool _mapEquals(Map<int, int> a, Map<int, int> b) {
    if (a.length != b.length) return false;
    for (final e in a.entries) {
      if (b[e.key] != e.value) return false;
    }
    return true;
  }
}
