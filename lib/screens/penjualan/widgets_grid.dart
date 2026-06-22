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
          // Tab bar kategori
          Container(
            color: Colors.white,
            child: TabBar(
              isScrollable: true,
              tabAlignment: TabAlignment.start,
              labelColor: const Color(0xFF1D273B),
              unselectedLabelColor: Colors.grey,
              indicatorColor: const Color(0xFF1D273B),
              labelStyle: TextStyle(
                fontSize: _isTinyTablet ? 11 : 13,
                fontWeight: FontWeight.w600,
              ),
              unselectedLabelStyle: TextStyle(
                fontSize: _isTinyTablet ? 11 : 13,
              ),
              tabs: _imageCategories
                  .map((cat) => Tab(text: cat['nama']?.toString() ?? ''))
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

  /// Grid produk gambar (dipakai oleh _buildImageGrid)
  Widget _buildProductGrid(List<Map<String, dynamic>> products) {
    return GridView.builder(
      padding: EdgeInsets.all(_isTinyTablet ? 6 : 10),
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: _gridColumns,
        mainAxisSpacing: _isTinyTablet ? 6 : 10,
        crossAxisSpacing: _isTinyTablet ? 6 : 10,
        childAspectRatio: 0.72,
      ),
      itemCount: products.length,
      itemBuilder: (_, i) {
        final p = products[i];
        final imageUrl = p['image']?.toString() ?? '';
        final nama = p['nama']?.toString() ?? '';
        final kode = p['kode']?.toString() ?? '';
        final hpj = (p['hpj'] as num? ?? 0).toDouble();

        final isProcessing = _processingKodes.contains(kode);

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
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      Expanded(
                        child: CachedNetworkImage(
                          imageUrl: imageUrl,
                          fit: BoxFit.cover,
                          // fadeIn agar transisi halus saat pertama load
                          fadeInDuration: const Duration(milliseconds: 200),
                          placeholder: (_, __) => Container(
                            color: Colors.grey.shade100,
                            child: const Center(
                              child: CircularProgressIndicator(strokeWidth: 2),
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: 6,
                          vertical: 5,
                        ),
                        color: Colors.white,
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              nama,
                              maxLines: 2,
                              overflow: TextOverflow.ellipsis,
                              style: const TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                            const SizedBox(height: 2),
                            Text(
                              'Rp ${CurrencyFormat.format(hpj)}',
                              style: const TextStyle(
                                fontSize: 11,
                                color: Color(0xFF1D273B),
                                fontWeight: FontWeight.bold,
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
  }

  // ============================================================
  // CART LIST
  // ============================================================

}
