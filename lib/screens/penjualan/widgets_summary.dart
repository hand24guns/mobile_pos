// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Layout side-by-side & stacked, summary, tombol aksi (Bayar/Pending).
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanSummaryWidgetsX on _PenjualanScreenState {
  Widget _buildStackedLayout(PenjualanState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        // constraints.maxHeight = tinggi yang tersedia setelah SafeArea + AppBar
        final availableHeight = constraints.maxHeight;
        if (_bodyHeight != availableHeight) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setState(() => _bodyHeight = availableHeight);
          });
        }

        // ── Image grid dibatasi maksimal 2 baris produk di portrait ──
        // Dulu grid pakai Expanded penuh, jadi di layar tinggi (tablet
        // 10"+) grid bisa memanjang sampai 4-5 baris, "mencuri" ruang
        // dari panel cart di bawahnya (yang akhirnya cuma kebagian
        // 200-280dp fixed, sering cuma cukup 1 row cart terlihat).
        // Sekarang tingginya dibatasi lewat ConstrainedBox, sisa ruang
        // (availableHeight - header - grid - divider) sepenuhnya jadi
        // milik panel bawah (cart + summary + tombol) lewat Expanded,
        // jadi cart bisa menampilkan 2 row (atau lebih) juga.
        //
        // Landscape TIDAK terpengaruh — _buildSideBySideLayout tetap
        // pakai Expanded penuh seperti sebelumnya.
        final imageGridMaxHeight =
            _stackedImageGridMaxHeight(constraints.maxWidth);

        return Column(
          children: [
            _buildHeader(state),
            ConstrainedBox(
              constraints: BoxConstraints(maxHeight: imageGridMaxHeight),
              child: _buildImageGrid(),
            ),
            Container(height: 1, color: Colors.grey.shade300),
            // Panel bawah (cart + summary + tombol) sekarang Expanded —
            // otomatis dapat semua sisa tinggi layar setelah header +
            // grid (yang sudah dibatasi 2 baris di atas), bukan lagi
            // dibatasi angka fixed 200-280dp.
            Expanded(
              child: LayoutBuilder(
                builder: (context, bottomConstraints) {
                  final bottomPanelHeight = bottomConstraints.maxHeight;
                  return Column(
                    children: [
                      Expanded(
                        child: RefreshIndicator(
                          onRefresh: _checkShiftStillActive,
                          color: const Color(0xFF1D273B),
                          child: _buildCartMobile(state),
                        ),
                      ),
                      Container(height: 1, color: Colors.grey.shade300),
                      // Budget riil summary = tinggi panel bawah yang
                      // benar-benar tersedia (bukan fraksi tinggi layar
                      // penuh) dikurangi perkiraan tinggi tombol aksi,
                      // supaya summary gak "mikir" dia boleh lebih besar
                      // dari ruang yang benar-benar tersisa untuk dia + cart.
                      _buildSummaryScrollable(
                        state,
                        availableHeight,
                        maxHeightOverride:
                            (bottomPanelHeight - _buttonHeight - 24)
                                .clamp(80.0, bottomPanelHeight),
                      ),
                      Container(height: 1, color: Colors.grey.shade300),
                      _buildActionButtons(state),
                    ],
                  );
                },
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // LAYOUT SIDE-BY-SIDE — landscape (semua ukuran)
  // Menggunakan LayoutBuilder agar summary panel kanan tidak
  // overflow ke bawah navbar saat di landscape dengan 3-button nav.
  // Di layar kecil (7") header compact aktif sehingga product grid
  // mendapat ruang yang cukup untuk terlihat.
  // ============================================================
  Widget _buildSideBySideLayout(PenjualanState state) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final availableHeight = constraints.maxHeight;
        // Isi _bodyHeight agar _isTinyTablet / _isSmallTablet / _isCompactHeader
        // pakai nilai yang sudah dikurangi AppBar + SafeArea (termasuk navbar).
        if (_bodyHeight != availableHeight) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _setState(() => _bodyHeight = availableHeight);
          });
        }

        return Row(
          children: [
            // ── KOLOM KIRI — identitas + product image grid ──
            Expanded(
              child: Column(
                children: [
                  _buildHeader(state),
                  Expanded(child: _buildImageGrid()),
                ],
              ),
            ),
            Container(width: 1, color: Colors.grey.shade300),
            // ── KOLOM KANAN — cart list + summary + action buttons ──
            SizedBox(
              width: _rightPanelWidth,
              child: Column(
                children: [
                  Expanded(
                    child: RefreshIndicator(
                      onRefresh: _checkShiftStillActive,
                      color: const Color(0xFF1D273B),
                      child: _buildCart(state),
                    ),
                  ),
                  Container(height: 1, color: Colors.grey.shade300),
                  _buildSummaryScrollable(state, availableHeight),
                  Container(height: 1, color: Colors.grey.shade300),
                  // Tombol PENDING + BAYAR dipinned di sini — selalu terlihat
                  // meskipun summary panjang / layar landscape kecil / 3-button navbar
                  _buildActionButtons(state),
                ],
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // SUMMARY SCROLLABLE WRAPPER
  // Compact mode (landscape kecil): maxHeight diperkecil agar
  // cart masih punya ruang yang cukup di atas summary.
  // ============================================================
  // maxHeightOverride: dipakai saat pemanggil sudah tahu budget riil yang
  // tersisa untuk summary (mis. di portrait, di dalam bottomPanelHeight
  // yang terbatas) — supaya summary tidak menghitung ulang dari fraksi
  // tinggi layar PENUH (yang bisa lebih besar dari budget aslinya dan
  // "mencuri" ruang dari cart). Kalau null, perilaku lama (fraksi dari
  // availableHeight) tetap dipakai — dipakai di layout landscape.
  Widget _buildSummaryScrollable(
    PenjualanState state,
    double availableHeight, {
    double? maxHeightOverride,
  }) {
    final keyboardHeight = MediaQuery.of(context).viewInsets.bottom;
    // Compact landscape: summary ringkas, beri maks ~50% tinggi
    // Normal landscape : ~60%
    // Portrait         : ~45%
    final double maxFraction;
    if (_isCompactHeader) {
      maxFraction = 0.52;
    } else if (_isLandscape) {
      maxFraction = 0.60;
    } else {
      maxFraction = 0.45;
    }

    final maxHeight = maxHeightOverride ?? (availableHeight * maxFraction);

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: maxHeight),
      child: SingleChildScrollView(
        padding: EdgeInsets.only(bottom: keyboardHeight),
        child: _buildSummary(state),
      ),
    );
  }

  // ============================================================
  // SUMMARY PANEL (kanan)
  // Compact mode: sembunyikan baris Gross/Diskon/DPP/Pajak agar
  // panel summary lebih pendek di layar landscape kecil.
  // ============================================================
  Widget _buildSummary(PenjualanState state) {
    // Compact sebelumnya cuma ke-trigger di landscape (_isCompactHeader).
    // Di portrait sempit (hp, _screenWidth < 600 → _isTinyTablet), summary
    // tetap nampilin detail Gross/Diskon/DPP/Pajak lengkap + padding besar
    // — inilah salah satu penyebab cart kepotong habis di hp portrait.
    // Sekarang portrait sempit ikut dianggap compact juga.
    final compact = _isCompactHeader || (!_isLandscape && _isTinyTablet);

    final isCash = _isCashCaraBayarId(state.caraBayarID);
    final isNonCash = state.caraBayarID != 0 && !isCash;

    // Non-cash: nominal selalu mengikuti total (termasuk saat total berubah
    // karena tambah/hapus item, voucher, ganti channel, dsb).
    if (isNonCash && state.nominalBayar != state.total) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final s = ref.read(penjualanProvider);
        if (_isCashCaraBayarId(s.caraBayarID)) return; // keburu pindah ke cash
        ref.read(penjualanProvider.notifier).setNominalBayar(s.total);
        _nominalController.text =
            CurrencyInputFormatter.thousands(s.total.toStringAsFixed(0));
      });
    }

    final inputDeco = InputDecoration(
      border: const OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(
        horizontal: 10,
        vertical: compact ? 6 : 8,
      ),
      isDense: true,
    );

    return Container(
      color: Colors.white,
      padding: compact ? _compactPadding : _panelPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // ── Total baris (selalu terlihat) ──
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'TOTAL',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: _labelFontSize,
                ),
              ),
              Text(
                'Rp ${CurrencyFormat.format(state.total)}',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: _labelFontSize,
                ),
              ),
            ],
          ),

          // ── Detail baris — sembunyikan di compact ──
          if (!compact) ...[
            const Divider(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Gross'),
                Text('Rp ${CurrencyFormat.format(state.gross)}'),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Diskon'),
                Text('Rp ${CurrencyFormat.format(state.diskon)}'),
              ],
            ),
            const Divider(height: 12),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'DPP',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: _smallFontSize,
                  ),
                ),
                Text(
                  'Rp ${CurrencyFormat.format(state.dpp)}',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: _smallFontSize,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 3),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  'Pajak',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: _smallFontSize,
                  ),
                ),
                Text(
                  'Rp ${CurrencyFormat.format(state.pajak)}',
                  style: TextStyle(
                    color: Colors.grey,
                    fontSize: _smallFontSize,
                  ),
                ),
              ],
            ),
          ] else ...[
            // Di compact: tampilkan DPP+Pajak ringkas 1 baris
            if (state.pajak > 0)
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    'Pajak',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: _smallFontSize,
                    ),
                  ),
                  Text(
                    'Rp ${CurrencyFormat.format(state.pajak)}',
                    style: TextStyle(
                      color: Colors.grey,
                      fontSize: _smallFontSize,
                    ),
                  ),
                ],
              ),
          ],

          SizedBox(height: compact ? 6 : 8),

          // Cara Bayar
          DropdownButtonFormField<int>(
            initialValue: state.caraBayarID == 0 ? null : state.caraBayarID,
            decoration: inputDeco.copyWith(labelText: 'Cara Bayar'),
            style: TextStyle(fontSize: _labelFontSize, color: Colors.black87),
            items: _caraBayarList.map((c) {
              return DropdownMenuItem<int>(
                value: int.parse(c['dim_carabayar_id'].toString()),
                child: Text(
                  c['nama'],
                  style: TextStyle(fontSize: _labelFontSize),
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                ref.read(penjualanProvider.notifier).setCaraBayar(val);
                final currentTotal = ref.read(penjualanProvider).total;
                _nominalController.text = CurrencyInputFormatter.thousands(
                  currentTotal.toStringAsFixed(0),
                );
                ref
                    .read(penjualanProvider.notifier)
                    .setNominalBayar(currentTotal);
              }
            },
          ),
          SizedBox(height: compact ? 5 : 8),

          // Nominal Bayar
          TextField(
            controller: _nominalController,
            readOnly: isNonCash, // non-cash: nominal terkunci = total
            keyboardType: TextInputType.number,
            style: TextStyle(
              fontSize: _labelFontSize,
              color: isNonCash ? Colors.grey.shade600 : Colors.black87,
            ),
            inputFormatters: [
              FilteringTextInputFormatter.digitsOnly,
              CurrencyInputFormatter(),
            ],
            decoration: inputDeco.copyWith(
              labelText: 'Nominal Bayar',
              prefixText: 'Rp ',
            ),
            onChanged: (val) {
              final nominal = CurrencyInputFormatter.toNumber(val);
              ref
                  .read(penjualanProvider.notifier)
                  .setNominalBayar(nominal.toDouble());
            },
          ),
        ],
      ),
    );
  }

  // ============================================================
  // Label tombol — ganti jadi spinner kecil selama _isCartSyncing
  // (mis. lagi recalculate channel / insert produk / apply voucher)
  // supaya kasir tahu ini "lagi proses", bukan tombol yang error.
  // ============================================================
  Widget _actionButtonChild(String label, double fontSize) {
    if (_isCartSyncing) {
      return const SizedBox(
        height: 16,
        width: 16,
        child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2),
      );
    }
    return Text(
      label,
      style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold, fontSize: fontSize),
    );
  }

  // ============================================================
  // ACTION BUTTONS — PENDING + BAYAR (pinned fixed footer)
  // Compact mode: 2 tombol sejajar horizontal agar hemat tinggi.
  //
  // Kedua tombol ikut ter-disable selama _isCartSyncing (ada
  // operasi cart yang masih berjalan — insert produk, update qty,
  // ganti channel, voucher, dsb) supaya tidak simpan pending/bayar
  // dengan harga yang belum sempat ter-update di server.
  // ============================================================
  Widget _buildActionButtons(PenjualanState state) {
    final compact = _isCompactHeader;
    final vPad = compact ? 6.0 : 8.0;
    final canTap = state.items.isNotEmpty && !_isCartSyncing;

    return Container(
      color: Colors.white,
      padding: EdgeInsets.fromLTRB(
        compact ? 8 : _panelPadding.left,
        vPad,
        compact ? 8 : _panelPadding.right,
        compact ? 6 : _panelPadding.bottom,
      ),
      child: compact
          // ── Landscape kecil: tombol sejajar ──
          ? Row(
              children: [
                Expanded(
                  child: SizedBox(
                    height: _buttonHeight,
                    child: ElevatedButton(
                      onPressed: canTap ? _showPendingDialog : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: Colors.red,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: _actionButtonChild('PENDING', _labelFontSize),
                    ),
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: SizedBox(
                    height: _buttonHeight,
                    child: ElevatedButton(
                      onPressed: canTap ? _prosesBayar : null,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFF1D273B),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(6),
                        ),
                        padding: EdgeInsets.zero,
                      ),
                      child: _actionButtonChild('BAYAR', _labelFontSize),
                    ),
                  ),
                ),
              ],
            )
          // ── Portrait / tablet besar: tombol vertikal ──
          : Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                SizedBox(
                  width: double.infinity,
                  height: _buttonHeight,
                  child: ElevatedButton(
                    onPressed: canTap ? _showPendingDialog : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.red,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _actionButtonChild('PENDING PAYMENT', _labelFontSize),
                  ),
                ),
                const SizedBox(height: 8),
                SizedBox(
                  width: double.infinity,
                  height: _buttonHeight,
                  child: ElevatedButton(
                    onPressed: canTap ? _prosesBayar : null,
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF1D273B),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(8),
                      ),
                    ),
                    child: _actionButtonChild('BAYAR', _labelFontSize),
                  ),
                ),
              ],
            ),
    );
  }

}
