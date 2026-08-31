// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Operasi cart (remove/qty/keterangan), tambah member, voucher dialog & apply, retur.
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanCartX on _PenjualanScreenState {
  Future<void> _removeItem(int index) async {
    await _runCartMutation(() async {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);
      final item = state.items[index];

      await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'deleteItem',
          'id': item.id,
          'number': state.number,
          'sku': item.kode,
          'packages_notes': item.packagesNotes ?? '',
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'voucher': _activeVoucher,
          'device_token': _deviceToken,
        }),
      );

      await _refreshFromApi();
    });
  }

  Future<void> _updateQty(int index, int qty) async {
    if (qty <= 0) {
      await _removeItem(index);
      return;
    }
    await _runCartMutation(() async {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);
      final item = state.items[index];

      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'updateQty',
          'id': item.id,
          'number': state.number,
          'sku': item.kode,
          'qty': qty,
          'packages_notes': item.packagesNotes ?? '',
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'voucher': _activeVoucher,
          'device_token': _deviceToken,
          'salestipe_id': state.salesTipeID,
        }),
      );

      if (res.data['success'] != true) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.data['message'] ?? 'Gagal mengubah qty'),
              backgroundColor: Colors.red,
            ),
          );
        }
        return;
      }

      await _refreshFromApi();
    });
  }

  Future<void> _updateItemKeterangan(int index, String keterangan) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);
    final item = state.items[index];

    await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'updateItemKeterangan',
        'id': item.id,
        'number': state.number,
        'sku': item.kode,
        'packages_notes': item.packagesNotes ?? '',
        'keterangan': keterangan,
        'device_token': _deviceToken,
      }),
    );

    // Dispose controller lama agar re-init dengan teks terbaru setelah refresh
    _itemNotesControllers[index]?.dispose();
    _itemNotesControllers.remove(index);

    // Refresh state agar keterangan tampil di bawah item
    await _refreshFromApi();
  }

  // ============================================================
  // MEMBER — Add Member Baru (bottom sheet)
  // ============================================================
  void _showAddMemberSheet() {
    final state = ref.read(penjualanProvider);
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AddMemberSheet(
        token: _token,
        organisasiID: state.organisasiID,
        onSuccess: (memberID, display, nama) async {
          // Set member ke state + field
          _memberController.text = display;
          ref.read(penjualanProvider.notifier).setMember(memberID, nama);

          // Recalculate diskon dengan member baru
          await _runCartMutation(() async {
            final dio = ApiService.getDio(token: _token);
            await dio.post(
              '/penjualan.php',
              data: FormData.fromMap({
                'action': 'recalculate',
                'number': state.number,
                'store_id': state.storeID,
                'organisasi_id': state.organisasiID,
                'member_id': memberID,
                'voucher': _activeVoucher,
                'device_token': _deviceToken,
              }),
            );

            await _refreshFromApi();
          });

          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text('Member "$nama" berhasil ditambahkan'),
                backgroundColor: Colors.green,
              ),
            );
          }
        },
      ),
    );
  }

  // ============================================================
  // VOUCHER
  // ============================================================
  void _showVoucherDialog() {
    final voucherController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Input Voucher'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (_activeVoucher.isNotEmpty)
              Container(
                padding: const EdgeInsets.all(8),
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.indigo.shade50,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      'Aktif: $_activeVoucher',
                      style: const TextStyle(color: Colors.indigo),
                    ),
                    GestureDetector(
                      onTap: () async {
                        Navigator.pop(context);
                        await _removeVoucher();
                      },
                      child: const Icon(
                        Icons.close,
                        size: 18,
                        color: Colors.red,
                      ),
                    ),
                  ],
                ),
              ),
            TextField(
              controller: voucherController,
              decoration: const InputDecoration(
                labelText: 'Kode Voucher',
                border: OutlineInputBorder(),
              ),
              autofocus: true,
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final kode = voucherController.text.trim();
              if (kode.isEmpty) return;
              Navigator.pop(context);
              await _applyVoucher(kode);
            },
            child: const Text('Apply'),
          ),
        ],
      ),
    );
  }

  Future<void> _applyVoucher(String kode) async {
    await _runCartMutation(() async {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);

      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'cekVoucher',
          'number': state.number,
          'voucher': kode,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'device_token': _deviceToken,
        }),
      );

      if (res.data['success'] == true) {
        _setState(() => _activeVoucher = kode);
        await _refreshFromApi();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Voucher $kode berhasil diapply'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.data['message'] ?? 'Voucher tidak valid'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  Future<void> _removeVoucher() async {
    await _runCartMutation(() async {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);

      await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'resetDiskon',
          'number': state.number,
          'device_token': _deviceToken,
        }),
      );

      await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'recalculate',
          'number': state.number,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'voucher': '',
          'device_token': _deviceToken,
        }),
      );

      _setState(() => _activeVoucher = '');
      await _refreshFromApi();
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Voucher dilepas')));
      }
    });
  }

  // ============================================================
  // RETUR
  // ============================================================
  void _showReturDialog() {
    final returController = TextEditingController();
    showDialog(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Retur Penjualan'),
        content: TextField(
          controller: returController,
          decoration: const InputDecoration(
            labelText: 'No. Transaksi Asal',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () async {
              final nomor = returController.text.trim();
              if (nomor.isEmpty) return;
              Navigator.pop(context);
              await _prosesRetur(nomor);
            },
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('RETUR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  // NOTE: cekRetur sengaja di luar _runCartMutation — itu cuma validasi
  // read-only, belum menyentuh temp_invoice, jadi kasir masih bebas
  // ngetik ulang nomor retur tanpa kena lock. Lock baru mulai begitu
  // loadRetur beneran menulis item retur ke temp_invoice — sama seperti
  // insert produk/ganti channel/voucher — supaya Pending/Bayar tidak
  // bisa dipencet sebelum item retur selesai masuk ke cart.
  Future<void> _prosesRetur(String returNumber) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final cekRes = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'cekRetur',
        'retur_number': returNumber,
        'store_id': state.storeID,
        'organisasi_id': state.organisasiID,
      }),
    );

    if (cekRes.data['success'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(cekRes.data['message']),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    await _runCartMutation(() async {
      final loadRes = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'loadRetur',
          'retur_number': returNumber,
          'number': state.number,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'device_token': _deviceToken,
        }),
      );

      if (loadRes.data['success'] == true) {
        ref.read(penjualanProvider.notifier).setReturSource(returNumber);
        await _refreshFromApi();
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('Mode retur aktif — $returNumber'),
              backgroundColor: Colors.orange,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Gagal load item retur'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
  }

  // ============================================================
  // FREE / GIFT ITEM — mis. barang mendekati ED dikasih gratis ke
  // customer. Dikunci qty 1, dan hanya boleh 1 item gratis per cart.
  // ============================================================
  static const List<String> _freeReasonOptions = [
    'Mendekati ED',
    'Rusak/Cacat Kemasan',
    'Komplain / Ganti Rugi',
    'Sample / Promosi',
    'Lainnya',
  ];

  void _showFreeItemSheet(int index) {
    final state = ref.read(penjualanProvider);
    final item = state.items[index];

    if (item.isFree) {
      showDialog(
        context: context,
        builder: (_) => AlertDialog(
          title: const Text('Batalkan Status Gratis?'),
          content: Text('${item.nama} akan dikembalikan ke harga normal.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('Batal'),
            ),
            ElevatedButton(
              onPressed: () async {
                Navigator.pop(context);
                await _setItemFree(index, isFree: false, reason: '');
              },
              style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
              child: const Text(
                'Ya, Batalkan',
                style: TextStyle(color: Colors.white),
              ),
            ),
          ],
        ),
      );
      return;
    }

    // Guard lokal — jangan buka sheet kalau cart sudah punya gift lain
    if (state.items.any((it) => it.isFree)) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Sudah ada item gratis di keranjang ini.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    if (item.qty != 1) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Item gratis harus qty 1. Kurangi qty dulu, atau pakai tombol + Tambah Item.',
          ),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    String? selectedReason;
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) => Padding(
          padding: EdgeInsets.only(
            left: 16,
            right: 16,
            top: 16,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  const Icon(Icons.card_giftcard, color: Colors.green),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'Jadikan Gratis — ${item.nama}',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 12),
              const Text('Alasan (wajib diisi)'),
              ..._freeReasonOptions.map(
                (r) => RadioListTile<String>(
                  dense: true,
                  contentPadding: EdgeInsets.zero,
                  title: Text(r),
                  value: r,
                  groupValue: selectedReason,
                  onChanged: (val) => setSheetState(() => selectedReason = val),
                ),
              ),
              const SizedBox(height: 8),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: selectedReason == null
                      ? null
                      : () async {
                          Navigator.pop(ctx);
                          await _setItemFree(
                            index,
                            isFree: true,
                            reason: selectedReason!,
                          );
                        },
                  style: ElevatedButton.styleFrom(backgroundColor: Colors.green),
                  child: const Text(
                    'Jadikan Gratis',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _setItemFree(
    int index, {
    required bool isFree,
    required String reason,
  }) async {
    await _runCartMutation(() async {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);
      final item = state.items[index];

      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'setItemFree',
          'id': item.id,
          'number': state.number,
          'is_free': isFree ? 1 : 0,
          'free_reason': reason,
          'device_token': _deviceToken,
        }),
      );

      if (res.data['success'] == true) {
        await _refreshFromApi();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data['message'] ?? 'Gagal mengubah status gratis'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  // ============================================================
  // "+ TAMBAH ITEM" — popup insert baris baru, TIDAK PERNAH MERGE
  // dengan baris produk yang sudah ada (dipakai a.l. untuk menambah
  // produk yang sama sebagai baris gift terpisah dari baris normal).
  //
  // Search produk di sheet ini sekarang sama seperti field SKU di
  // header: ketik kode ATAU nama (backend action `searchProduk` sudah
  // pakai `kode LIKE ? OR nama LIKE ?`), lalu:
  //   - 1 hasil  -> langsung terpilih otomatis
  //   - >1 hasil -> muncul suggestion list di dalam sheet, tap salah
  //     satu untuk memilih
  // Kalau kasir langsung scan barcode + submit tanpa pernah lihat
  // suggestion (kode persis 1 match), tetap jalan seperti biasa —
  // tidak ada langkah tambahan yang mengganggu alur scanner.
  // ============================================================
  void _showAddItemSheet() {
    final searchController = TextEditingController();
    final qtyController = TextEditingController(text: '1');
    bool isGift = false;
    String? giftReason;

    // Produk yang sudah pasti terpilih (siap di-submit).
    String? selectedKode;
    String? selectedNama;
    // Eligibility gift produk yang dipilih (dim_produk.is_gift) — menentukan
    // apakah switch "Jadikan Gratis/Gift" ditampilkan sama sekali.
    bool selectedIsGiftEligible = false;

    // Hasil pencarian yang belum dipilih (ditampilkan sebagai suggestion).
    List<Map<String, dynamic>> searchResults = [];
    bool isSearching = false;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setSheetState) {
          Future<void> runSearch(String term) async {
            if (term.isEmpty) return;
            setSheetState(() {
              isSearching = true;
              searchResults = [];
            });

            try {
              final state = ref.read(penjualanProvider);
              final dio = ApiService.getDio(token: _token);
              final res = await dio.post(
                '/penjualan.php',
                data: FormData.fromMap({
                  'action': 'searchProduk',
                  'term': term,
                  'organisasi_id': state.organisasiID,
                  'salestipe_id': state.salesTipeID,
                }),
              );

              final data = List<Map<String, dynamic>>.from(
                res.data['data'] ?? [],
              );

              if (data.isEmpty) {
                setSheetState(() => isSearching = false);
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    SnackBar(content: Text('Produk "$term" tidak ditemukan')),
                  );
                }
                return;
              }

              if (data.length == 1) {
                // Match tunggal — langsung terpilih, tidak perlu tap lagi.
                final p = data.first;
                final isGiftEligible =
                    p['is_gift'] == true || p['is_gift'] == 1;
                setSheetState(() {
                  selectedKode = p['kode']?.toString();
                  selectedNama = p['nama']?.toString();
                  selectedIsGiftEligible = isGiftEligible;
                  searchController.text =
                      '${p['nama']} (${p['kode']})';
                  searchResults = [];
                  isSearching = false;
                  // Reset pilihan gift kalau produk yang baru terpilih
                  // ternyata tidak eligible.
                  if (!isGiftEligible) {
                    isGift = false;
                    giftReason = null;
                  }
                });
              } else {
                setSheetState(() {
                  searchResults = data;
                  isSearching = false;
                });
              }
            } catch (_) {
              setSheetState(() => isSearching = false);
              if (mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(
                    content: Text('Gagal mencari produk, coba lagi'),
                    backgroundColor: Colors.red,
                  ),
                );
              }
            }
          }

          void selectProduk(Map<String, dynamic> p) {
            final isGiftEligible = p['is_gift'] == true || p['is_gift'] == 1;
            setSheetState(() {
              selectedKode = p['kode']?.toString();
              selectedNama = p['nama']?.toString();
              selectedIsGiftEligible = isGiftEligible;
              searchController.text = '${p['nama']} (${p['kode']})';
              searchResults = [];
              // Reset pilihan gift kalau produk yang baru terpilih
              // ternyata tidak eligible.
              if (!isGiftEligible) {
                isGift = false;
                giftReason = null;
              }
            });
          }

          return Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 16,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Tambah Item',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: searchController,
                  decoration: InputDecoration(
                    labelText: 'Kode / Nama Produk',
                    border: const OutlineInputBorder(),
                    suffixIcon: isSearching
                        ? const Padding(
                            padding: EdgeInsets.all(12),
                            child: SizedBox(
                              width: 16,
                              height: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            ),
                          )
                        : IconButton(
                            icon: const Icon(Icons.search),
                            onPressed: () =>
                                runSearch(searchController.text.trim()),
                          ),
                  ),
                  autofocus: true,
                  onChanged: (_) {
                    // Teks diubah manual lagi setelah sempat terpilih —
                    // batalkan pilihan lama supaya tidak submit produk
                    // yang salah kalau kasir lupa search ulang.
                    if (selectedKode != null) {
                      setSheetState(() {
                        selectedKode = null;
                        selectedNama = null;
                        selectedIsGiftEligible = false;
                        isGift = false;
                        giftReason = null;
                      });
                    }
                  },
                  onSubmitted: runSearch,
                ),
                if (searchResults.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  ConstrainedBox(
                    constraints: const BoxConstraints(maxHeight: 220),
                    child: Card(
                      margin: EdgeInsets.zero,
                      child: ListView.separated(
                        shrinkWrap: true,
                        itemCount: searchResults.length,
                        separatorBuilder: (_, __) => const Divider(height: 1),
                        itemBuilder: (_, i) {
                          final p = searchResults[i];
                          return ListTile(
                            dense: true,
                            title: Text(p['nama']?.toString() ?? ''),
                            subtitle: Text(p['kode']?.toString() ?? ''),
                            trailing: Text(
                              'Rp ${CurrencyFormat.format(p['hpj'])}',
                            ),
                            onTap: () => selectProduk(p),
                          );
                        },
                      ),
                    ),
                  ),
                ],
                if (selectedKode != null) ...[
                  const SizedBox(height: 8),
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 6,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green.shade50,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(color: Colors.green.shade200),
                    ),
                    child: Row(
                      children: [
                        const Icon(
                          Icons.check_circle,
                          size: 16,
                          color: Colors.green,
                        ),
                        const SizedBox(width: 6),
                        Expanded(
                          child: Text(
                            'Terpilih: $selectedNama',
                            style: const TextStyle(fontSize: 13),
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
                const SizedBox(height: 12),
                Row(
                  children: [
                    const Text('Qty'),
                    const SizedBox(width: 12),
                    SizedBox(
                      width: 80,
                      child: TextField(
                        controller: qtyController,
                        enabled: !isGift, // qty dikunci 1 kalau gift
                        keyboardType: TextInputType.number,
                        textAlign: TextAlign.center,
                        decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          isDense: true,
                        ),
                      ),
                    ),
                  ],
                ),
                // Switch gift hanya muncul untuk produk yang ditandai
                // eligible (is_gift = 1 di dim_produk) — bukan tiap produk.
                if (selectedIsGiftEligible) ...[
                  const SizedBox(height: 8),
                  SwitchListTile(
                    contentPadding: EdgeInsets.zero,
                    title: const Text('Jadikan Gratis / Gift'),
                    value: isGift,
                    onChanged: (val) {
                      setSheetState(() {
                        isGift = val;
                        if (val) qtyController.text = '1';
                      });
                    },
                  ),
                ],
                if (isGift) ...[
                  const SizedBox(height: 4),
                  const Text('Alasan (wajib diisi)'),
                  ..._freeReasonOptions.map(
                    (r) => RadioListTile<String>(
                      dense: true,
                      contentPadding: EdgeInsets.zero,
                      title: Text(r),
                      value: r,
                      groupValue: giftReason,
                      onChanged: (val) =>
                          setSheetState(() => giftReason = val),
                    ),
                  ),
                ],
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                    onPressed: (isGift && giftReason == null)
                        ? null
                        : () async {
                            // Kalau sudah ada hasil terpilih dari suggestion,
                            // pakai kode itu. Kalau belum (mis. kasir scan
                            // barcode lalu langsung tekan "Tambah" tanpa
                            // pernah lihat suggestion), kirim teks apa
                            // adanya — backend tetap exact-match by kode,
                            // jadi alur scanner lama tidak berubah.
                            final sku =
                                selectedKode ?? searchController.text.trim();
                            final qty =
                                int.tryParse(qtyController.text.trim()) ?? 1;
                            if (sku.isEmpty) return;
                            Navigator.pop(ctx);
                            await _insertItemNewRow(
                              sku,
                              qty,
                              isFree: isGift,
                              reason: giftReason ?? '',
                            );
                          },
                    child: const Text('Tambah'),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _insertItemNewRow(
    String sku,
    int qty, {
    required bool isFree,
    required String reason,
  }) async {
    await _runCartMutation(() async {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);

      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'insertItemNewRow',
          'number': state.number,
          'sku': sku,
          'qty': qty,
          'is_free': isFree ? 1 : 0,
          'free_reason': reason,
          'store_id': state.storeID,
          'organisasi_id': state.organisasiID,
          'member_id': state.memberID ?? 0,
          'voucher': _activeVoucher,
          'device_token': _deviceToken,
          'salestipe_id': state.salesTipeID,
        }),
      );

      if (res.data['success'] == true) {
        await _refreshFromApi();
      } else if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data['message'] ?? 'Gagal menambah item'),
            backgroundColor: Colors.red,
          ),
        );
      }
    });
  }

  // ============================================================
  // PROSES BAYAR
  // ============================================================

}
