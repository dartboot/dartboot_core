import 'dart:io';

/// 获取本机IP地址
Future<String> localIp() async {
  for (NetworkInterface l in await NetworkInterface.list()) {
    for (InternetAddress address in l.addresses) {
      if (address?.address != '127.0.0.1') {
        return address.address;
      }
    }
  }
  return InternetAddress.anyIPv4.address;
}
