import 'string.dart';

int get DAY_MILLS => 1000 * 60 * 60 * 24;

/// 获取当前DateTime对象
DateTime get dtn => DateTime.now();

/// 获取当前时间
int get now => DateTime.now().millisecondsSinceEpoch;

/// 获取今天的开始时间毫秒
int get todayStartMills => dayStart(DateTime.now());

/// 获取今天的开始时间
DateTime get todayStart => DateTime(dtn.year, dtn.month, dtn.day);

/// 获取指定日期的开始时间
int dayStart(DateTime d) => d != null
    ? DateTime(d.year, d.month, d.day, 0, 0, 0, 0).millisecondsSinceEpoch
    : 0;

/// 获取指定日期的结束时间
int dayEnd(DateTime d) => d != null
    ? DateTime(d.year, d.month, d.day, 23, 59, 59, 999).millisecondsSinceEpoch
    : 0;

/// 格式化日期
String formatDate(DateTime dateTime) {
  return "${dateTime.year.toString()}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')}";
}

/// 格式化时间
String formatTime(DateTime dateTime) {
  return "${dateTime.year.toString()}-${dateTime.month.toString().padLeft(2, '0')}-${dateTime.day.toString().padLeft(2, '0')} ${dateTime.hour.toString().padLeft(2, '0')}:${dateTime.minute.toString().padLeft(2, '0')}:${dateTime.second.toString().padLeft(2, '0')}:${dateTime.millisecond.toString().padLeft(3, '0')}";
}

/// 解析日期字符串 YYYY-MM-DD
DateTime parseDate(String date) {
  assert(RegExp('[0-9]{4}-[0-9]{2}-[0-9]{2}').hasMatch(date),
      'Not support this date format');

  int year = int.parse('${date.substring(0, 4)}');
  int month = int.parse('${date.substring(5, 7)}');
  int day = int.parse('${date.substring(8, 10)}');
  return DateTime(year, month, day);
}

/// 解析日期字符串到时间戳 YYYY-MM-DD
int parseDate2Mills(String date) {
  assert(isNotEmpty(date), '时间不能为空');
  assert(RegExp('[0-9]{4}-[0-9]{2}-[0-9]{2}').hasMatch(date),
      'Not support this date format');

  int year = int.parse('${date.substring(0, 4)}');
  int month = int.parse('${date.substring(5, 7)}');
  int day = int.parse('${date.substring(8, 10)}');
  return DateTime(year, month, day).millisecondsSinceEpoch;
}
