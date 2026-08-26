// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Widget cart (daftar item, inline notes, qty controls).
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanCartWidgetsX on _PenjualanScreenState {
  Widget _buildCart(PenjualanState state) {
    if (state.items.isEmpty) {
      return ListView(
        physics: const AlwaysScrollableScrollPhysics(),
        children: const [
          SizedBox(height: 80),
          Center(
            child: Text(
              'Belum ada produk',
              style: TextStyle(color: Colors.grey),
            ),
          ),
        ],
      );
    }

    return ListView.builder(
      padding: const EdgeInsets.all(8),
      itemCount: state.items.length,
      itemBuilder: (_, i) {
        final item = state.items[i];
        // Tampilkan badge "Package" jika ada packagesNotes
        final isPackage =
            item.packagesNotes != null && item.packagesNotes!.isNotEmpty;

        // Inisialisasi controller notes jika belum ada
        if (!_itemNotesControllers.containsKey(i)) {
          _itemNotesControllers[i] = TextEditingController(
            text: item.keterangan ?? '',
          );
        }
        final notesCtrl = _itemNotesControllers[i]!;
        final isExpanded = _expandedNotes.contains(i);
        final hasNotes = (item.keterangan ?? '').isNotEmpty;

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  item.nama,
                                  style: const TextStyle(
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              if (isPackage)
                                Container(
                                  margin: const EdgeInsets.only(left: 4),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 2,
                                  ),
                                  decoration: BoxDecoration(
                                    color: Colors.blue.shade50,
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                      color: Colors.blue.shade200,
                                    ),
                                  ),
                                  child: const Text(
                                    'Package',
                                    style: TextStyle(
                                      fontSize: 10,
                                      color: Colors.blue,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                          Text(
                            item.kode,
                            style: const TextStyle(
                              fontSize: 12,
                              color: Colors.grey,
                            ),
                          ),
                          Text(
                            'Rp ${CurrencyFormat.format(item.hpj)}',
                            style: const TextStyle(fontSize: 12),
                          ),
                        ],
                      ),
                    ),
                    // Qty control
                    Row(
                      children: [
                        IconButton(
                          icon: const Icon(Icons.remove_circle_outline),
                          onPressed: () => _updateQty(i, item.qty - 1),
                        ),
                        Text(
                          '${item.qty}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        IconButton(
                          icon: const Icon(Icons.add_circle_outline),
                          onPressed: () => _updateQty(i, item.qty + 1),
                        ),
                      ],
                    ),
                    // Subtotal + delete + notes toggle
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Text(
                          'Rp ${CurrencyFormat.format(item.subtotal)}',
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            // Ikon notes — kuning jika sudah ada notes
                            IconButton(
                              icon: Icon(
                                hasNotes
                                    ? Icons.edit_note
                                    : Icons.add_comment_outlined,
                                size: 20,
                                color: hasNotes
                                    ? Colors.amber.shade700
                                    : Colors.grey,
                              ),
                              tooltip: 'Catatan item',
                              onPressed: () {
                                _setState(() {
                                  if (isExpanded) {
                                    _expandedNotes.remove(i);
                                  } else {
                                    _expandedNotes.add(i);
                                  }
                                });
                              },
                            ),
                            // Edit pilihan package — HANYA untuk item
                            // package. Single item tidak butuh edit
                            // karena tidak ada isian/addon untuk diganti.
                            if (item.isPackage)
                              IconButton(
                                icon: const Icon(
                                  Icons.tune,
                                  color: Colors.indigo,
                                  size: 20,
                                ),
                                tooltip: 'Edit pilihan package',
                                onPressed: () => _editPackageItem(i),
                              ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.red,
                                size: 20,
                              ),
                              onPressed: () => _removeItem(i),
                            ),
                          ],
                        ),
                      ],
                    ),
                  ],
                ),
                // Inline notes input — tampil jika expanded
                if (isExpanded)
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 2),
                    child: TextField(
                      controller: notesCtrl,
                      autofocus: true,
                      decoration: InputDecoration(
                        hintText: 'Catatan untuk item ini...',
                        border: const OutlineInputBorder(),
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 10,
                          vertical: 6,
                        ),
                        isDense: true,
                        suffixIcon: IconButton(
                          icon: const Icon(
                            Icons.check,
                            size: 18,
                            color: Color(0xFF1D273B),
                          ),
                          onPressed: () async {
                            final ket = notesCtrl.text.trim();
                            await _updateItemKeterangan(i, ket);
                            _setState(() => _expandedNotes.remove(i));
                          },
                        ),
                      ),
                      maxLines: 1,
                      textInputAction: TextInputAction.done,
                      onSubmitted: (val) async {
                        await _updateItemKeterangan(i, val.trim());
                        _setState(() => _expandedNotes.remove(i));
                      },
                    ),
                  )
                // Tampilkan notes yang sudah tersimpan (collapsed)
                else if (hasNotes)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notes,
                          size: 13,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.keterangan ?? '',
                            style: TextStyle(
                              fontSize: 11,
                              color: Colors.amber.shade800,
                              fontStyle: FontStyle.italic,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
              ],
            ),
          ),
        );
      },
    );
  }

  // ============================================================
  // LAYOUT STACKED — portrait / layar sempit (< 600dp)
  // Menggunakan LayoutBuilder agar tinggi panel bawah dihitung
  // dari sisa ruang yang benar-benar tersedia (sudah dikurangi
  // SafeArea + AppBar), bukan dari size.height mentah.
  // ============================================================

}
