// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Header full & compact (store info, channel, member, sku search).
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanHeaderWidgetsX on _PenjualanScreenState {
  Widget _buildHeader(PenjualanState state) {
    if (_isHeaderTiny) return _buildHeaderTiny(state);
    if (_isCompactHeader) return _buildHeaderCompact(state);
    return _buildHeaderFull(state);
  }

  // ── TINY HEADER (7" landscape, semua nav type) ───────────────
  // 1 baris saja: store+channel+sku search dalam 1 Row horizontal.
  // Member, Voucher, Keterangan tersembunyi — akses via ikon kecil.
  // Tinggi total: ~52dp agar grid produk mendapat ≥300dp ruang
  // dan muat minimal 2 baris produk (cell ~183dp + spacing).
  Widget _buildHeaderTiny(PenjualanState state) {
    final inputDeco = InputDecoration(
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      isDense: true,
    );

    return Container(
      color: Colors.white,
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      child: Row(
        children: [
          // Store name + nomor invoice (teks sangat kecil)
          Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                state.storeName,
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                state.number,
                style: TextStyle(fontSize: 9, color: Colors.grey.shade500),
              ),
            ],
          ),
          const SizedBox(width: 8),

          // Channel dropdown — compact
          Expanded(
            flex: 3,
            child: DropdownButtonFormField<int>(
              initialValue: state.salesTipeID,
              decoration: inputDeco.copyWith(hintText: 'Channel'),
              style: const TextStyle(fontSize: 11, color: Colors.black87),
              isDense: true,
              items: _channels.map((c) {
                return DropdownMenuItem<int>(
                  value: int.parse(c['dim_salestipe_id'].toString()),
                  child: Text(c['nama'],
                      style: const TextStyle(fontSize: 11)),
                );
              }).toList(),
              onChanged: (val) async {
                if (val != null) {
                  ref.read(penjualanProvider.notifier).setSalesTipe(val);
                }
                final s = ref.read(penjualanProvider);
                if (s.items.isNotEmpty) {
                  try {
                    final dio = ApiService.getDio(token: _token);
                    await dio.post(
                      '/penjualan.php',
                      data: FormData.fromMap({
                        'action': 'recalculateChannel',
                        'number': s.number,
                        'salestipe_id': val,
                        'store_id': s.storeID,
                        'organisasi_id': s.organisasiID,
                        'device_token': _deviceToken,
                      }),
                    );
                    await _refreshFromApi();
                  } catch (_) {}
                }
                _loadImageProducts();
                _focusSku();
              },
            ),
          ),
          const SizedBox(width: 6),

          // ── Ikon-ikon aksi: Member | Voucher | Retur | Keterangan ──
          // Setiap ikon punya label teks kecil di bawahnya agar kasir baru
          // langsung tahu fungsinya tanpa harus long-press tooltip.
          _buildTinyIconBtn(
            icon: state.memberID != null
                ? Icons.person
                : Icons.person_outline,
            label: state.memberID != null ? 'Member ✓' : 'Member',
            color: state.memberID != null
                ? const Color(0xFF1D273B)
                : Colors.grey.shade600,
            badge: state.memberID != null,
            badgeColor: const Color(0xFF1D273B),
            onTap: () {
              if (state.memberID != null) {
                _memberController.clear();
                ref.read(penjualanProvider.notifier).setMember(null, '');
                _setState(() {});
              } else {
                _showMemberSearchSheet(state);
              }
            },
          ),
          _buildTinyIconBtn(
            icon: Icons.confirmation_number_outlined,
            label: 'Voucher',
            color: _activeVoucher.isNotEmpty
                ? Colors.indigo
                : Colors.grey.shade600,
            badge: _activeVoucher.isNotEmpty,
            badgeColor: Colors.indigo,
            onTap: _showVoucherDialog,
          ),
          _buildTinyIconBtn(
            icon: Icons.assignment_return_outlined,
            label: 'Retur',
            color: Colors.red.shade400,
            onTap: _showReturDialog,
          ),
          _buildTinyIconBtn(
            icon: _keteranganController.text.isNotEmpty
                ? Icons.edit_note
                : Icons.notes_outlined,
            label: 'Catatan',
            color: _keteranganController.text.isNotEmpty
                ? Colors.amber.shade700
                : Colors.grey.shade600,
            badge: _keteranganController.text.isNotEmpty,
            badgeColor: Colors.amber.shade700,
            onTap: _showKeteranganSheet,
          ),
          const SizedBox(width: 2),

          // Cari SKU — field utama untuk barcode scanner
          Expanded(
            flex: 4,
            child: TextField(
              controller: _skuController,
              focusNode: _skuFocusNode,
              decoration: inputDeco.copyWith(
                hintText: 'Cari / scan SKU',
                hintStyle: const TextStyle(fontSize: 11),
                prefixIcon: const Icon(Icons.qr_code_scanner, size: 16),
                suffixIcon: IconButton(
                  icon: const Icon(Icons.search, size: 16),
                  padding: EdgeInsets.zero,
                  onPressed: () =>
                      _searchProduk(_skuController.text.trim()),
                ),
              ),
              style: const TextStyle(fontSize: 11),
              onSubmitted: (val) => _searchProduk(val.trim()),
            ),
          ),
        ],
      ),
    );
  }

  // Helper: bottom sheet keterangan transaksi untuk _buildHeaderTiny
  void _showKeteranganSheet() {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
          left: 16,
          right: 16,
          top: 16,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'Keterangan Transaksi',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _keteranganController,
              autofocus: true,
              decoration: const InputDecoration(
                hintText: 'Catatan transaksi (opsional)...',
                border: OutlineInputBorder(),
                prefixIcon: Icon(Icons.notes_outlined),
              ),
              maxLines: 2,
              textInputAction: TextInputAction.done,
              onSubmitted: (_) {
                Navigator.pop(context);
                _setState(() {}); // refresh badge
                _focusSku();
              },
            ),
            const SizedBox(height: 10),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () {
                    _keteranganController.clear();
                    Navigator.pop(context);
                    _setState(() {}); // hapus badge
                    _focusSku();
                  },
                  child: const Text(
                    'Hapus',
                    style: TextStyle(color: Colors.red),
                  ),
                ),
                const SizedBox(width: 8),
                ElevatedButton(
                  onPressed: () {
                    Navigator.pop(context);
                    _setState(() {}); // refresh badge
                    _focusSku();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFF1D273B),
                  ),
                  child: const Text(
                    'Simpan',
                    style: TextStyle(color: Colors.white),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
          ],
        ),
      ),
    );
  }

  /// Widget ikon + label kecil di bawahnya untuk _buildHeaderTiny.
  /// Dipakai untuk Member, Voucher, Retur, Keterangan — agar kasir baru
  /// langsung tahu fungsi setiap ikon tanpa long-press.
  Widget _buildTinyIconBtn({
    required IconData icon,
    required String label,
    required Color color,
    required VoidCallback onTap,
    bool badge = false,
    Color badgeColor = Colors.red,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 3),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(icon, size: 18, color: color),
                const SizedBox(height: 1),
                Text(
                  label,
                  style: TextStyle(
                    fontSize: 8.5,
                    color: color,
                    fontWeight: FontWeight.w500,
                    height: 1.1,
                  ),
                ),
              ],
            ),
          ),
          if (badge)
            Positioned(
              right: 2,
              top: 0,
              child: Container(
                width: 7,
                height: 7,
                decoration: BoxDecoration(
                  color: badgeColor,
                  shape: BoxShape.circle,
                ),
              ),
            ),
        ],
      ),
    );
  }

  void _showMemberSearchSheet(PenjualanState state) {
    final searchCtrl = TextEditingController();
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (_) => Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.of(context).viewInsets.bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const SizedBox(height: 12),
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: TextField(
                controller: searchCtrl,
                autofocus: true,
                decoration: const InputDecoration(
                  labelText: 'Cari Member',
                  border: OutlineInputBorder(),
                  prefixIcon: Icon(Icons.search),
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
                  if (!mounted) return;
                  Navigator.pop(context);
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
                },
              ),
            ),
            const SizedBox(height: 16),
          ],
        ),
      ),
    );
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
          DropdownButtonFormField<int>(
            initialValue: state.salesTipeID,
            decoration: inputDeco.copyWith(hintText: 'Channel'),
            items: _channels.map((c) {
              return DropdownMenuItem<int>(
                value: int.parse(c['dim_salestipe_id'].toString()),
                child: Text(c['nama']),
              );
            }).toList(),
            onChanged: (val) async {
              if (val != null) {
                ref.read(penjualanProvider.notifier).setSalesTipe(val);
              }
              final state = ref.read(penjualanProvider);
              if (state.items.isNotEmpty) {
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
                } catch (_) {}
              }
              _loadImageProducts();
              _focusSku();
            },
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
                  onSubmitted: (val) => _searchProduk(val.trim()),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── COMPACT HEADER (landscape kecil/sedang ≤ 700dp height) ──
  // Layout 2-kolom agar total tinggi header ~120-140dp
  Widget _buildHeaderCompact(PenjualanState state) {
    final p = _compactPadding;
    final inputDeco = InputDecoration(
      border: const OutlineInputBorder(),
      contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
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
                child: Row(
                  children: [
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          state.storeName,
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: _labelFontSize,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                        Text(
                          state.number,
                          style: TextStyle(
                            fontSize: _smallFontSize,
                            color: Colors.grey,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              // Channel dropdown
              Expanded(
                flex: 3,
                child: DropdownButtonFormField<int>(
                  initialValue: state.salesTipeID,
                  decoration: inputDeco.copyWith(labelText: 'Channel'),
                  style: TextStyle(
                    fontSize: _labelFontSize,
                    color: Colors.black87,
                  ),
                  items: _channels.map((c) {
                    return DropdownMenuItem<int>(
                      value: int.parse(c['dim_salestipe_id'].toString()),
                      child: Text(
                        c['nama'],
                        style: TextStyle(fontSize: _labelFontSize),
                      ),
                    );
                  }).toList(),
                  onChanged: (val) async {
                    if (val != null) {
                      ref.read(penjualanProvider.notifier).setSalesTipe(val);
                    }
                    final state = ref.read(penjualanProvider);
                    if (state.items.isNotEmpty) {
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
                      } catch (_) {}
                    }
                    _loadImageProducts();
                    _focusSku();
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),

          // ── Baris B: Member | Voucher | Retur ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberController,
                  style: TextStyle(fontSize: _labelFontSize),
                  decoration: inputDeco.copyWith(
                    labelText: 'Member',
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
              const SizedBox(width: 6),
              // Voucher — icon only jika tiny
              Stack(
                children: [
                  _isTinyTablet
                      ? IconButton(
                          icon: Icon(
                            Icons.confirmation_number_outlined,
                            size: 22,
                            color: _activeVoucher.isNotEmpty
                                ? Colors.indigo
                                : Colors.grey.shade600,
                          ),
                          tooltip: 'Voucher',
                          onPressed: _showVoucherDialog,
                          padding: EdgeInsets.zero,
                          constraints: const BoxConstraints(
                            minWidth: 36,
                            minHeight: 36,
                          ),
                        )
                      : OutlinedButton.icon(
                          onPressed: _showVoucherDialog,
                          icon: const Icon(
                            Icons.confirmation_number_outlined,
                            size: 16,
                          ),
                          label: const Text('Voucher'),
                          style: OutlinedButton.styleFrom(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 8,
                            ),
                            foregroundColor: _activeVoucher.isNotEmpty
                                ? Colors.indigo
                                : null,
                            side: _activeVoucher.isNotEmpty
                                ? const BorderSide(color: Colors.indigo)
                                : null,
                            textStyle: TextStyle(fontSize: _smallFontSize),
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
              const SizedBox(width: 4),
              // Retur — icon only jika tiny
              _isTinyTablet
                  ? IconButton(
                      icon: const Icon(
                        Icons.assignment_return_outlined,
                        size: 22,
                        color: Colors.red,
                      ),
                      tooltip: 'Retur',
                      onPressed: _showReturDialog,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 36,
                        minHeight: 36,
                      ),
                    )
                  : OutlinedButton.icon(
                      onPressed: _showReturDialog,
                      icon: const Icon(
                        Icons.assignment_return_outlined,
                        size: 16,
                      ),
                      label: const Text('Retur'),
                      style: OutlinedButton.styleFrom(
                        foregroundColor: Colors.red,
                        side: const BorderSide(color: Colors.red),
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 8,
                        ),
                        textStyle: TextStyle(fontSize: _smallFontSize),
                      ),
                    ),
            ],
          ),
          const SizedBox(height: 5),

          // ── Baris C: Keterangan | SKU Search (2-kolom) ──
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _keteranganController,
                  style: TextStyle(fontSize: _labelFontSize),
                  decoration: inputDeco.copyWith(
                    labelText: 'Keterangan',
                    prefixIcon: const Icon(Icons.notes_outlined, size: 16),
                  ),
                  maxLines: 1,
                  textInputAction: TextInputAction.done,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: TextField(
                  controller: _skuController,
                  focusNode: _skuFocusNode,
                  style: TextStyle(fontSize: _labelFontSize),
                  decoration: inputDeco.copyWith(
                    labelText: 'Cari produk (nama / SKU)',
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, size: 18),
                      onPressed: () =>
                          _searchProduk(_skuController.text.trim()),
                    ),
                  ),
                  onSubmitted: (val) => _searchProduk(val.trim()),
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
