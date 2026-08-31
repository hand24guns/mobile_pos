import '../utils/currency_format.dart';

class CartItem {
  /// Primary key baris `temp_invoice` di backend. Dipakai untuk semua
  /// mutasi (updateQty/deleteItem/updateItemKeterangan/setItemFree) —
  /// penting sejak cart bisa punya 2 baris produk yang sama (harga
  /// normal + gift), yang tidak lagi bisa dibedakan lewat kode+packagesNotes.
  final int id;
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
  bool isFree;
  final String? freeReason;
  /// Eligibility produk ini untuk dijadikan gratis/gift (dim_produk.is_gift),
  /// dikirim backend sebagai produk_is_gift. Menentukan apakah tombol
  /// "Jadikan gratis" ditampilkan untuk baris ini di cart.
  final bool isGiftEligible;

  CartItem({
    required this.id,
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
    this.isFree = false,
    this.freeReason,
    this.isGiftEligible = false,
  }) : subtotal = subtotal ?? (qty * hpj);

  double get gross => qty * hpj;

  /// Item ini punya isian/addon package (bukan produk single).
  /// Dipakai untuk menentukan apakah tombol "Edit pilihan" ditampilkan.
  bool get isPackage => packagesNotes != null && packagesNotes!.isNotEmpty;

  String get diskonLabel {
    if (isFree) return 'GRATIS';
    if (diskonPersen > 0) return '${diskonPersen.toStringAsFixed(0)}%';
    if (diskonNominal > 0) return CurrencyFormat.format(diskonNominal);
    return '-';
  }

  factory CartItem.fromJson(Map<String, dynamic> json) {
    return CartItem(
      id: int.tryParse(json['id'].toString()) ?? 0,
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
      isFree: (json['is_free']?.toString() ?? '0') == '1',
      freeReason: (json['free_reason'] as String?)?.isNotEmpty == true
          ? json['free_reason'] as String
          : null,
      isGiftEligible: (json['produk_is_gift']?.toString() ?? '0') == '1',
    );
  }
}
