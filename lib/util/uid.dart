import 'package:uuid/uuid.dart';

/// 全局的uuid
var uuid = Uuid();

/// 获取4位UUID
get uid4 => uuid.v1().replaceAll('-', '').substring(0, 4);

/// 获取8位UUID
get uid8 => uuid.v1().replaceAll('-', '').substring(0, 8);

/// 获取16位UUID
get uid16 => uuid.v1().replaceAll('-', '').substring(0, 16);

/// 获取完整的UUID
get uid => uuid.v1().replaceAll('-', '');
