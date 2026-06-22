// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Shift polling, dialog buka/tutup shift, navigasi home, rekap row helper.
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanShiftX on _PenjualanScreenState {
  void _startShiftPolling() {
    _shiftPollingTimer?.cancel();
    _shiftPollingTimer = Timer.periodic(const Duration(seconds: 60), (_) {
      _checkShiftStillActive();
    });
  }

  Future<void> _checkShiftStillActive() async {
    if (_shiftID == 0 || _activeStoreID == 0 || _activeOrgID == 0) return;
    try {
      final result = await ShiftService.cekShift(
        token: _token,
        storeID: _activeStoreID,
        organisasiID: _activeOrgID,
        userID: _userID,
      );
      final stillActive =
          result.status == ShiftStatus.milikSaya && result.shiftID == _shiftID;
      if (!stillActive && mounted) _onShiftForceClosed();
    } catch (_) {
      // Offline/timeout → diam saja
    }
  }

  void _onShiftForceClosed() {
    _shiftPollingTimer?.cancel();
    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Shift Ditutup'),
        content: const Text(
          'Shift kamu telah ditutup dari perangkat lain.\n'
          'Silakan buka shift baru untuk melanjutkan.',
        ),
        actions: [
          ElevatedButton(
            onPressed: () {
              Navigator.pop(context);
              _goToHome();
            },
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D273B),
            ),
            child: const Text('OK', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }

  void _goToHome() {
    if (!mounted) return;
    Navigator.pushAndRemoveUntil(
      context,
      MaterialPageRoute(builder: (_) => const HomeScreen()),
      (route) => false,
    );
  }

  // ============================================================
  // PHASE 1 — Load session + store (tanpa shift check)
  // ============================================================
  Future<int> _showBukaShiftDialog({
    required int storeID,
    required int organisasiID,
  }) async {
    final modalController = TextEditingController(text: '0');

    final confirm = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (_) => AlertDialog(
        title: const Text('Buka Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Input modal kasir awal:',
              style: TextStyle(color: Colors.grey),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: modalController,
              keyboardType: TextInputType.number,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Modal Kasir',
                border: OutlineInputBorder(),
                prefixText: 'Rp ',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF1D273B),
            ),
            child: const Text(
              'Buka Shift',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return 0;

    final modal =
        double.tryParse(modalController.text.replaceAll(',', '').trim()) ?? 0;

    final shiftID = await ShiftService.bukaShift(
      token: _token,
      storeID: storeID,
      organisasiID: organisasiID,
      userID: _userID,
      modalKasir: modal,
    );

    if (shiftID == 0 && mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal buka shift'),
          backgroundColor: Colors.red,
        ),
      );
    }
    return shiftID;
  }

  // ============================================================
  // BUKA SHIFT — Bottom Sheet blocker (dari flow V2.1)
  // Non-dismissible: user HARUS buka shift untuk lanjut ke POS.
  // Dipanggil dari _checkAndEnsureShift ketika shift belum ada.
  // ============================================================
  Future<int> _showBukaShiftSheet({
    required int storeID,
    required int organisasiID,
    required String storeName,
  }) async {
    final modalController = TextEditingController(text: '0');
    final completer = Completer<int>();

    if (!mounted) return 0;

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(ctx).viewInsets.bottom),
        child: Container(
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // Handle bar
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: Colors.grey.shade300,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              // Icon + judul
              Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1D273B).withValues(alpha: 0.08),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: const Icon(
                      Icons.lock_clock,
                      color: Color(0xFF1D273B),
                      size: 22,
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Shift Belum Dibuka',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.bold,
                            color: Color(0xFF1D273B),
                          ),
                        ),
                        Text(
                          storeName,
                          style: TextStyle(
                            fontSize: 13,
                            color: Colors.grey.shade600,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              const Text(
                'Modal kasir awal:',
                style: TextStyle(fontSize: 13, color: Colors.grey),
              ),
              const SizedBox(height: 8),
              TextField(
                controller: modalController,
                keyboardType: TextInputType.number,
                autofocus: false,
                decoration: const InputDecoration(
                  labelText: 'Modal Kasir',
                  border: OutlineInputBorder(),
                  prefixText: 'Rp ',
                ),
              ),
              const SizedBox(height: 20),
              _BukaShiftButton(
                token: _token,
                storeID: storeID,
                organisasiID: organisasiID,
                userID: _userID,
                modalController: modalController,
                onSuccess: (shiftID) {
                  completer.complete(shiftID);
                  Navigator.pop(ctx);
                },
              ),
            ],
          ),
        ),
      ),
    );

    // Jika sheet ditutup tanpa complete (seharusnya tidak terjadi karena
    // isDismissible:false), kembalikan 0 sebagai safety net.
    return completer.isCompleted ? completer.future : Future.value(0);
  }

  // ============================================================
  // TUTUP SHIFT
  // ============================================================
  Future<void> _tutupShift() async {
    final state = ref.read(penjualanProvider);

    final rekap = await ShiftService.getRekapShift(
      token: _token,
      shiftID: _shiftID,
      storeID: state.storeID,
      organisasiID: state.organisasiID,
    );

    if (rekap.isEmpty || !mounted) return;

    final openShift = rekap['open_shift'] ?? '';
    final modalKasir = (rekap['modal_kasir'] as num).toDouble();
    final totalSales = (rekap['total_sales'] as num).toDouble();
    final jumlahInv = rekap['jumlah_invoice'] as int;

    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Tutup Shift'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            _rekapRow('Buka Shift', openShift.toString().substring(0, 16)),
            const Divider(),
            _rekapRow('Modal Kasir', 'Rp ${CurrencyFormat.format(modalKasir)}'),
            _rekapRow('Jumlah Invoice', '$jumlahInv transaksi'),
            _rekapRow('Total Sales', 'Rp ${CurrencyFormat.format(totalSales)}'),
            const Divider(),
            const SizedBox(height: 8),
            const Text(
              'Yakin ingin menutup shift?',
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            onPressed: () => Navigator.pop(context, true),
            style: ElevatedButton.styleFrom(backgroundColor: Colors.red),
            child: const Text(
              'Tutup Shift',
              style: TextStyle(color: Colors.white),
            ),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    final berhasil = await ShiftService.tutupShift(
      token: _token,
      shiftID: _shiftID,
      storeID: state.storeID,
      organisasiID: state.organisasiID,
      totalSales: totalSales,
      jumlahInvoice: jumlahInv,
    );

    if (!mounted) return;

    if (berhasil) {
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Shift Ditutup'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.check_circle, color: Colors.green, size: 56),
              const SizedBox(height: 16),
              Text(
                'Total Sales: Rp ${CurrencyFormat.format(totalSales)}',
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              Text(
                '$jumlahInv transaksi',
                style: const TextStyle(color: Colors.grey),
              ),
            ],
          ),
          actions: [
            ElevatedButton(
              onPressed: () {
                Navigator.pop(context);
                _goToHome();
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
    } else {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Gagal menutup shift'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Widget _rekapRow(String label, String value) => Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Text(label, style: const TextStyle(color: Colors.grey)),
            Text(value, style: const TextStyle(fontWeight: FontWeight.bold)),
          ],
        ),
      );

  // ============================================================
  // SEARCH PRODUK — cek package dulu sebelum insert
  // ============================================================

}
