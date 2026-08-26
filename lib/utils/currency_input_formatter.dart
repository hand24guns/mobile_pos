// Formatter untuk field input nominal (mis. Nominal Bayar di summary kasir).
// Menambahkan pemisah ribuan "." secara live saat kasir mengetik, supaya
// kasir tidak salah input karena kebanyakan/kekurangan digit 0.
//
// Pasang bersama FilteringTextInputFormatter.digitsOnly agar karakter
// selain angka tidak bisa masuk sama sekali:
//
//   inputFormatters: [
//     FilteringTextInputFormatter.digitsOnly,
//     CurrencyInputFormatter(),
//   ],
//
// Untuk mengambil nilai numeriknya kembali (di onChanged / saat submit),
// gunakan CurrencyInputFormatter.toNumber(controller.text).
import 'package:flutter/services.dart';

class CurrencyInputFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    // Ambil digit murni dari input baru (jaga-jaga kalau formatter lain
    // belum menyaring, mis. saat paste teks).
    var digits = newValue.text.replaceAll(RegExp(r'[^0-9]'), '');

    if (digits.isEmpty) {
      return const TextEditingValue(text: '');
    }

    // Buang leading zero berlebih, misal "0075000" -> "75000".
    digits = digits.replaceFirst(RegExp(r'^0+(?=\d)'), '');

    final formatted = CurrencyInputFormatter.thousands(digits);

    return TextEditingValue(
      text: formatted,
      // Kursor selalu di akhir — cukup untuk field nominal yang diketik
      // berurutan dari kiri ke kanan (kasir jarang edit di tengah angka).
      selection: TextSelection.collapsed(offset: formatted.length),
    );
  }

  /// Menyisipkan "." tiap 3 digit dari kanan. Input harus string digit murni.
  static String thousands(String digits) {
    final buffer = StringBuffer();
    for (int i = 0; i < digits.length; i++) {
      final posFromRight = digits.length - i;
      buffer.write(digits[i]);
      if (posFromRight > 1 && posFromRight % 3 == 1) {
        buffer.write('.');
      }
    }
    return buffer.toString();
  }

  /// Kebalikan dari [thousands] — ambil angka int dari teks yang sudah
  /// diformat (atau teks mentah apa pun), aman dipakai di onChanged.
  static int toNumber(String formattedText) {
    final digits = formattedText.replaceAll(RegExp(r'[^0-9]'), '');
    return digits.isEmpty ? 0 : int.parse(digits);
  }
}
