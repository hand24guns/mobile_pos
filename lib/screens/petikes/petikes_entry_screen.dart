import 'dart:io';
import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/session_service.dart';

const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);
const Color _red = Color(0xFFEF4444);

class _KasKecilRow {
  final kategoriId = ValueNotifier<int?>(null);
  final kategoriCtrl = TextEditingController();
  final kategoriFocus = FocusNode();
  final deskripsiCtrl = TextEditingController();
  final nominalCtrl = TextEditingController(text: '0');

  void dispose() {
    kategoriId.dispose();
    kategoriCtrl.dispose();
    kategoriFocus.dispose();
    deskripsiCtrl.dispose();
    nominalCtrl.dispose();
  }
}

class KasKecilEntryScreen extends StatefulWidget {
  // Sama seperti KasKecilScreen: outlets dari session login
  // (diteruskan dari KasKecilScreen, bukan di-fetch ulang di sini).
  final List<int> outlets;
  final int initialStoreId;
  final int organisasiID;
  // Opsional: id store -> nama store, kalau parent (KasKecilScreen)
  // kebetulan sudah punya datanya dan mau menghindari fetch dobel.
  // Kalau tidak dikirim, screen ini fetch sendiri lewat action
  // 'getStores' (sama seperti pola di ItemTerjualReportScreen).
  final Map<int, String> storeNames;

  const KasKecilEntryScreen({
    super.key,
    required this.outlets,
    required this.initialStoreId,
    required this.organisasiID,
    this.storeNames = const {},
  });

  @override
  State<KasKecilEntryScreen> createState() => _KasKecilEntryScreenState();
}

class _KasKecilEntryScreenState extends State<KasKecilEntryScreen> {
  String _token = '';
  late int _selectedStoreId;
  DateTime _tanggal = DateTime.now();
  String? _tipe; // 'masuk' atau 'keluar'
  String _number = '';
  final _keteranganCtrl = TextEditingController();

  List<Map<String, dynamic>> _opexList = [];
  Map<int, String> _storeNames = {}; // id -> nama, dari action getStores
  final List<_KasKecilRow> _rows = [_KasKecilRow()];
  final List<XFile> _images = [];

