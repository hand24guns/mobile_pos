// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Operasi cart (remove/qty/keterangan), tambah member, voucher dialog & apply, retur.
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanCartX on _PenjualanScreenState {
  Future<void> _removeItem(int index) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);
    final item = state.items[index];

    await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'deleteItem',
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
  }

  Future<void> _updateQty(int index, int qty) async {
    if (qty <= 0) {
      await _removeItem(index);
      return;
    }
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);
    final item = state.items[index];

    await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'updateQty',
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

    await _refreshFromApi();
  }

  Future<void> _updateItemKeterangan(int index, String keterangan) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);
    final item = state.items[index];

    await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'updateItemKeterangan',
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
  }

  Future<void> _removeVoucher() async {
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
  }

  // ============================================================
  // PROSES BAYAR
  // ============================================================

}
