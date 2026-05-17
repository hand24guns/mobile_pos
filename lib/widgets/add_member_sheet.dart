import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import '../services/api_service.dart';

// ============================================================
// AddMemberSheet
//
// Dipanggil dari _PenjualanScreenState._showAddMemberSheet()
// Trigger: tap icon person_add di sebelah field member
//
// Flow:
//   1. User isi form (Nama*, HP*, Email, IG, Tgl Lahir)
//   2. Tap "Simpan"
//   3. POST cekHPMember → cek duplikat HP
//   4. POST insertMember → simpan ke dim_bp
//   5. Callback onSuccess(id, namaHP) → set member di state
// ============================================================

class AddMemberSheet extends StatefulWidget {
  final String token;
  final int organisasiID;

  /// Dipanggil setelah member berhasil disimpan.
  /// [memberID]  — dim_bp_id baru
  /// [display]   — string untuk ditampilkan di field member (nama - hp)
  /// [nama]      — nama saja (untuk provider)
  final void Function(int memberID, String display, String nama) onSuccess;

  const AddMemberSheet({
    super.key,
    required this.token,
    required this.organisasiID,
    required this.onSuccess,
  });

  @override
  State<AddMemberSheet> createState() => _AddMemberSheetState();
}

class _AddMemberSheetState extends State<AddMemberSheet> {
  final _namaCtrl    = TextEditingController();
  final _hpCtrl      = TextEditingController();
  final _emailCtrl   = TextEditingController();
  final _igCtrl      = TextEditingController();
  final _tglCtrl     = TextEditingController();

  final _formKey = GlobalKey<FormState>();
  bool _isSaving = false;

  @override
  void dispose() {
    _namaCtrl.dispose();
    _hpCtrl.dispose();
    _emailCtrl.dispose();
    _igCtrl.dispose();
    _tglCtrl.dispose();
    super.dispose();
  }

  // Validasi format HP: awali 08, panjang 10–13 digit
  String? _validateHP(String? val) {
    if (val == null || val.isEmpty) return 'No HP wajib diisi';
    final pattern = RegExp(r'^08[1-9][0-9]{7,10}$');
    if (!pattern.hasMatch(val)) {
      return 'Format HP: 08xxxxxxxxx (10–13 digit)';
    }
    return null;
  }

