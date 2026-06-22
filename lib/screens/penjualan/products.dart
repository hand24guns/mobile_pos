// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Search/insert produk, package, voucher check internal, refresh, image grid loader, product picker.
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanProductsX on _PenjualanScreenState {
  Future<void> _searchProduk(String sku) async {
    if (sku.isEmpty) return;
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'searchProduk',
        'term': sku,
        'organisasi_id': state.organisasiID,
        'salestipe_id': state.salesTipeID,
      }),
    );

    final data = List<Map<String, dynamic>>.from(res.data['data']);
    if (data.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Produk "$sku" tidak ditemukan')),
        );
      }
      return;
    }

    if (data.length == 1) {
      await _insertProduk(data.first['kode'] as String);
    } else {
      _showProductPicker(data);
    }
    _skuController.clear();
  }

  // ============================================================
  // INSERT PRODUK — wrap: cek package dulu
  // Pakai ResponseType.plain agar tidak crash jika PHP ada output
  // warning/notice sebelum JSON — bersihkan string lalu parse.
  // ============================================================
  Future<void> _insertProduk(String sku) async {
    // ── Guard: abaikan tap jika kode ini sedang diproses ──
    if (_processingKodes.contains(sku)) return;
    if (mounted) _setState(() => _processingKodes.add(sku));

    try {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);

      Map<String, dynamic> cekData;
      try {
        final rawRes = await dio.post(
          '/penjualan.php',
          data: FormData.fromMap({
            'action': 'cekPackage',
            'sku': sku,
            'organisasi_id': state.organisasiID,
            'salestipe_id': state.salesTipeID,
          }),
          options: Options(responseType: ResponseType.plain),
        );

        final rawStr = rawRes.data?.toString() ?? '';
        final jsonStart = rawStr.indexOf('{');
        if (jsonStart < 0) {
          debugPrint('[cekPackage] Response tidak valid (no JSON): $rawStr');
          await _doInsertProduk(sku);
          return;
        }
        final cleanStr = rawStr.substring(jsonStart);
        final decoded = jsonDecode(cleanStr);
        if (decoded is! Map) {
          debugPrint('[cekPackage] JSON bukan Map: $cleanStr');
          await _doInsertProduk(sku);
          return;
        }
        cekData = Map<String, dynamic>.from(decoded);
      } on DioException catch (e) {
        debugPrint('[cekPackage] DioException: ${e.message}');
        await _doInsertProduk(sku);
        return;
      } catch (e) {
        debugPrint('[cekPackage] Exception: $e');
        await _doInsertProduk(sku);
        return;
      }

      final isPackage =
          cekData['is_package'] == true || cekData['is_package'] == 1;

      if (isPackage) {
        if (!mounted) return;
        showDialog(
          context: context,
          barrierDismissible: false,
          builder: (_) => PackageDialog(
            sku: sku,
            packageData: cekData,
            onConfirm: (isianDipilih, addonDipilih, addonTotal, keterangan) {
              _doInsertPackage(
                sku: sku,
                isianDipilih: isianDipilih,
                addonDipilih: addonDipilih,
                addonTotal: addonTotal,
                keterangan: keterangan,
              );
            },
          ),
        );
        // Untuk package: lock dilepas setelah dialog muncul,
        // bukan setelah insert — karena insert terjadi dari callback dialog.
      } else {
        await _doInsertProduk(sku);
      }
    } finally {
      // Lock selalu dilepas, apapun yang terjadi
      if (mounted) _setState(() => _processingKodes.remove(sku));
    }
  }

  /// Insert produk biasa ke temp_invoice
  Future<void> _doInsertProduk(String sku) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'insertItem',
        'number': state.number,
        'sku': sku,
        'organisasi_id': state.organisasiID,
        'store_id': state.storeID,
        'member_id': state.memberID ?? 0,
        'voucher': _activeVoucher,
        'device_token': _deviceToken,
        'salestipe_id': state.salesTipeID,
      }),
    );

    if (res.data['success'] == true) {
      _checkVoucherValid(res.data);
      await _refreshFromApi();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(res.data['message'] ?? 'Gagal menambahkan produk'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
    _skuController.clear();
  }

  /// Insert produk package ke temp_invoice
  Future<void> _doInsertPackage({
    required String sku,
    required List<Map<String, dynamic>> isianDipilih,
    required List<Map<String, dynamic>> addonDipilih,
    required double addonTotal,
    String keterangan = '',
  }) async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final res = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'insertPackage',
        'number': state.number,
        'sku': sku,
        'organisasi_id': state.organisasiID,
        'store_id': state.storeID,
        'member_id': state.memberID ?? 0,
        'voucher': _activeVoucher,
        'device_token': _deviceToken,
        'isian': jsonEncode(isianDipilih),
        'addon': jsonEncode(addonDipilih),
        'addon_harga': addonTotal,
        'keterangan': keterangan,
        'salestipe_id': state.salesTipeID,
      }),
    );

    if (res.data['success'] == true) {
      _checkVoucherValid(res.data);
      await _refreshFromApi();
    } else {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              res.data['message'] ?? 'Gagal menambahkan produk package',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================
  // CEK VOUCHER VALID — auto-lepas jika tidak memenuhi syarat
  // ============================================================
  void _checkVoucherValid(Map<String, dynamic> responseData) {
    if (_activeVoucher.isNotEmpty && responseData['voucher_valid'] == false) {
      _setState(() => _activeVoucher = '');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Voucher dilepas — total belanja tidak memenuhi syarat',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
    }
  }

  // ============================================================
  // REFRESH CART & SUMMARY
  // ============================================================
  Future<void> _refreshFromApi() async {
    final state = ref.read(penjualanProvider);
    final dio = ApiService.getDio(token: _token);

    final itemsRes = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'getItems',
        'number': state.number,
        'device_token': _deviceToken,
      }),
    );

    final itemsData = List<Map<String, dynamic>>.from(itemsRes.data['data']);
    final items = itemsData.map((e) => CartItem.fromJson(e)).toList();

    final summaryRes = await dio.post(
      '/penjualan.php',
      data: FormData.fromMap({
        'action': 'getSummary',
        'number': state.number,
        'store_id': state.storeID,
        'device_token': _deviceToken,
      }),
    );

    final summary = summaryRes.data;
    ref.read(penjualanProvider.notifier).updateItems(items);
    ref.read(penjualanProvider.notifier).updateSummary(
          gross: (summary['gross'] as num).toDouble(),
          diskon: (summary['diskon'] as num).toDouble(),
          total: (summary['total'] as num).toDouble(),
          dpp: (summary['dpp'] as num).toDouble(),
          pajak: (summary['tax'] as num).toDouble(),
        );
  }

  // ============================================================
  // LOAD PRODUK DENGAN IMAGE untuk grid kiri — per kategori
  // ============================================================
  Future<void> _loadImageProducts() async {
    if (_isLoadingImages) return;
    _setState(() => _isLoadingImages = true);
    try {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);

      final rawRes = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'getImageProducts',
          'organisasi_id': state.organisasiID,
          'salestipe_id': state.salesTipeID,
        }),
        options: Options(responseType: ResponseType.plain),
      );

      final rawStr = rawRes.data?.toString() ?? '';

      final jsonStart = rawStr.indexOf('{');
      if (jsonStart < 0) {
        return;
      }
      final parsed = jsonDecode(rawStr.substring(jsonStart)) as Map;

      // Backend baru return list of { id, nama, produk: [...] }
      final rawData = parsed['data'];
      if (rawData is List) {
        final categories = rawData
            .map<Map<String, dynamic>>(
              (cat) => {
                'id': cat['id'] ?? 0,
                'nama': cat['nama']?.toString() ?? '',
                'produk': (cat['produk'] as List? ?? [])
                    .map<Map<String, dynamic>>(
                      (p) => {
                        'kode': p['kode']?.toString() ?? '',
                        'nama': p['nama']?.toString() ?? '',
                        'hpj': (p['hpj'] as num? ?? 0).toDouble(),
                        'image': p['image']?.toString() ?? '',
                        'is_package':
                            p['is_package'] == true || p['is_package'] == 1,
                      },
                    )
                    .where((p) => p['image']!.isNotEmpty)
                    .toList(),
              },
            )
            .where((cat) => (cat['produk'] as List).isNotEmpty)
            .toList();
        if (mounted) {
          _setState(() => _imageCategories = categories);
          _prewarmImageCache();
        }
      }
    } catch (e) {
    } finally {
      if (mounted) _setState(() => _isLoadingImages = false);
    }
  }

  /// Pre-warm: decode gambar ke memory di background setelah grid dimuat,
  /// agar saat pertama kali tab dibuka sudah siap render.
  void _prewarmImageCache() {
    for (final cat in _imageCategories) {
      for (final p in (cat['produk'] as List<Map<String, dynamic>>)) {
        final url = p['image']?.toString() ?? '';
        if (url.isNotEmpty) {
          precacheImage(CachedNetworkImageProvider(url), context);
        }
      }
    }
  }

  void _showProductPicker(List<Map<String, dynamic>> products) {
    showModalBottomSheet(
      context: context,
      builder: (_) => ListView.builder(
        itemCount: products.length,
        itemBuilder: (_, i) {
          final p = products[i];
          return ListTile(
            title: Text(p['nama']),
            subtitle: Text(p['kode']),
            trailing: Text('Rp ${CurrencyFormat.format(p['hpj'])}'),
            onTap: () {
              Navigator.pop(context);
              _insertProduk(p['kode'] as String);
            },
          );
        },
      ),
    );
  }

  // ============================================================
  // REMOVE & UPDATE QTY
  // ============================================================

}
