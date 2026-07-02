// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Pending order: simpan, retrieve, delete, print pending (customer/kitchen/both).
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanPendingX on _PenjualanScreenState {
  Future<void> _showPendingDialog() async {
    final state = ref.read(penjualanProvider);

    if (state.items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Belum ada produk')));
      return;
    }

    // Tampilkan dialog — untuk update, field label sudah terisi nama sebelumnya
    final labelController = TextEditingController(
      text: _activePendingOrderID != null ? _activePendingLabel : '',
    );
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Hold Order'),
        content: TextField(
          controller: labelController,
          decoration: const InputDecoration(
            labelText: 'Label / No. Meja (opsional)',
            border: OutlineInputBorder(),
          ),
          autofocus: true,
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text('Simpan', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    await _doSimpanPending(
      state: state,
      label: labelController.text.trim(),
      pendingOrderID: _activePendingOrderID,
    );
  }

  Future<void> _doSimpanPending({
    required PenjualanState state,
    required String? label,
    required int? pendingOrderID,
  }) async {
    final session = await SessionService.getSession();
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'simpanPending',
        'number': state.number,
        'store_id': state.storeID,
        'organisasi_id': state.organisasiID,
        'member_id': state.memberID ?? 0,
        'user_id': session['user_id'],
        'label': label ?? '',
        'device_token': _deviceToken,
        'salestipe_id': state.salesTipeID,
        'keterangan': _keteranganController.text.trim(),
        if (pendingOrderID != null) 'pending_order_id': pendingOrderID,
      }),
    );

    if (res.data['success'] == true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              pendingOrderID != null
                  ? 'Pending order diperbarui'
                  : 'Order disimpan sebagai pending',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      _setState(() => _activePendingOrderID = null);
      await _resetTransaksi();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data['message'] ?? 'Gagal simpan pending'),
          ),
        );
      }
    }
  }

  // ============================================================
  // RETRIEVE ORDER
  // ============================================================
  Future<void> _showRetrieveDialog() async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'getPendingOrders',
        'store_id': state.storeID,
      }),
    );

    final orders = List<Map<String, dynamic>>.from(res.data['data']);
    if (orders.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Tidak ada pending order')),
        );
      }
      return;
    }
    if (!mounted) return;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.6,
        child: Column(
          children: [
            Container(
              padding: const EdgeInsets.all(16),
              color: const Color(0xFF1D273B),
              width: double.infinity,
              child: const Text(
                'Pending Orders',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                  fontSize: 16,
                ),
              ),
            ),
            Expanded(
              child: ListView.builder(
                itemCount: orders.length,
                itemBuilder: (_, i) {
                  final order = orders[i];
                  return Card(
                    margin: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 6,
                    ),
                    child: ListTile(
                      leading: const Icon(
                        Icons.receipt_long,
                        color: Color(0xFF1D273B),
                      ),
                      title: Text(
                        order['label']?.isNotEmpty == true
                            ? order['label']
                            : order['kode'],
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        '${(order['member'] as String?)?.isNotEmpty == true ? order['member'] : 'Tanpa Member'} • ${order['created_date'].toString().substring(0, 16)}',
                      ),
                      trailing: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          // Print pending
                          IconButton(
                            icon: const Icon(
                              Icons.print_outlined,
                              color: Colors.blueGrey,
                            ),
                            tooltip: 'Print Struk Pending',
                            onPressed: () async {
                              await _printPendingOrder(order);
                            },
                          ),
                          IconButton(
                            icon: const Icon(
                              Icons.play_circle,
                              color: Colors.green,
                            ),
                            onPressed: () async {
                              Navigator.pop(context);
                              await _retrievePending(
                                int.parse(order['id'].toString()),
                                order['member'] as String? ?? '',
                              );
                            },
                          ),
                          IconButton(
                            icon: const Icon(Icons.delete, color: Colors.red),
                            onPressed: () async {
                              final del = await showDialog<bool>(
                                context: context,
                                builder: (_) => AlertDialog(
                                  title: const Text('Hapus Order?'),
                                  content: Text(
                                    'Order ${order['label'] ?? order['kode']} akan dihapus.',
                                  ),
                                  actions: [
                                    TextButton(
                                      onPressed: () =>
                                          Navigator.pop(context, false),
                                      child: const Text('Batal'),
                                    ),
                                    ElevatedButton(
                                      onPressed: () =>
                                          Navigator.pop(context, true),
                                      style: ElevatedButton.styleFrom(
                                        backgroundColor: Colors.red,
                                      ),
                                      child: const Text(
                                        'Hapus',
                                        style: TextStyle(color: Colors.white),
                                      ),
                                    ),
                                  ],
                                ),
                              );
                              if (del == true) {
                                await _deletePending(
                                  int.parse(order['id'].toString()),
                                );
                                if (mounted) Navigator.pop(context);
                                await _showRetrieveDialog();
                              }
                            },
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _retrievePending(int salesOrderID, String member) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'retrievePending',
        'sales_order_id': salesOrderID,
        'number': state.number,
        'device_token': _deviceToken,
      }),
    );

    if (res.data['success'] == true) {
      final restoredNumber = res.data['number'] as String? ?? state.number;

      // Resolve salestipe dulu sebelum setInitialData
      final salestipeID = res.data['salestipe_id'];
      final resolvedSalesTipeID =
          (salestipeID != null && int.parse(salestipeID.toString()) > 0)
              ? int.parse(salestipeID.toString())
              : state.salesTipeID;

      // Set semua data awal sekaligus — number, store, DAN salestipe dalam satu call
      // agar tidak ada state yang ter-reset atau ter-timpa oleh call berikutnya
      ref.read(penjualanProvider.notifier).setInitialData(
            number: restoredNumber,
            storeID: state.storeID,
            storeName: state.storeName,
            organisasiID: state.organisasiID,
            salesTipeID: resolvedSalesTipeID,
          );

      // Set member
      final memberID = res.data['member_id'];
      if (memberID != null && int.parse(memberID.toString()) > 0) {
        _memberController.text = res.data['member'] ?? '';
        ref
            .read(penjualanProvider.notifier)
            .setMember(int.parse(memberID.toString()), member);
      } else {
        _memberController.clear();
        ref.read(penjualanProvider.notifier).setMember(null, '');
      }

      // Restore keterangan
      final keterangan = res.data['keterangan'] as String? ?? '';
      _keteranganController.text = keterangan;

      // Reload grid image jika salestipe berubah
      _loadImageProducts();

      // Simpan ID pending order yang sedang aktif agar bisa di-update (bukan insert baru)
      _setState(() {
        _activePendingOrderID = salesOrderID;
        _activePendingLabel = res.data['order_nama'] as String? ?? '';
      });

      // FIX: Load items langsung dari temp_invoice tanpa recalculate harga.
      // _refreshFromApi() yang lama menyebabkan hpj di-overwrite dengan harga
      // default dari dim_produk, mengabaikan harga salestipe (ShopeeFood, GrabFood, dll).
      await _loadItemsFromTemp(restoredNumber);

      // Fokus ke SKU setelah retrieve agar scanner langsung bisa scan item berikutnya
      _focusSku();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Order berhasil di-retrieve'),
            backgroundColor: Colors.green,
          ),
        );
      }
    }
  }

  // ============================================================
  // LOAD ITEMS FROM TEMP (tanpa recalculate harga)
  // Dipakai khusus setelah retrievePending agar harga salestipe
  // tidak ter-overwrite oleh _refreshFromApi().
  //
  // PHP action 'getCartItemsAsIs' SELECT langsung dari temp_invoice
  // tanpa JOIN ke dim_produk — hpj yang tersimpan dipakai as-is.
  // ============================================================
  Future<void> _loadItemsFromTemp(String number) async {
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'getCartItemsAsIs',
        'number': number,
        'device_token': _deviceToken,
      }),
    );

    if (res.data['success'] != true) return;

    final rawItems = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
    final items = rawItems.map((j) => CartItem.fromJson(j)).toList();

    // updateItems() menghitung ulang gross/diskon/total dari item.subtotal
    // yang sudah tersimpan di temp — hpj tidak diubah sama sekali.
    ref.read(penjualanProvider.notifier).updateItems(items);
  }

  // Void pending order (server: UPDATE status = 'VO', bukan delete keras —
  // histori order & detail tetap ada untuk audit).
  Future<void> _deletePending(int salesOrderID) async {
    final session = await SessionService.getSession();
    final dio = ApiService.getDio(token: _token);
    await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'deletePending',
        'sales_order_id': salesOrderID,
        'user_id': session['user_id'],
      }),
    );
  }

  // ============================================================
  // PRINT PENDING ORDER
  // Jika FnB: tampilkan bottom sheet pilih Customer/Kitchen/Keduanya
  // Jika non-FnB: langsung print customer copy (sama seperti penjualan normal)
  // ============================================================
  Future<void> _printPendingOrder(Map<String, dynamic> order) async {
    if (_isFnb) {
      // FnB → tampilkan pilihan print seperti penjualan normal
      await _showPendingPrintSheet(order);
    } else {
      // Non-FnB → langsung print customer copy
      await _doPrintPendingCustomer(order);
    }
  }

  // ── Bottom sheet pilih Customer / Kitchen / Keduanya untuk pending ──
  Future<void> _showPendingPrintSheet(Map<String, dynamic> order) async {
    final invoiceLabel = (order['label'] as String? ?? '').isNotEmpty
        ? order['label'] as String
        : order['kode'] as String;

    await showModalBottomSheet(
      context: context,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (ctx) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 12),
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 4,
                ),
                child: Text(
                  'Print Pending — $invoiceLabel',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const Divider(),
              ListTile(
                leading: const Icon(
                  Icons.receipt_long,
                  color: Color(0xFF1D273B),
                ),
                title: const Text('Customer Copy'),
                subtitle: const Text('Struk estimasi untuk pelanggan'),
                onTap: () {
                  Navigator.pop(ctx);
                  _doPrintPendingCustomer(order);
                },
              ),
              ListTile(
                leading: const Icon(Icons.kitchen, color: Colors.orange),
                title: const Text('Kitchen Copy'),
                subtitle: const Text('Struk order untuk dapur'),
                onTap: () {
                  Navigator.pop(ctx);
                  _doPrintPendingKitchen(order);
                },
              ),
              ListTile(
                leading: const Icon(Icons.print_rounded, color: Colors.green),
                title: const Text('Customer + Kitchen'),
                subtitle: const Text('Print dua-duanya'),
                onTap: () {
                  Navigator.pop(ctx);
                  _doPrintPendingBoth(order);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );
  }

  // ── Helper: ambil data store + items pending ──────────────────
  Future<Map<String, dynamic>?> _fetchPendingPrintData(
    Map<String, dynamic> order,
  ) async {
    // Pastikan printer terhubung
    final connected = await PrinterHelper.isConnected();
    if (!connected) {
      final prefs = await SharedPreferences.getInstance();
      final savedMac = prefs.getString('printer_mac');
      if (savedMac == null) {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text(
                'Belum ada printer terhubung. Buka pengaturan printer.',
              ),
              backgroundColor: Colors.orange,
            ),
          );
        }
        return null;
      }
      await PrinterHelper.connect(savedMac);
    }

    final salesOrderID = int.parse(order['id'].toString());
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final itemsRes = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'getPendingOrderItems',
        'sales_order_id': salesOrderID,
      }),
    );

    if (itemsRes.data['success'] != true) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal ambil data item'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return null;
    }

    final storeRes = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'getStoreData',
        'store_id': state.storeID,
      }),
    );

    // Gunakan salestipe_nama & keterangan dari header order (bukan dari state aktif)
    final salesTipeNama = (itemsRes.data['salestipe_nama'] as String? ?? '')
            .isNotEmpty
        ? itemsRes.data['salestipe_nama'] as String
        : (_channels.isNotEmpty
            ? (_channels
                    .firstWhere(
                      (c) =>
                          int.parse(c['dim_salestipe_id'].toString()) ==
                          (itemsRes.data['salestipe_id'] as num? ?? 0).toInt(),
                      orElse: () => {'nama': ''},
                    )['nama']
                    ?.toString() ??
                '')
            : '');
    final keteranganOrder = itemsRes.data['keterangan_order'] as String? ?? '';
    // Tanggal dari tr_sales_order.tanggal (date saat order dibuat)
    final tanggalRaw = itemsRes.data['tanggal']?.toString() ?? '';
    final tanggal = tanggalRaw.isNotEmpty
        ? tanggalRaw.substring(
            0,
            tanggalRaw.length >= 10 ? 10 : tanggalRaw.length,
          )
        : DateTime.now().toString().substring(0, 10); // fallback
    // Jam transaksi dari created_date order pending (format: "2024-01-15 14:30:00" → "14:30")
    final createdDateRaw = itemsRes.data['created_date']?.toString() ?? '';
    final jamTransaksiPending = createdDateRaw.length >= 16
        ? createdDateRaw.substring(11, 16)
        : (createdDateRaw.length >= 13 ? createdDateRaw.substring(11) : '');

    final kasirNama =
        (await SessionService.getSession())['nama'] as String? ?? '';
    final invoiceLabel = (order['label'] as String? ?? '').isNotEmpty
        ? order['label'] as String
        : order['kode'] as String;

    return {
      'items': List<Map<String, dynamic>>.from(itemsRes.data['data']),
      'estimasiTotal': (itemsRes.data['total'] as num? ?? 0).toDouble(),
      'storeName': storeRes.data['nama'] ?? '',
      'storeAddress': storeRes.data['alamat'] ?? '',
      'storeNpwp': storeRes.data['npwp'] ?? '',
      'invoiceNote': storeRes.data['invoice_note'] ?? '',
      'logoFileName': storeRes.data['logo_file_name'] ?? '',
      'logoUrl': storeRes.data['logo_url'] ?? '',
      'salesTipeNama': salesTipeNama,
      'kasirNama': kasirNama,
      'tanggal': tanggal,
      'invoiceLabel': invoiceLabel,
      'memberNama': order['member'] as String? ?? '',
      'keterangan': keteranganOrder,
      'jamTransaksi': jamTransaksiPending,
    };
  }

  // ── Print customer copy pending ───────────────────────────────
  Future<void> _doPrintPendingCustomer(Map<String, dynamic> order) async {
    try {
      final d = await _fetchPendingPrintData(order);
      if (d == null) return;

      await PrinterHelper.printPendingOrder(
        storeName: d['storeName'],
        storeAddress: d['storeAddress'],
        invoiceNumber: d['invoiceLabel'],
        tanggal: d['tanggal'],
        kasir: d['kasirNama'],
        memberNama: d['memberNama'],
        items: d['items'],
        estimasiTotal: d['estimasiTotal'],
        npwp: (d['storeNpwp'] as String).isNotEmpty ? d['storeNpwp'] : null,
        invoiceNote:
            (d['invoiceNote'] as String).isNotEmpty ? d['invoiceNote'] : null,
        salesTipe: (d['salesTipeNama'] as String).isNotEmpty
            ? d['salesTipeNama']
            : null,
        keterangan:
            (d['keterangan'] as String).isNotEmpty ? d['keterangan'] : null,
        logoFileName:
            (d['logoFileName'] as String).isNotEmpty ? d['logoFileName'] : null,
        logoUrl: (d['logoUrl'] as String).isNotEmpty ? d['logoUrl'] : null,
        jamTransaksi:
            (d['jamTransaksi'] as String).isNotEmpty ? d['jamTransaksi'] : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Print Customer pending berhasil!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal print: $e')));
      }
    }
  }

  // ── Print kitchen copy pending ────────────────────────────────
  Future<void> _doPrintPendingKitchen(Map<String, dynamic> order) async {
    try {
      final d = await _fetchPendingPrintData(order);
      if (d == null) return;

      await PrinterHelper.printKitchen(
        storeName: d['storeName'],
        invoiceNumber: d['invoiceLabel'],
        tanggal: d['tanggal'],
        kasir: d['kasirNama'],
        memberNama: d['memberNama'],
        items: d['items'],
        total: d['estimasiTotal'],
        salesTipe: (d['salesTipeNama'] as String).isNotEmpty
            ? d['salesTipeNama']
            : null,
        keterangan:
            (d['keterangan'] as String).isNotEmpty ? d['keterangan'] : null,
        jamTransaksi:
            (d['jamTransaksi'] as String).isNotEmpty ? d['jamTransaksi'] : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Print Kitchen pending berhasil!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal print kitchen: $e')));
      }
    }
  }

  // ── Print customer + kitchen pending sekaligus ────────────────
  Future<void> _doPrintPendingBoth(Map<String, dynamic> order) async {
    try {
      final d = await _fetchPendingPrintData(order);
      if (d == null) return;

      // Customer copy
      await PrinterHelper.printPendingOrder(
        storeName: d['storeName'],
        storeAddress: d['storeAddress'],
        invoiceNumber: d['invoiceLabel'],
        tanggal: d['tanggal'],
        kasir: d['kasirNama'],
        memberNama: d['memberNama'],
        items: d['items'],
        estimasiTotal: d['estimasiTotal'],
        npwp: (d['storeNpwp'] as String).isNotEmpty ? d['storeNpwp'] : null,
        invoiceNote:
            (d['invoiceNote'] as String).isNotEmpty ? d['invoiceNote'] : null,
        salesTipe: (d['salesTipeNama'] as String).isNotEmpty
            ? d['salesTipeNama']
            : null,
        keterangan:
            (d['keterangan'] as String).isNotEmpty ? d['keterangan'] : null,
        logoFileName:
            (d['logoFileName'] as String).isNotEmpty ? d['logoFileName'] : null,
        logoUrl: (d['logoUrl'] as String).isNotEmpty ? d['logoUrl'] : null,
        jamTransaksi:
            (d['jamTransaksi'] as String).isNotEmpty ? d['jamTransaksi'] : null,
      );

      await Future.delayed(const Duration(milliseconds: 500));

      // Kitchen copy
      await PrinterHelper.printKitchen(
        storeName: d['storeName'],
        invoiceNumber: d['invoiceLabel'],
        tanggal: d['tanggal'],
        kasir: d['kasirNama'],
        memberNama: d['memberNama'],
        items: d['items'],
        total: d['estimasiTotal'],
        salesTipe: (d['salesTipeNama'] as String).isNotEmpty
            ? d['salesTipeNama']
            : null,
        keterangan:
            (d['keterangan'] as String).isNotEmpty ? d['keterangan'] : null,
        jamTransaksi:
            (d['jamTransaksi'] as String).isNotEmpty ? d['jamTransaksi'] : null,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Print Customer + Kitchen pending berhasil!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal print: $e')));
      }
    }
  }
}
