import 'dart:convert';
import 'dart:mirrors';

import '../annotation/annotation.dart';
import '../error/custom_error.dart';
import '../util/string.dart';

/// model的工具类
///
/// @author luodongseu
class ModelUtils {
  /// copy对象属性
  /// skipEmpty: true 跳过空(含0)
  static copy(dynamic x, dynamic y, {bool skipEmpty = false}) {
    InstanceMirror xMirror = reflect(x);
    InstanceMirror yMirror = reflect(y);
    List<VariableMirror> yDeclarations = getAllDeepVariables(yMirror.type);
    List<DeclarationMirror> xDeclarations = getAllDeepVariables(xMirror.type);

    Map<String, VariableMirror> xDeclareMap = {};
    xDeclarations.forEach((d) {
      if (d is VariableMirror) {
        xDeclareMap[MirrorSystem.getName(d.simpleName)] = d;
      }
    });

    yDeclarations.forEach((dm) {
      String varName = MirrorSystem.getName(dm.simpleName);
      if (xDeclareMap.containsKey(varName) &&
          dm.type.reflectedType == xDeclareMap[varName].type.reflectedType) {
        Object value = xMirror.getField(dm.simpleName).reflectee;
        if (skipEmpty && (isEmpty(value) || value == 0)) {
          return;
        }
        yMirror.setField(
            dm.simpleName, xMirror.getField(dm.simpleName).reflectee);
      }
    });
  }

  /// 从json序列化
  static R fromJson<R>(Map<String, dynamic> json) {
    TypeMirror typeMirror = reflectType(R);
    if (!(typeMirror is ClassMirror)) {
      throw CustomError('Only support class type.');
    }
    ClassMirror clz = typeMirror as ClassMirror;
    InstanceMirror thisMirror = clz.newInstance(Symbol.empty, []);
    if (isEmpty(json) || json.keys.isEmpty) {
      return thisMirror.reflectee;
    }

    // 变量列表
    List<VariableMirror> variables = getAllDeepVariables(clz);
    variables.forEach((v) {
      String vName = MirrorSystem.getName(v.simpleName);
      if (json.keys.contains(vName)) {
        setRFields(thisMirror, v, json[vName]);
      }
    });
    return thisMirror.reflectee;
  }

  /// 转换成Json对象
  static Map<String, dynamic> toJson(dynamic v,
      {bool skipEmptyAndZero = false}) {
    Map<String, dynamic> json = Map();
    InstanceMirror thisMirror = reflect(v);
    List<VariableMirror> variables = getAllDeepVariables(thisMirror.type);
    variables.forEach((dm) {
      if (dm is VariableMirror && !dm.isFinal && !dm.isConst) {
        Object value = thisMirror.getField(dm.simpleName).reflectee;
        if (skipEmptyAndZero) {
          if (isEmpty(value)) {
            return;
          }
          if (value is num && value == 0) {
            return;
          }
        }
        json[MirrorSystem.getName(dm.simpleName)] = value;
      }
    });
    return json;
  }

