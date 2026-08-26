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

        // Panel bawah (cart + summary + tombol) diberi tinggi cukup untuk
        // menampilkan cart minimal 2 item + summary + tombol, tanpa
        // "mencuri" terlalu banyak ruang dari grid produk di atas.
        //
        // Rumus: gunakan sisa setelah grid diprioritaskan minimal 2 baris.
        // - 1 baris grid ≈ (lebar panel / 4 kolom) + teks ~45dp
        //   Pada portrait 7" (~600dp wide setelah right panel): cell ~130dp
        // - 2 baris grid = ~260dp + tab bar ~40dp + header ~170dp = ~470dp
        // - Sisa untuk bottom: availableHeight - 470, minimum 220dp
        //   (cukup untuk 2 item cart + summary ringkas + tombol)
        //
        // Alternatif lebih simpel: clamp antara 200–280dp.
        // 7" portrait body ~600dp → bottom 230dp → grid sisa 370dp → 2 baris
        // 10" portrait body ~900dp → bottom 280dp → grid sisa 620dp → 4+ baris
        final bottomPanelHeight = (availableHeight * 0.36).clamp(200.0, 280.0);

        return Column(
          children: [
            _buildHeader(state),
            Expanded(child: _buildImageGrid()),
            Container(height: 1, color: Colors.grey.shade300),
            SizedBox(
              height: bottomPanelHeight,
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
  Widget _buildSummaryScrollable(PenjualanState state, double availableHeight) {
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

    return ConstrainedBox(
      constraints: BoxConstraints(maxHeight: availableHeight * maxFraction),
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
    final compact = _isCompactHeader; // reuse flag
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
            keyboardType: TextInputType.number,
            style: TextStyle(fontSize: _labelFontSize),
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