  Future<void> _simpan() async {
    if (!_formKey.currentState!.validate()) return;

    final nama  = _namaCtrl.text.trim();
    final hp    = _hpCtrl.text.trim();
    final email = _emailCtrl.text.trim();
    final ig    = _igCtrl.text.trim();
    final tgl   = _tglCtrl.text.trim();

    setState(() => _isSaving = true);

    try {
      final dio = ApiService.getDio(token: widget.token);

      // ── Step 1: Cek duplikat HP ──────────────────────────
      final cekRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action':        'cekHPMember',
            'hp':            hp,
            'organisasi_id': widget.organisasiID,
          }));

      if (cekRes.data['success'] == true) {
        final namaExist = cekRes.data['nama'] ?? '';
        if (mounted) {
          _showError('No HP sudah terdaftar atas nama $namaExist');
        }
        setState(() => _isSaving = false);
        return;
      }

      // ── Step 2: Insert member ─────────────────────────────
      final insertRes = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action':        'insertMember',
            'nama':          nama,
            'hp':            hp,
            'email':         email,
            'ig':            ig,
            'tgl_lahir':     tgl,
            'organisasi_id': widget.organisasiID,
          }));

      if (insertRes.data['success'] == true) {
        final newID = int.parse(insertRes.data['id'].toString());

        if (mounted) {
          Navigator.pop(context); // tutup sheet
          widget.onSuccess(newID, '$nama - $hp', nama);
        }
      } else {
        _showError('Gagal menyimpan member. Coba lagi.');
      }
    } catch (e) {
      _showError('Terjadi kesalahan: $e');
    }

    if (mounted) setState(() => _isSaving = false);
  }

  void _showError(String msg) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(msg), backgroundColor: Colors.red),
    );
  }

  Future<void> _pickDate() async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime(now.year - 20),
      firstDate: DateTime(1940),
      lastDate: now,
      helpText: 'Tanggal Lahir',
    );
    if (picked != null) {
      _tglCtrl.text =
          '${picked.year}-${picked.month.toString().padLeft(2, '0')}-${picked.day.toString().padLeft(2, '0')}';
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      // Geser form ke atas saat keyboard muncul
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Container(
        decoration: const BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            // ── Handle bar ──────────────────────────────────
            Container(
              margin: const EdgeInsets.only(top: 12),
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: Colors.grey.shade300,
                borderRadius: BorderRadius.circular(2),
              ),
            ),

            // ── Header ──────────────────────────────────────
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 4),
              child: Row(
                children: [
                  const Icon(Icons.person_add,
                      color: Color(0xFF1D273B), size: 22),
                  const SizedBox(width: 10),
                  const Expanded(
                    child: Text(
                      'Tambah Member Baru',
                      style: TextStyle(
                        fontSize: 17,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF1D273B),
                      ),
                    ),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.pop(context),
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                  ),
                ],
              ),
            ),

            const Divider(height: 1),

            // ── Form ─────────────────────────────────────────
            Flexible(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
                child: Form(
                  key: _formKey,
                  child: Column(
                    children: [
                      // Nama (wajib)
                      TextFormField(
                        controller: _namaCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Nama *',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.person_outline),
                        ),
                        textCapitalization: TextCapitalization.words,
                        validator: (v) =>
                            v == null || v.trim().isEmpty
                                ? 'Nama wajib diisi'
                                : null,
                      ),
                      const SizedBox(height: 14),

                      // No HP (wajib)
                      TextFormField(
                        controller: _hpCtrl,
                        decoration: const InputDecoration(
                          labelText: 'No HP / WA *',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.phone_android_outlined),
                          hintText: '08xxxxxxxxx',
                        ),
                        keyboardType: TextInputType.phone,
                        validator: _validateHP,
                      ),
                      const SizedBox(height: 14),

                      // Email (opsional)
                      TextFormField(
                        controller: _emailCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Email',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.mail_outline),
                        ),
                        keyboardType: TextInputType.emailAddress,
                      ),
                      const SizedBox(height: 14),

                      // Instagram (opsional)
                      TextFormField(
                        controller: _igCtrl,
                        decoration: const InputDecoration(
                          labelText: 'Akun Instagram',
                          border: OutlineInputBorder(),
                          isDense: true,
                          prefixIcon: Icon(Icons.camera_alt_outlined),
                          hintText: '@username',
                        ),
                      ),
                      const SizedBox(height: 14),

                      // Tanggal Lahir (opsional, date picker)
                      TextFormField(
                        controller: _tglCtrl,
                        readOnly: true,
                        decoration: InputDecoration(
                          labelText: 'Tanggal Lahir',
                          border: const OutlineInputBorder(),
                          isDense: true,
                          prefixIcon:
                              const Icon(Icons.calendar_today_outlined),
                          suffixIcon: _tglCtrl.text.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.close, size: 18),
                                  onPressed: () =>
                                      setState(() => _tglCtrl.clear()),
                                )
                              : null,
                        ),
                        onTap: _pickDate,
                      ),
                      const SizedBox(height: 20),

                      // Tombol Simpan
                      SizedBox(
                        width: double.infinity,
                        height: 48,
                        child: ElevatedButton.icon(
                          onPressed: _isSaving ? null : _simpan,
                          icon: _isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: Colors.white,
                                  ),
                                )
                              : const Icon(Icons.save_outlined),
                          label: Text(_isSaving ? 'Menyimpan...' : 'Simpan Member'),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFF1D273B),
                            foregroundColor: Colors.white,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
