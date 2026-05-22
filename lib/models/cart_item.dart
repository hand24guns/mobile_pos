import '../utils/currency_format.dart';

class CartItem {
  final String kode;
  final String nama;
  final String? packagesNotes;
  final double packageAddonHarga;
  final String? keterangan;
  int qty;
  double hpj;
  double diskonPersen;
  double diskonNominal;
  double subtotal;

  CartItem({
    required this.kode,
    required this.nama,
    required this.qty,
    required this.hpj,
    this.packagesNotes,
    this.packageAddonHarga = 0,
    this.keterangan,
    this.diskonPersen = 0,
    this.diskonNominal = 0,
    double? subtotal,
  }) : subtotal = subtotal ?? (qty * hpj);

  double get gross => qty * hpj;

  String get diskonLabel {
    if (diskonPersen > 0) return '${diskonPersen.toStringAsFixed(0)}%';
    if (diskonNominal > 0) return CurrencyFormat.format(diskonNominal);
    return '-';
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      kode: json['kode'] ?? '',
      nama: json['nama'] ?? '',
      qty: int.tryParse(json['qty'].toString()) ?? 0,
      hpj: double.tryParse(json['hpj'].toString().replaceAll(',', '')) ?? 0,
      packagesNotes: json['packages_notes'] as String?,
      packageAddonHarga:
          double.tryParse(json['package_addon_harga']?.toString() ?? '0') ?? 0,
      keterangan: (json['keterangan'] as String?)?.isNotEmpty == true
          ? json['keterangan'] as String
          : null,
      diskonPersen:
          double.tryParse(json['diskon_persen']?.toString() ?? '0') ?? 0,
      diskonNominal:
          double.tryParse(json['diskon_nominal']?.toString() ?? '0') ?? 0,
      subtotal:
          double.tryParse(json['subtotal'].toString().replaceAll(',', '')) ?? 0,
    );
  }
}
