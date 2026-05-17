import 'dart:convert';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class PrinterHelper {
  // ── Scan device bluetooth yang tersedia ─────────────────────
  static Future<List<BluetoothInfo>> scanDevices() async {
    bool isConnected = await PrintBluetoothThermal.connectionStatus;
    if (isConnected) {
      await PrintBluetoothThermal.disconnect;
    }
    List<BluetoothInfo> devices =
        await PrintBluetoothThermal.pairedBluetooths;
    return devices;
  }

  // ── Connect ke printer ───────────────────────────────────────
  static Future<bool> connect(String macAddress) async {
    bool result = await PrintBluetoothThermal.connect(
        macPrinterAddress: macAddress);
    return result;
  }

  // ── Disconnect ───────────────────────────────────────────────
  static Future<void> disconnect() async {
    await PrintBluetoothThermal.disconnect;
  }

  // ── Cek status koneksi ───────────────────────────────────────
  static Future<bool> isConnected() async {
    return await PrintBluetoothThermal.connectionStatus;
  }

  // ── Print invoice (customer copy) ───────────────────────────
  //
  // [copyCount] — berapa kali invoice ini sudah dicetak (termasuk ini).
  //   copyCount == 1  → first print, tidak ada ribbon COPY
  //   copyCount >= 2  → reprint, tampilkan ribbon "***** COPY N *****"
  //   Nilai N = copyCount - 1  (misal print ke-2 = COPY 1, ke-3 = COPY 2)
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
    // ── Field opsional ──────────────────────────────────────────
    int copyCount = 1,         // 1 = first print, >=2 = reprint
    double storeTax = 0,       // dari dim_divisi.tax — jika > 0 tampilkan DPP & pajak
    String? voucherKode,
    String? npwp,
    String? invoiceNote,       // dari dim_divisi.invoice_note
    String? salesTipe,         // dari dim_salestipe.nama — channel penjualan
  }) async {
    final profile   = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // ── HEADER ──────────────────────────────────────────────────
    bytes += generator.text(
      storeName,
      styles: const PosStyles(
        align: PosAlign.center,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
        bold: true,
      ),
    );
    if (storeAddress.isNotEmpty) {
      bytes += generator.text(
        storeAddress,
        styles: const PosStyles(align: PosAlign.center),
      );
    }

    // NPWP
    final npwpText = (npwp != null && npwp.isNotEmpty)
        ? npwp
        : '0 00.000.000.0-000.000';
    bytes += generator.text(
      'NPWP: $npwpText',
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.hr();

    // ── RIBBON COPY — hanya muncul saat reprint ──────────────────
    if (copyCount >= 2) {
      final copyNum = copyCount - 1;
      bytes += generator.text(
        '***** COPY $copyNum *****',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.hr();
    }

    // ── INFO TRANSAKSI ───────────────────────────────────────────
    bytes += generator.text('No : $invoiceNumber');
    bytes += generator.text('Tgl: $tanggal');
    bytes += generator.text('Kas: $kasir');
    if (memberNama.isNotEmpty) {
      bytes += generator.text('Mbr: $memberNama');
    }

    // ── Channel penjualan ────────────────────────────────────────
    if (salesTipe != null && salesTipe.isNotEmpty) {
      bytes += generator.hr();
      bytes += generator.text(
        salesTipe.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
        ),
      );
    }

    bytes += generator.hr();

    // ── ITEM LIST ────────────────────────────────────────────────
    for (var item in items) {
      final packagesNotesRaw = item['packages_notes'] as String? ?? '';
      final isPackage = packagesNotesRaw.isNotEmpty;

      // Nama produk
      bytes += generator.text(
        item['nama'] as String,
        styles: const PosStyles(bold: true),
      );

      // Baris qty × harga = subtotal
      final qty      = item['qty'];
      final hpj      = _formatNumber(item['hpj']);
      final subtotal = _formatNumber(item['subtotal']);
      bytes += generator.text('  $qty x $hpj = $subtotal');

      // Diskon (jika ada)
      if ((item['diskon_persen'] ?? 0) > 0) {
        bytes += generator.text('  Diskon: ${item['diskon_persen']}%');
      } else if ((item['diskon_nominal'] ?? 0) > 0) {
        bytes += generator.text(
            '  Diskon: ${_formatNumber(item['diskon_nominal'])}');
      }

      // ── Sub-item package ───────────────────────────────────────
      if (isPackage) {
        final packageLines = _buildPackageLines(packagesNotesRaw);
        for (final line in packageLines) {
          bytes += generator.text(line);
        }
      }
    }

    bytes += generator.hr();

    // ── SUMMARY ──────────────────────────────────────────────────
    bytes += generator.row([
      PosColumn(text: 'Gross', width: 6),
      PosColumn(
        text: _formatNumber(gross),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    if (diskon > 0) {
      bytes += generator.row([
        PosColumn(text: 'Diskon', width: 6),
        PosColumn(
          text: _formatNumber(diskon),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    if (voucherKode != null && voucherKode.isNotEmpty) {
      bytes += generator.row([
        PosColumn(text: 'Voucher', width: 6),
        PosColumn(
          text: voucherKode,
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
    }

    bytes += generator.hr();

    // TOTAL — double size
    bytes += generator.row([
      PosColumn(
        text: 'TOTAL',
        width: 6,
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
      PosColumn(
        text: _formatNumber(total),
        width: 6,
        styles: const PosStyles(
          align: PosAlign.right,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    ]);

    bytes += generator.hr();

    // Bayar & kembali
    bytes += generator.row([
      PosColumn(text: 'Bayar ($caraBayar)', width: 6),
      PosColumn(
        text: _formatNumber(nominalBayar),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);
    bytes += generator.row([
      PosColumn(
        text: 'Kembali',
        width: 6,
        styles: const PosStyles(bold: true),
      ),
      PosColumn(
        text: _formatNumber(kembalian),
        width: 6,
        styles: const PosStyles(align: PosAlign.right, bold: true),
      ),
    ]);

    bytes += generator.hr();

    // ── DPP & PAJAK — hanya tampil jika storeTax > 0 dan pajak > 0 ──
    if (storeTax > 0 && pajak > 0) {
      bytes += generator.row([
        PosColumn(text: 'DPP', width: 6),
        PosColumn(
          text: _formatNumber(dpp),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.row([
        PosColumn(text: 'Pajak', width: 6),
        PosColumn(
          text: _formatNumber(pajak),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);
      bytes += generator.hr();
    }

    // ── FOOTER — dari dim_divisi.invoice_note ────────────────────
    final noteText = (invoiceNote != null && invoiceNote.isNotEmpty)
        ? invoiceNote.replaceAll(RegExp(r'<[^>]*>'), '').trim()
        : 'Terima kasih atas kunjungan Anda';
    bytes += generator.text(
      noteText,
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.feed(3);
    bytes += generator.cut();

    return await PrintBluetoothThermal.writeBytes(bytes);
  }

  // ── Print kitchen order ──────────────────────────────────────
  //
  // Struk untuk dapur: tidak ada harga per item, hanya list item
  // beserta qty + catatan isian/addon. Di bawah hanya tampil
  // TOTAL akhir (tanpa breakdown gross/diskon/dll).
  //
  // Parameter [tableInfo] opsional — bisa diisi "Meja 3", "Takeaway",
  // nama customer, dll. sesuai kebutuhan bisnis.
  //
  // [copyCount] — sama seperti printInvoice, >= 2 = reprint ribbon
  static Future<bool> printKitchen({
    required String storeName,
    required String invoiceNumber,
    required String tanggal,
    required String kasir,
    required List<Map<String, dynamic>> items,
    required double total,
    int copyCount = 1,       // 1 = first print, >=2 = reprint
    String? tableInfo,       // meja / nama customer / takeaway
    String? salesTipe,       // channel penjualan (dine-in, takeaway, dll)
    String? orderNote,       // catatan order keseluruhan
  }) async {
    final profile   = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // ── HEADER KITCHEN ───────────────────────────────────────────
    bytes += generator.text(
      '*** KITCHEN ORDER ***',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
        height: PosTextSize.size2,
        width: PosTextSize.size2,
      ),
    );
    bytes += generator.text(
      storeName,
      styles: const PosStyles(align: PosAlign.center, bold: true),
    );

    bytes += generator.hr();

    // ── RIBBON COPY KITCHEN — hanya saat reprint ─────────────────
    if (copyCount >= 2) {
      final copyNum = copyCount - 1;
      bytes += generator.text(
        '***** COPY $copyNum *****',
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
      bytes += generator.hr();
    }

    // ── INFO ORDER ───────────────────────────────────────────────
    bytes += generator.text('No : $invoiceNumber');
    bytes += generator.text('Tgl: $tanggal');
    bytes += generator.text('Kas: $kasir');

    if (tableInfo != null && tableInfo.isNotEmpty) {
      bytes += generator.text(
        'Meja: $tableInfo',
        styles: const PosStyles(bold: true),
      );
    }

    // ── Channel / tipe order ─────────────────────────────────────
    if (salesTipe != null && salesTipe.isNotEmpty) {
      bytes += generator.hr();
      bytes += generator.text(
        salesTipe.toUpperCase(),
        styles: const PosStyles(
          align: PosAlign.center,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );
    }

    bytes += generator.hr();

    // ── ITEM LIST (tanpa harga) ──────────────────────────────────
    for (var item in items) {
      final packagesNotesRaw = item['packages_notes'] as String? ?? '';
      final isPackage = packagesNotesRaw.isNotEmpty;

      // Nama + qty — bold, ukuran lebih besar agar mudah dibaca dapur
      final qty  = item['qty'];
      final nama = item['nama'] as String;
      bytes += generator.text(
        '$qty x $nama',
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      );

      // Catatan item (jika ada kolom 'note' per item)
      final itemNote = item['note'] as String? ?? '';
      if (itemNote.isNotEmpty) {
        bytes += generator.text('  >> $itemNote');
      }

      // ── Sub-item package ───────────────────────────────────────
      if (isPackage) {
        final packageLines = _buildPackageLines(packagesNotesRaw);
        for (final line in packageLines) {
          bytes += generator.text(line);
        }
      }
    }

    bytes += generator.hr();

    // ── TOTAL (hanya angka akhir, tanpa breakdown) ───────────────
    bytes += generator.row([
      PosColumn(
        text: 'TOTAL',
        width: 6,
        styles: const PosStyles(
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
      PosColumn(
        text: _formatNumber(total),
        width: 6,
        styles: const PosStyles(
          align: PosAlign.right,
          bold: true,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
        ),
      ),
    ]);

    bytes += generator.hr();

    // ── Catatan order keseluruhan ────────────────────────────────
    if (orderNote != null && orderNote.isNotEmpty) {
      bytes += generator.text(
        'Catatan: $orderNote',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.hr();
    }

    bytes += generator.feed(3);
    bytes += generator.cut();

    return await PrintBluetoothThermal.writeBytes(bytes);
  }

  // ── Helper: print customer + kitchen sekaligus (1 printer) ──
  //
  // Panggil method ini setelah payment sukses untuk FnB.
  // First print selalu copyCount=1 (tidak ada ribbon).
  // Jika bisnis punya 2 printer, panggil printInvoice dan
  // printKitchen secara terpisah dengan connect ke MAC masing-masing.
  static Future<({bool customer, bool kitchen})> printBoth({
    // — shared params —
    required String storeName,
    required String storeAddress,
    required String invoiceNumber,
    required String tanggal,
    required String kasir,
    required List<Map<String, dynamic>> items,
    required double total,
    // — customer-only params —
    required String memberNama,
    required double gross,
    required double diskon,
    required double dpp,
    required double pajak,
    required String caraBayar,
    required double nominalBayar,
    required double kembalian,
    double storeTax = 0,
    String? voucherKode,
    String? npwp,
    String? invoiceNote,
    // — kitchen-only params —
    String? tableInfo,
    String? orderNote,
    // — shared optional —
    String? salesTipe,
  }) async {
    final customerOk = await printInvoice(
      storeName: storeName,
      storeAddress: storeAddress,
      invoiceNumber: invoiceNumber,
      tanggal: tanggal,
      kasir: kasir,
      memberNama: memberNama,
      items: items,
      gross: gross,
      diskon: diskon,
      total: total,
      dpp: dpp,
      pajak: pajak,
      caraBayar: caraBayar,
      nominalBayar: nominalBayar,
      kembalian: kembalian,
      storeTax: storeTax,
      voucherKode: voucherKode,
      npwp: npwp,
      invoiceNote: invoiceNote,
      salesTipe: salesTipe,
      copyCount: 1, // first print, tidak ada ribbon
    );

    // Jeda singkat antar print agar buffer printer tidak penuh
    await Future.delayed(const Duration(milliseconds: 500));

    final kitchenOk = await printKitchen(
      storeName: storeName,
      invoiceNumber: invoiceNumber,
      tanggal: tanggal,
      kasir: kasir,
      items: items,
      total: total,
      tableInfo: tableInfo,
      salesTipe: salesTipe,
      orderNote: orderNote,
      copyCount: 1, // first print, tidak ada ribbon
    );

    return (customer: customerOk, kitchen: kitchenOk);
  }

  // ── Parse packages_notes dan bangun baris struk ─────────────
  //
  // Format baru (setelah fix PHP):
  //   {"isian":["Gurita","Crabstick"],"addon":[{"nama":"Bon Cabe","harga":1000},{"nama":"Topping Terpisah","harga":2000}]}
  //
  // Format lama (data yang sudah ada sebelum fix):
  //   {"isian":["Gurita","Crabstick"],"addon":["Bon Cabe","Topping Terpisah"]}
  //
  // Kedua format ditangani.
  static List<String> _buildPackageLines(String notesJson) {
    if (notesJson.isEmpty) return [];

    final List<String> lines = [];

    try {
      final Map<String, dynamic> notes = jsonDecode(notesJson);

      // ── Isian ────────────────────────────────────────────────
      final isianRaw = notes['isian'];
      if (isianRaw is List && isianRaw.isNotEmpty) {
        lines.add('  Isian:');
        for (final item in isianRaw) {
          lines.add('    * ${item.toString()}');
        }
      }

      // ── Addon ────────────────────────────────────────────────
      final addonRaw = notes['addon'];
      if (addonRaw is List && addonRaw.isNotEmpty) {
        lines.add('  Add On:');
        for (final addon in addonRaw) {
          if (addon is Map) {
            // Format baru: {"nama": "Bon Cabe", "harga": 1000}
            final nama  = addon['nama']?.toString() ?? '';
            final harga = double.tryParse(addon['harga'].toString()) ?? 0;
            if (nama.isNotEmpty) {
              final hargaStr = harga > 0 ? ' +${_formatNumber(harga)}' : '';
              lines.add('    * $nama$hargaStr');
            }
          } else {
            // Format lama: string biasa tanpa harga
            if (addon.toString().isNotEmpty) {
              lines.add('    * ${addon.toString()}');
            }
          }
        }
      }
    } catch (_) {
      // JSON tidak valid — skip sub-item, tidak crash
    }

    return lines;
  }

  // ── Format angka dengan titik ribuan ────────────────────────
  static String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final double val = double.tryParse(value.toString()) ?? 0;
    return val
        .toStringAsFixed(0)
        .replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }
}
