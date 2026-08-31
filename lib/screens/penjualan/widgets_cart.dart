// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Widget cart (daftar item, inline notes, qty controls).
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya, KECUALI layout item card
// (lihat catatan di bawah): diubah dari 3-kolom sejajar (nama|qty|subtotal+icons)
// jadi stacked 3-baris (nama full-width | kode+harga | qty+subtotal+aksi),
// supaya nama produk panjang tidak lagi diperas jadi wrap per-karakter di
// tablet 7 inch setelah penambahan icon gift.
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

    // Dipakai untuk gating icon "jadikan gratis" — hanya boleh 1 item
    // gratis per transaksi.
    final hasFreeItem = state.items.any((it) => it.isFree);

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
        // Nama produk di-tap untuk expand/collapse — supaya nama panjang
        // dengan banyak addon (yang di-ellipsis di layout ringkas) tetap
        // bisa dibaca lengkap tanpa mengorbankan tinggi baris saat normal.
        final isNameExpanded = _expandedNames.contains(i);

        return Card(
          child: Padding(
            padding: const EdgeInsets.all(8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ------------------------------------------------------
                // Baris 1: nama produk — full width, 1 baris, ellipsis.
                // Badge (Package/Gratis) ditaruh SETELAH Expanded supaya
                // ukurannya tetap (intrinsic) dan nama yang mengalah
                // memendek dengan "...", bukan sebaliknya.
                // ------------------------------------------------------
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _setState(() {
                      if (isNameExpanded) {
                        _expandedNames.remove(i);
                      } else {
                        _expandedNames.add(i);
                      }
                    });
                  },
                  child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Text(
                        item.nama,
                        maxLines: isNameExpanded ? null : 1,
                        overflow: isNameExpanded
                            ? TextOverflow.visible
                            : TextOverflow.ellipsis,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                    Icon(
                      isNameExpanded
                          ? Icons.unfold_less
                          : Icons.unfold_more,
                      size: 14,
                      color: Colors.grey.shade400,
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
                          border: Border.all(color: Colors.blue.shade200),
                        ),
                        child: const Text(
                          'Package',
                          style: TextStyle(fontSize: 10, color: Colors.blue),
                        ),
                      ),
                    if (item.isFree)
                      Container(
                        margin: const EdgeInsets.only(left: 4),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: Colors.green.shade50,
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: Colors.green.shade300),
                        ),
                        child: Text(
                          'GRATIS${item.freeReason != null ? " · ${item.freeReason}" : ""}',
                          style: TextStyle(
                            fontSize: 10,
                            color: Colors.green.shade800,
                          ),
                        ),
                      ),
                  ],
                  ),
                ),
                // ------------------------------------------------------
                // Baris 2: kode SKU + harga satuan (kecil, abu-abu)
                // ------------------------------------------------------
                const SizedBox(height: 2),
                Row(
                  children: [
                    Text(
                      item.kode,
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'Rp ${CurrencyFormat.format(item.hpj)}',
                      style: const TextStyle(fontSize: 12, color: Colors.grey),
                    ),
                  ],
                ),
                // ------------------------------------------------------
                // Baris 3: qty stepper (kiri) — subtotal + aksi (kanan).
                // Icon sekunder (catatan, edit package) digabung ke
                // PopupMenuButton supaya jumlah tap-target yang harus
                // muat sejajar tetap sedikit walau fitur baru ditambah.
                // ------------------------------------------------------
                const SizedBox(height: 2),
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: item.isFree
                          ? null
                          : () => _updateQty(i, item.qty - 1),
                    ),
                    Text(
                      '${item.qty}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 22),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: item.isFree
                          ? null
                          : () => _updateQty(i, item.qty + 1),
                    ),
                    const Spacer(),
                    Text(
                      'Rp ${CurrencyFormat.format(item.subtotal)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: item.isFree ? Colors.green.shade700 : null,
                      ),
                    ),
                    const SizedBox(width: 4),
                    // Toggle gratis/gift — tetap terlihat langsung (dipakai
                    // sering, keputusan sadar), hanya muncul untuk produk
                    // eligible atau baris yang sudah gratis.
                    if (item.isFree || item.isGiftEligible)
                      IconButton(
                        icon: Icon(
                          Icons.card_giftcard,
                          size: 20,
                          color: item.isFree
                              ? Colors.green
                              : (hasFreeItem
                                  ? Colors.grey.shade300
                                  : Colors.grey),
                        ),
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(
                          minWidth: 32,
                          minHeight: 32,
                        ),
                        tooltip: item.isFree
                            ? 'Batalkan gratis'
                            : (hasFreeItem
                                ? 'Hanya boleh 1 item gratis per transaksi'
                                : 'Jadikan gratis'),
                        onPressed: (!item.isFree && hasFreeItem)
                            ? null
                            : () => _showFreeItemSheet(i),
                      ),
                    // Icon sekunder (catatan + edit package) → overflow menu
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: hasNotes ? Colors.amber.shade700 : Colors.grey,
                      ),
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'notes') {
                          _setState(() {
                            if (isExpanded) {
                              _expandedNotes.remove(i);
                            } else {
                              _expandedNotes.add(i);
                            }
                          });
                        } else if (value == 'package') {
                          _editPackageItem(i);
                        }
                      },
                      itemBuilder: (context) => [
                        PopupMenuItem(
                          value: 'notes',
                          child: Row(
                            children: [
                              Icon(
                                hasNotes
                                    ? Icons.edit_note
                                    : Icons.add_comment_outlined,
                                size: 18,
                                color: hasNotes
                                    ? Colors.amber.shade700
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(hasNotes ? 'Edit catatan' : 'Tambah catatan'),
                            ],
                          ),
                        ),
                        // Edit pilihan package — HANYA untuk item package.
                        if (item.isPackage)
                          const PopupMenuItem(
                            value: 'package',
                            child: Row(
                              children: [
                                Icon(Icons.tune, size: 18, color: Colors.indigo),
                                SizedBox(width: 8),
                                Text('Edit pilihan package'),
                              ],
                            ),
                          ),
                      ],
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete, color: Colors.red, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 32,
                        minHeight: 32,
                      ),
                      onPressed: () => _removeItem(i),
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
  //
  // Versi ringkas cart untuk mobile/portrait: baris yang SELALU
  // terlihat cuma nama produk (tap-to-expand) + qty stepper +
  // subtotal. Aksi lain (jadikan gratis, catatan, edit package,
  // hapus) digabung ke menu overflow (⋮) supaya baris tetap
  // pendek di layar hp yang sempit.
  // ============================================================
  Widget _buildCartMobile(PenjualanState state) {
    if (state.items.isEmpty) {
      return const Center(
        child: Text('Belum ada produk', style: TextStyle(color: Colors.grey)),
      );
    }

    final hasFreeItem = state.items.any((it) => it.isFree);

    return ListView.builder(
      padding: const EdgeInsets.all(6),
      itemCount: state.items.length,
      itemBuilder: (_, i) {
        final item = state.items[i];
        final isPackage =
            item.packagesNotes != null && item.packagesNotes!.isNotEmpty;

        if (!_itemNotesControllers.containsKey(i)) {
          _itemNotesControllers[i] = TextEditingController(
            text: item.keterangan ?? '',
          );
        }
        final notesCtrl = _itemNotesControllers[i]!;
        final isExpanded = _expandedNotes.contains(i);
        final hasNotes = (item.keterangan ?? '').isNotEmpty;
        final isNameExpanded = _expandedNames.contains(i);

        return Card(
          margin: const EdgeInsets.symmetric(vertical: 2),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Baris nama — tap untuk expand, badge Package/Gratis inline
                GestureDetector(
                  behavior: HitTestBehavior.opaque,
                  onTap: () {
                    _setState(() {
                      if (isNameExpanded) {
                        _expandedNames.remove(i);
                      } else {
                        _expandedNames.add(i);
                      }
                    });
                  },
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          item.nama,
                          maxLines: isNameExpanded ? null : 1,
                          overflow: isNameExpanded
                              ? TextOverflow.visible
                              : TextOverflow.ellipsis,
                          style: const TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      Icon(
                        isNameExpanded ? Icons.unfold_less : Icons.unfold_more,
                        size: 13,
                        color: Colors.grey.shade400,
                      ),
                      if (isPackage)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.blue.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.blue.shade200),
                          ),
                          child: const Text(
                            'Package',
                            style: TextStyle(fontSize: 9, color: Colors.blue),
                          ),
                        ),
                      if (item.isFree)
                        Container(
                          margin: const EdgeInsets.only(left: 4),
                          padding: const EdgeInsets.symmetric(
                            horizontal: 5,
                            vertical: 1,
                          ),
                          decoration: BoxDecoration(
                            color: Colors.green.shade50,
                            borderRadius: BorderRadius.circular(4),
                            border: Border.all(color: Colors.green.shade300),
                          ),
                          child: Text(
                            'GRATIS',
                            style: TextStyle(
                              fontSize: 9,
                              color: Colors.green.shade800,
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 4),
                // Baris qty + subtotal + menu ⋮ (semua aksi lain di sini)
                Row(
                  children: [
                    IconButton(
                      icon: const Icon(Icons.remove_circle_outline, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      onPressed: item.isFree
                          ? null
                          : () => _updateQty(i, item.qty - 1),
                    ),
                    Text(
                      '${item.qty}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    IconButton(
                      icon: const Icon(Icons.add_circle_outline, size: 20),
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 30,
                        minHeight: 30,
                      ),
                      onPressed: item.isFree
                          ? null
                          : () => _updateQty(i, item.qty + 1),
                    ),
                    const Spacer(),
                    Text(
                      'Rp ${CurrencyFormat.format(item.subtotal)}',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 13,
                        color: item.isFree ? Colors.green.shade700 : null,
                      ),
                    ),
                    PopupMenuButton<String>(
                      icon: Icon(
                        Icons.more_vert,
                        size: 20,
                        color: hasNotes ? Colors.amber.shade700 : Colors.grey,
                      ),
                      padding: EdgeInsets.zero,
                      onSelected: (value) {
                        if (value == 'notes') {
                          _setState(() {
                            if (isExpanded) {
                              _expandedNotes.remove(i);
                            } else {
                              _expandedNotes.add(i);
                            }
                          });
                        } else if (value == 'package') {
                          _editPackageItem(i);
                        } else if (value == 'gift') {
                          _showFreeItemSheet(i);
                        } else if (value == 'delete') {
                          _removeItem(i);
                        }
                      },
                      itemBuilder: (context) => [
                        if (item.isFree || item.isGiftEligible)
                          PopupMenuItem(
                            value: 'gift',
                            enabled: item.isFree || !hasFreeItem,
                            child: Row(
                              children: [
                                Icon(
                                  Icons.card_giftcard,
                                  size: 18,
                                  color:
                                      item.isFree ? Colors.green : Colors.grey,
                                ),
                                const SizedBox(width: 8),
                                Text(
                                  item.isFree
                                      ? 'Batalkan gratis'
                                      : (hasFreeItem
                                          ? 'Sudah ada item gratis'
                                          : 'Jadikan gratis'),
                                ),
                              ],
                            ),
                          ),
                        PopupMenuItem(
                          value: 'notes',
                          child: Row(
                            children: [
                              Icon(
                                hasNotes
                                    ? Icons.edit_note
                                    : Icons.add_comment_outlined,
                                size: 18,
                                color: hasNotes
                                    ? Colors.amber.shade700
                                    : Colors.grey,
                              ),
                              const SizedBox(width: 8),
                              Text(
                                hasNotes ? 'Edit catatan' : 'Tambah catatan',
                              ),
                            ],
                          ),
                        ),
                        if (item.isPackage)
                          const PopupMenuItem(
                            value: 'package',
                            child: Row(
                              children: [
                                Icon(Icons.tune, size: 18, color: Colors.indigo),
                                SizedBox(width: 8),
                                Text('Edit pilihan package'),
                              ],
                            ),
                          ),
                        const PopupMenuItem(
                          value: 'delete',
                          child: Row(
                            children: [
                              Icon(Icons.delete, size: 18, color: Colors.red),
                              SizedBox(width: 8),
                              Text('Hapus item'),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
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
                else if (hasNotes)
                  Padding(
                    padding: const EdgeInsets.only(top: 2, left: 2),
                    child: Row(
                      children: [
                        Icon(
                          Icons.notes,
                          size: 12,
                          color: Colors.amber.shade700,
                        ),
                        const SizedBox(width: 4),
                        Expanded(
                          child: Text(
                            item.keterangan ?? '',
                            style: TextStyle(
                              fontSize: 10,
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
}