  /// 转换成insert sql语句
  static String toBatchInsertSql(List<dynamic> data) {
    if (isEmpty(data)) {
      return null;
    }
    List<String> cols = [];
    InstanceMirror thisMirror = reflect(data[0]);
    List<VariableMirror> declarations = getAllDeepVariables(thisMirror.type);
    List<dynamic> colDefs = [];

    declarations.forEach((dm) {
      final String propertyName = MirrorSystem.getName(dm.simpleName);
      String col = propertyName;
      int i = -1;
      while ((i = col.indexOf(RegExp('[A-Z]'))) >= 0) {
        String left = col.substring(i + 1);
        col = col.substring(0, i) + '_' + col[i].toLowerCase() + left;
      }
      dynamic value = thisMirror.getField(dm.simpleName).reflectee;
      if (null == value) {
        // 不处理空 注意后面如果不为空，也会被过滤
        return;
      }
      String reflectType =
          thisMirror.getField(dm.simpleName).type?.reflectedType?.toString() ??
              'String';
      var enumMetadata;
      if (reflectType == 'String') {
        enumMetadata = dm.metadata.firstWhere(
            (pm) => pm.hasReflectee && pm.reflectee is Enum,
            orElse: () => null);
      }
      cols.add(col);
      colDefs.add({
        'col': col,
        'type': reflectType,
        'property': propertyName,
        'enums':
            null != enumMetadata ? (enumMetadata.reflectee as Enum).enums : null
      });
    });

    List<String> valueSqls = [];
    for (dynamic _data in data) {
      dynamic __data = toJson(_data);
      List<String> values = [];
      for (dynamic colDef in colDefs) {
        final reflectType = colDef['type'];
        final enums = colDef['enums'];
        final value = __data['${colDef['property']}'];
        switch (reflectType) {
          case 'bool':
            values.add('${value == true ? 1 : 0}');
            break;
          case 'String':
            if (null != enums) {
              values.add('${enums[value] ?? 0}');
            } else {
              values.add('''\'${(value ?? '').replaceAll('\'', '\\\'')}\'''');
            }
            break;
          case 'List<String>':
            values
                .add('(${(value as List).map((v) => '''\'$v\'''').join(',')})');
            break;
          case 'List<int>':
            values.add('(${(value as List).map((v) => '$v').join(',')})');
            break;
          case 'int':
          case 'double':
          case 'num':
          case 'bigint':
          default:
            values.add('$value');
            break;
        }
      }
      valueSqls.add('(${values.join(',')})');
    }
    return 'insert into ${_tableName(thisMirror.type)} (${cols.join(',')}) values ${valueSqls.join(',')}';
  }

  /// 转换成insert sql语句
  static String toInsertSql(dynamic v) {
    List<String> cols = [];
    List<String> values = [];
    InstanceMirror thisMirror = reflect(v);
    List<VariableMirror> variables = getAllDeepVariables(thisMirror.type);
    variables.forEach((dm) {
      final String propertyName = MirrorSystem.getName(dm.simpleName);
      String col = propertyName;
      int i = -1;
      while ((i = col.indexOf(RegExp('[A-Z]'))) >= 0) {
        String left = col.substring(i + 1);
        col = col.substring(0, i) + '_' + col[i].toLowerCase() + left;
      }
      dynamic value = thisMirror.getField(dm.simpleName).reflectee;
      if (null == value) {
        // 不处理空
        return;
      }

      cols.add('$col');
      String reflectType =
          thisMirror.getField(dm.simpleName).type?.reflectedType?.toString() ??
              'String';
      switch (reflectType) {
        case 'bool':
          values.add('${value == true ? 1 : 0}');
          break;
        case 'String':
          var enumMetadata = dm.metadata.firstWhere(
              (pm) => pm.hasReflectee && pm.reflectee is Enum,
              orElse: () => null);
          if (null != enumMetadata) {
            values.add('${(enumMetadata.reflectee as Enum).enums[value] ?? 0}');
          } else {
            values.add('\'${value ?? ''}\'');
          }
          break;
        case 'List<String>':
          values.add('(${(value as List).map((v) => '\'$v\'').join(',')})');
          break;
        case 'List<int>':
          values.add('(${(value as List).map((v) => '$v').join(',')})');
          break;
        case 'int':
        case 'double':
        case 'num':
        case 'bigint':
        default:
          values.add('$value');
          break;
      }
    });
    return 'insert into ${_tableName(thisMirror.type)} (${cols.join(',')}) values (${values.join(',')})';
  }

  /// 转换count all sql语句
  static String toCountAllSql(dynamic v) {
    return 'select count(*) from ${_tableName(reflect(v).type)}';
  }

  /// 转换成string
  static String toString2(dynamic v) {
    return json.encode(toJson(v));
  }

  /// 获取表名称
  static String tableName(dynamic v) => _tableName(reflect(v).type);

  /// 获取表名称
  static String tableNameByType<R>() {
    TypeMirror typeMirror = reflectType(R);
    assert(typeMirror is ClassMirror, 'T must be class wrapped with @Table');
    return _tableName((typeMirror as ClassMirror));
  }

  /// 获取表名称
  static String _tableName(ClassMirror clzMirror) => (clzMirror.metadata
          .firstWhere(
            (m) => m.hasReflectee && m.reflectee is Table,
          )
          ?.reflectee as Table)
      ?.tableName;

  /// 获取表的分区名称
  static String tablePartitionBy(thisMirror) => (thisMirror.type.metadata
          .firstWhere(
            (m) => m.hasReflectee && m.reflectee is Table,
          )
          ?.reflectee as Table)
      ?.partitionBy;

  /// 转换为create table sql
  static toChTableSql(dynamic v) {
    List<String> cols = [];
    var thisMirror = reflect(v);
    List<VariableMirror> variables = getAllDeepVariables(thisMirror.type);
    variables.forEach((dm) {
      var propertyName = MirrorSystem.getName(dm.simpleName);
      var col = propertyName;
      final columnDef = dm.metadata.firstWhere(
          (pm) => pm.hasReflectee && pm.reflectee is Column,
          orElse: () => null);
      var cDef = columnDef?.reflectee as Column;
      var defaultValue = cDef?.defaultValue ?? null;
      var nullable = (cDef)?.nullable ?? true;
      var isId = (cDef)?.id ?? false;
      if (isNotEmpty((cDef)?.name)) {
        col = (cDef)?.name;
      } else {
        int i = -1;
        while ((i = col.indexOf(RegExp('[A-Z]'))) >= 0) {
          String left = col.substring(i + 1);
          col = col.substring(0, i) + '_' + col[i].toLowerCase() + left;
        }
      }
//      if (cDef?.indexed == true) {
//        col = 'INDEX `$col`';
//      }else {
      col = '`$col`';
//      }

      String reflectType = dm.type?.reflectedType?.toString() ?? 'String';
      switch (reflectType) {
        case 'bool':
          cols.add(
              '$col ${nullable ? 'Nullable(Int8)' : 'Int8'} DEFAULT ${defaultValue ?? 0}');
          break;
        case 'String':
          var enumMetadata = dm.metadata.firstWhere(
              (pm) => pm.hasReflectee && pm.reflectee is Enum,
              orElse: () => null);
          if (null != enumMetadata) {
            cols.add(
                '$col Int8 ${null != defaultValue ? 'DEFAULT $defaultValue' : ''}');
          } else {
            cols.add(
                '$col ${nullable ? 'Nullable(String)' : 'String'} ${null != defaultValue ? 'DEFAULT $defaultValue' : ''}');
          }
          break;
        case 'int':
        case 'num':
        case 'bigint':
          cols.add(
              '$col ${nullable ? 'Nullable(Int64)' : 'Int64'} DEFAULT ${defaultValue ?? (isId ? 'toUUID(rand64())' : 0)}');
          break;
        case 'double':
          cols.add(
              '$col ${nullable ? 'Nullable(Float64)' : 'Float64'} DEFAULT ${defaultValue ?? 0}');
          break;
        default:
          throw CustomError('Not support column type [$col $reflectType].');
      }
    });
    if (!cols.any((c) => c.contains('`id`'))) {
      cols.insert(0, '`id` Int64');
    }
    // 做字典排序
    cols.sort();
    // 将id放在最前面
    var idIndex = cols.indexWhere((x) => x.contains('`id`'));
    if (idIndex >= 0) {
      var idCol = cols[idIndex];
      cols.removeAt(idIndex);
      cols.insert(0, idCol);
    }
    var pb = tablePartitionBy(thisMirror);
    return 'CREATE TABLE ${_tableName(thisMirror.type)} (${cols.join(',')}, `_insert_time` Int64 DEFAULT toUnixTimestamp(now()) * 1000, `_insert_date` Int64 DEFAULT toUnixTimestamp(toStartOfDay(now(), \'Asia/Shanghai\')) * 1000, INDEX _id id TYPE minmax GRANULARITY 4) ENGINE = MergeTree() ${isNotEmpty(pb) ? 'PARTITION BY $pb' : ''} ORDER BY id';
  }

  /// Result -> Model
  static R resultMapper<R>(dynamic result) {
    return resultsMapper<R>([result])[0];
  }

  /// Results -> List<Model>
  static List<R> resultsMapper<R>(List<dynamic> results) {
    var typeMirror = reflectType(R);
    if (!(typeMirror is ClassMirror)) {
      throw CustomError('Only support class type.');
    }
    var data = [];
    var _rm = (typeMirror as ClassMirror).newInstance(Symbol.empty, []);
    List<DeclarationMirror> variables = getAllDeepVariables(_rm.type);

    // 准备declare map
    var declareMap = {};
    variables.forEach((syb) {
      var varName = MirrorSystem.getName(syb.simpleName);
      // 映射原始名称
      declareMap[varName] = syb;
      // 映射_名称
      var colName = toSqlColumnName(varName);
      if (colName != varName) {
        declareMap[colName] = syb;
      }
    });

    results.forEach((row) {
      InstanceMirror rm =
          (typeMirror as ClassMirror).newInstance(Symbol.empty, []);
      (row as Map).forEach((k, value) {
        // 先匹配原始字段名
        if (declareMap.containsKey(k)) {
          setRFields(rm, declareMap[k], value);
        }
      });
      data.add(rm.reflectee);
    });
    return data;
  }

  /// 转换字段名到sql column名称
  static String toSqlColumnName(String varName) {
    assert(isNotEmpty(varName), 'Column name must not be empty');
    if (varName.contains(RegExp(r'[A-Z]'))) {
      return varName.replaceAllMapped(
          RegExp(r'[A-Z]'), (m) => '_${m.group(0)}'.toLowerCase());
    }
    return varName;
  }

  /// 设置R的字段
  static void setRFields(
      InstanceMirror rm, DeclarationMirror variable, dynamic value) {
    var dim = variable as VariableMirror;
    var reflectType = dim.type?.reflectedType?.toString() ?? 'String';
    switch (reflectType) {
      case 'bool':
        rm.setField(variable.simpleName,
            value == 1 || value == true || '$value' == 'true');
        return;
      case 'String':
        var enumMetadata = dim.metadata.firstWhere(
            (pm) => pm.hasReflectee && pm.reflectee is Enum,
            orElse: () => null);
        if (null != enumMetadata && value is int) {
          var _enums = (enumMetadata.reflectee as Enum).enums;
          for (var p in _enums.entries) {
            if (p.value == value) {
              rm.setField(variable.simpleName, p.key);
              return;
            }
          }
        }
        if (null != value) {
          rm.setField(variable.simpleName, '${value ?? ''}');
        }
        return;
      case 'int':
      case 'num':
      case 'bigint':
        if (value is DateTime) {
          rm.setField(variable.simpleName, value.millisecondsSinceEpoch);
        } else if (value is int) {
          rm.setField(variable.simpleName, value);
        } else {
          rm.setField(variable.simpleName, int.parse('${value ?? 0}'));
        }
        return;
      case 'double':
        rm.setField(variable.simpleName, double.parse('${value ?? 0}'));
        return;
      case 'List<dynamic>':
        if (value is List) {
          rm.setField(variable.simpleName, value);
        } else if (value != null) {
          rm.setField(variable.simpleName, [value]);
        }
        return;
      default:
        return;
    }
  }

  /// 格式化sql
  static formatSql(String sql) {
    return '$sql'
        .replaceFirst(RegExp(r'^\s+'), '')
        .replaceFirst(RegExp(r'\s+$'), '')
        .replaceAll(RegExp(r'\s{2,}'), ' ');
  }

  /// 获取所有的variables镜像
  static List<VariableMirror> getVariableMirrors<T>() {
    var typeMirror = reflectType(T);
    assert(typeMirror is ClassMirror, 'Only class type supported');

    return getAllDeepVariables(typeMirror as ClassMirror);
  }

  /// 获取单个variable镜像
  static VariableMirror getVariableMirror<T>(String key) {
    return getVariableMirrors<T>().firstWhere(
        (v) => MirrorSystem.getName(v.simpleName) == key,
        orElse: () => null);
  }

  /// 获取指定variable的注解R
  static R getVariableAnnotation<T, R>(String key) {
    VariableMirror variableMirror = getVariableMirror<T>(key);
    if (null == variableMirror) {
      return null;
    }
    InstanceMirror instanceMirror = variableMirror.metadata.firstWhere(
        (m) => m.hasReflectee && m.reflectee is R,
        orElse: () => null);
    if (null == instanceMirror) {
      return null;
    }
    return instanceMirror.reflectee as R;
  }
}