  bool _isLoadingOpex = true;
  bool _isLoadingNumber = false;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedStoreId = widget.initialStoreId;
    _init();
  }

  @override
  void dispose() {
    for (final r in _rows) {
      r.dispose();
    }
    _keteranganCtrl.dispose();
    super.dispose();
  }

  Future<void> _init() async {
    final session = await SessionService.getSession();
    _token = session['token'];
    await Future.wait([
      _loadOpex(),
      _loadStoreNames(session['user_id']),
    ]);
  }

  // Sama seperti pola di ItemTerjualReportScreen: action 'getStores'
  // (MasterHandler.php) mengembalikan {id, nama} untuk semua outlet
  // yang bisa diakses user, dipakai supaya header tampilkan nama store
  // (bukan ID mentah).
  Future<void> _loadStoreNames(dynamic userId) async {
    try {
      final dio = ApiService.getDio(token: _token);
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getStores',
            'user_id': '$userId',
          }));

      if (!mounted) return;
      if (res.data['success'] == true) {
        final list = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
        setState(() {
          _storeNames = {
            for (final s in list)
              if (s['id'] != null)
                (s['id'] is int ? s['id'] as int : int.parse('${s['id']}')):
                    '${s['nama']}',
          };
        });
      }
    } catch (_) {
      // gagal ambil nama store — header fallback tampilkan "Store {id}"
    }
  }

  Future<void> _loadOpex() async {
    try {
      final dio = ApiService.getDio(token: _token);
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getOpexPetikes',
            'organisasi_id': widget.organisasiID,
          }));

      if (!mounted) return;
      if (res.data['success'] == true) {
        setState(() {
          _opexList = List<Map<String, dynamic>>.from(res.data['data'] ?? []);
        });
      }
    } catch (_) {
      // gagal memuat kategori, biarkan kosong; pesan error muncul
      // saat validasi submit
    } finally {
      if (mounted) setState(() => _isLoadingOpex = false);
    }
  }

  // Nomor dokumen digenerate ulang setiap kali tipe (masuk/keluar)
  // berubah, sama seperti event 'change' pada #tipe di InputPetikes.js.
  Future<void> _onTipeChanged(String? value) async {
    setState(() {
      _tipe = value;
      _number = '';
    });
    if (value == null) return;

    setState(() => _isLoadingNumber = true);
    try {
      final dio = ApiService.getDio(token: _token);
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getNumberPetikes',
            'tipe': value,
            'organisasi_id': widget.organisasiID,
          }));

      if (!mounted) return;
      if (res.data['success'] == true) {
        setState(() => _number = res.data['number'] ?? '');
      } else {
        _showSnack(res.data['message'] ?? 'Gagal generate nomor dokumen.');
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('Gagal terhubung ke server.');
    } finally {
      if (mounted) setState(() => _isLoadingNumber = false);
    }
  }

  Future<void> _pickDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _tanggal,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked != null) setState(() => _tanggal = picked);
  }

  void _addRow() => setState(() => _rows.add(_KasKecilRow()));

  void _removeRow(int index) {
    if (_rows.length <= 1) {
      // minimal 1 baris — kosongkan saja isinya, sama seperti versi web
      setState(() {
        _rows[index].kategoriId.value = null;
        _rows[index].kategoriCtrl.clear();
        _rows[index].deskripsiCtrl.clear();
        _rows[index].nominalCtrl.text = '0';
      });
      return;
    }
    setState(() {
      _rows[index].dispose();
      _rows.removeAt(index);
    });
  }

  Future<void> _pickImages() async {
    final picker = ImagePicker();
    final picked = await picker.pickMultiImage(imageQuality: 80);
    if (picked.isEmpty) return;

    const maxSize = 4 * 1024 * 1024; // 4 MB, samakan dengan batas backend
    final valid = <XFile>[];
    for (final f in picked) {
      final size = await f.length();
      if (size > maxSize) {
        _showSnack('File "${f.name}" melebihi 4 MB, dilewati.');
        continue;
      }
      valid.add(f);
    }

    setState(() => _images.addAll(valid));
  }

  void _removeImage(int index) => setState(() => _images.removeAt(index));

  double _parseNominal(String raw) =>
      double.tryParse(raw.replaceAll(',', '').trim()) ?? 0;

  String? _validate() {
    if (_tipe == null) return 'Tipe Kas belum dipilih.';
    if (_number.isEmpty) {
      return 'Nomor dokumen belum ter-generate. Pilih tipe kas terlebih dahulu.';
    }

    bool hasAnyValid = false;

    for (var i = 0; i < _rows.length; i++) {
      final row = _rows[i];
      final desc = row.deskripsiCtrl.text.trim();
      final nominal = _parseNominal(row.nominalCtrl.text);

      final isBlankRow =
          desc.isEmpty && nominal == 0 && row.kategoriId.value == null;
      if (isBlankRow && _rows.length == 1) continue;

      if (row.kategoriId.value == null) {
        return 'Kategori pada baris ke-${i + 1} belum dipilih.';
      }
      if (desc.isEmpty) {
        return 'Deskripsi pada baris ke-${i + 1} tidak boleh kosong.';
      }
      if (nominal <= 0) {
        return 'Nominal pada baris ke-${i + 1} harus lebih dari 0.';
      }

      hasAnyValid = true;
    }

    if (!hasAnyValid) return 'Tidak ada data kas yang valid untuk disimpan.';

    return null;
  }

  Future<void> _submit() async {
    final error = _validate();
    if (error != null) {
      _showSnack(error);
      return;
    }

    setState(() => _isSaving = true);

    try {
      final formMap = <String, dynamic>{
        'action': 'simpanPetikes',
        'organisasi_id': widget.organisasiID,
        'store_id': _selectedStoreId,
        'tipe': _tipe,
        'tanggal': DateFormat('yyyy-MM-dd').format(_tanggal),
        'number': _number,
        'keterangan': _keteranganCtrl.text.trim(),
      };

      final formData = FormData.fromMap(formMap);

      for (final row in _rows) {
        final desc = row.deskripsiCtrl.text.trim();
        final nominal = _parseNominal(row.nominalCtrl.text);
        if (desc.isEmpty && nominal == 0) continue;

        // PENTING: backend (PetikesHandler.php -> case 'simpanPetikes')
        // membaca nominal dari $_POST['nominal'], arah transaksinya
        // (masuk/keluar) sudah ditentukan lewat header 'tipe' -> $tipeID,
        // bukan dari nama field nominal ini.
        formData.fields.add(MapEntry('kategori[]', '${row.kategoriId.value}'));
        formData.fields.add(MapEntry('deskripsi[]', desc));
        formData.fields.add(MapEntry('nominal[]', '$nominal'));
      }

      for (final img in _images) {
        formData.files.add(MapEntry(
          'images[]',
          await MultipartFile.fromFile(img.path, filename: img.name),
        ));
      }

      final dio = ApiService.getDio(token: _token);
      final res = await dio.post('/penjualan.php', data: formData);

      if (!mounted) return;

      // res.data seharusnya sudah berupa Map (dio auto-decode JSON).
      // Kalau backend sempat mencetak warning/notice PHP sebelum
      // echo json_encode(...), responsenya jadi bukan JSON murni dan
      // res.data bisa berupa String, bukan Map — makanya dicek dulu
      // supaya tidak crash diam-diam kalau format tidak sesuai.
      final data = res.data;
      if (data is Map && data['success'] == true) {
        Navigator.pop(context, true);
      } else if (data is Map) {
        _showSnack(data['message']?.toString() ?? 'Gagal menyimpan.');
      } else {
        // Response bukan JSON (kemungkinan ada PHP warning/notice atau
        // HTML error tercampur sebelum JSON). Tampilkan potongan
        // response mentah supaya lebih mudah dilacak dari sisi backend.
        final raw = data?.toString() ?? '';
        _showSnack(
          'Format response tidak dikenali dari server.'
          '${raw.isNotEmpty ? ' (${raw.length > 200 ? raw.substring(0, 200) : raw})' : ''}',
        );
      }
    } on DioException catch (e) {
      if (!mounted) return;
      // Tampilkan status code / pesan asli dari server (kalau ada)
      // supaya lebih jelas ini gagal koneksi vs error di server.
      final status = e.response?.statusCode;
      final body = e.response?.data;
      _showSnack(
        status != null
            ? 'Gagal menyimpan (HTTP $status): ${body ?? e.message}'
            : 'Gagal terhubung ke server: ${e.message}',
      );
    } catch (e) {
      if (!mounted) return;
      _showSnack('Terjadi kesalahan tak terduga: $e');
    } finally {
      if (mounted) setState(() => _isSaving = false);
    }
  }

  String _storeLabel(int id) =>
      widget.storeNames[id] ?? _storeNames[id] ?? 'Store $id';

  void _showSnack(String msg) {
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(msg)));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Input Kas Kecil'),
      ),
      body: _isLoadingOpex
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.fromLTRB(14, 14, 14, 100),
              children: [
                _buildHeaderCard(),
                const SizedBox(height: 12),
                _buildRowsCard(),
                const SizedBox(height: 12),
                _buildImagesCard(),
              ],
            ),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(14),
          child: SizedBox(
            width: double.infinity,
            height: 46,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: _blue),
              onPressed: _isSaving ? null : _submit,
              icon: _isSaving
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                          strokeWidth: 2, color: Colors.white),
                    )
                  : const Icon(Icons.save_outlined, color: Colors.white),
              label: Text(_isSaving ? 'Menyimpan...' : 'Simpan',
                  style: const TextStyle(color: Colors.white)),
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildHeaderCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            // Baris 1: Store - Tanggal
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: widget.outlets.length > 1
                      ? DropdownButtonFormField<int>(
                          value: _selectedStoreId,
                          isExpanded: true,
                          decoration: const InputDecoration(
                            labelText: 'Store',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          items: widget.outlets
                              .map((o) => DropdownMenuItem(
                                    value: o,
                                    child: Text(_storeLabel(o),
                                        overflow: TextOverflow.ellipsis),
                                  ))
                              .toList(),
                          onChanged: (v) {
                            if (v != null) {
                              setState(() => _selectedStoreId = v);
                            }
                          },
                        )
                      : InputDecorator(
                          decoration: const InputDecoration(
                            labelText: 'Store',
                            border: OutlineInputBorder(),
                            isDense: true,
                          ),
                          child: Text(_storeLabel(_selectedStoreId),
                              overflow: TextOverflow.ellipsis),
                        ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InkWell(
                    onTap: _pickDate,
                    child: InputDecorator(
                      decoration: const InputDecoration(
                        labelText: 'Tanggal',
                        border: OutlineInputBorder(),
                        isDense: true,
                        suffixIcon:
                            Icon(Icons.calendar_today_outlined, size: 18),
                      ),
                      child: Text(DateFormat('yyyy-MM-dd').format(_tanggal)),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Baris 2: Tipe Kas - No. Dokumen
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: DropdownButtonFormField<String>(
                    value: _tipe,
                    isExpanded: true,
                    decoration: const InputDecoration(
                      labelText: 'Tipe Kas',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                    items: const [
                      DropdownMenuItem(
                          value: 'masuk', child: Text('Kas Masuk')),
                      DropdownMenuItem(
                          value: 'keluar', child: Text('Kas Keluar')),
                    ],
                    onChanged: _onTipeChanged,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: InputDecorator(
                    decoration: InputDecoration(
                      labelText: 'No. Dokumen',
                      border: const OutlineInputBorder(),
                      isDense: true,
                      suffixIcon: _isLoadingNumber
                          ? const Padding(
                              padding: EdgeInsets.all(10),
                              child: SizedBox(
                                width: 14,
                                height: 14,
                                child:
                                    CircularProgressIndicator(strokeWidth: 2),
                              ),
                            )
                          : null,
                    ),
                    child: Text(_number.isEmpty ? '-' : _number,
                        overflow: TextOverflow.ellipsis),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // Baris 3: Keterangan header (full width, opsional)
            TextField(
              controller: _keteranganCtrl,
              maxLines: 2,
              minLines: 1,
              decoration: const InputDecoration(
                labelText: 'Keterangan',
                hintText: 'Isi Keterangan...',
                border: OutlineInputBorder(),
                isDense: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRowsCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text('Detail Transaksi',
                style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            for (var i = 0; i < _rows.length; i++) _buildRow(i),
            const SizedBox(height: 4),
            OutlinedButton.icon(
              onPressed: _addRow,
              icon: const Icon(Icons.add),
              label: const Text('Tambah Baris'),
            ),
          ],
        ),
      ),
    );
  }

  // Kategori searchable (ketik untuk cari), pakai RawAutocomplete bawaan
  // Flutter — tidak perlu tambah dependency baru untuk perilaku ala select2.
  Widget _buildKategoriField(_KasKecilRow row) {
    return RawAutocomplete<Map<String, dynamic>>(
      textEditingController: row.kategoriCtrl,
      focusNode: row.kategoriFocus,
      optionsBuilder: (textEditingValue) {
        final q = textEditingValue.text.trim().toLowerCase();
        if (q.isEmpty) return _opexList;
        return _opexList
            .where((o) => '${o['keterangan']}'.toLowerCase().contains(q));
      },
      displayStringForOption: (o) => '${o['keterangan']}',
      onSelected: (o) {
        final id = o['dim_opex_id'] is int
            ? o['dim_opex_id']
            : int.tryParse('${o['dim_opex_id']}');
        row.kategoriId.value = id;
      },
      fieldViewBuilder: (context, controller, focusNode, onFieldSubmitted) {
        return TextField(
          controller: controller,
          focusNode: focusNode,
          decoration: InputDecoration(
            labelText: 'Kategori',
            hintText: 'Ketik untuk cari...',
            isDense: true,
            border: const OutlineInputBorder(),
            suffixIcon: controller.text.isEmpty
                ? const Icon(Icons.search, size: 18)
                : IconButton(
                    icon: const Icon(Icons.clear, size: 18),
                    onPressed: () {
                      controller.clear();
                      row.kategoriId.value = null;
                    },
                  ),
          ),
          onChanged: (text) {
            // Kalau teks diubah manual sampai tidak cocok lagi dengan
            // kategori yang sudah dipilih, anggap belum ada pilihan.
            if (row.kategoriId.value != null &&
                !_opexList.any((o) => '${o['keterangan']}' == text)) {
              row.kategoriId.value = null;
            }
          },
        );
      },
      optionsViewBuilder: (context, onSelected, options) {
        return Align(
          alignment: Alignment.topLeft,
          child: Material(
            elevation: 4,
            borderRadius: BorderRadius.circular(8),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 260, maxWidth: 360),
              child: options.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(12),
                      child: Text('Kategori tidak ditemukan.'),
                    )
                  : ListView.builder(
                      padding: EdgeInsets.zero,
                      shrinkWrap: true,
                      itemCount: options.length,
                      itemBuilder: (context, index) {
                        final o = options.elementAt(index);
                        return ListTile(
                          dense: true,
                          title: Text('${o['keterangan']}',
                              overflow: TextOverflow.ellipsis),
                          onTap: () => onSelected(o),
                        );
                      },
                    ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildRow(int index) {
    final row = _rows[index];
    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: Colors.grey[50],
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.grey.shade300),
      ),
      child: LayoutBuilder(
        builder: (context, constraints) {
          // 1 baris penuh di layar lebar (tablet/landscape). Di HP
          // (sempit), field terlalu kecil kalau dipaksa 1 baris, jadi
          // dipecah jadi 2 baris supaya masih nyaman diketik.
          final isWide = constraints.maxWidth >= 640;

          final kategoriField = _buildKategoriField(row);

          final deskripsiField = TextField(
            controller: row.deskripsiCtrl,
            decoration: const InputDecoration(
              labelText: 'Deskripsi',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          );

          final nominalField = TextField(
            controller: row.nominalCtrl,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Nominal',
              isDense: true,
              border: OutlineInputBorder(),
            ),
          );

          final deleteBtn = IconButton(
            icon: const Icon(Icons.close, color: _red, size: 20),
            onPressed: () => _removeRow(index),
            tooltip: 'Hapus baris',
          );

          if (isWide) {
            return Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Expanded(flex: 3, child: kategoriField),
                const SizedBox(width: 8),
                Expanded(flex: 3, child: deskripsiField),
                const SizedBox(width: 8),
                Expanded(flex: 2, child: nominalField),
                deleteBtn,
              ],
            );
          }

          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(child: kategoriField),
                  deleteBtn,
                ],
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(flex: 3, child: deskripsiField),
                  const SizedBox(width: 8),
                  Expanded(flex: 2, child: nominalField),
                ],
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildImagesCard() {
    return Card(
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Foto Nota (opsional)',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                TextButton.icon(
                  onPressed: _pickImages,
                  icon: const Icon(Icons.add_photo_alternate_outlined),
                  label: const Text('Tambah'),
                ),
              ],
            ),
            if (_images.isNotEmpty)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: List.generate(_images.length, (i) {
                  return Stack(
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: Image.file(
                          File(_images[i].path),
                          width: 80,
                          height: 80,
                          fit: BoxFit.cover,
                        ),
                      ),
                      Positioned(
                        top: -6,
                        right: -6,
                        child: IconButton(
                          icon: const Icon(Icons.cancel, color: _red, size: 20),
                          onPressed: () => _removeImage(i),
                        ),
                      ),
                    ],
                  );
                }),
              ),
          ],
        ),
      ),
    );
  }
}
