import 'package:flutter/material.dart';
import 'package:dio/dio.dart';
import 'package:intl/intl.dart';
import '../../services/api_service.dart';
import '../../services/session_service.dart';
import 'petikes_entry_screen.dart';

// ─── Palette (disamakan dengan home_screen.dart) ───────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _navyMid = Color(0xFF1A2F5A);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);
const Color _green = Color(0xFF22C55E);
const Color _red = Color(0xFFEF4444);

class KasKecilScreen extends StatefulWidget {
  // Sama seperti LaporanScreen/PengaturanScreen: outlets datang dari
  // session login (HomeScreen._outlets), bukan di-fetch ulang lewat
  // getStores() di sini. Kasir dengan akses 1 store otomatis cuma
  // lihat store itu; role dengan akses banyak store bisa pilih lewat
  // dropdown filter.
  final List<int> outlets;

  const KasKecilScreen({super.key, required this.outlets});

  @override
  State<KasKecilScreen> createState() => _KasKecilScreenState();
}

class _KasKecilScreenState extends State<KasKecilScreen> {
  String _token = '';
  int _organisasiID = 0;
  int? _selectedStoreId;

  DateTime _startDate = DateTime.now().subtract(const Duration(days: 7));
  DateTime _endDate = DateTime.now();

  bool _isLoading = true;
  String? _errorMessage;
  List<Map<String, dynamic>> _dataPerTanggal = [];
  double _saldoTotal = 0;

  @override
  void initState() {
    super.initState();
    _selectedStoreId = widget.outlets.length == 1 ? widget.outlets.first : null;
    _init();
  }

  Future<void> _init() async {
    try {
      final session = await SessionService.getSession();
      _token = session['token'];

      if (_selectedStoreId != null) {
        await _loadOrganisasi(_selectedStoreId!);
        await _loadData();
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Gagal memuat data awal.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  // organisasi_id tidak tersimpan di session, jadi tetap diambil per
  // store terpilih lewat action getOrganisasiID (MasterHandler.php),
  // sama seperti pola di invoice_list_screen.dart.
  Future<void> _loadOrganisasi(int storeId) async {
    final dio = ApiService.getDio(token: _token);
    final orgRes = await dio.post('/penjualan.php',
        data: FormData.fromMap({
          'action': 'getOrganisasiID',
          'store_id': storeId,
        }));
    _organisasiID = int.parse(orgRes.data['organisasi_id'].toString());
  }

  Future<void> _onStoreChanged(int? storeId) async {
    if (storeId == null) return;
    setState(() {
      _selectedStoreId = storeId;
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      await _loadOrganisasi(storeId);
      await _loadData();
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Gagal memuat data organisasi.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _loadData() async {
    if (_selectedStoreId == null) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final dio = ApiService.getDio(token: _token);
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getPetikesList',
            'store_id': _selectedStoreId,
            'organisasi_id': _organisasiID,
            'start_date': DateFormat('yyyy-MM-dd').format(_startDate),
            'end_date': DateFormat('yyyy-MM-dd').format(_endDate),
          }));

      if (!mounted) return;

      if (res.data['success'] == true) {
        setState(() {
          _dataPerTanggal =
              List<Map<String, dynamic>>.from(res.data['data'] ?? []);
          _saldoTotal = double.tryParse('${res.data['saldo_total'] ?? 0}') ?? 0;
        });
      } else {
        setState(() => _errorMessage =
            res.data['message'] ?? 'Gagal memuat data kas kecil.');
      }
    } catch (_) {
      if (!mounted) return;
      setState(() => _errorMessage = 'Gagal terhubung ke server.');
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  Future<void> _pickDate({required bool isStart}) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: isStart ? _startDate : _endDate,
      firstDate: DateTime(2020),
      lastDate: DateTime.now(),
    );
    if (picked == null) return;
    setState(() {
      if (isStart) {
        _startDate = picked;
      } else {
        _endDate = picked;
      }
    });
  }

  Future<void> _openEntry() async {
    if (_selectedStoreId == null) return;

    final result = await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => KasKecilEntryScreen(
          outlets: widget.outlets,
          initialStoreId: _selectedStoreId!,
          organisasiID: _organisasiID,
        ),
      ),
    );
    if (result == true) {
      _loadData();
    }
  }

