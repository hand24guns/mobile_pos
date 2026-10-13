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
    final res = await PendingOrderService.savePending(
      number: state.number,
      storeId: state.storeID,
      organisasiId: state.organisasiID,
      memberId: state.memberID ?? 0,
      userId: session['user_id'],
      label: label ?? '',
      deviceToken: _deviceToken,
      salesTipeId: state.salesTipeID,
      keterangan: _keteranganController.text.trim(),
      pendingOrderId: pendingOrderID,
    );

    if (res['success'] == true) {
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
            content: Text(res['message'] ?? 'Gagal simpan pending'),
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
    final orders = await PendingOrderService.getPendingOrders(
      storeId: state.storeID,
    );

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
                                if (mounted)
                                  Navigator.pop(
                                      context); // Tutup bottom sheet aktif
                                await _deletePending(
                                    int.parse(order['id'].toString()));
                                if (mounted) {
                                  _showRetrieveDialog(); // Panggil dialog segar dari konteks utama
                                }
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

    Map<String, dynamic> res;
    try {
      res = await PendingOrderService.retrievePending(
        salesOrderId: salesOrderID,
        number: state.number,
        deviceToken: _deviceToken,
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Gagal retrieve order: $e')),
        );
      }
      return;
    }

    if (res['success'] == true) {
      final restoredNumber = res['number'] as String? ?? state.number;

      // Resolve salestipe dulu sebelum setInitialData
      final salestipeID = res['salestipe_id'];
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
      final memberID = res['member_id'];
      if (memberID != null && int.parse(memberID.toString()) > 0) {
        _memberController.text = res['member'] ?? '';
        ref
            .read(penjualanProvider.notifier)
            .setMember(int.parse(memberID.toString()), member);
      } else {
        _memberController.clear();
        ref.read(penjualanProvider.notifier).setMember(null, '');
      }

      // Restore keterangan
      final keterangan = res['keterangan'] as String? ?? '';
      _keteranganController.text = keterangan;

      // Reload grid image jika salestipe berubah
      _loadImageProducts();

      // Simpan ID pending order yang sedang aktif agar bisa di-update (bukan insert baru)
      _setState(() {
        _activePendingOrderID = salesOrderID;
        _activePendingLabel = res['order_nama'] as String? ?? '';
      });
      // Override box dari keranjang sebelumnya tidak boleh terbawa
      _clearKemasanState();

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
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res['message']?.toString() ?? 'Gagal retrieve order',
            ),
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
  // REST API: GET /v1/cart/items-as-is
  // Fallback: POST /penjualan.php (action: getCartItemsAsIs)
  // ============================================================
  Future<void> _loadItemsFromTemp(String number) async {
    final rawItems = await CartService.getCartItemsAsIs(
      number: number,
      deviceToken: _deviceToken,
    );

    if (rawItems.isEmpty) return;

    final items = rawItems.map((j) => CartItem.fromJson(j)).toList();

    // updateItems() menghitung ulang gross/diskon/total dari item.subtotal
    // yang sudah tersimpan di temp — hpj tidak diubah sama sekali.
    ref.read(penjualanProvider.notifier).updateItems(items);
  }

  // Void pending order (server: UPDATE status = 'VO', bukan delete keras —
  // histori order & detail tetap ada untuk audit).
  Future<void> _deletePending(int salesOrderID) async {
    final session = await SessionService.getSession();
    await PendingOrderService.deletePending(
      salesOrderId: salesOrderID,
      userId: session['user_id'],
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

    final itemsRes = await PendingOrderService.getPendingOrderItems(
      salesOrderId: salesOrderID,
    );

    if (itemsRes['success'] != true) {
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

    final storeRes = await StoreService.getStoreData(state.storeID);

    // Gunakan salestipe_nama & keterangan dari header order (bukan dari state aktif)
    final salesTipeNama = (itemsRes['salestipe_nama'] as String? ?? '')
            .isNotEmpty
        ? itemsRes['salestipe_nama'] as String
        : (_channels.isNotEmpty
            ? (_channels
                    .firstWhere(
                      (c) =>
                          int.parse(c['dim_salestipe_id'].toString()) ==
                          (itemsRes['salestipe_id'] as num? ?? 0).toInt(),
                      orElse: () => {'nama': ''},
                    )['nama']
                    ?.toString() ??
                '')
            : '');
    final keteranganOrder = itemsRes['keterangan_order'] as String? ?? '';
    // Tanggal dari tr_sales_order.tanggal (date saat order dibuat)
    final tanggalRaw = itemsRes['tanggal']?.toString() ?? '';
    final tanggal = tanggalRaw.isNotEmpty
        ? tanggalRaw.substring(
            0,
            tanggalRaw.length >= 10 ? 10 : tanggalRaw.length,
          )
        : DateTime.now().toString().substring(0, 10); // fallback
    // Jam transaksi dari created_date order pending (format: "2024-01-15 14:30:00" → "14:30")
    final createdDateRaw = itemsRes['created_date']?.toString() ?? '';
    final jamTransaksiPending = createdDateRaw.length >= 16
        ? createdDateRaw.substring(11, 16)
        : (createdDateRaw.length >= 13 ? createdDateRaw.substring(11) : '');

    final kasirNama =
        (await SessionService.getSession())['nama'] as String? ?? '';
    final invoiceLabel = (order['label'] as String? ?? '').isNotEmpty
        ? order['label'] as String
        : order['kode'] as String;

    // Backend getPendingOrderItems hanya balikin 'total' (sum netto per item),
    // bukan gross/diskon per order — jadi dihitung di sini dari tiap item:
    // gross = qty x hpj (sebelum diskon), diskon = gross - subtotal (netto).
    final pendingItems = List<Map<String, dynamic>>.from(itemsRes['data'] ?? []);
    double computedGross = 0;
    double computedDiskon = 0;
    for (final item in pendingItems) {
      final qty = (item['qty'] as num?)?.toDouble() ?? 0;
      final hpj = (item['hpj'] as num?)?.toDouble() ?? 0;
      final subtotal = (item['subtotal'] as num?)?.toDouble() ?? 0;
      final lineGross = qty * hpj;
      computedGross += lineGross;
      computedDiskon += (lineGross - subtotal);
    }

    return {
      'items': pendingItems,
      'total': (itemsRes['total'] as num? ?? 0).toDouble(),
      'gross': computedGross,
      'diskon': computedDiskon,
      'storeName': storeRes['nama'] ?? '',
      'storeAddress': storeRes['alamat'] ?? '',
      'storeNpwp': storeRes['npwp'] ?? '',
      'invoiceNote': storeRes['invoice_note'] ?? '',
      'logoFileName': storeRes['logo_file_name'] ?? '',
      'logoUrl': storeRes['logo_url'] ?? '',
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
        gross: d['gross'],
        diskon: d['diskon'],
        total: d['total'],
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
        total: d['total'],
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
        gross: d['gross'],
        diskon: d['diskon'],
        total: d['total'],
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
        total: d['total'],
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
