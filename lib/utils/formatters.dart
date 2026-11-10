import 'package:intl/intl.dart';

class AppFormatters {
  static const String shekelSymbol = '₪';

  static final NumberFormat _currencyFormatter = NumberFormat.currency(
    locale: 'en_IL',
    symbol: shekelSymbol,
    decimalDigits: 2,
  );

  static final NumberFormat _compactCurrencyFormatter = NumberFormat.currency(
    locale: 'en_IL',
    symbol: shekelSymbol,
    decimalDigits: 0,
  );

  static final DateFormat _monthYearFormatter = DateFormat('MMMM yyyy');
  static final DateFormat _dateTimeFormatter = DateFormat('dd MMM yyyy, HH:mm');
  static final DateFormat _shortDateFormatter = DateFormat('dd MMM, HH:mm');

  /// Formats a double amount with the proper New Israeli Shekel symbol (₪).
  /// Drops `.00` if the amount is an exact integer for cleaner display when [compactIfWhole] is true.
  static String formatShekel(double amount, {bool compactIfWhole = false}) {
    if (compactIfWhole && amount == amount.roundToDouble()) {
      return _compactCurrencyFormatter.format(amount);
    }
    return _currencyFormatter.format(amount);
  }

  static String formatMonthYear(DateTime date) =>
      _monthYearFormatter.format(date);

  static String formatDateTime(DateTime date) =>
      _dateTimeFormatter.format(date);

  static String formatShortDate(DateTime date) =>
      _shortDateFormatter.format(date);
}