  Future<void> _confirmVoid(int paymentID, String kode) async {
    final confirm = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Text('Void Transaksi?'),
        content: Text(
            'Transaksi "$kode" akan di-void. Data tidak bisa dikembalikan.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Batal'),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: _red),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Void', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      final dio = ApiService.getDio(token: _token);
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'voidPetikes',
            'payment_id': paymentID,
          }));

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res.data['message'] ?? '')),
      );

      if (res.data['success'] == true) {
        _loadData();
      }
    } catch (_) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Gagal menghubungi server.')),
      );
    }
  }

  void _showJurnal(int paymentID, String kode) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (_) =>
          _JurnalSheet(token: _token, paymentID: paymentID, kode: kode),
    );
  }

  String _rp(num value) => NumberFormat.decimalPattern('id_ID').format(value);

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Kas Kecil'),
      ),
      floatingActionButton: _selectedStoreId == null
          ? null
          : FloatingActionButton.extended(
              backgroundColor: _blue,
              onPressed: _openEntry,
              icon: const Icon(Icons.add, color: Colors.white),
              label:
                  const Text('Tambah', style: TextStyle(color: Colors.white)),
            ),
      body: Column(
        children: [
          _buildFilterCard(),
          if (_errorMessage != null)
            Padding(
              padding: const EdgeInsets.all(12),
              child: Text(_errorMessage!, style: const TextStyle(color: _red)),
            ),
          Expanded(
            child: _isLoading
                ? const Center(child: CircularProgressIndicator())
                : _dataPerTanggal.isEmpty
                    ? const Center(
                        child: Text('Tidak ada data pada periode ini.'))
                    : ListView(
                        padding: const EdgeInsets.fromLTRB(12, 8, 12, 90),
                        children: [
                          for (final harian in _dataPerTanggal)
                            _buildDayCard(harian),
                          _buildTotalCard(),
                        ],
                      ),
          ),
        ],
      ),
    );
  }

  Widget _buildFilterCard() {
    return Container(
      color: Colors.white,
      padding: const EdgeInsets.all(12),
      child: Column(
        children: [
          if (widget.outlets.length > 1)
            DropdownButtonFormField<int>(
              value: _selectedStoreId,
              decoration: const InputDecoration(
                labelText: 'Store',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: widget.outlets
                  .map((o) =>
                      DropdownMenuItem(value: o, child: Text('Store $o')))
                  .toList(),
              onChanged: _onStoreChanged,
            ),
          if (widget.outlets.length > 1) const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _DateField(
                  label: 'Dari',
                  date: _startDate,
                  onTap: () => _pickDate(isStart: true),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: _DateField(
                  label: 'Sampai',
                  date: _endDate,
                  onTap: () => _pickDate(isStart: false),
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
            width: double.infinity,
            child: ElevatedButton(
              style: ElevatedButton.styleFrom(backgroundColor: _navyMid),
              onPressed: _loadData,
              child: const Text('Tampilkan',
                  style: TextStyle(color: Colors.white)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildDayCard(Map<String, dynamic> harian) {
    final tanggal = harian['tanggal'] ?? '';
    final transaksi =
        List<Map<String, dynamic>>.from(harian['transaksi'] ?? []);
    final saldoHarian = double.tryParse('${harian['saldo_harian'] ?? 0}') ?? 0;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: const BoxDecoration(
              color: _navy,
              borderRadius: BorderRadius.vertical(top: Radius.circular(12)),
            ),
            child: Text(
              tanggal,
              style: const TextStyle(
                  color: Colors.white, fontWeight: FontWeight.w600),
            ),
          ),
          for (final trx in transaksi) _buildTrxRow(trx),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(color: Colors.grey[100]),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                const Text('Saldo Harian',
                    style: TextStyle(fontWeight: FontWeight.w600)),
                Text(_rp(saldoHarian),
                    style: const TextStyle(fontWeight: FontWeight.w600)),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildTrxRow(Map<String, dynamic> trx) {
    final masuk = double.tryParse('${trx['uang_masuk'] ?? 0}') ?? 0;
    final keluar = double.tryParse('${trx['uang_keluar'] ?? 0}') ?? 0;
    final saldo = double.tryParse('${trx['saldo_berjalan'] ?? 0}') ?? 0;
    final paymentID = int.tryParse('${trx['payment_id'] ?? 0}') ?? 0;
    final kode = '${trx['kode'] ?? ''}';

    return InkWell(
      onTap: () => _showJurnal(paymentID, kode),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        child: Row(
          children: [
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(kode,
                      style: const TextStyle(fontSize: 12, color: Colors.grey)),
                  Text('${trx['keterangan'] ?? ''}'),
                ],
              ),
            ),
            Expanded(
              flex: 2,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    masuk > 0
                        ? '+ ${_rp(masuk)}'
                        : (keluar > 0 ? '- ${_rp(keluar)}' : '-'),
                    style: TextStyle(
                      fontWeight: FontWeight.w600,
                      color: masuk > 0
                          ? _green
                          : (keluar > 0 ? _red : Colors.grey),
                    ),
                  ),
                  Text('Saldo: ${_rp(saldo)}',
                      style: const TextStyle(fontSize: 11, color: Colors.grey)),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: _red, size: 20),
              onPressed: () => _confirmVoid(paymentID, kode),
              tooltip: 'Void',
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildTotalCard() {
    return Card(
      color: _navy,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            const Text('Saldo Total Periode',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.w600)),
            Text(_rp(_saldoTotal),
                style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 16)),
          ],
        ),
      ),
    );
  }
}

class _DateField extends StatelessWidget {
  final String label;
  final DateTime date;
  final VoidCallback onTap;

  const _DateField(
      {required this.label, required this.date, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return InkWell(
      onTap: onTap,
      child: InputDecorator(
        decoration: InputDecoration(
          labelText: label,
          border: const OutlineInputBorder(),
          isDense: true,
          suffixIcon: const Icon(Icons.calendar_today_outlined, size: 18),
        ),
        child: Text(DateFormat('yyyy-MM-dd').format(date)),
      ),
    );
  }
}

// ─── Bottom sheet: detail jurnal + foto nota ───────────────────
class _JurnalSheet extends StatefulWidget {
  final String token;
  final int paymentID;
  final String kode;

  const _JurnalSheet(
      {required this.token, required this.paymentID, required this.kode});

  @override
  State<_JurnalSheet> createState() => _JurnalSheetState();
}

class _JurnalSheetState extends State<_JurnalSheet> {
  bool _isLoading = true;
  List<Map<String, dynamic>> _detil = [];
  List<String> _images = [];
  double _totalDebit = 0;
  double _totalKredit = 0;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final dio = ApiService.getDio(token: widget.token);
      final res = await dio.post('/penjualan.php',
          data: FormData.fromMap({
            'action': 'getJurnal',
            'payment_id': widget.paymentID,
          }));

      if (!mounted) return;
      setState(() {
        _detil = List<Map<String, dynamic>>.from(res.data['detil'] ?? []);
        _images = List<String>.from(res.data['images'] ?? []);
        _totalDebit = double.tryParse('${res.data['total_debit'] ?? 0}') ?? 0;
        _totalKredit = double.tryParse('${res.data['total_kredit'] ?? 0}') ?? 0;
      });
    } catch (_) {
      // biarkan list kosong, tampilkan pesan default di UI
    } finally {
      if (mounted) setState(() => _isLoading = false);
    }
  }

  String _rp(num v) => NumberFormat.decimalPattern('id_ID').format(v);

  @override
  Widget build(BuildContext context) {
    return DraggableScrollableSheet(
      initialChildSize: 0.6,
      maxChildSize: 0.9,
      minChildSize: 0.4,
      expand: false,
      builder: (context, scrollController) {
        return Padding(
          padding: const EdgeInsets.all(16),
          child: _isLoading
              ? const Center(child: CircularProgressIndicator())
              : ListView(
                  controller: scrollController,
                  children: [
                    Text('Jurnal — ${widget.kode}',
                        style: const TextStyle(
                            fontSize: 16, fontWeight: FontWeight.bold)),
                    const SizedBox(height: 12),
                    if (_detil.isEmpty)
                      const Text('Tidak ada data jurnal.')
                    else
                      ..._detil.map((d) => ListTile(
                            dense: true,
                            title: Text('${d['nocoa']} - ${d['nama']}'),
                            subtitle: Text('${d['keterangan'] ?? ''}'),
                            trailing: Text(
                              (double.tryParse('${d['valuedb']}') ?? 0) > 0
                                  ? 'Rp ${_rp(double.parse('${d['valuedb']}'))}'
                                  : 'Rp ${_rp(double.tryParse('${d['valuecr']}') ?? 0)}',
                            ),
                          )),
                    const Divider(),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        const Text('Total',
                            style: TextStyle(fontWeight: FontWeight.bold)),
                        Text('Db ${_rp(_totalDebit)} / Cr ${_rp(_totalKredit)}',
                            style:
                                const TextStyle(fontWeight: FontWeight.bold)),
                      ],
                    ),
                    if (_images.isNotEmpty) ...[
                      const SizedBox(height: 16),
                      const Text('Foto Nota',
                          style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: _images
                            .map((url) => ClipRRect(
                                  borderRadius: BorderRadius.circular(8),
                                  child: Image.network(url,
                                      width: 90, height: 90, fit: BoxFit.cover),
                                ))
                            .toList(),
                      ),
                    ],
                  ],
                ),
        );
      },
    );
  }
}
