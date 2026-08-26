// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Search/insert produk, package, voucher check internal, refresh, image grid loader, product picker.
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
//
// CATATAN: butuh package flutter_cache_manager di pubspec.yaml
// (sudah ditambahkan) dan import di penjualan_screen.dart (file utama):
//   import 'package:flutter_cache_manager/flutter_cache_manager.dart';
part of 'penjualan_screen.dart';

// ============================================================
// CACHE MANAGER KHUSUS GAMBAR PRODUK
// Dipisah dari default cache manager cached_network_image supaya:
// - Gambar produk tidak ikut ke-evict bareng cache lain di app
// - stalePeriod jelas: gambar dianggap "boleh dipakai apa adanya"
//   selama 7 hari sebelum dicoba re-fetch di background (tetap tampil
//   dari cache dulu selama re-fetch, tidak blocking UI)
// - maxNrOfCacheObjects dibatasi supaya tidak membengkak tanpa batas
//   di tablet dengan storage terbatas
// ============================================================
final CacheManager productImageCacheManager = CacheManager(
  Config(
    'productImageCache',
    stalePeriod: const Duration(days: 7),
    maxNrOfCacheObjects: 300,
  ),
);

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
    // ── Guard: masih ada operasi cart lain berjalan (ganti channel,
    // insert produk lain, update qty, voucher, dsb). Kalau dibiarkan,
    // dialog package tetap bisa kebuka & tampil harga yang benar, tapi
    // begitu "Tambah ke Order" ditekan, _doInsertPackage/_runCartMutation
    // akan diam-diam no-op karena _isCartSyncing masih true — dialog
    // sudah kepencet Batal, kasir mengira sudah masuk padahal tidak.
    // Makanya block dari sini, sebelum cekPackage / dialog dibuka sama sekali.
    if (_isCartSyncing) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tunggu proses sebelumnya selesai...'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }
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
    await _runCartMutation(() async {
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
        _focusSku();
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
    });
  }

  /// Insert produk package ke temp_invoice
  Future<void> _doInsertPackage({
    required String sku,
    required List<Map<String, dynamic>> isianDipilih,
    required List<Map<String, dynamic>> addonDipilih,
    required double addonTotal,
    String keterangan = '',
  }) async {
    await _runCartMutation(() async {
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
        _focusSku();
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
    });
  }

  // ============================================================
  // EDIT PILIHAN PACKAGE — item yang SUDAH ada di cart
  // ============================================================

  /// Buka ulang PackageDialog untuk item package yang sudah ada di cart,
  /// dengan isian/addon lama sudah tercentang (prefill) sesuai
  /// packages_notes item tersebut.
  Future<void> _editPackageItem(int index) async {
    if (_isCartSyncing) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Tunggu proses sebelumnya selesai...'),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 1),
          ),
        );
      }
      return;
    }

    final state = ref.read(penjualanProvider);
    final item = state.items[index];
    if (!item.isPackage) return; // guard tambahan, tombol harusnya tak muncul

    final dio = ApiService.getDio(token: _token);

    Map<String, dynamic> cekData;
    try {
      final rawRes = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'cekPackage',
          'sku': item.kode,
          'organisasi_id': state.organisasiID,
          'salestipe_id': state.salesTipeID,
        }),
        options: Options(responseType: ResponseType.plain),
      );
      final rawStr = rawRes.data?.toString() ?? '';
      final jsonStart = rawStr.indexOf('{');
      if (jsonStart < 0) throw Exception('Response cekPackage tidak valid');
      cekData =
          Map<String, dynamic>.from(jsonDecode(rawStr.substring(jsonStart)));
    } catch (e) {
      debugPrint('[_editPackageItem] gagal ambil data package: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Gagal memuat data package'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    if (cekData['is_package'] != true) {
      // Produk sudah tidak lagi berstatus package di master data
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Produk ini sudah bukan package lagi'),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return;
    }

    // Parse pilihan sebelumnya dari packages_notes tersimpan.
    // Format: {"isian":[{"id":..,"nama":..}], "addon":[{"id":..,"nama":..,"harga":..}]}
    // NOTE: cart lama (sebelum backend disimpan id-nya) mungkin cuma
    // punya 'nama' tanpa 'id' — untuk kasus itu id dianggap 0 dan
    // prefill jatuh ke "tidak tercentang" (aman, cuma kurang akurat
    // khusus untuk item lama yang sudah ada sebelum update ini).
    Set<int> selectedIsianIds = {};
    Set<int> selectedAddonIds = {};
    final prevKeterangan = item.keterangan ?? '';
    try {
      final oldNotes =
          jsonDecode(item.packagesNotes!) as Map<String, dynamic>;
      selectedIsianIds = ((oldNotes['isian'] as List?) ?? [])
          .map((e) => (e is Map ? (e['id'] as num?)?.toInt() ?? 0 : 0))
          .where((id) => id != 0)
          .toSet();
      selectedAddonIds = ((oldNotes['addon'] as List?) ?? [])
          .map((e) => (e is Map ? (e['id'] as num?)?.toInt() ?? 0 : 0))
          .where((id) => id != 0)
          .toSet();
    } catch (e) {
      debugPrint('[_editPackageItem] gagal parse packages_notes lama: $e');
    }

    if (!mounted) return;
    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (_) => PackageDialog(
        sku: item.kode,
        packageData: cekData,
        initialSelectedIsianIds: selectedIsianIds,
        initialSelectedAddonIds: selectedAddonIds,
        initialKeterangan: prevKeterangan,
        isEditMode: true,
        onConfirm: (isianDipilih, addonDipilih, addonTotal, keterangan) {
          _doEditPackage(
            sku: item.kode,
            oldPackagesNotes: item.packagesNotes!,
            isianDipilih: isianDipilih,
            addonDipilih: addonDipilih,
            addonTotal: addonTotal,
            keterangan: keterangan,
          );
        },
      ),
    );
  }

  Future<void> _doEditPackage({
    required String sku,
    required String oldPackagesNotes,
    required List<Map<String, dynamic>> isianDipilih,
    required List<Map<String, dynamic>> addonDipilih,
    required double addonTotal,
    String keterangan = '',
  }) async {
    await _runCartMutation(() async {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);

      final res = await dio.post(
        '/penjualan.php',
        data: FormData.fromMap({
          'action': 'editPackage',
          'number': state.number,
          'sku': sku,
          'old_packages_notes': oldPackagesNotes,
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
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text('Pilihan package berhasil diubah'),
              backgroundColor: Colors.green,
            ),
          );
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(res.data['message'] ?? 'Gagal mengubah package'),
              backgroundColor: Colors.red,
            ),
          );
        }
      }
    });
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
    _setState(() {
      _isLoadingImages = true;
      _imageLoadError = false;
    });
    try {
      final state = ref.read(penjualanProvider);
      final dio = ApiService.getDio(token: _token);

      // Retry ringan (2x) untuk request ini juga — grid produk adalah
      // hal pertama yang dilihat kasir, jadi blip koneksi sesaat
      // sebaiknya coba pulih sendiri dulu sebelum tampil ke user
      // sebagai "gagal, tap retry".
      final rawRes = await _withRetry(
        () => dio
            .post(
              '/penjualan.php',
              data: FormData.fromMap({
                'action': 'getImageProducts',
                'organisasi_id': state.organisasiID,
                'salestipe_id': state.salesTipeID,
              }),
              options: Options(responseType: ResponseType.plain),
            )
            .timeout(const Duration(seconds: 12)),
        maxAttempts: 2,
      );

      final rawStr = rawRes.data?.toString() ?? '';

      final jsonStart = rawStr.indexOf('{');
      if (jsonStart < 0) {
        // Response tidak valid (bukan JSON) — ini kegagalan, bukan
        // "memang tidak ada produk". Dulu di-return begitu saja dan
        // _imageCategories tetap [] tanpa penanda apa pun, sehingga UI
        // menampilkan "Tidak ada produk dengan gambar" yang menyesatkan.
        debugPrint('[_loadImageProducts] response tidak valid: $rawStr');
        if (mounted) _setState(() => _imageLoadError = true);
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
      } else {
        // 'data' bukan List sama sekali — response backend tidak
        // sesuai kontrak, perlakukan sebagai gagal juga.
        debugPrint('[_loadImageProducts] field data bukan List: $parsed');
        if (mounted) _setState(() => _imageLoadError = true);
      }
    } catch (e) {
      // Dulu: catch kosong, error timeout/connection reset ditelan
      // total tanpa jejak. Sekarang ditandai + dilog supaya UI bisa
      // tawarkan tombol retry alih-alih diam menampilkan grid kosong.
      debugPrint('[_loadImageProducts] gagal: $e');
      if (mounted) _setState(() => _imageLoadError = true);
    } finally {
      if (mounted) _setState(() => _isLoadingImages = false);
    }
  }

  /// Pre-warm: decode gambar ke memory di background setelah grid dimuat,
  /// agar saat pertama kali tab dibuka sudah siap render.
  ///
  /// PENTING (kondisi sinyal 4G/tethering naik-turun):
  /// - Request gambar ditembak dalam BATCH kecil (bukan semua sekaligus),
  ///   supaya tidak membanjiri koneksi yang sedang lemah dengan puluhan/
  ///   ratusan request paralel yang ujung-ujungnya sama-sama timeout.
  /// - Setiap gambar punya timeout sendiri dan error-nya diisolasi per-item
  ///   — satu gambar gagal tidak boleh menghentikan gambar lain di batch
  ///   yang sama maupun batch berikutnya.
  /// - Pakai productImageCacheManager (bukan default global cache manager)
  ///   supaya kebijakan cache gambar produk (stalePeriod, max object)
  ///   konsisten dan tidak tercampur cache lain di app.
  Future<void> _prewarmImageCache() async {
    final urls = <String>[];
    for (final cat in _imageCategories) {
      for (final p in (cat['produk'] as List<Map<String, dynamic>>)) {
        final url = p['image']?.toString() ?? '';
        if (url.isNotEmpty) urls.add(url);
      }
    }
    if (urls.isEmpty) return;

    // Batch kecil (4 paralel) — cukup untuk memanfaatkan koneksi tanpa
    // membanjiri saat sinyal sedang lemah. Kalau nanti dirasa masih berat
    // di tethering, turunkan ke 2-3.
    const batchSize = 4;
    const perImageTimeout = Duration(seconds: 8);

    for (var i = 0; i < urls.length; i += batchSize) {
      if (!mounted) return; // user sudah pindah screen, hentikan prewarm

      final batch = urls.skip(i).take(batchSize);
      await Future.wait(
        batch.map((url) async {
          try {
            await precacheImage(
              CachedNetworkImageProvider(
                url,
                cacheManager: productImageCacheManager,
              ),
              context,
            ).timeout(perImageTimeout);
          } catch (e) {
            // Sengaja diam — gambar ini akan dicoba ulang otomatis oleh
            // CachedNetworkImage widget di grid saat benar-benar dirender
            // (lihat errorWidget dengan tombol retry di widgets_grid.dart).
            debugPrint('[prewarmImageCache] gagal muat: $url ($e)');
          }
        }),
      );
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
