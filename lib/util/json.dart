import 'dart:mirrors';

import './pageable.dart';

/// 解析json，适配各种复杂的json
dynamic encodeJson(dynamic v) {
  if (v is num || v is String || v is bool || v is Map) {
    return v;
  }
  if (v is DateTime) {
    return v.millisecondsSinceEpoch;
  }
//  if (v is ObjectId) {
//    return v.toString();
//  }
  if (v is PageImpl) {
    return v.toJson(skipEmptyAndZero: true);
  }
  InstanceMirror instanceMirror = reflect(v);
  ClassMirror mirror = instanceMirror.type;
  if (mirror.instanceMembers?.containsKey(Symbol('toJson')) ?? false) {
    return encodeJson(instanceMirror.invoke(Symbol('toJson'), []).reflectee);
  }
  return v;
}
