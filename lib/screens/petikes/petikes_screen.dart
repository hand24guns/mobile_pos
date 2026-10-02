import 'package:flutter/material.dart';
import 'package:intl/intl.dart';
import '../../services/petty_cash_service.dart';
import '../../services/store_service.dart';
import 'petikes_entry_screen.dart';

// ─── Palette (disamakan dengan home_screen.dart, ditambah aksen dari
// redesign Kas Kecil) ───────────────────────────────────────────
const Color _navy = Color(0xFF0D1B3E);
const Color _navyGradientEnd = Color(0xFF203D7B);
const Color _summaryGradientStart = Color(0xFF1D3972);
const Color _summaryGradientEnd = Color(0xFF102656);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);
const Color _red = Color(0xFFEF4444);
const Color _borderGray = Color(0xFFE0E6F0);
const Color _fieldBorderGray = Color(0xFFD8E0ED);
const Color _titleNavy = Color(0xFF20375F);
const Color _mutedGray = Color(0xFF7A8BA8);
const Color _incomeGreenText = Color(0xFF159D50);
const Color _incomeGreenBg = Color(0xFFE3F8E9);
const Color _expenseBlueText = Color(0xFF2872D8);
const Color _expenseBlueBg = Color(0xFFEAF2FD);

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
    final orgData = await StoreService.getOrganisasiId(storeId);
    _organisasiID = (orgData['organisasi_id'] as int?) ?? 0;
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
      final res = await PettyCashService.getPettyCashList(
        storeId: _selectedStoreId!,
        organisasiId: _organisasiID,
        startDate: DateFormat('yyyy-MM-dd').format(_startDate),
        endDate: DateFormat('yyyy-MM-dd').format(_endDate),
      );

      if (!mounted) return;

      if (res['success'] == true) {
        setState(() {
          _dataPerTanggal =
              List<Map<String, dynamic>>.from(res['data'] ?? []);
          _saldoTotal = (res['saldo_total'] as num?)?.toDouble() ?? 0.0;
        });
      } else {
        setState(() => _errorMessage =
            res['message']?.toString() ?? 'Gagal memuat data kas kecil.');
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
      final res = await PettyCashService.voidPettyCash(paymentId: paymentID);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(res['message']?.toString() ?? '')),
      );

      if (res['success'] == true) {
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
          _JurnalSheet(paymentID: paymentID, kode: kode),
    );
  }

  String _rp(num value) => NumberFormat.decimalPattern('id_ID').format(value);

  // Total jumlah baris transaksi di seluruh grup tanggal yang sedang
  // tampil (dipakai utk badge "N Transaksi").
  int get _totalTransaksiCount {
    var total = 0;
    for (final harian in _dataPerTanggal) {
      total += List.from(harian['transaksi'] ?? []).length;
    }
    return total;
  }

  // Backend belum mengirim saldo awal periode secara eksplisit, jadi
  // dihitung di sisi klien: saldo_total (posisi akhir periode) dikurangi
  // total mutasi bersih (masuk - keluar) selama periode yang tampil.
  double get _saldoAwalPeriode {
    var netMutasi = 0.0;
    for (final harian in _dataPerTanggal) {
      final transaksi =
          List<Map<String, dynamic>>.from(harian['transaksi'] ?? []);
      for (final trx in transaksi) {
        final masuk = double.tryParse('${trx['uang_masuk'] ?? 0}') ?? 0;
        final keluar = double.tryParse('${trx['uang_keluar'] ?? 0}') ?? 0;
        netMutasi += masuk - keluar;
      }
    }
    return _saldoTotal - netMutasi;
  }

  // Nama bulan pendek ditulis manual (bukan lewat DateFormat(..., 'id_ID'))
  // supaya tidak butuh initializeDateFormatting('id_ID') yang belum tentu
  // dipanggil di main.dart — sebelumnya inilah penyebab
  // "LocaleDataException: Locale data has not been initialized".
  static const List<String> _bulanPendek = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'Mei',
    'Jun',
    'Jul',
    'Agu',
    'Sep',
    'Okt',
    'Nov',
    'Des',
  ];

  String _formatTanggalPendek(DateTime d) =>
      '${d.day} ${_bulanPendek[d.month - 1]} ${d.year}';

  String get _periodeText =>
      '${_formatTanggalPendek(_startDate)} – ${_formatTanggalPendek(_endDate)}';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Kas Kecil'),
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final bool compact = constraints.maxWidth < 800;

          return SingleChildScrollView(
            padding: EdgeInsets.fromLTRB(
              compact ? 12 : 24,
              12,
              compact ? 12 : 24,
              20,
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (widget.outlets.length > 1) ...[
                  _buildStoreField(),
                  const SizedBox(height: 12),
                ],
                _buildSummaryCard(compact),
                const SizedBox(height: 14),
                _buildDateFilter(compact),
                if (_errorMessage != null) ...[
                  const SizedBox(height: 12),
                  Text(_errorMessage!, style: const TextStyle(color: _red)),
                ],
                const SizedBox(height: 16),
                _buildTransactionCard(),
              ],
            ),
          );
        },
      ),
    );
  }

  Widget _buildStoreField() {
    return DropdownButtonFormField<int>(
      value: _selectedStoreId,
      decoration: InputDecoration(
        labelText: 'Store',
        filled: true,
        fillColor: Colors.white,
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(13),
          borderSide: const BorderSide(color: _fieldBorderGray),
        ),
        isDense: true,
      ),
      items: widget.outlets
          .map((o) => DropdownMenuItem(value: o, child: Text('Store $o')))
          .toList(),
      onChanged: _onStoreChanged,
    );
  }

  Widget _buildSummaryCard(bool compact) {
    final saldoCard = Container(
      padding: EdgeInsets.symmetric(
        horizontal: compact ? 16 : 20,
        vertical: compact ? 16 : 12,
      ),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [_summaryGradientStart, _summaryGradientEnd],
        ),
        borderRadius: BorderRadius.circular(18),
        boxShadow: [
          BoxShadow(
            color: _navy.withOpacity(0.12),
            blurRadius: 12,
            offset: const Offset(0, 5),
          ),
        ],
      ),
      child: compact
          ? Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _summaryHeaderRow(),
                const SizedBox(height: 14),
                Row(
                  children: [
                    Expanded(
                        child: _summaryInfo(Icons.calendar_month_outlined,
                            'Periode', _periodeText)),
                    _summaryDivider(),
                    Expanded(
                        child: _summaryInfo(Icons.description_outlined,
                            'Saldo Awal', 'Rp ${_rp(_saldoAwalPeriode)}')),
                  ],
                ),
              ],
            )
          : Row(
              children: [
                Expanded(
                  flex: 2,
                  child: _summaryHeaderRow(),
                ),
                _summaryDivider(),
                Expanded(
                  flex: 2,
                  child: _summaryInfo(
                      Icons.calendar_month_outlined, 'Periode', _periodeText),
                ),
                _summaryDivider(),
                Expanded(
                  flex: 2,
                  child: _summaryInfo(
                    Icons.description_outlined,
                    'Saldo Awal',
                    'Rp ${_rp(_saldoAwalPeriode)}',
                  ),
                ),
              ],
            ),
    );

    final tambahButton = InkWell(
      borderRadius: BorderRadius.circular(18),
      onTap: _selectedStoreId == null ? null : _openEntry,
      child: Container(
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: _blue,
          borderRadius: BorderRadius.circular(18),
          boxShadow: [
            BoxShadow(
              color: _blue.withOpacity(0.20),
              blurRadius: 12,
              offset: const Offset(0, 5),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 46,
              height: 46,
              decoration: BoxDecoration(
                color: Colors.white.withOpacity(0.18),
                borderRadius: BorderRadius.circular(14),
              ),
              child: const Icon(Icons.add, color: Colors.white, size: 28),
            ),
            const SizedBox(width: 12),
            const Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Tambah',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  SizedBox(height: 2),
                  Text(
                    'Pengeluaran / Pemasukan',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(color: Color(0xFFE4EDFF), fontSize: 12),
                  ),
                ],
              ),
            ),
            const Icon(Icons.chevron_right, color: Colors.white, size: 26),
          ],
        ),
      ),
    );

    if (compact) {
      return Column(
        children: [
          saldoCard,
          const SizedBox(height: 12),
          tambahButton,
        ],
      );
    }

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(flex: 2, child: saldoCard),
          const SizedBox(width: 14),
          Expanded(flex: 1, child: tambahButton),
        ],
      ),
    );
  }

  Widget _summaryHeaderRow() {
    return Row(
      children: [
        Container(
          width: 42,
          height: 42,
          decoration: BoxDecoration(
            color: _blue.withOpacity(0.85),
            borderRadius: BorderRadius.circular(15),
          ),
          child: const Icon(Icons.account_balance_wallet_outlined,
              color: Colors.white, size: 22),
        ),
        const SizedBox(width: 10),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Text(
                'Saldo Kas Kecil',
                style: TextStyle(
                  color: Color(0xFFD8E0F1),
                  fontSize: 11,
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                'Rp ${_rp(_saldoTotal)}',
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.w800,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryInfo(IconData icon, String label, String value) {
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(icon, color: Colors.white, size: 20),
        const SizedBox(width: 8),
        Flexible(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(label,
                  style:
                      const TextStyle(color: Color(0xFFBAC7DF), fontSize: 11)),
              const SizedBox(height: 3),
              Text(
                value,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _summaryDivider() {
    return Container(
      height: 44,
      width: 1,
      margin: const EdgeInsets.symmetric(horizontal: 14),
      color: Colors.white.withOpacity(0.20),
    );
  }

  Widget _buildDateFilter(bool compact) {
    return Row(
      children: [
        Expanded(
          child: _buildDateField(
            'Dari',
            DateFormat('yyyy-MM-dd').format(_startDate),
            () => _pickDate(isStart: true),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: _buildDateField(
            'Sampai',
            DateFormat('yyyy-MM-dd').format(_endDate),
            () => _pickDate(isStart: false),
          ),
        ),
        const SizedBox(width: 10),
        SizedBox(
          width: compact ? 84 : 120,
          height: 58,
          child: OutlinedButton.icon(
            onPressed: _selectedStoreId == null ? null : _loadData,
            icon: const Icon(Icons.filter_alt_outlined, size: 19),
            label: const Text('Filter'),
            style: OutlinedButton.styleFrom(
              foregroundColor: _navy,
              side: const BorderSide(color: _fieldBorderGray),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(13),
              ),
              backgroundColor: Colors.white,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildDateField(String label, String value, VoidCallback onTap) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(13),
      child: Container(
        height: 58,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(13),
          border: Border.all(color: _fieldBorderGray),
        ),
        child: Row(
          children: [
            const Icon(Icons.calendar_month_outlined,
                color: Color(0xFF294675), size: 19),
            const SizedBox(width: 8),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label,
                      style: const TextStyle(
                          color: Color(0xFF7283A3), fontSize: 11)),
                  const SizedBox(height: 2),
                  Text(
                    value,
                    style: const TextStyle(
                      color: Color(0xFF1D335D),
                      fontSize: 13,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            const Icon(Icons.keyboard_arrow_down,
                color: Color(0xFF526785), size: 20),
          ],
        ),
      ),
    );
  }

  Widget _buildTransactionCard() {
    return Container(
      decoration: BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: _borderGray),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(18, 16, 18, 12),
            child: Row(
              children: [
                const Text(
                  'Riwayat Transaksi',
                  style: TextStyle(
                    color: Color(0xFF1C355F),
                    fontSize: 18,
                    fontWeight: FontWeight.w800,
                  ),
                ),
                const Spacer(),
                Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                  decoration: BoxDecoration(
                    color: const Color(0xFFEAF3FF),
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Text(
                    '$_totalTransaksiCount Transaksi',
                    style: const TextStyle(
                      color: Color(0xFF2370E8),
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const Divider(height: 1),
          if (_isLoading)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (_dataPerTanggal.isEmpty)
            const Padding(
              padding: EdgeInsets.all(24),
              child: Center(child: Text('Tidak ada data pada periode ini.')),
            )
          else
            for (final harian in _dataPerTanggal) _buildDayGroup(harian),
        ],
      ),
    );
  }

  Widget _buildDayGroup(Map<String, dynamic> harian) {
    final tanggal = '${harian['tanggal'] ?? ''}';
    final transaksi =
        List<Map<String, dynamic>>.from(harian['transaksi'] ?? []);
    final saldoHarian = double.tryParse('${harian['saldo_harian'] ?? 0}') ?? 0;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 9),
          decoration: const BoxDecoration(
            gradient: LinearGradient(
              colors: [_navy, _navyGradientEnd],
              begin: Alignment.centerLeft,
              end: Alignment.centerRight,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                tanggal,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 13,
                    fontWeight: FontWeight.w700),
              ),
              Text(
                'Saldo Harian: Rp ${_rp(saldoHarian)}',
                style: const TextStyle(
                  color: Color(0xFFBAC7DF),
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                ),
              ),
            ],
          ),
        ),
        for (final trx in transaksi) _buildTrxRow(trx),
      ],
    );
  }

  Widget _buildTrxRow(Map<String, dynamic> trx) {
    final masuk = double.tryParse('${trx['uang_masuk'] ?? 0}') ?? 0;
    final keluar = double.tryParse('${trx['uang_keluar'] ?? 0}') ?? 0;
    final saldo = double.tryParse('${trx['saldo_berjalan'] ?? 0}') ?? 0;
    final paymentID = int.tryParse('${trx['payment_id'] ?? 0}') ?? 0;
    final kode = '${trx['kode'] ?? ''}';
    final keterangan = '${trx['keterangan'] ?? ''}';
    final income = masuk > 0;

    return InkWell(
      onTap: () => _showJurnal(paymentID, kode),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 12),
        decoration: const BoxDecoration(
          border: Border(bottom: BorderSide(color: _borderGray, width: 0.6)),
        ),
        child: Row(
          children: [
            // Detil transaksi: tanpa ikon, subtext memakai nomor transaksi
            // (kode), bukan deskripsi/keterangan tambahan.
            Expanded(
              flex: 3,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    keterangan,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: _titleNavy,
                      fontSize: 14,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    kode,
                    style: const TextStyle(color: _mutedGray, fontSize: 12),
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
              decoration: BoxDecoration(
                color: income ? _incomeGreenBg : _expenseBlueBg,
                borderRadius: BorderRadius.circular(15),
              ),
              child: Text(
                income ? 'Pemasukan' : 'Pengeluaran',
                style: TextStyle(
                  color: income ? _incomeGreenText : _expenseBlueText,
                  fontSize: 11,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
            const SizedBox(width: 12),
            SizedBox(
              width: 130,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    masuk > 0
                        ? '+ Rp ${_rp(masuk)}'
                        : (keluar > 0 ? '- Rp ${_rp(keluar)}' : '-'),
                    style: TextStyle(
                      color: masuk > 0
                          ? _incomeGreenText
                          : (keluar > 0 ? _red : Colors.grey),
                      fontSize: 14,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'Saldo: Rp ${_rp(saldo)}',
                    style: const TextStyle(color: _mutedGray, fontSize: 11),
                  ),
                ],
              ),
            ),
            IconButton(
              icon: const Icon(Icons.delete_outline, color: _red, size: 20),
              onPressed: () => _confirmVoid(paymentID, kode),
              tooltip: 'Void',
              padding: EdgeInsets.zero,
              constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
            ),
          ],
        ),
      ),
    );
  }
}

// ─── Bottom sheet: detail jurnal + foto nota ───────────────────
class _JurnalSheet extends StatefulWidget {
  final int paymentID;
  final String kode;

  const _JurnalSheet(
      {required this.paymentID, required this.kode});

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
      final res = await PettyCashService.getJournalDetail(
        paymentId: widget.paymentID,
      );

      if (!mounted) return;
      setState(() {
        _detil = List<Map<String, dynamic>>.from(res['detil'] ?? []);
        _images = List<String>.from(res['images'] ?? []);
        _totalDebit = (res['total_debit'] as num?)?.toDouble() ?? 0.0;
        _totalKredit = (res['total_kredit'] as num?)?.toDouble() ?? 0.0;
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
