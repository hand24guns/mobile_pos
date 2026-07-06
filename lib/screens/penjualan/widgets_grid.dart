// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Image grid & product grid widgets.
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanGridWidgetsX on _PenjualanScreenState {
  Widget _buildImageGrid() {
    if (_isLoadingImages) {
      return const Center(child: CircularProgressIndicator());
    }
    if (_imageCategories.isEmpty) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.image_not_supported_outlined,
              size: 48,
              color: Colors.grey.shade400,
            ),
            const SizedBox(height: 8),
            Text(
              'Tidak ada produk dengan gambar',
              style: TextStyle(color: Colors.grey.shade500),
            ),
          ],
        ),
      );
    }

    // Selalu pakai DefaultTabController agar tab kategori selalu muncul
    return DefaultTabController(
      length: _imageCategories.length,
      child: Column(
        children: [
          // Tab bar kategori — lebih tipis di tiny tablet
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF1D273B),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF1D273B),
              labelPadding: EdgeInsets.symmetric(
                horizontal: _isTinyTablet ? 10 : 16,
              ),
              labelStyle: TextStyle(
                fontSize: _isTinyTablet ? 11 : 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: _isTinyTablet ? 11 : 13,
              ),
              // Kurangi tinggi tab bar di tiny tablet: default 46dp → 34dp
              tabs: _imageCategories
                  .map((cat) => SizedBox(
                        height: _isTinyTablet ? 34 : 46,
                        child: Center(
                          child: Text(cat['nama']?.toString() ?? ''),
                        ),
                      ))
                  .toList(),
            ),
          ),
          // Grid produk per tab
          Expanded(
            child: TabBarView(
              children: _imageCategories.map((cat) {
                final produk = cat['produk'] as List<Map<String, dynamic>>;
                return _buildProductGrid(produk);
              }).toList(),
            ),
          ),
        ],
      ),
    );
  }

  /// Grid produk gambar (dipakai oleh _buildImageGrid) — SELALU 4 kolom.
  ///
  /// Gambar dibuat square (1:1) via AspectRatio, dan childAspectRatio
  /// grid dihitung dinamis dari lebar cell aktual (bukan angka statis),
  /// dengan rumus:
  ///   tinggi cell = lebar cell (gambar square) + tinggi area teks
  /// Tinggi area teks dihitung dari font size nama (2 baris) + harga
  /// (1 baris) + padding, jadi nama & harga selalu punya ruang cukup
  /// dan tidak ter-truncate meski di tablet 7" 3-button nav (body sempit).
  Widget _buildProductGrid(List<Map<String, dynamic>> products) {
    // Padding dan spacing lebih kecil di tiny tablet untuk hemat ruang vertikal
    final double gridPadding = _isTinyTablet ? 4 : 10;
    final double spacing = _isTinyTablet ? 4 : 10;
    final int columns = _gridColumns;

    final double nameFontSize = _isTinyTablet ? 10.0 : 12;
    final double priceFontSize = _isTinyTablet ? 10.0 : 12;
    // Tiny: padding lebih kecil (4dp total) agar cell lebih pendek
    final double textVerticalPadding = _isTinyTablet ? 4 : 10;
    final double textGap = 2;
    final double safetyBuffer = 2;
    // Tiny tablet: nama 1 baris saja agar cell lebih pendek → muat 2 baris grid
    final int nameMaxLines = _isTinyTablet ? 1 : 2;

    return LayoutBuilder(
      builder: (context, constraints) {
        // Lebar 1 cell setelah dikurangi padding grid & spacing antar kolom
        final double cellWidth = (constraints.maxWidth -
                (gridPadding * 2) -
                (spacing * (columns - 1))) /
            columns;

        // Tinggi area teks: nama (1 atau 2 baris) + gap + harga + padding
        final double textHeight = (nameFontSize * 1.25 * nameMaxLines) +
            textGap +
            (priceFontSize * 1.25) +
            textVerticalPadding +
            safetyBuffer;

        // Tinggi total cell = gambar square (= cellWidth) + area teks
        final double cellHeight = cellWidth + textHeight;
        final double childAspectRatio = cellWidth / cellHeight;

        return GridView.builder(
          padding: EdgeInsets.all(gridPadding),
          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
            crossAxisCount: columns,
            mainAxisSpacing: spacing,
            crossAxisSpacing: spacing,
            childAspectRatio: childAspectRatio,
          ),
          itemCount: products.length,
          itemBuilder: (_, i) {
            final p = products[i];
            final imageUrl = p['image']?.toString() ?? '';
            final nama = p['nama']?.toString() ?? '';
            final kode = p['kode']?.toString() ?? '';
            final hpj = (p['hpj'] as num? ?? 0).toDouble();

            // isProcessing: kode ini sendiri lagi diproses, ATAU ada
            // operasi cart lain (ganti channel/insert/qty/voucher) yang
            // masih berjalan — lihat guard _isCartSyncing di _insertProduk.
            final isProcessing =
                _processingKodes.contains(kode) || _isCartSyncing;

            return GestureDetector(
              onTap: isProcessing ? null : () => _insertProduk(kode),
              child: Opacity(
                opacity: isProcessing ? 0.55 : 1.0,
                child: Card(
                  elevation: 2,
                  clipBehavior: Clip.antiAlias,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Stack(
                    children: [
                      Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          // ── Gambar square (1:1) ──
                          AspectRatio(
                            aspectRatio: 1,
                            child: CachedNetworkImage(
                              imageUrl: imageUrl,
                              fit: BoxFit.cover,
                              fadeInDuration: const Duration(milliseconds: 200),
                              placeholder: (_, __) => Container(
                                color: Colors.grey.shade100,
                                child: const Center(
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                  ),
                                ),
                              ),
                              errorWidget: (_, __, ___) => Container(
                                color: Colors.grey.shade200,
                                child: const Icon(
                                  Icons.broken_image,
                                  color: Colors.grey,
                                  size: 32,
                                ),
                              ),
                            ),
                          ),
                          Container(
                            padding: EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: textVerticalPadding / 2,
                            ),
                            color: Colors.white,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  nama,
                                  maxLines: nameMaxLines,
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontSize: nameFontSize,
                                    fontWeight: FontWeight.w600,
                                    height: 1.25,
                                  ),
                                ),
                                SizedBox(height: textGap),
                                Text(
                                  'Rp ${CurrencyFormat.format(hpj)}',
                                  style: TextStyle(
                                    fontSize: priceFontSize,
                                    color: const Color(0xFF1D273B),
                                    fontWeight: FontWeight.bold,
                                    height: 1.25,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      // Spinner overlay saat sedang diproses
                      if (isProcessing)
                        const Positioned.fill(
                          child: Center(
                            child: CircularProgressIndicator(
                              strokeWidth: 2.5,
                              color: Color(0xFF1D273B),
                            ),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            );
          },
        );
      },
    );
  }

  // ============================================================
  // CART LIST
  // ============================================================
}
