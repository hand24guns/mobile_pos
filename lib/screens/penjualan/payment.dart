// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Proses bayar, kirim WA/Email, reset transaksi, print invoice/kitchen.
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanPaymentX on _PenjualanScreenState {
  Future<void> _prosesBayar() async {
    final state = ref.read(penjualanProvider);

    if (state.items.isEmpty) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Belum ada produk')));
      return;
    }
    if (state.caraBayarID == 0) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(const SnackBar(content: Text('Pilih cara bayar dulu')));
      return;
    }
    if (state.nominalBayar < state.total) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Nominal bayar kurang dari total')),
      );
      return;
    }

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Konfirmasi Pembayaran'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Total'),
                Text(
                  'Rp ${CurrencyFormat.format(state.total)}',
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
              ],
            ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Bayar'),
                Text('Rp ${CurrencyFormat.format(state.nominalBayar)}'),
              ],
            ),
            const Divider(),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text(
                  'Kembalian',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                Text(
                  'Rp ${CurrencyFormat.format(state.nominalBayar - state.total)}',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 18,
                    color: Color(0xFF1D273B),
                  ),
                ),
              ],
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          StatefulBuilder(
            builder: (ctx, setDialogState) {
              bool isSubmitting = false;
              return ElevatedButton(
                onPressed: isSubmitting
                    ? null
                    : () {
                        setDialogState(() => isSubmitting = true);
                        Navigator.pop(context, true);
                      },
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D273B)),
                child: isSubmitting
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white),
                      )
                    : const Text('Proses',
                        style: TextStyle(color: Colors.white)),
              );
            },
          ),
        ],
      ),
    );

    if (confirm != true) return;

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => const Center(child: CircularProgressIndicator()),
    );

    try {
      final session = await SessionService.getSession();

      final res = await OrderService.checkoutOrder(
        number: state.number,
        caraBayarId: state.caraBayarID,
        storeId: state.storeID,
        organisasiId: state.organisasiID,
        userId: session['user_id'],
        salesTipeId: state.salesTipeID,
        memberId: state.memberID ?? 0,
        voucher: _activeVoucher,
        returSource: ref.read(penjualanProvider).returSource,
        nominalBayar: state.nominalBayar,
        deviceToken: _deviceToken,
        keterangan: _keteranganController.text.trim(),
        pendingOrderId: _activePendingOrderID ?? 0,
      );

      if (mounted) Navigator.pop(context); // tutup loading

      if (res['success'] == true) {
        final kembalian = res['kembalian'];

        _kirimWADanEmail(
          invoiceNumber: state.number,
          storeID: state.storeID,
          organisasiID: state.organisasiID,
          memberID: state.memberID,
        );

        if (mounted) {
          await showDialog(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('Transaksi Berhasil!'),
              content: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.check_circle, color: Colors.green, size: 64),
                  const SizedBox(height: 16),
                  Text(
                    'Kembalian: Rp ${CurrencyFormat.format(kembalian)}',
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              actions: [
                // ── Tombol Print — adaptif FnB vs non-FnB ───────
                if (_isFnb)
                  // FnB: satu tombol → buka bottom sheet pilih
                  // Customer / Kitchen / Keduanya
                  TextButton.icon(
                    onPressed: () async {
                      final caraBayar = _caraBayarList.firstWhere(
                            (c) =>
                                int.parse(
                                  c['dim_carabayar_id'].toString(),
                                ) ==
                                state.caraBayarID,
                            orElse: () => {'nama': ''},
                          )['nama'] as String? ??
                          '';
                      Navigator.pop(context); // tutup dialog sukses dulu
                      await _showPrintSheet(
                        invoiceNumber: state.number,
                        kembalian: (kembalian as num).toDouble(),
                        caraBayar: caraBayar,
                        currentState: state,
                      );
                      // Pending order (jika ada) sudah di-void atomic di
                      // server saat prosesBayar sukses — di sini cukup
                      // bersihkan state lokal.
                      _setState(() => _activePendingOrderID = null);
                      _resetTransaksi();
                    },
                    icon: const Icon(Icons.print, size: 18),
                    label: const Text('Print'),
                  )
                else
                  // Non-FnB (retail): langsung print customer copy
                  TextButton.icon(
                    onPressed: () async {
                      final caraBayar = _caraBayarList.firstWhere(
                            (c) =>
                                int.parse(
                                  c['dim_carabayar_id'].toString(),
                                ) ==
                                state.caraBayarID,
                            orElse: () => {'nama': ''},
                          )['nama'] as String? ??
                          '';
                      await _handlePrint(
                        invoiceNumber: state.number,
                        kembalian: (kembalian as num).toDouble(),
                        caraBayar: caraBayar,
                        currentState: state,
                        isKitchenMode: false,
                      );
                      if (mounted) {
                        Navigator.pop(context);
                        // Pending order (jika ada) sudah di-void atomic di
                        // server saat prosesBayar sukses.
                        _setState(() => _activePendingOrderID = null);
                        _resetTransaksi();
                      }
                    },
                    icon: const Icon(Icons.receipt_long, size: 18),
                    label: const Text('Print'),
                  ),
                ElevatedButton(
                  onPressed: () async {
                    Navigator.pop(context);
                    // Pending order (jika ada) sudah di-void atomic di
                    // server saat prosesBayar sukses.
                    _setState(() => _activePendingOrderID = null);
                    _resetTransaksi();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D273B),
                  ),
                  child: const Text(
                    'Selesai',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(content: Text(res['message'] ?? 'Transaksi gagal')),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        Navigator.pop(context); // pastikan loading tertutup meski error
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Gagal memproses transaksi: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _kirimWADanEmail({
    required String invoiceNumber,
    required int storeID,
    required int organisasiID,
    required int? memberID,
  }) async {
    if (memberID == null || memberID == 0) return;

    OrderService.sendReceiptWhatsApp(
      invoiceNumber: invoiceNumber,
      storeId: storeID,
      organisasiId: organisasiID,
      memberId: memberID,
    );

    OrderService.sendReceiptEmail(
      invoiceNumber: invoiceNumber,
      storeId: storeID,
      organisasiId: organisasiID,
      memberId: memberID,
    );
  }

  Future<void> _resetTransaksi() async {
    final currentState = ref.read(penjualanProvider);
    final storeID = currentState.storeID;
    final storeName = currentState.storeName;
    final organisasiID = currentState.organisasiID;

    final newNumber = await PosDataService.getNextOrderNumber(
      storeId: storeID,
      deviceToken: _deviceToken,
    );

    ref.read(penjualanProvider.notifier).reset();

    final defaultChannel = _channels.firstWhere(
      (c) => c['is_default'].toString() == '1',
      orElse: () =>
          _channels.isNotEmpty ? _channels.first : {'dim_salestipe_id': 0},
    );
    final targetSalesTipeID =
        int.tryParse(defaultChannel['dim_salestipe_id'].toString()) ?? 0;

    ref.read(penjualanProvider.notifier).setInitialData(
          number: newNumber,
          storeID: storeID,
          storeName: storeName,
          organisasiID: organisasiID,
          salesTipeID: targetSalesTipeID,
        );

    _setState(() {
      _activeVoucher = '';
      _activePendingOrderID = null;
      _activePendingLabel = '';
    });
    _clearKemasanState();
    ref.read(penjualanProvider.notifier).setReturSource('');
    _memberController.clear();
    _nominalController.clear();
    _skuController.clear();
    _keteranganController.clear();
    // Reset item notes
    for (final c in _itemNotesControllers.values) {
      c.dispose();
    }
    _itemNotesControllers.clear();
    _expandedNotes.clear();
    if (_imageCategories.isEmpty) {
      _loadImageProducts();
    }
  }

  // ============================================================
  // PRINT
  // ============================================================
  //
  // _handlePrint — entry point tunggal untuk semua print.
  //
  // [isKitchenMode] = true  → print 2x (customer + kitchen), untuk FnB.
  //                  false → print 1x (customer only), untuk retail.
  //
  // Dipanggil dari:
  //   • Dialog sukses bayar — tombol "Print" (retail) atau "Print (2x)" (FnB)
  //   • Tombol "Print Kitchen" di dialog sukses bayar
  //   • Invoice list screen (reprint)
  Future<void> _handlePrint({
    required String invoiceNumber,
    required double kembalian,
    required String caraBayar,
    required PenjualanState currentState,
    bool isKitchenMode = false,
  }) async {
    // ── Tangkap keterangan SEBELUM await apa pun ─────────────────
    // _resetTransaksi() (yang membersihkan _keteranganController)
    // bisa jalan bersamaan (race) dengan fungsi print ini karena
    // pemanggilnya tidak selalu meng-await print sampai selesai.
    // Kalau dibaca setelah network call (getStoreData dsb), ada
    // kemungkinan controller sudah ke-clear duluan → keterangan
    // kosong di struk yang baru saja dicetak.
    final keteranganTrx = _keteranganController.text.trim();

    try {
      // ── Pastikan printer terhubung ───────────────────────────
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
          return;
        }
        await PrinterHelper.connect(savedMac);
      }

      final state = ref.read(penjualanProvider);
      final storeData = await StoreService.getStoreData(state.storeID);

      final storeName = storeData['nama'] ?? '';
      final storeAddress = storeData['alamat'] ?? '';
      final storeNpwp = storeData['npwp'] ?? '';
      final invoiceNote = storeData['invoice_note'] ?? '';
      final storeTax = (storeData['tax'] as num? ?? 0).toDouble();
      final logoFileName = storeData['logo_file_name'] ?? '';
      final logoUrl = storeData['logo_url'] ?? '';
      // isFnb: dibaca dari state yang sudah di-set saat load awal
      // (jasa_perusahaan == 3 di dim_organisasi → FnB/resto)
      final isFnb = _isFnb;

      // (keteranganTrx sudah ditangkap di awal fungsi — lihat atas)

      // ── Siapkan items — include keterangan per item ──────────
      final items = currentState.items
          .map(
            (item) => {
              'nama': item.nama,
              'qty': item.qty,
              'hpj': item.hpj,
              'subtotal': item.subtotal,
              'diskon_persen': item.diskonPersen,
              'diskon_nominal': item.diskonNominal,
              'packages_notes': item.packagesNotes ?? '',
              'keterangan': item.keterangan ?? '',
            },
          )
          .toList();

      // ── Ambil nama channel ───────────────────────────────────
      final salesTipeNama = _channels
              .firstWhere(
                (c) =>
                    int.parse(c['dim_salestipe_id'].toString()) ==
                    currentState.salesTipeID,
                orElse: () => {'nama': ''},
              )['nama']
              ?.toString() ??
          '';

      final kasirNama =
          (await SessionService.getSession())['nama'] as String? ?? '';
      final tanggal = DateTime.now().toString().substring(0, 16);
      // Jam transaksi — dari waktu sekarang (saat baru bayar)
      final nowForJam = DateTime.now();
      final jamTransaksi =
          '${nowForJam.hour.toString().padLeft(2, '0')}:${nowForJam.minute.toString().padLeft(2, '0')}';

      // ── Print berdasarkan mode ───────────────────────────────
      if (isFnb || isKitchenMode) {
        // FnB: print customer struk + kitchen order sekaligus
        final result = await PrinterHelper.printBoth(
          storeName: storeName,
          storeAddress: storeAddress,
          invoiceNumber: invoiceNumber,
          tanggal: tanggal,
          kasir: kasirNama,
          memberNama: currentState.memberNama,
          items: items,
          gross: currentState.gross,
          diskon: currentState.diskon,
          total: currentState.total,
          dpp: currentState.dpp,
          pajak: currentState.pajak,
          caraBayar: caraBayar,
          nominalBayar: currentState.nominalBayar,
          kembalian: kembalian,
          storeTax: storeTax,
          voucherKode: _activeVoucher.isNotEmpty ? _activeVoucher : null,
          npwp: storeNpwp,
          invoiceNote: invoiceNote,
          salesTipe: salesTipeNama.isNotEmpty ? salesTipeNama : null,
          keterangan: keteranganTrx.isNotEmpty ? keteranganTrx : null,
          logoFileName: logoFileName.isNotEmpty ? logoFileName : null,
          logoUrl: logoUrl.isNotEmpty ? logoUrl : null,
          jamTransaksi: jamTransaksi,
        );

        if (mounted) {
          if (result.customer && result.kitchen) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Print berhasil! (Customer + Kitchen)'),
                backgroundColor: Colors.green,
              ),
            );
          } else if (result.customer && !result.kitchen) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Struk customer OK, kitchen print gagal. Coba ulangi.',
                ),
                backgroundColor: Colors.orange,
              ),
            );
          } else {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text('Print gagal'),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      } else {
        // Retail: print customer struk saja
        await PrinterHelper.printInvoice(
          storeName: storeName,
          storeAddress: storeAddress,
          npwp: storeNpwp,
          invoiceNote: invoiceNote,
          invoiceNumber: invoiceNumber,
          tanggal: tanggal,
          kasir: kasirNama,
          memberNama: currentState.memberNama,
          items: items,
          gross: currentState.gross,
          diskon: currentState.diskon,
          total: currentState.total,
          dpp: currentState.dpp,
          pajak: currentState.pajak,
          caraBayar: caraBayar,
          nominalBayar: currentState.nominalBayar,
          kembalian: kembalian,
          voucherKode: _activeVoucher.isNotEmpty ? _activeVoucher : null,
          storeTax: storeTax,
          salesTipe: salesTipeNama.isNotEmpty ? salesTipeNama : null,
          keterangan: keteranganTrx.isNotEmpty ? keteranganTrx : null,
          logoFileName: logoFileName.isNotEmpty ? logoFileName : null,
          logoUrl: logoUrl.isNotEmpty ? logoUrl : null,
          jamTransaksi: jamTransaksi,
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Print berhasil!'),
              backgroundColor: Colors.green,
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Gagal print: $e')));
      }
    }
  }

  // ── Legacy alias — dipakai oleh invoice_list_screen reprint ──
  Future<void> _printInvoice({
    required String invoiceNumber,
    required double kembalian,
    required String caraBayar,
    required PenjualanState currentState,
  }) =>
      _handlePrint(
        invoiceNumber: invoiceNumber,
        kembalian: kembalian,
        caraBayar: caraBayar,
        currentState: currentState,
      );

  // ============================================================
  // PRINT SHEET (FnB) — bottom sheet pilih Customer/Kitchen/Keduanya
  // Dipanggil dari dialog sukses bayar ketika _isFnb == true.
  // Konsisten dengan _showReprintSheet di invoice_list_screen.
  // ============================================================
  Future<void> _showPrintSheet({
    required String invoiceNumber,
    required double kembalian,
    required String caraBayar,
    required PenjualanState currentState,
  }) async {
    // Bottom sheet hanya MENGEMBALIKAN pilihan kasir (customer/kitchen/both),
    // tidak langsung memanggil fungsi print di dalam onTap. Print yang
    // sebenarnya dijalankan (dan di-await) SETELAH showModalBottomSheet
    // selesai, di bawah. Ini penting supaya `await _showPrintSheet(...)`
    // di pemanggil baru benar-benar resolve setelah print selesai —
    // sebelumnya print jalan fire-and-forget dan bisa race dengan
    // _resetTransaksi() yang dipanggil tepat setelahnya (controller
    // keterangan bisa ke-clear sebelum sempat dibaca oleh print).
    final selected = await showModalBottomSheet<String>(
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
              // Handle bar
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
                  'Pilih Print — $invoiceNumber',
                  style: const TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ),
              const Divider(),
              // Customer copy
              ListTile(
                leading: const Icon(
                  Icons.receipt_long,
                  color: Color(0xFF1D273B),
                ),
                title: const Text('Customer Copy'),
                subtitle: const Text('Struk untuk pelanggan'),
                onTap: () => Navigator.pop(ctx, 'customer'),
              ),
              // Kitchen copy
              ListTile(
                leading: const Icon(Icons.kitchen, color: Colors.orange),
                title: const Text('Kitchen Copy'),
                subtitle: const Text('Struk untuk dapur'),
                onTap: () => Navigator.pop(ctx, 'kitchen'),
              ),
              // Keduanya
              ListTile(
                leading: const Icon(Icons.print_rounded, color: Colors.green),
                title: const Text('Customer + Kitchen'),
                subtitle: const Text('Print dua-duanya'),
                onTap: () => Navigator.pop(ctx, 'both'),
              ),
              const SizedBox(height: 8),
            ],
          ),
        ),
      ),
    );

    // Sheet sudah tertutup di sini. Jalankan print sesuai pilihan dan
    // AWAIT sampai selesai sebelum _showPrintSheet() ini return.
    switch (selected) {
      case 'customer':
        await _handlePrint(
          invoiceNumber: invoiceNumber,
          kembalian: kembalian,
          caraBayar: caraBayar,
          currentState: currentState,
          isKitchenMode: false,
        );
        break;
      case 'kitchen':
        // isKitchenMode=true tapi kita hanya mau kitchen saja.
        // _handlePrint dengan isKitchenMode=true + isFnb=true
        // akan masuk ke PrinterHelper.printBoth.
        // Untuk print kitchen-only kita panggil helper langsung.
        await _printKitchenOnly(
          invoiceNumber: invoiceNumber,
          currentState: currentState,
        );
        break;
      case 'both':
        await _handlePrint(
          invoiceNumber: invoiceNumber,
          kembalian: kembalian,
          caraBayar: caraBayar,
          currentState: currentState,
          isKitchenMode: true,
        );
        break;
      default:
        // Kasir menutup sheet tanpa memilih — tidak print apa-apa.
        break;
    }
  }

  // ── Print kitchen-only setelah bayar (tanpa struk customer) ──
  Future<void> _printKitchenOnly({
    required String invoiceNumber,
    required PenjualanState currentState,
  }) async {
    // ── Tangkap keterangan SEBELUM await apa pun (lihat _handlePrint) ──
    final keteranganTrx = _keteranganController.text.trim();

    try {
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
          return;
        }
        await PrinterHelper.connect(savedMac);
      }

      final storeRes = await StoreService.getStoreData(currentState.storeID);
      final storeName = storeRes['nama'] ?? '';

      // (keteranganTrx sudah ditangkap di awal fungsi — lihat atas)

      final items = currentState.items
          .map(
            (item) => {
              'nama': item.nama,
              'qty': item.qty,
              'hpj': item.hpj,
              'subtotal': item.subtotal,
              'diskon_persen': item.diskonPersen,
              'diskon_nominal': item.diskonNominal,
              'packages_notes': item.packagesNotes ?? '',
              'keterangan': item.keterangan ?? '',
            },
          )
          .toList();

      final kasirNama =
          (await SessionService.getSession())['nama'] as String? ?? '';
      final tanggal = DateTime.now().toString().substring(0, 16);
      final nowForJam = DateTime.now();
      final jamTransaksi =
          '${nowForJam.hour.toString().padLeft(2, '0')}:${nowForJam.minute.toString().padLeft(2, '0')}';

      await PrinterHelper.printKitchen(
        storeName: storeName,
        invoiceNumber: invoiceNumber,
        tanggal: tanggal,
        kasir: kasirNama,
        items: items,
        memberNama: currentState.memberNama,
        total: currentState.total,
        keterangan: keteranganTrx.isNotEmpty ? keteranganTrx : null,
        jamTransaksi: jamTransaksi,
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Print Kitchen berhasil!'),
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

  // ============================================================
  // PENDING PAYMENT
  // ============================================================
}
