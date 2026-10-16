import 'package:flutter/material.dart';

const Color _navy = Color(0xFF0D1B3E);
const Color _blue = Color(0xFF2563EB);
const Color _bgGray = Color(0xFFF0F4FA);

// ============================================================
// SCREEN: TransferOrderScreen (placeholder)
// ============================================================
// Halaman sementara untuk menu Transfer Order selama fitur masih
// dikembangkan. Nanti diganti dengan halaman asli: 2 card
// (Barang Masuk & Ajuan Penyesuaian) dalam satu page.
//
// [outlets] sudah disiapkan supaya signature-nya sama dengan
// LaporanScreen / KasKecilScreen dan home screen tidak perlu diubah
// saat halaman aslinya dibuat.
class TransferOrderScreen extends StatelessWidget {
  final List<int> outlets;

  const TransferOrderScreen({super.key, this.outlets = const []});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _bgGray,
      appBar: AppBar(
        backgroundColor: _navy,
        foregroundColor: Colors.white,
        title: const Text('Transfer Order'),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 420),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Container(
                  width: 96,
                  height: 96,
                  decoration: const BoxDecoration(
                    color: Colors.white,
                    shape: BoxShape.circle,
                  ),
                  child: const Icon(
                    Icons.construction_rounded,
                    color: _blue,
                    size: 48,
                  ),
                ),
                const SizedBox(height: 24),
                const Text(
                  'Sedang Dalam Pengembangan',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                    color: _navy,
                    fontWeight: FontWeight.bold,
                    fontSize: 20,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  'Fitur Transfer Order untuk menerima barang dari gudang pusat dan mengajukan penyesuaian stok akan segera tersedia.',
                  textAlign: TextAlign.center,
                  style: TextStyle(color: Colors.grey[600], fontSize: 14),
                ),
                const SizedBox(height: 24),
                ElevatedButton.icon(
                  onPressed: () => Navigator.pop(context),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: const Text('Kembali'),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: _navy,
                    foregroundColor: Colors.white,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
