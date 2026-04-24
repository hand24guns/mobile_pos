import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class PrinterHelper {
  // Scan device bluetooth yang tersedia
  static Future<List<BluetoothInfo>> scanDevices() async {
    bool isConnected = await PrintBluetoothThermal.connectionStatus;
    if (isConnected) {
      await PrintBluetoothThermal.disconnect;
    }
    List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices;
  }

  // Connect ke printer
  static Future<bool> connect(String macAddress) async {
    bool result =
        await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
    return result;
  }

  // Disconnect
  static Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
  }

  // Cek status koneksi
  static Future<bool> isConnected() async {
    return await PrintBluetoothThermal.connectionStatus;
  }

  // Print invoice
  static Future<bool> printInvoice({
    required String storeName,
    required String storeAddress,
    required String invoiceNumber,
    required String tanggal,
    required String kasir,
    required String memberNama,
    required List<Map<String, dynamic>> items,
    required double gross,
    required double diskon,
    required double total,
    required double dpp,
    required double pajak,
    required String caraBayar,
    required double nominalBayar,
    required double kembalian,
    String? voucherKode,
    String? npwp,
    String? invoiceNote,
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // Header
    bytes += generator.text(storeName,
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ));
    bytes += generator.text(storeAddress,
        styles: const PosStyles(align: PosAlign.center));

    // Tambahkan NPWP di sini
    final npwpText =
        (npwp != null && npwp.isNotEmpty) ? npwp : '0 00.000.000.0-000.000';
    bytes += generator.text('NPWP: $npwpText',
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.hr();

    // Info invoice
    bytes += generator.text('No : $invoiceNumber');
    bytes += generator.text('Tgl: $tanggal');
    bytes += generator.text('Kas: $kasir');
    if (memberNama.isNotEmpty) {
      bytes += generator.text('Mbr: $memberNama');
    }
    bytes += generator.hr();

    // Items
    for (var item in items) {
      bytes +=
          generator.text(item['nama'], styles: const PosStyles(bold: true));
      final qty = item['qty'];
      final hpj = _formatNumber(item['hpj']);
      final subtotal = _formatNumber(item['subtotal']);
      bytes += generator.text('  $qty x $hpj = $subtotal');
      if ((item['diskon_persen'] ?? 0) > 0) {
        bytes += generator.text('  Diskon: ${item['diskon_persen']}%');
      } else if ((item['diskon_nominal'] ?? 0) > 0) {
        bytes += generator
            .text('  Diskon: ${_formatNumber(item['diskon_nominal'])}');
      }
    }

    bytes += generator.hr();

    // Summary
    bytes += generator.row([
      PosColumn(text: 'Gross', width: 6),
      PosColumn(
          text: _formatNumber(gross),
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);

    if (diskon > 0) {
      bytes += generator.row([
        PosColumn(text: 'Diskon', width: 6),
        PosColumn(
            text: _formatNumber(diskon),
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    if (voucherKode != null && voucherKode.isNotEmpty) {
      bytes += generator.row([
        PosColumn(text: 'Voucher', width: 6),
        PosColumn(
            text: voucherKode,
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
    }

    bytes += generator.hr();

    bytes += generator.row([
      PosColumn(
          text: 'TOTAL',
          width: 6,
          styles: const PosStyles(
              bold: true, height: PosTextSize.size2, width: PosTextSize.size2)),
      PosColumn(
          text: _formatNumber(total),
          width: 6,
          styles: const PosStyles(
              align: PosAlign.right,
              bold: true,
              height: PosTextSize.size2,
              width: PosTextSize.size2)),
    ]);

    bytes += generator.hr();

    bytes += generator.row([
      PosColumn(text: 'Bayar ($caraBayar)', width: 6),
      PosColumn(
          text: _formatNumber(nominalBayar),
          width: 6,
          styles: const PosStyles(align: PosAlign.right)),
    ]);

    bytes += generator.row([
      PosColumn(text: 'Kembali', width: 6, styles: const PosStyles(bold: true)),
      PosColumn(
          text: _formatNumber(kembalian),
          width: 6,
          styles: const PosStyles(align: PosAlign.right, bold: true)),
    ]);

    bytes += generator.hr();

    // DPP & Pajak
    if (pajak > 0) {
      bytes += generator.row([
        PosColumn(text: 'DPP', width: 6),
        PosColumn(
            text: _formatNumber(dpp),
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Pajak', width: 6),
        PosColumn(
            text: _formatNumber(pajak),
            width: 6,
            styles: const PosStyles(align: PosAlign.right)),
      ]);
      bytes += generator.hr();
    }

    // Footer dari invoice_note
    final noteText = (invoiceNote != null && invoiceNote.isNotEmpty)
        ? invoiceNote.replaceAll(RegExp(r'<[^>]*>'), '') // strip HTML tags
        : 'Terima kasih atas kunjungan Anda';
    bytes += generator.text(noteText,
        styles: const PosStyles(align: PosAlign.center));

    bytes += generator.feed(3);
    bytes += generator.cut();

    return await PrintBluetoothThermal.writeBytes(bytes);
  }

  static String _formatNumber(dynamic value) {
    if (value == null) return '0';
    double val = double.tryParse(value.toString()) ?? 0;
    return val.toStringAsFixed(0).replaceAllMapped(
        RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'), (m) => '${m[1]}.');
  }
}
