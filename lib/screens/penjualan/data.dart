// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Loading data awal, ensure shift, load POS data, logout.
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanDataX on _PenjualanScreenState {
  // ============================================================
  // RETRY HELPER — untuk request kritikal di chain load awal
  // (cekShiftUser, getStores, getOrganisasiID, getNumber, getChannels,
  // getCaraBayar). Kalau salah satu gagal (timeout/connection reset di
  // 4G/tethering yang naik-turun), seluruh chain dulu langsung batal
  // dan ditelan diam-diam oleh catch di _loadMinimalData — akibatnya
  // Scaffold tetap dirender "sukses" (isLoading=false) padahal Channel
  // dropdown kosong, grid produk kosong, dsb, tanpa pesan apa pun.
  //
  // Sekarang: retry otomatis dengan backoff naik (1s, 2s) dulu sebelum
  // benar-benar dianggap gagal, supaya blip koneksi sesaat tidak
  // langsung menjatuhkan seluruh layar ke error state.
  // ============================================================
  Future<T> _withRetry<T>(
    Future<T> Function() action, {
    int maxAttempts = 3,
  }) async {
    DioException? lastError;
    for (var attempt = 1; attempt <= maxAttempts; attempt++) {
      try {
        return await action();
      } on DioException catch (e) {
        lastError = e;
        debugPrint(
          '[_withRetry] percobaan $attempt/$maxAttempts gagal: ${e.message}',
        );
        if (attempt < maxAttempts) {
          await Future.delayed(Duration(seconds: attempt));
        }
      }
    }
    throw lastError!;
  }

  /// Dipanggil dari tombol "Coba Lagi" di layar error (lihat build()
  /// di penjualan_screen.dart). Reset state loading lalu ulangi chain
  /// dari awal.
  Future<void> _retryLoadMinimalData() async {
    if (mounted) {
      _setState(() {
        _isLoading = true;
        _loadError = false;
      });
    }
    await _loadMinimalData();
    _focusSku();
  }

  Future<void> _loadMinimalData() async {
    try {
      final session = await SessionService.getSession();
      _token = session['token'];
      _userID = session['user_id'];
      _deviceToken = await SessionService.getDeviceToken();

      // Cek apakah user sudah punya shift aktif
      final shiftUserData = await _withRetry(
        () => ShiftService.cekShiftUser(userId: _userID),
      );

      final shiftUserRes = await _withRetry(
        () => dio.post(
          '/penjualan.php',
          data:
              FormData.fromMap({'action': 'cekShiftUser', 'user_id': _userID}),
        ),
      );
      );

      int storeID = 0;
      int organisasiID = 0;
      String storeName = '';

      if (shiftUserData['has_shift'] == true) {
        // User sudah punya shift → ambil data store dari shift
        storeID = int.tryParse(shiftUserData['store_id']?.toString() ?? '') ?? 0;
        organisasiID =
            int.tryParse(shiftUserData['organisasi_id']?.toString() ?? '') ?? 0;
        storeName = shiftUserData['store_nama']?.toString() ?? '';
        _shiftID = int.tryParse(shiftUserData['shift_id']?.toString() ?? '') ?? 0;
        _isFnb = shiftUserData['is_fnb'] == true;

        _activeStoreID = storeID;
        _activeOrgID = organisasiID;
        _activeStoreName = storeName;

        // Langsung load data POS — tidak perlu cek shift lagi
        await _loadPosData(
          storeID: storeID,
          organisasiID: organisasiID,
          storeName: storeName,
        );
      } else {
        // Belum punya shift → pilih store dulu, lalu shift check
        final stores = await _withRetry(
          () => StoreService.getStores(userId: _userID),
        );

        Map<String, dynamic>? pickedStore;
        if (stores.length == 1) {
          pickedStore = stores.first;
        } else {
          if (!mounted) return;
          pickedStore = await _showStorePicker(stores);
          if (pickedStore == null) {
            // User cancel store picker → kembali ke HomeScreen
            _goToHome();
            return;
          }
        }

        storeID = int.parse(pickedStore['id'].toString());
        storeName = pickedStore['nama'].toString();

        final orgRes = await _withRetry(
          () => StoreService.getOrganisasiId(storeID),
        );
        organisasiID = int.tryParse(orgRes['organisasi_id']?.toString() ?? '') ?? 0;
        _isFnb = orgRes['is_fnb'] == true;

        _activeStoreID = storeID;
        _activeOrgID = organisasiID;
        _activeStoreName = storeName;

        // Phase 2 — shift check + buka shift jika perlu
        if (!mounted) return;
        await _checkAndEnsureShift(
          storeID: storeID,
          organisasiID: organisasiID,
          storeName: storeName,
        );
      }
    } catch (e) {
      // Dulu: hanya _isLoading = false, error ditelan diam-diam.
      // Akibatnya Scaffold transaksi tetap dirender "sukses" walau
      // sebagian/seluruh data (channel, cara bayar, nomor invoice,
      // grid produk) gagal ke-load — persis gejala di laporan bug:
      // semua field kelihatan ada tapi kosong, tanpa pesan error.
      //
      // Sekarang: tandai _loadError = true supaya build() menampilkan
      // layar retry yang jelas, bukan Scaffold dengan data setengah.
      debugPrint('[_loadMinimalData] gagal: $e');
      if (mounted) {
        _setState(() {
          _isLoading = false;
          _loadError = true;
        });
      }
    }
  }

  // ============================================================
  // PHASE 2 — Cek shift, buka jika belum ada
  // ============================================================
  Future<void> _checkAndEnsureShift({
    required int storeID,
    required int organisasiID,
    required String storeName,
  }) async {
    final shiftRes = await ShiftService.cekShift(
      token: _token,
      storeID: storeID,
      organisasiID: organisasiID,
      userID: _userID,
    );

    if (shiftRes.status == ShiftStatus.milikOrangLain) {
      // Store sedang dipakai orang lain → notif → kembali ke HomeScreen
      if (!mounted) return;
      await showDialog(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Store Sedang Digunakan'),
          content: Text(
            'Store $storeName sedang digunakan oleh ${shiftRes.kasirNama}.\n\n'
            'Silakan pilih store lain atau minta kasir tersebut menutup shiftnya.',
          ),
          actions: [
            ElevatedButton(
              onPressed: () => Navigator.pop(context),
              style: ElevatedButton.styleFrom(
                backgroundColor: const Color(0xFF1D273B),
              ),
              child: const Text('OK', style: TextStyle(color: Colors.white)),
            ),
          ],
        ),
      );
      _goToHome();
      return;
    }

    if (shiftRes.status == ShiftStatus.tidakAda) {
      // Belum ada shift → tampilkan bottom sheet buka shift (non-dismissible)
      if (!mounted) return;
      final shiftID = await _showBukaShiftSheet(
        storeID: storeID,
        organisasiID: organisasiID,
        storeName: storeName,
      );
      if (shiftID == 0) {
        // User tidak bisa dismiss sheet — ini seharusnya tidak terjadi,
        // tapi sebagai safety net kembalikan ke HomeScreen
        _goToHome();
        return;
      }
      _shiftID = shiftID;
    }

    // Shift OK (tidakAda → sudah dibuka, atau milikSaya dari cekShift)
    if (!mounted) return;
    await _loadPosData(
      storeID: storeID,
      organisasiID: organisasiID,
      storeName: storeName,
    );
  }

  // ============================================================
  // PHASE 3 — Load data POS (number, channels, cara bayar)
  // Dipanggil setelah shift dipastikan ada.
  // ============================================================
  Future<void> _loadPosData({
    required int storeID,
    required int organisasiID,
    required String storeName,
  }) async {
    final newNumber = await _withRetry(
      () => PosDataService.getNextOrderNumber(
        storeId: storeID,
        deviceToken: _deviceToken,
      ),
    );
    final newNumber = numberRes.data['number'];

    _channels = await _withRetry(
      () => PosDataService.getChannels(
        organisasiId: organisasiID,
      ),
    );

    _caraBayarList = await _withRetry(
      () => PosDataService.getCaraBayar(
        organisasiId: organisasiID,
      ),
    );

    // Channel awal = yang is_default = 1. Backend (getChannels) memang
    // sudah ORDER BY is_default DESC jadi selama ini _channels.first
    // "kebetulan" selalu default — di sini dibuat eksplisit supaya tidak
    // diam-diam salah kalau urutan query backend berubah suatu saat,
    // dengan fallback ke channel pertama kalau tidak ada is_default = 1.
    final Map<String, dynamic>? defaultChannel = _channels.isNotEmpty
        ? _channels.firstWhere(
            (c) => c['is_default'].toString() == '1',
            orElse: () => _channels.first,
          )
        : null;
    final targetSalesTipeID =
        int.tryParse(defaultChannel?['dim_salestipe_id']?.toString() ?? '') ??
            0;

    ref.read(penjualanProvider.notifier).setInitialData(
          number: newNumber,
          storeID: storeID,
          storeName: storeName,
          organisasiID: organisasiID,
          salesTipeID: targetSalesTipeID,
        );

    // WA banner
    try {
      final storeData = await StoreService.getStoreData(storeID);
      _waDisconnected =
          (storeData['wa_disconnected'] as num? ?? 0).toInt();
    } catch (_) {}

    if (mounted) _setState(() => _isLoading = false);
    _loadImageProducts();
  }

  Future<void> _logout() async {
    await SessionService.clearSession();
    if (mounted) {
      Navigator.pushReplacement(
        context,
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  // ============================================================
  // STORE PICKER — Modal Bottom Sheet
  // ============================================================
  Future<Map<String, dynamic>?> _showStorePicker(
    List<Map<String, dynamic>> stores,
  ) async {
    Map<String, dynamic>? selected;
    return showModalBottomSheet<Map<String, dynamic>>(
      context: context,
      isScrollControlled: true,
      isDismissible: false,
      enableDrag: false,
      backgroundColor: Colors.transparent,
      builder: (_) => StatefulBuilder(
        builder: (ctx, setState) => Container(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          decoration: const BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                margin: const EdgeInsets.only(top: 12),
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: Colors.grey.shade300,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 8),
                child: Row(
                  children: [
                    const Icon(Icons.store, color: Color(0xFF1D273B), size: 22),
                    const SizedBox(width: 10),
                    const Expanded(
                      child: Text(
                        'Pilih Store',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                          color: Color(0xFF1D273B),
                        ),
                      ),
                    ),
                    Text(
                      '${stores.length} store',
                      style: TextStyle(
                        fontSize: 12,
                        color: Colors.grey.shade500,
                      ),
                    ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Flexible(
                child: ListView.separated(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  shrinkWrap: true,
                  itemCount: stores.length,
                  separatorBuilder: (_, __) => const SizedBox(height: 6),
                  itemBuilder: (_, i) {
                    final s = stores[i];
                    final isSelected =
                        selected?['id'].toString() == s['id'].toString();
                    return InkWell(
                      onTap: () => setState(() => selected = s),
                      borderRadius: BorderRadius.circular(10),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 150),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 14,
                        ),
                        decoration: BoxDecoration(
                          color: isSelected
                              ? const Color(0xFF1D273B)
                              : Colors.grey.shade50,
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: isSelected
                                ? const Color(0xFF1D273B)
                                : Colors.grey.shade200,
                            width: isSelected ? 2 : 1,
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(
                              isSelected ? Icons.store : Icons.store_outlined,
                              color: isSelected
                                  ? Colors.white
                                  : Colors.grey.shade500,
                              size: 20,
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Text(
                                s['nama'].toString(),
                                style: TextStyle(
                                  color: isSelected
                                      ? Colors.white
                                      : Colors.black87,
                                  fontWeight: isSelected
                                      ? FontWeight.bold
                                      : FontWeight.normal,
                                  fontSize: 15,
                                ),
                              ),
                            ),
                            if (isSelected)
                              const Icon(
                                Icons.check_circle,
                                color: Colors.white,
                                size: 18,
                              ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
                child: Row(
                  children: [
                    Expanded(
                      child: OutlinedButton(
                        onPressed: () => Navigator.pop(ctx, null),
                        child: const Text('Cancel'),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      flex: 2,
                      child: ElevatedButton(
                        onPressed: selected == null
                            ? null
                            : () => Navigator.pop(ctx, selected),
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF1D273B),
                        ),
                        child: Text(
                          selected == null
                              ? 'Pilih Store'
                              : 'Masuk ke ${selected!['nama']}',
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ============================================================
  // BUKA SHIFT
  // ============================================================
}
