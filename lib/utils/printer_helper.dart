import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:http/http.dart' as http;
import 'package:image/image.dart' as img;
import 'package:path_provider/path_provider.dart';
import 'package:print_bluetooth_thermal/print_bluetooth_thermal.dart';
import 'package:esc_pos_utils_plus/esc_pos_utils_plus.dart';

class PrinterHelper {
  // ── Ambil logo untuk print ───────────────────────────────────
  //
  // Flow:
  //   1. Cek file lokal di app documents dir → pakai langsung jika ada
  //   2. Jika tidak ada → download dari [logoUrl] → simpan lokal → pakai
  //   3. Jika gagal semua → return null (cetak tanpa logo, graceful)
  //
  // [logoFileName] — nama file saja, contoh: "logo_abc.png"
  // [logoUrl]      — full URL untuk download fallback
  static Future<img.Image?> _getLogoImage({
    required String logoFileName,
    required String logoUrl,
  }) async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final localPath = '${dir.path}/logos/$logoFileName';
      final localFile = File(localPath);

      Uint8List imageBytes;

      if (await localFile.exists()) {
        // ── Pakai file lokal (cache) ──────────────────────────
        imageBytes = await localFile.readAsBytes();
      } else {
        // ── Download dari server ──────────────────────────────
        final response = await http
            .get(Uri.parse(logoUrl))
            .timeout(const Duration(seconds: 8));
        if (response.statusCode != 200) return null;

        imageBytes = response.bodyBytes;

        // Simpan ke lokal untuk dipakai berikutnya
        await localFile.parent.create(recursive: true);
        await localFile.writeAsBytes(imageBytes);
      }

      // ── Decode & proses untuk thermal ────────────────────────
      // Resize max 200px width (proporsional), lalu grayscale
      // agar hasil cetak bersih di kertas 58mm
      final decoded = img.decodeImage(imageBytes);
      if (decoded == null) return null;

