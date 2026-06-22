// AUTO-SPLIT FROM penjualan_screen.dart — bagian: Header full & compact (store info, channel, member, sku search).
// Berisi method/widget yang dipindah ke extension agar file utama lebih ringkas.
// Behavior identik dengan versi monolitik sebelumnya.
part of 'penjualan_screen.dart';

extension PenjualanHeaderWidgetsX on _PenjualanScreenState {
  Widget _buildHeader(PenjualanState state) {
    if (_isCompactHeader) return _buildHeaderCompact(state);
    return _buildHeaderFull(state);
  }

  // ── FULL HEADER (portrait / tablet besar) ───────────────────
  Widget _buildHeaderFull(PenjualanState state) {
    return Container(
      color: Colors.white,
      padding: _panelPadding,
      child: Column(
        children: [
          // Row 1: Store + Invoice
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Store',
                      style: TextStyle(fontSize: 11, color: Colors.grey),
                    ),
                    Text(
                      state.storeName,
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                  ],
                ),
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  const Text(
                    'No. Invoice',
                    style: TextStyle(fontSize: 11, color: Colors.grey),
                  ),
                  Text(
                    state.number,
                    style: const TextStyle(fontWeight: FontWeight.bold),
                  ),
                ],
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 2: Channel
          DropdownButtonFormField<int>(
            initialValue: state.salesTipeID,
            decoration: const InputDecoration(
              labelText: 'Channel',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
            ),
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

              // Recalculate harga cart jika sudah ada item
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

              // Reload grid produk agar harga tile ikut berubah
              _loadImageProducts();
            },
          ),
          const SizedBox(height: 8),

          // Row 3: Member (search + add baru) + Voucher + Retur
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _memberController,
                  decoration: InputDecoration(
                    labelText: 'Member (opsional)',
                    border: const OutlineInputBorder(),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    isDense: true,
                    // ── Ikon di kiri: add member / clear ──────────
                    prefixIcon: state.memberID != null
                        ? IconButton(
                            icon: const Icon(
                              Icons.close,
                              size: 18,
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
                              size: 18,
                              color: Color(0xFF1D273B),
                            ),
                            tooltip: 'Tambah member baru',
                            onPressed: _showAddMemberSheet,
                          ),
                    // ── Ikon search di kanan ─────────────────────
                    suffixIcon: const Icon(Icons.search, size: 18),
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
              // Voucher badge jika aktif
              Stack(
                children: [
                  OutlinedButton.icon(
                    onPressed: _showVoucherDialog,
                    icon: const Icon(
                      Icons.confirmation_number_outlined,
                      size: 18,
                    ),
                    label: const Text('Voucher'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 12,
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
                icon: const Icon(Icons.assignment_return_outlined, size: 18),
                label: const Text('Retur'),
                style: OutlinedButton.styleFrom(
                  foregroundColor: Colors.red,
                  side: const BorderSide(color: Colors.red),
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 12,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),

          // Row 3.5: Keterangan Transaksi
          TextField(
            controller: _keteranganController,
            decoration: const InputDecoration(
              labelText: 'Keterangan transaksi (opsional)',
              border: OutlineInputBorder(),
              contentPadding: EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              isDense: true,
              prefixIcon: Icon(Icons.notes_outlined, size: 18),
            ),
            maxLines: 1,
            textInputAction: TextInputAction.done,
          ),
          const SizedBox(height: 8),

          // Row 4: SKU Search
          TextField(
            controller: _skuController,
            decoration: InputDecoration(
              labelText: 'Cari produk (nama / SKU)',
              border: const OutlineInputBorder(),
              contentPadding: const EdgeInsets.symmetric(
                horizontal: 12,
                vertical: 8,
              ),
              isDense: true,
              suffixIcon: IconButton(
                icon: const Icon(Icons.search),
                onPressed: () => _searchProduk(_skuController.text.trim()),
              ),
            ),
            onSubmitted: (val) => _searchProduk(val.trim()),
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