/// 获取所有深度的变量
List<DeclarationMirror> getAllDeepDeclares(ClassMirror m) {
  List<DeclarationMirror> declares = [];
  Set<String> keys = Set();
  m.declarations?.forEach((k, v) {
    String vn = MirrorSystem.getName(k);
    if (!keys.contains(vn)) {
      keys.add(vn);
      declares.add(v);
    }
  });
  ClassMirror superClz = m.superclass;
  while (null != superClz) {
    superClz.declarations?.forEach((k, v) {
      String vn = MirrorSystem.getName(k);
      if (!keys.contains(vn)) {
        keys.add(vn);
        declares.add(v);
      }
    });
    superClz = superClz.superclass;
  }
  return declares;
}

/// 获取所有的变量
List<VariableMirror> getAllDeepVariables(ClassMirror m) {
  return getAllDeepDeclares(m)
      .where((dm) =>
          dm is VariableMirror && !dm.isFinal && !dm.isConst && !dm.isPrivate)
      .map((d) => d as VariableMirror)
      .toList();
}

/// 获取所有的变量名称
List<String> getAllDeepVariableNames(ClassMirror m) {
  return getAllDeepDeclares(m)
      .where((dm) =>
          dm is VariableMirror && !dm.isFinal && !dm.isConst && !dm.isPrivate)
      .map((d) => MirrorSystem.getName(d.simpleName))
      .toList();
}
