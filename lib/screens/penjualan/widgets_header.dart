// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Header full & compact (store info, channel, member, sku search).
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanHeaderWidgetsX on _PenjualanScreenState {
  // ============================================================
  // HANDLER GANTI CHANNEL — dipakai baik oleh header full maupun
  // compact. Dibungkus _runCartMutation supaya tombol Pending/Bayar
  // otomatis ter-disable selama recalculateChannel berjalan —
  // mencegah kasir simpan pending dengan harga channel lama kalau
  // keburu pencet Pending sebelum harga baru selesai ter-update
  // di server.
  // ============================================================
  Future<void> _onChannelChanged(int? val) async {
    if (val == null) return;
    ref.read(penjualanProvider.notifier).setSalesTipe(val);

    final state = ref.read(penjualanProvider);
    if (state.items.isNotEmpty) {
      await _runCartMutation(() async {
        try {
          final dio = ApiService.getDio(token: _token);
          await dio.post(
            '/penjualan.php',
            data: FormData.fromMap({
              'action': 'recalculateChannel',
              'number': state.number,
              'salestipe_id': val,
              'store_id': state.storeID,
              'organisasi_id': state.organisasiID,
              'device_token': _deviceToken,
            }),
          );
          await _refreshFromApi();
        } catch (_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(
                content: Text(
                  'Gagal update harga channel — coba ganti channel lagi',
                ),
                backgroundColor: Colors.red,
              ),
            );
          }
        }
      });
    }
    _loadImageProducts();
    _focusSku();
  }

  // Header SELALU menggunakan input box (bukan ikon) untuk Member,
  // Voucher, Retur, dan Keterangan — termasuk pada tablet 7" dengan
  // 3-button navigation (body ~390-530dp landscape). Untuk ruang yang
  // sangat sempit, _buildHeaderCompact memangkas padding/ukuran font
  // via flag `ultraCompact` di dalamnya, bukan mengganti field jadi ikon.
  Widget _buildHeader(PenjualanState state) {
    if (_isCompactHeader) return _buildHeaderCompact(state);
    return _buildHeaderFull(state);
  }


  // ── FULL HEADER (portrait / tablet besar) ───────────────────
  Widget _buildHeaderFull(PenjualanState state) {
    // Dekorasi input kompak — tanpa labelText (pakai hintText saja)
    // agar tidak ada float label yang makan tinggi ekstra.
    const inputDeco = InputDecoration(
      border: OutlineInputBorder(),
      contentPadding: EdgeInsets.symmetric(horizontal: 10, vertical: 7),
      isDense: true,
    );

    return Container(
      color: Colors.white,
      padding: _panelPadding,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Baris 1: Store + No. Invoice inline (teks kecil, 1 baris) ──
          Row(
            children: [
              const Icon(Icons.store_outlined, size: 14, color: Colors.grey),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  state.storeName,
                  style: TextStyle(
                    fontSize: _labelFontSize,
                    fontWeight: FontWeight.w600,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 8),
              Text(
                state.number,
                style: TextStyle(
                  fontSize: _smallFontSize,
                  color: Colors.grey.shade600,
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Baris 2: Channel ──
          // Dropdown ikut ter-disable selama _isCartSyncing agar kasir
          // tidak bisa ganti channel lagi sebelum recalculateChannel
          // sebelumnya selesai (mencegah request overlap).
          DropdownButtonFormField<int>(
            initialValue: state.salesTipeID,
            decoration: inputDeco.copyWith(hintText: 'Channel'),
            items: _channels.map((c) {
              return DropdownMenuItem<int>(
                value: int.parse(c['dim_salestipe_id'].toString()),
                child: Text(c['nama']),
              );
            }).toList(),
            onChanged: _isCartSyncing ? null : _onChannelChanged,
          ),
          const SizedBox(height: 6),

          // ── Baris 3: Member | Voucher | Retur ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberController,
                  decoration: inputDeco.copyWith(
                    hintText: 'Member (opsional)',
                    prefixIcon: state.memberID != null
                        ? IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 16,
                              color: Colors.red,
                            ),
                            tooltip: 'Hapus member',
                            onPressed: () {
                              _memberController.clear();
                              ref
                                  .read(penjualanProvider.notifier)
                                  .setMember(null, '');
                            },
                          )
                        : IconButton(
                            icon: const Icon(
                              Icons.person_add,
                              size: 16,
                              color: Color(0xFF1D273B),
                            ),
                            tooltip: 'Tambah member baru',
                            onPressed: _showAddMemberSheet,
                          ),
                    suffixIcon: const Icon(Icons.search, size: 16),
                  ),
                  onSubmitted: (val) async {
                    if (val.isEmpty) return;
                    final dio = ApiService.getDio(token: _token);
                    final res = await dio.post(
                      '/penjualan.php',
                      data: FormData.fromMap({
                        'action': 'searchMember',
                        'term': val,
                        'organisasi_id': state.organisasiID,
                      }),
                    );
                    final data = List<Map<String, dynamic>>.from(
                      res.data['data'],
                    );
                    if (data.isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Member tidak ditemukan'),
                          ),
                        );
                      }
                      return;
                    }
                    if (mounted) {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => ListView.builder(
                          itemCount: data.length,
                          itemBuilder: (_, i) {
                            final m = data[i];
                            return ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(m['nama']),
                              subtitle: Text(m['telp']),
                              onTap: () {
                                Navigator.pop(context);
                                _memberController.text =
                                    '${m['nama']} - ${m['telp']}';
                                ref
                                    .read(penjualanProvider.notifier)
                                    .setMember(
                                      int.parse(m['dim_bp_id'].toString()),
                                      m['nama'],
                                    );
                                _focusSku();
                              },
                            );
                          },
                        ),
                      );
                    }
                  },
                ),
              ),
              const SizedBox(width: 8),
              // Voucher badge
              Stack(
                children: [
                  OutlinedButton.icon(
                    onPressed: _showVoucherDialog,
                    icon: const Icon(
                      Icons.confirmation_number_outlined,
                      size: 16,
                    ),
                    label: const Text('Voucher'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 9,
                      ),
                      foregroundColor:
                          _activeVoucher.isNotEmpty ? Colors.indigo : null,
                      side: _activeVoucher.isNotEmpty
                          ? const BorderSide(color: Colors.indigo)
                          : null,
                    ),
                  ),
                  if (_activeVoucher.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 8,
                        height: 8,
                        decoration: const BoxDecoration(
                          color: Colors.indigo,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              const SizedBox(width: 8),
              OutlinedButton.icon(
                onPressed: _showReturDialog,
                icon: const Icon(Icons.assignment_return_outlined, size: 16),
                label: const Text('Retur'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 9,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),

          // ── Baris 4: Keterangan | Cari SKU (2 kolom dalam 1 baris) ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keteranganController,
                  decoration: inputDeco.copyWith(
                    hintText: 'Keterangan (opsional)',
                    prefixIcon:
                        const Icon(Icons.notes_outlined, size: 16),
                  ),
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                  onSubmitted: (_) => _focusSku(),
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _skuController,
                  focusNode: _skuFocusNode,
                  keyboardType: _skuKeyboardVisible
                      ? TextInputType.text
                      : TextInputType.none,
                  onTap: _focusSkuWithKeyboard,
                  decoration: inputDeco.copyWith(
                    hintText: 'Cari produk (nama / SKU)',
                    prefixIcon:
                        const Icon(Icons.qr_code_scanner, size: 16),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, size: 18),
                      onPressed: () =>
                          _searchProduk(_skuController.text.trim()),
                    ),
                  ),
                  onSubmitted: (val) {
                    _searchProduk(val.trim());
                    _setState(() => _skuKeyboardVisible = false);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── COMPACT HEADER (landscape kecil/sedang, termasuk tablet 7" ──
  // dengan 3-button navigation, body ~390-620dp) ───────────────────
  // Tetap 3 baris input box biasa (Store+Channel / Member+Voucher+Retur /
  // Keterangan+SKU) seperti layout besar — hanya lebih ringkas.
  // Saat ruang sangat sempit (`ultraCompact`, body < 520dp — kasus
  // umum tablet 7" 3-button nav), padding/font dipangkas lebih jauh
  // agar tetap muat, TANPA mengubah field jadi ikon.
  Widget _buildHeaderCompact(PenjualanState state) {
    final ultraCompact = _isHeaderTiny;
    final p = _compactPadding;
    final fieldVPad = ultraCompact ? 4.0 : 6.0;
    final rowGap = ultraCompact ? 3.0 : 5.0;
    final fontSize = ultraCompact ? 11.0 : _labelFontSize;
    final smallFont = ultraCompact ? 9.5 : _smallFontSize;
    final iconSize = ultraCompact ? 14.0 : 16.0;

    final inputDeco = InputDecoration(
      border: const OutlineInputBorder(),
      contentPadding:
          EdgeInsets.symmetric(horizontal: 10, vertical: fieldVPad),
      isDense: true,
    );

    return Container(
      color: Colors.white,
      padding: p,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // ── Baris A: Store | No.Invoice | Channel ──
          Row(
            children: [
              // Store + Invoice (compact inline)
              Expanded(
                flex: 2,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      state.storeName,
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: fontSize,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      state.number,
                      style: TextStyle(
                        fontSize: smallFont,
                        color: Colors.grey,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Channel dropdown — hintText saja (bukan labelText) agar
              // tidak ada floating label yang makan tinggi ekstra.
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int>(
                  initialValue: state.salesTipeID,
                  decoration: inputDeco.copyWith(hintText: 'Channel'),
                  style: TextStyle(
                    fontSize: fontSize,
                    color: Colors.black87,
                  ),
                  isDense: true,
                  items: _channels.map((c) {
                    return DropdownMenuItem<int>(
                      value: int.parse(c['dim_salestipe_id'].toString()),
                      child: Text(
                        c['nama'],
                        style: TextStyle(fontSize: fontSize),
                      ),
                    );
                  }).toList(),
                  onChanged: _isCartSyncing ? null : _onChannelChanged,
                ),
              ),
            ],
          ),
          SizedBox(height: rowGap),

          // ── Baris B: Member | Voucher | Retur ──
          // Ketiganya tetap berupa input box / tombol berlabel biasa,
          // hanya dipadatkan (padding & font lebih kecil di ultraCompact).
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _memberController,
                  style: TextStyle(fontSize: fontSize),
                  decoration: inputDeco.copyWith(
                    hintText: 'Member',
                    prefixIcon: state.memberID != null
                        ? IconButton(
                            icon: Icon(Icons.close,
                                size: iconSize, color: Colors.red),
                            tooltip: 'Hapus member',
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              _memberController.clear();
                              ref
                                  .read(penjualanProvider.notifier)
                                  .setMember(null, '');
                            },
                          )
                        : IconButton(
                            icon: Icon(
                              Icons.person_add,
                              size: iconSize,
                              color: const Color(0xFF1D273B),
                            ),
                            tooltip: 'Tambah member baru',
                            padding: EdgeInsets.zero,
                            onPressed: _showAddMemberSheet,
                          ),
                    suffixIcon: Icon(Icons.search, size: iconSize),
                  ),
                  onSubmitted: (val) async {
                    if (val.isEmpty) return;
                    final dio = ApiService.getDio(token: _token);
                    final res = await dio.post(
                      '/penjualan.php',
                      data: FormData.fromMap({
                        'action': 'searchMember',
                        'term': val,
                        'organisasi_id': state.organisasiID,
                      }),
                    );
                    final data = List<Map<String, dynamic>>.from(
                      res.data['data'],
                    );
                    if (data.isEmpty) {
                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('Member tidak ditemukan'),
                          ),
                        );
                      }
                      return;
                    }
                    if (mounted) {
                      showModalBottomSheet(
                        context: context,
                        builder: (_) => ListView.builder(
                          itemCount: data.length,
                          itemBuilder: (_, i) {
                            final m = data[i];
                            return ListTile(
                              leading: const Icon(Icons.person),
                              title: Text(m['nama']),
                              subtitle: Text(m['telp']),
                              onTap: () {
                                Navigator.pop(context);
                                _memberController.text =
                                    '${m['nama']} - ${m['telp']}';
                                ref.read(penjualanProvider.notifier).setMember(
                                      int.parse(m['dim_bp_id'].toString()),
                                      m['nama'],
                                    );
                                _focusSku();
                              },
                            );
                          },
                        ),
                      );
                    }
                  },
                ),
              ),
              SizedBox(width: ultraCompact ? 4 : 6),
              // Voucher — tetap tombol berlabel (bukan ikon polos)
              Stack(
                clipBehavior: Clip.none,
                children: [
                  OutlinedButton.icon(
                    onPressed: _showVoucherDialog,
                    icon: Icon(
                      Icons.confirmation_number_outlined,
                      size: iconSize,
                    ),
                    label: Text(
                      'Voucher',
                      style: TextStyle(fontSize: smallFont),
                    ),
                    style: OutlinedButton.styleFrom(
                      padding: EdgeInsets.symmetric(
                        horizontal: ultraCompact ? 6 : 8,
                        vertical: fieldVPad,
                      ),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      foregroundColor:
                          _activeVoucher.isNotEmpty ? Colors.indigo : null,
                      side: _activeVoucher.isNotEmpty
                          ? const BorderSide(color: Colors.indigo)
                          : null,
                    ),
                  ),
                  if (_activeVoucher.isNotEmpty)
                    Positioned(
                      right: 0,
                      top: 0,
                      child: Container(
                        width: 7,
                        height: 7,
                        decoration: const BoxDecoration(
                          color: Colors.indigo,
                          shape: BoxShape.circle,
                        ),
                      ),
                    ),
                ],
              ),
              SizedBox(width: ultraCompact ? 4 : 6),
              // Retur — tetap tombol berlabel
              OutlinedButton.icon(
                onPressed: _showReturDialog,
                icon: Icon(Icons.assignment_return_outlined, size: iconSize),
                label: Text('Retur', style: TextStyle(fontSize: smallFont)),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: EdgeInsets.symmetric(
                    horizontal: ultraCompact ? 6 : 8,
                    vertical: fieldVPad,
                  ),
                  minimumSize: Size.zero,
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                ),
              ),
            ],
          ),
          SizedBox(height: rowGap),

          // ── Baris C: Keterangan | SKU Search (2-kolom) ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keteranganController,
                  style: TextStyle(fontSize: fontSize),
                  decoration: inputDeco.copyWith(
                    hintText: 'Keterangan',
                    prefixIcon: Icon(Icons.notes_outlined, size: iconSize),
                  ),
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                ),
              ),
              SizedBox(width: ultraCompact ? 4 : 6),
              Expanded(
                child: TextField(
                  controller: _skuController,
                  focusNode: _skuFocusNode,
                  style: TextStyle(fontSize: fontSize),
                  keyboardType: _skuKeyboardVisible
                      ? TextInputType.text
                      : TextInputType.none,
                  onTap: _focusSkuWithKeyboard,
                  decoration: inputDeco.copyWith(
                    hintText: 'Cari produk (nama / SKU)',
                    prefixIcon: Icon(Icons.qr_code_scanner, size: iconSize),
                    suffixIcon: IconButton(
                      icon: Icon(Icons.search, size: iconSize + 2),
                      padding: EdgeInsets.zero,
                      onPressed: () =>
                          _searchProduk(_skuController.text.trim()),
                    ),
                  ),
                  onSubmitted: (val) {
                    _searchProduk(val.trim());
                    _setState(() => _skuKeyboardVisible = false);
                  },
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }


  // ============================================================
  // PRODUCT IMAGE GRID (kiri bawah)
  // ============================================================

}
