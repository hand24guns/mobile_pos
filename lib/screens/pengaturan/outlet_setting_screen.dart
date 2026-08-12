import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import '../../services/session_service.dart';
import '../../services/api_service.dart';

const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);

/// Form setting Outlet — versi mobile dari "Edit Store" di web,
/// tanpa Kode Store & Status (dua field itu tetap dari web).
class OutletSettingScreen extends StatefulWidget {
  final List<int> outlets;

  const OutletSettingScreen({super.key, required this.outlets});

  @override
  State<OutletSettingScreen> createState() => _OutletSettingScreenState();
}

class _OutletSettingScreenState extends State<OutletSettingScreen> {
  bool _loading = true;
  bool _saving = false;
  String? _error;

  List<Map<String, dynamic>> _stores = [];
  int? _selectedStoreId;

  final _telpCtrl = TextEditingController();
  final _alamatCtrl = TextEditingController();
  final _npwpCtrl = TextEditingController();
  final _taxCtrl = TextEditingController();
  final _noteCtrl = TextEditingController();
  bool _waAktif = false;

  static final RegExp _telpPattern = RegExp(r'^(0)8[1-9][0-9]{7,10}$');

  @override
  void initState() {
    super.initState();
    _loadStores();
  }

  @override
  void dispose() {
    _telpCtrl.dispose();
    _alamatCtrl.dispose();
    _npwpCtrl.dispose();
    _taxCtrl.dispose();
    _noteCtrl.dispose();
    super.dispose();
  }