      final resized = img.copyResize(decoded, width: 200);
      final grayscaled = img.grayscale(resized);
      return grayscaled;
    } catch (_) {
      // Network error, decode error, dsb → skip logo
      return null;
    }
  }

  // ── Hapus semua cache logo lokal ─────────────────────────────
  //
  // Panggil ini saat logo toko diupdate di server,
  // supaya print berikutnya otomatis re-download yang baru.
  static Future<void> clearLogoCache() async {
    try {
      final dir = await getApplicationDocumentsDirectory();
      final logosDir = Directory('${dir.path}/logos');
      if (await logosDir.exists()) {
        await logosDir.delete(recursive: true);
      }
    } catch (_) {}
  }

  // ── Scan device bluetooth yang tersedia ─────────────────────
  static Future<List<BluetoothInfo>> scanDevices() async {
    bool isConnected = await PrintBluetoothThermal.connectionStatus;
    if (isConnected) {
      await PrintBluetoothThermal.disconnect;
    }
    List<BluetoothInfo> devices = await PrintBluetoothThermal.pairedBluetooths;
    return devices;
  }

  // ── Connect ke printer ───────────────────────────────────────
  static Future<bool> connect(String macAddress) async {
    bool result =
        await PrintBluetoothThermal.connect(macPrinterAddress: macAddress);
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
  // [items] — setiap Map boleh mengandung field berikut:
  //   'nama'            String   — nama produk (wajib)
  //   'qty'             num      — kuantitas (wajib)
  //   'hpj'             num      — harga per unit (wajib)
  //   'subtotal'        num      — qty × hpj (wajib)
  //   'diskon_persen'   num?     — diskon persen (opsional)
  //   'diskon_nominal'  num?     — diskon nominal (opsional)
  //   'packages_notes'  String?  — JSON isian/addon gabungan (opsional)
  //   'isian'           List?    — list string nama isian (opsional, fallback)
  //   'addon'           List?    — list map/string addon (opsional, fallback)
  //
  // [salesTipe] — dari dim_salestipe.nama (JOIN tr_invoice → dim_salestipe
  //   via dim_salestipe_id). Contoh: "POS - OFFLINE", "ONLINE", "DINE IN".
  //   Ditampilkan di tengah dengan bold setelah info transaksi.
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
    int copyCount = 0, // 0 = first print, >=1 = reprint
    double storeTax = 0, // dari dim_divisi.tax — jika > 0 tampilkan DPP & pajak
    String? voucherKode,
    String? npwp,
    String? invoiceNote, // dari dim_divisi.invoice_note
    String? salesTipe, // dari dim_salestipe.nama — channel penjualan
    String?
        keterangan, // catatan keseluruhan transaksi (dari tr_invoice.keterangan)
    String? logoFileName, // nama file logo saja, contoh: "logo_abc.png"
    String? logoUrl, // full URL untuk download fallback
    String? jamTransaksi, // jam transaksi dari created_date (HH:mm)
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // ── Sanitasi semua teks bebas sebelum diproses ke printer ───
    // Mencegah "Contains invalid characters" akibat smart-quote,
    // emoji, atau karakter non-ASCII lain dari input manual kasir.
    storeName = _sanitizeForPrint(storeName);
    storeAddress = _sanitizeForPrint(storeAddress);
    memberNama = _sanitizeForPrint(memberNama);
    if (npwp != null) npwp = _sanitizeForPrint(npwp);
    if (keterangan != null) keterangan = _sanitizeForPrint(keterangan);
    if (salesTipe != null) salesTipe = _sanitizeForPrint(salesTipe);
    if (voucherKode != null) voucherKode = _sanitizeForPrint(voucherKode);
    if (invoiceNote != null) invoiceNote = _sanitizeForPrint(invoiceNote);

    // ── RESET printer — pastikan mulai dari state bersih ────────
    bytes += generator.reset();

    // ── LOGO — sebelum nama toko ─────────────────────────────────
    // Cek lokal dulu, download jika belum ada, skip jika gagal
    if (logoFileName != null &&
        logoFileName.isNotEmpty &&
        logoUrl != null &&
        logoUrl.isNotEmpty) {
      final logoImage = await _getLogoImage(
        logoFileName: logoFileName,
        logoUrl: logoUrl,
      );
      if (logoImage != null) {
        bytes += generator.image(logoImage, align: PosAlign.center);
        bytes += generator.feed(1);
      }
    }

    // ── HEADER — store name dengan word-wrap ─────────────────────
    // Kertas 58mm double-size = ±16 karakter per baris.
    // _wrapWords memastikan pecah di awal kata, bukan di tengah kata.
    const int headerLineWidth = 16;
    final storeNameLines = _wrapWords(storeName, headerLineWidth);
    for (final line in storeNameLines) {
      bytes += generator.text(
        line,
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ),
      );
    }

    if (storeAddress.isNotEmpty) {
      bytes += generator.text(
        storeAddress,
        styles: const PosStyles(align: PosAlign.center),
      );
    }

    // NPWP
    final npwpText =
        (npwp != null && npwp.isNotEmpty) ? npwp : '0 00.000.000.0-000.000';
    bytes += generator.text(
      'NPWP: $npwpText',
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.hr();

    // ── FIX #4: RIBBON COPY — hanya muncul saat reprint ─────────
    if (copyCount >= 1) {
      bytes += generator.text(
        '*** COPY $copyCount ***',
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
    if (jamTransaksi != null && jamTransaksi.isNotEmpty) {
      bytes += generator.text('Jam: $jamTransaksi');
    }
    bytes += generator.text('Kas: $kasir');
    if (memberNama.isNotEmpty) {
      bytes += generator.text('Mbr: $memberNama');
    }
    if (keterangan != null && keterangan.isNotEmpty) {
      bytes += generator.text('Ket: $keterangan');
    }

    // ── FIX #3: Sales tipe / channel penjualan ───────────────────
    // Nilai dari: tr_invoice JOIN dim_salestipe ON dim_salestipe_id
    // Pass via parameter salesTipe. Contoh: "POS - OFFLINE"
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

    // ── FIX #2: ITEM LIST dengan isian & addon ───────────────────
    for (var item in items) {
      // Nama produk
      final namaProduk = _sanitizeForPrint(item['nama'] as String);
      bytes += generator.text(
        namaProduk,
        styles: const PosStyles(bold: true),
      );

      // Baris qty × harga = subtotal
      final qty = item['qty'];
      final hpj = _formatNumber(item['hpj']);
      final subtotal = _formatNumber(item['subtotal']);
      bytes += generator.text('  $qty x $hpj = $subtotal');

      // Diskon (jika ada)
      if ((item['diskon_persen'] ?? 0) > 0) {
        bytes += generator.text('  Diskon: ${item['diskon_persen']}%');
      } else if ((item['diskon_nominal'] ?? 0) > 0) {
        bytes += generator
            .text('  Diskon: ${_formatNumber(item['diskon_nominal'])}');
      }

      // ── Sub-item: isian & addon ──────────────────────────────
      // Prioritas 1: packages_notes (JSON string gabungan)
      // Prioritas 2: field 'isian' dan 'addon' langsung di map item
      final packagesNotesRaw = item['packages_notes'] as String? ?? '';
      if (packagesNotesRaw.isNotEmpty) {
        final packageLines = _buildPackageLines(packagesNotesRaw);
        for (final line in packageLines) {
          bytes += generator.text(line);
        }
      } else {
        // Fallback: baca field isian/addon langsung dari item map
        final packageLines = _buildPackageLinesFromMap(item);
        for (final line in packageLines) {
          bytes += generator.text(line);
        }
      }

      // Keterangan per item (jika ada)
      final itemKet = _sanitizeForPrint(item['keterangan'] as String? ?? '');
      if (itemKet.isNotEmpty) {
        bytes += generator.text('  >> Note : $itemKet');
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

    // ── Bayar ────────────────────────────────────────────────────
    bytes += generator.text('Bayar :');
    bytes += generator.row([
      PosColumn(text: caraBayar, width: 6),
      PosColumn(
        text: _formatNumber(nominalBayar),
        width: 6,
        styles: const PosStyles(align: PosAlign.right),
      ),
    ]);

    // ── Kembali — hanya untuk pembayaran tunai ───────────────────
    final isCash = caraBayar.toLowerCase().contains('cash') ||
        caraBayar.toLowerCase().contains('tunai');

    if (isCash) {
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
    }

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
        ? _sanitizeForPrint(
            invoiceNote.replaceAll(RegExp(r'<[^>]*>'), '').trim())
        : 'Terima kasih atas kunjungan Anda';
    bytes += generator.text(
      noteText,
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.feed(1);
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
  static Future<bool> printKitchen({
    required String storeName,
    required String invoiceNumber,
    required String tanggal,
    required String kasir,
    required List<Map<String, dynamic>> items,
    double total =
        0, // tidak dipakai di struk, disimpan untuk kompatibilitas caller
    int copyCount = 0, // 0 = first print, >=1 = reprint
    String memberNama = '', // nama member — tampil di bawah kasir
    String? tableInfo, // meja / nama customer / takeaway
    String? salesTipe, // channel penjualan (dine-in, takeaway, dll)
    String? orderNote, // catatan order keseluruhan
    String? keterangan, // catatan transaksi (dari tr_invoice.keterangan)
    String? jamTransaksi, // jam transaksi dari created_date (HH:mm)
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // ── Sanitasi semua teks bebas sebelum diproses ke printer ───
    storeName = _sanitizeForPrint(storeName);
    memberNama = _sanitizeForPrint(memberNama);
    if (tableInfo != null) tableInfo = _sanitizeForPrint(tableInfo);
    if (salesTipe != null) salesTipe = _sanitizeForPrint(salesTipe);
    if (orderNote != null) orderNote = _sanitizeForPrint(orderNote);
    if (keterangan != null) keterangan = _sanitizeForPrint(keterangan);

    // ── RESET printer — pastikan mulai dari state bersih ────────
    bytes += generator.reset();

    // ── HEADER KITCHEN ───────────────────────────────────────────
    bytes += generator.text(
      '*** KITCHEN ORDER ***',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
      ),
    );

    // Store name dengan word-wrap (normal size, tidak double di kitchen)
    const int kitchenHeaderWidth = 32;
    final storeNameLines = _wrapWords(storeName, kitchenHeaderWidth);
    for (final line in storeNameLines) {
      bytes += generator.text(
        line,
        styles: const PosStyles(align: PosAlign.center, bold: true),
      );
    }

    bytes += generator.hr();

    // ── RIBBON COPY KITCHEN — hanya saat reprint ─────────────────
    if (copyCount >= 1) {
      bytes += generator.text(
        '*** COPY $copyCount ***',
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
    if (jamTransaksi != null && jamTransaksi.isNotEmpty) {
      bytes += generator.text('Jam: $jamTransaksi');
    }
    bytes += generator.text('Kas: $kasir');
    if (memberNama.isNotEmpty) {
      bytes += generator.text('Mbr: $memberNama');
    }
    if (keterangan != null && keterangan.isNotEmpty) {
      bytes += generator.text('Ket: $keterangan');
    }

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
    //
    // Lebar kertas 58mm normal size = ~32 char per baris.
    // Format: baris pertama  "1 x Nama Awal"
    //         baris lanjutan "    Nama Lanjutan"
    const int kitchenLineWidth = 32; // char per baris untuk normal size
    for (var item in items) {
      final qty = item['qty'];
      final nama = _sanitizeForPrint(item['nama'] as String);

      // Prefix baris pertama: "1 x " — lanjutan: spasi sejumlah prefix
      final prefix = '$qty x ';
      final prefixBlank = ' ' * prefix.length;
      final namaLines = _wrapWords(nama, kitchenLineWidth - prefix.length);

      for (int i = 0; i < namaLines.length; i++) {
        final lineText = (i == 0 ? prefix : prefixBlank) + namaLines[i];
        bytes += generator.text(
          lineText,
          styles: const PosStyles(bold: true),
        );
      }

      // ── Sub-item package (isian & addon) — tanpa harga addon ──
      final packagesNotesRaw = item['packages_notes'] as String? ?? '';
      if (packagesNotesRaw.isNotEmpty) {
        final packageLines =
            _buildPackageLines(packagesNotesRaw, showAddonPrice: false);
        for (final line in packageLines) {
          bytes += generator.text(line);
        }
      } else {
        final packageLines =
            _buildPackageLinesFromMap(item, showAddonPrice: false);
        for (final line in packageLines) {
          bytes += generator.text(line);
        }
      }

      // Catatan item (jika ada kolom 'note' per item)
      final itemNote = _sanitizeForPrint(item['note'] as String? ?? '');
      if (itemNote.isNotEmpty) {
        bytes += generator.text('  >> Note: $itemNote');
      }

      // Keterangan per item (dari kolom keterangan temp_invoice / tr_invoicedetil)
      final itemKet = _sanitizeForPrint(item['keterangan'] as String? ?? '');
      if (itemKet.isNotEmpty) {
        bytes += generator.text('  >> Note: $itemKet');
      }
    }

    bytes += generator.hr();

    // ── Catatan order keseluruhan ────────────────────────────────
    if (orderNote != null && orderNote.isNotEmpty) {
      bytes += generator.text(
        'Catatan: $orderNote',
        styles: const PosStyles(bold: true),
      );
      bytes += generator.hr();
    }

    bytes += generator.feed(1);
    bytes += generator.cut();

    return await PrintBluetoothThermal.writeBytes(bytes);
  }

  // ── Helper: print customer + kitchen sekaligus (1 printer) ──
  //
  // Panggil method ini setelah payment sukses untuk FnB.
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
    String? keterangan, // catatan transaksi — diteruskan ke customer & kitchen
    String? logoFileName, // nama file logo — hanya untuk customer copy
    String? logoUrl, // full URL fallback download logo
    String? jamTransaksi, // jam transaksi — diteruskan ke customer & kitchen
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
      keterangan: keterangan,
      logoFileName: logoFileName,
      logoUrl: logoUrl,
      jamTransaksi: jamTransaksi,
      copyCount: 0,
    );

    await Future.delayed(const Duration(milliseconds: 500));

    final kitchenOk = await printKitchen(
      storeName: storeName,
      invoiceNumber: invoiceNumber,
      tanggal: tanggal,
      kasir: kasir,
      memberNama: memberNama,
      items: items,
      total: total,
      tableInfo: tableInfo,
      salesTipe: salesTipe,
      orderNote: orderNote,
      keterangan: keterangan,
      jamTransaksi: jamTransaksi,
      copyCount: 0,
    );

    return (customer: customerOk, kitchen: kitchenOk);
  }

  // ── Print struk pending order (customer copy, lengkap dengan harga) ─
  //
  // Struk untuk customer saat order di-hold (pending payment).
  // Sekarang disamakan dengan printInvoice — item list, diskon,
  // isian/addon, dan summary Diskon/Voucher/TOTAL semuanya identik.
  // Perbedaan dengan printInvoice:
  //   • Header "*** PENDING ORDER ***" sebelum nama toko
  //   • Tidak ada section Bayar / Cara Bayar / Kembali — diganti satu
  //     baris keterangan "--- Belum Dibayar ---" (bold, center)
  //   • Tidak ada ribbon COPY (selalu first print)
  //   • Tidak ada DPP / Pajak
  //   • Gross & Diskon hanya tampil jika diskon > 0 — jika tidak ada
  //     diskon, langsung tampilkan TOTAL saja
  //
  // [items] — sama seperti printInvoice: 'nama', 'qty', 'hpj', 'subtotal',
  //           'diskon_persen'/'diskon_nominal', 'packages_notes'
  //           (atau fallback 'isian'/'addon'), 'keterangan'.
  // [gross] / [diskon] / [total] — sama seperti printInvoice.
  static Future<bool> printPendingOrder({
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
    // ── Field opsional ────────────────────────────────────────────
    String? voucherKode,
    String? npwp,
    String? invoiceNote,
    String? salesTipe,
    String? keterangan,
    String? logoFileName,
    String? logoUrl,
    String? jamTransaksi, // jam transaksi dari created_date (HH:mm)
  }) async {
    final profile = await CapabilityProfile.load();
    final generator = Generator(PaperSize.mm58, profile);
    List<int> bytes = [];

    // ── Sanitasi semua teks bebas sebelum diproses ke printer ───
    storeName = _sanitizeForPrint(storeName);
    storeAddress = _sanitizeForPrint(storeAddress);
    memberNama = _sanitizeForPrint(memberNama);
    if (npwp != null) npwp = _sanitizeForPrint(npwp);
    if (keterangan != null) keterangan = _sanitizeForPrint(keterangan);
    if (salesTipe != null) salesTipe = _sanitizeForPrint(salesTipe);
    if (voucherKode != null) voucherKode = _sanitizeForPrint(voucherKode);

    // ── RESET printer — pastikan mulai dari state bersih ────────
    bytes += generator.reset();

    // ── LOGO ─────────────────────────────────────────────────────
    if (logoFileName != null &&
        logoFileName.isNotEmpty &&
        logoUrl != null &&
        logoUrl.isNotEmpty) {
      final logoImage = await _getLogoImage(
        logoFileName: logoFileName,
        logoUrl: logoUrl,
      );
      if (logoImage != null) {
        bytes += generator.image(logoImage, align: PosAlign.center);
        bytes += generator.feed(1);
      }
    }

    // ── HEADER PENDING ───────────────────────────────────────────
    bytes += generator.text(
      '*** PENDING ORDER ***',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
      ),
    );

    // Store name (double size, word-wrap)
    const int headerLineWidth = 16;
    final storeNameLines = _wrapWords(storeName, headerLineWidth);
    for (final line in storeNameLines) {
      bytes += generator.text(
        line,
        styles: const PosStyles(
          align: PosAlign.center,
          height: PosTextSize.size2,
          width: PosTextSize.size2,
          bold: true,
        ),
      );
    }

    if (storeAddress.isNotEmpty) {
      bytes += generator.text(
        storeAddress,
        styles: const PosStyles(align: PosAlign.center),
      );
    }

    final npwpText =
        (npwp != null && npwp.isNotEmpty) ? npwp : '0 00.000.000.0-000.000';
    bytes += generator.text(
      'NPWP: $npwpText',
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.hr();

    // ── INFO TRANSAKSI ───────────────────────────────────────────
    bytes += generator.text('No : $invoiceNumber');
    bytes += generator.text('Tgl: $tanggal');
    if (jamTransaksi != null && jamTransaksi.isNotEmpty) {
      bytes += generator.text('Jam: $jamTransaksi');
    }
    bytes += generator.text('Kas: $kasir');
    if (memberNama.isNotEmpty) {
      bytes += generator.text('Mbr: $memberNama');
    }
    if (keterangan != null && keterangan.isNotEmpty) {
      bytes += generator.text('Ket: $keterangan');
    }

    // ── Channel / tipe order ─────────────────────────────────────
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

    // ── ITEM LIST dengan harga, diskon, isian & addon ────────────
    // (identik dengan printInvoice)
    for (var item in items) {
      // Nama produk
      final namaProduk = _sanitizeForPrint(item['nama'] as String);
      bytes += generator.text(
        namaProduk,
        styles: const PosStyles(bold: true),
      );

      // Baris qty × harga = subtotal
      final qty = item['qty'];
      final hpj = _formatNumber(item['hpj']);
      final subtotal = _formatNumber(item['subtotal']);
      bytes += generator.text('  $qty x $hpj = $subtotal');

      // Diskon (jika ada)
      if ((item['diskon_persen'] ?? 0) > 0) {
        bytes += generator.text('  Diskon: ${item['diskon_persen']}%');
      } else if ((item['diskon_nominal'] ?? 0) > 0) {
        bytes += generator
            .text('  Diskon: ${_formatNumber(item['diskon_nominal'])}');
      }

      // ── Sub-item: isian & addon ──────────────────────────────
      // Prioritas 1: packages_notes (JSON string gabungan)
      // Prioritas 2: field 'isian' dan 'addon' langsung di map item
      final packagesNotesRaw = item['packages_notes'] as String? ?? '';
      if (packagesNotesRaw.isNotEmpty) {
        final packageLines = _buildPackageLines(packagesNotesRaw);
        for (final line in packageLines) {
          bytes += generator.text(line);
        }
      } else {
        final packageLines = _buildPackageLinesFromMap(item);
        for (final line in packageLines) {
          bytes += generator.text(line);
        }
      }

      // Keterangan per item (jika ada)
      final itemKet = _sanitizeForPrint(item['keterangan'] as String? ?? '');
      if (itemKet.isNotEmpty) {
        bytes += generator.text('  >> Note : $itemKet');
      }
    }

    bytes += generator.hr();

    // ── SUMMARY — Gross & Diskon hanya tampil jika ada diskon ────
    if (diskon > 0) {
      bytes += generator.row([
        PosColumn(text: 'Gross', width: 6),
        PosColumn(
          text: _formatNumber(gross),
          width: 6,
          styles: const PosStyles(align: PosAlign.right),
        ),
      ]);

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

    // ── Keterangan belum dibayar — pengganti section Bayar/Kembali ──
    bytes += generator.text(
      '--- Belum Dibayar ---',
      styles: const PosStyles(
        align: PosAlign.center,
        bold: true,
      ),
    );

    bytes += generator.hr();

    // ── FOOTER — dari dim_divisi.invoice_note ────────────────────
    final noteText = (invoiceNote != null && invoiceNote.isNotEmpty)
        ? _sanitizeForPrint(
            invoiceNote.replaceAll(RegExp(r'<[^>]*>'), '').trim())
        : 'Terima kasih atas kunjungan Anda';
    bytes += generator.text(
      noteText,
      styles: const PosStyles(align: PosAlign.center),
    );

    bytes += generator.feed(1);
    bytes += generator.cut();

    return await PrintBluetoothThermal.writeBytes(bytes);
  }

  // ── Word-wrap: pecah teks per kata agar tidak terpotong ─────
  //
  // [maxWidth] = maks jumlah karakter per baris.
  // Pindah baris selalu di awal kata, bukan di tengah.
  static List<String> _wrapWords(String text, int maxWidth) {
    if (maxWidth <= 0) return [text];
    final words = text.split(' ');
    final List<String> lines = [];
    String current = '';

    for (final word in words) {
      if (current.isEmpty) {
        current = word;
      } else if ((current.length + 1 + word.length) <= maxWidth) {
        current += ' $word';
      } else {
        lines.add(current);
        current = word;
      }
    }
    if (current.isNotEmpty) lines.add(current);
    return lines.isEmpty ? [''] : lines;
  }

  // ── Parse packages_notes (JSON string) dan bangun baris struk ─
  //
  // Format baru (setelah fix PHP):
  //   {"isian":["Gurita","Crabstick"],"addon":[{"nama":"Bon Cabe","harga":1000}]}
  //
  // Format lama (data yang sudah ada sebelum fix):
  //   {"isian":["Gurita","Crabstick"],"addon":["Bon Cabe","Topping Terpisah"]}
  //
  // Kedua format ditangani.
  static List<String> _buildPackageLines(String notesJson,
      {bool showAddonPrice = true}) {
    if (notesJson.isEmpty) return [];
    try {
      final Map<String, dynamic> notes = jsonDecode(notesJson);
      return _extractIsianAddon(
        isianRaw: notes['isian'],
        addonRaw: notes['addon'],
        showAddonPrice: showAddonPrice,
      );
    } catch (_) {
      // JSON tidak valid — skip sub-item, tidak crash
      return [];
    }
  }

  // ── Fallback: baca isian/addon langsung dari item Map ────────
  //
  // Digunakan jika packages_notes tidak ada atau kosong.
  // Item map boleh mengandung:
  //   'isian'  → List<dynamic> berisi string nama isian
  //   'addon'  → List<dynamic> berisi string atau Map {nama, harga}
  static List<String> _buildPackageLinesFromMap(Map<String, dynamic> item,
      {bool showAddonPrice = true}) {
    final isianRaw = item['isian'];
    final addonRaw = item['addon'];
    if (isianRaw == null && addonRaw == null) return [];
    return _extractIsianAddon(
        isianRaw: isianRaw, addonRaw: addonRaw, showAddonPrice: showAddonPrice);
  }

  // ── Core extractor: dari raw isian/addon ke list baris teks ──
  //
  // [showAddonPrice] — true untuk customer copy (tampilkan +harga addon),
  //                    false untuk kitchen (addon tanpa harga)
  static List<String> _extractIsianAddon({
    dynamic isianRaw,
    dynamic addonRaw,
    bool showAddonPrice = true,
  }) {
    final List<String> lines = [];

    // Isian
    if (isianRaw is List && isianRaw.isNotEmpty) {
      lines.add('  Isian:');
      for (final item in isianRaw) {
        if (item is Map) {
          // Format baru: {"id": 4, "nama": "Keju"} → tampilkan nama saja
          final nama = _sanitizeForPrint(item['nama']?.toString() ?? '');
          if (nama.isNotEmpty) {
            lines.add('    * $nama');
          }
        } else {
          // Format lama: string biasa
          final nama = _sanitizeForPrint(item.toString());
          if (nama.isNotEmpty) {
            lines.add('    * $nama');
          }
        }
      }
    }

    // Addon
    if (addonRaw is List && addonRaw.isNotEmpty) {
      lines.add('  Add On:');
      for (final addon in addonRaw) {
        if (addon is Map) {
          // Format baru: {"nama": "Bon Cabe", "harga": 1000}
          final nama = _sanitizeForPrint(addon['nama']?.toString() ?? '');
          final harga = double.tryParse(addon['harga'].toString()) ?? 0;
          if (nama.isNotEmpty) {
            final hargaStr = (showAddonPrice && harga > 0)
                ? ' +${_formatNumber(harga)}'
                : '';
            lines.add('    * $nama$hargaStr');
          }
        } else {
          // Format lama: string biasa tanpa harga
          final nama = _sanitizeForPrint(addon.toString());
          if (nama.isNotEmpty) {
            lines.add('    * $nama');
          }
        }
      }
    }

    return lines;
  }

  // ── Sanitasi teks bebas sebelum dikirim ke printer ───────────
  //
  // Thermal printer (via esc_pos_utils_plus) encode teks pakai
  // code page terbatas (mis. CP437/CP1252). Karakter "smart"
  // typographic (smart quote, en/em dash, ellipsis) atau emoji
  // dari autocorrect keyboard TIDAK ada di code page itu, dan
  // generator.text() akan throw:
  //   "Invalid argument (string): Contains invalid characters."
  //
  // Fungsi ini:
  //   1. Ganti karakter smart/typographic umum ke padanan ASCII-nya
  //   2. Buang sisa karakter apa pun di luar printable ASCII (0x20-0x7E)
  //      supaya print tidak pernah gagal karena karakter aneh.
  static String _sanitizeForPrint(String text) {
    if (text.isEmpty) return text;
    var t = text
        .replaceAll(RegExp(r'[\u2018\u2019\u201A\u201B]'), "'") // ‘ ’ ‚ ‛
        .replaceAll(RegExp(r'[\u201C\u201D\u201E\u201F]'), '"') // “ ” „ ‟
        .replaceAll(RegExp(r'[\u2013\u2014]'), '-') // – —
        .replaceAll('\u2026', '...'); // …
    // Buang semua karakter di luar printable ASCII (termasuk emoji, dsb)
    t = t.replaceAll(RegExp(r'[^\x20-\x7E]'), '');
    return t;
  }

  // ── Format angka dengan titik ribuan ────────────────────────
  static String _formatNumber(dynamic value) {
    if (value == null) return '0';
    final double val = double.tryParse(value.toString()) ?? 0;
    return val.toStringAsFixed(0).replaceAllMapped(
          RegExp(r'(\d{1,3})(?=(\d{3})+(?!\d))'),
          (m) => '${m[1]}.',
        );
  }
}
