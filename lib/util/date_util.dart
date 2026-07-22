import 'package:intl/intl.dart' show DateFormat;

class DateUtil {
  DateUtil._();
  static String getDateNowInUTC() {
    DateTime dateNow = DateTime.now().toUtc();
    final formatter = DateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'");
    return formatter.format(dateNow);
  }
}