  Future<void> _loadStores() async {
    setState(() {
      _loading = true;
      _error = null;
    });

    try {
      final token = await SessionService.getToken() ?? '';
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/penjualan.php'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {'action': 'getOutletSetting'},
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (data['success'] == true) {
        final stores = List<Map<String, dynamic>>.from(
          (data['stores'] as List).map((e) => Map<String, dynamic>.from(e)),
        );
        if (!mounted) return;
        setState(() {
          _stores = stores;
          _loading = false;
        });
        if (stores.isNotEmpty) {
          _selectStore(stores.first['dim_divisi_id'] as int);
        }
      } else {
        if (!mounted) return;
        setState(() {
          _loading = false;
          _error = data['message'] ?? 'Gagal memuat data outlet';
        });
      }
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Gagal memuat data outlet';
      });
    }
  }

  void _selectStore(int storeId) {
    final store = _stores.firstWhere(
      (e) => e['dim_divisi_id'] == storeId,
      orElse: () => {},
    );
    if (store.isEmpty) return;

    setState(() {
      _selectedStoreId = storeId;
      _telpCtrl.text = store['telp'] ?? '';
      _alamatCtrl.text = store['alamat'] ?? '';
      _npwpCtrl.text = store['npwp'] ?? '';
      final tax = (store['tax'] as num?) ?? 0;
      _taxCtrl.text =
          tax == tax.roundToDouble() ? tax.toInt().toString() : tax.toString();
      _noteCtrl.text = store['note'] ?? '';
      _waAktif = (store['wa'] ?? 0) == 1;
    });
  }

  Future<void> _save() async {
    if (_selectedStoreId == null) return;

    final telp = _telpCtrl.text.trim();
    if (telp.isNotEmpty && !_telpPattern.hasMatch(telp)) {
      _showSnack('Format No. HP tidak sesuai', isError: true);
      return;
    }

    setState(() => _saving = true);
    try {
      final token = await SessionService.getToken() ?? '';
      final response = await http.post(
        Uri.parse('${ApiService.baseUrl}/penjualan.php'),
        headers: {
          'Authorization': 'Bearer $token',
          'Content-Type': 'application/x-www-form-urlencoded',
        },
        body: {
          'action': 'updateOutletSetting',
          'store_id': _selectedStoreId.toString(),
          'telp': telp,
          'alamat': _alamatCtrl.text.trim(),
          'npwp': _npwpCtrl.text.trim(),
          'wa': _waAktif ? '1' : '0',
          'tax': _taxCtrl.text.trim().isEmpty ? '0' : _taxCtrl.text.trim(),
          'note': _noteCtrl.text.trim(),
        },
      ).timeout(const Duration(seconds: 10));

      final data = jsonDecode(response.body);
      if (!mounted) return;
      if (data['success'] == true) {
        _showSnack('Data outlet berhasil disimpan');
        final idx = _stores.indexWhere(
          (e) => e['dim_divisi_id'] == _selectedStoreId,
        );
        if (idx != -1) {
          _stores[idx] = {
            ..._stores[idx],
            'telp': telp,
            'alamat': _alamatCtrl.text.trim(),
            'npwp': _npwpCtrl.text.trim(),
            'wa': _waAktif ? 1 : 0,
            'tax': double.tryParse(_taxCtrl.text.trim()) ?? 0,
            'note': _noteCtrl.text.trim(),
          };
        }
      } else {
        _showSnack(data['message'] ?? 'Gagal menyimpan data outlet',
            isError: true);
      }
    } catch (_) {
      if (!mounted) return;
      _showSnack('Gagal menyimpan data outlet', isError: true);
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  void _showSnack(String message, {bool isError = false}) {
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(message),
        backgroundColor: isError ? Colors.red[600] : Colors.green[600],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Center(child: CircularProgressIndicator(color: _blue));
    }

    if (_error != null) {
      return Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.error_outline_rounded,
                size: 48, color: Colors.grey[400]),
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: Colors.grey[600])),
            const SizedBox(height: 12),
            TextButton(onPressed: _loadStores, child: const Text('Coba Lagi')),
          ],
        ),
      );
    }

    return Container(
      color: _bgGray,
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(20),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 560),
          child: Card(
            color: Colors.white,
            elevation: 0,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(color: Colors.grey.shade200),
            ),
            child: Padding(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'Setting Outlet',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                      color: _navy,
                    ),
                  ),
                  const SizedBox(height: 20),
                  _buildOutletSelector(),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'No. Telp (HP)',
                    controller: _telpCtrl,
                    hint: 'Telepon / WA',
                    keyboardType: TextInputType.phone,
                    inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Alamat',
                    controller: _alamatCtrl,
                    hint: 'Alamat..',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'NPWP',
                    controller: _npwpCtrl,
                    hint: 'NPWP',
                  ),
                  const SizedBox(height: 16),
                  _buildWaSwitch(),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Pajak (%)',
                    controller: _taxCtrl,
                    hint: '0',
                    keyboardType:
                        const TextInputType.numberWithOptions(decimal: true),
                    inputFormatters: [
                      FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                    ],
                  ),
                  const SizedBox(height: 16),
                  _buildTextField(
                    label: 'Description',
                    controller: _noteCtrl,
                    hint: 'Note untuk print struk',
                    maxLines: 4,
                  ),
                  const SizedBox(height: 24),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: _saving ? null : _save,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: _blue,
                        padding: const EdgeInsets.symmetric(vertical: 14),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      child: _saving
                          ? const SizedBox(
                              height: 18,
                              width: 18,
                              child: CircularProgressIndicator(
                                strokeWidth: 2,
                                color: Colors.white,
                              ),
                            )
                          : const Text(
                              'Simpan',
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.w700,
                              ),
                            ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // Outlet selector — dropdown kalau akses > 1 store,
  // field disabled kalau cuma 1 store.
  // ============================================================
  Widget _buildOutletSelector() {
    final singleStore = _stores.length <= 1;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const Text('Store',
            style: TextStyle(fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 6),
        if (singleStore)
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            decoration: BoxDecoration(
              color: Colors.grey.shade100,
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: Text(
              _stores.isEmpty ? '-' : (_stores.first['nama'] ?? '-'),
              style: TextStyle(color: Colors.grey[700]),
            ),
          )
        else
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: Colors.grey.shade300),
            ),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<int>(
                value: _selectedStoreId,
                isExpanded: true,
                items: _stores
                    .map(
                      (e) => DropdownMenuItem<int>(
                        value: e['dim_divisi_id'] as int,
                        child: Text(e['nama'] ?? ''),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) _selectStore(value);
                },
              ),
            ),
          ),
      ],
    );
  }

  Widget _buildWaSwitch() {
    return Row(
      children: [
        const Expanded(
          child: Text('Whatsapp',
              style: TextStyle(fontSize: 13, color: Colors.black87)),
        ),
        Switch(
          value: _waAktif,
          activeThumbColor: _blue,
          onChanged: (value) => setState(() => _waAktif = value),
        ),
        Text(
          _waAktif ? 'Aktif' : 'Non Aktif',
          style: TextStyle(
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: _waAktif ? _blue : Colors.grey[500],
          ),
        ),
      ],
    );
  }

  Widget _buildTextField({
    required String label,
    required TextEditingController controller,
    String? hint,
    int maxLines = 1,
    TextInputType? keyboardType,
    List<TextInputFormatter>? inputFormatters,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label,
            style: const TextStyle(fontSize: 13, color: Colors.black87)),
        const SizedBox(height: 6),
        TextField(
          controller: controller,
          maxLines: maxLines,
          keyboardType: keyboardType,
          inputFormatters: inputFormatters,
          decoration: InputDecoration(
            hintText: hint,
            isDense: true,
            contentPadding:
                const EdgeInsets.symmetric(horizontal: 14, vertical: 14),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: BorderSide(color: Colors.grey.shade300),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(10),
              borderSide: const BorderSide(color: _blue),
            ),
          ),
        ),
      ],
    );
  }
}
