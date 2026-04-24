import 'package:intl/intl.dart';

class CurrencyFormat {
  static String format(dynamic value) {
    if (value == null) return '0';
    double val = double.tryParse(value.toString()) ?? 0;
    return NumberFormat('#,###', 'id_ID').format(val);
  }

  static double parse(String value) {
    return double.tryParse(value.replaceAll('.', '').replaceAll(',', '')) ?? 0;
  }
}