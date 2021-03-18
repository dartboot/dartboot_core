////////////////////////////////////////////////////////
//// 字符串操作工具类
///
/// @author luodongseu
////////////////////////////////////////////////////////

/// 是否为空
bool isEmpty(s) {
  if (null == s) {
    return true;
  }
  if (s is List) {
    return s.isEmpty;
  }
  if (s is String) {
    return '$s'.trim().length == 0;
  }
  if (s is Map) {
    return s.keys.isEmpty;
  }
  return '$s'.length == 0;
}

/// 非空判断
bool isNotEmpty(s) => !isEmpty(s);

/// 格式化URL路径
String formatUrlPath(String url) {
  String end(u) => '${u ?? ''}'.replaceAll(RegExp('[/]{2,}'), '/');
  if (url.startsWith('http://')) {
    return 'http://' + end(url.substring(7));
  }
  if (url.startsWith('https://')) {
    return 'https://' + end(url.substring(8));
  }
  return end(url);
}
