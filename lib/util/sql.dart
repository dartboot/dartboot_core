import '../annotation/annotation.dart';
import './model_utils.dart';
import '../error/custom_error.dart';
import '../util/string.dart';

/// SQL构造器
///
/// @author luodongseu
class SqlBuilder<T> {
  /// 表名
  String _tableName = '';

  /// 选中
  List<String> _selects = ['*'];

  /// 操作列表
  List<SqlOp> _operations = [];

  /// 排序列表
  List<SqlOrder> _orders = [];

  /// 分组列表
  List<String> _group = [];

  /// 分组条件列表
  String _having = '';

  /// 查询限制
  SqlLimit _limit;

  /// 追加的sql片段
  List<String> _appendSqlSegments = [];

  SqlBuilder() {
    if (T != dynamic) {
      _tableName = ModelUtils.tableNameByType<T>() ?? '';
    }
  }

  /// 选择的表
  SqlBuilder from(String tableName) {
    assert(isNotEmpty(tableName), 'Table name must not be empty');

    _tableName = tableName;
    return this;
  }

  /// 选择列
  SqlBuilder select(List<String> cols, {bool keepName = false}) {
    if (isEmpty(cols)) {
      return this;
    }
    if (_selects.length == 1 && _selects[0] == '*') {
      _selects.clear();
    }
    _selects.addAll(cols.where((col) => isNotEmpty(col)).map((col) =>
        keepName ? col : '${ModelUtils.toSqlColumnName(col)} AS $col'));
    return this;
  }

  /// 等于操作
  SqlBuilder eq(String col, Object value, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    if (null == value) {
      return this;
    }
    if (isEmpty(col)) {
      return this;
    }

    String _value = '';
    if (value is num) {
      _value = '$value';
    } else if (value is String) {
      if (isEmpty(value)) {
        return this;
      }
      if (value == '?') {
        _value = '?';
      } else {
        _value = '\'$value\'';
        if (T != dynamic) {
          // 处理@Enum
          Enum e = ModelUtils.getVariableAnnotation<T, Enum>(col);
          if (null != e) {
            assert(e.enums.containsKey(value),
                'Enum type:$value missmatch:${e.enums}');
            _value = '${e.enums[value]}';
          }
        }
      }
    } else if (value is bool) {
      _value = '${value == true ? 1 : 0}';
    } else if (value is List<int> || value is List<double>) {
      _value = '(${(value as List).join(',')})';
    } else if (value is List<String>) {
      _value = '(${value.map((v) => '\'$v\'').join(',')})';
    } else {
      throw CustomError('Not support value:[$value] type');
    }
    _operations.add(SqlOp(col, '=', _value, keepName: keepName));
    return this;
  }

  /// 大于等于
  SqlBuilder gte(String col, num value, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    if (null == value) {
      return this;
    }
    _operations.add(SqlOp(col, '>=', '$value', keepName: keepName));
    return this;
  }

  /// 大于等于
  SqlBuilder lte(String col, num value, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    if (null == value) {
      return this;
    }
    _operations.add(SqlOp(col, '<=', '$value', keepName: keepName));
    return this;
  }

  /// 不等于
  SqlBuilder ne(String col, value, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    if (null == value) {
      return this;
    }
    String _value;
    if (value is num) {
      _value = '$value';
    } else if (value is String) {
      if (isEmpty(value)) {
        return this;
      }
      if (value == '?') {
        _value = '?';
      } else {
        _value = '\'$value\'';
      }
    } else if (value is bool) {
      _value = '${value == true ? 1 : 0}';
    } else {
      throw CustomError('Not support value:[$value] type');
    }
    _operations.add(SqlOp(col, '<>', '$_value', keepName: keepName));
    return this;
  }

  /// In操作
  SqlBuilder isIn(String col, List<dynamic> value, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    if (null == value || value.isEmpty) {
      return this;
    }
    String _value;
    if (value[0] is int || value[0] is double) {
      _value = '${value.join(',')}';
    } else if (value[0] is String) {
      _value = '${value.map((v) => v != '?' ? '\'$v\'' : '?').join(',')}';
    } else {
      throw CustomError('Not support value:[$value] type');
    }
    _operations.add(SqlOp(col, 'in', '($_value)', keepName: keepName));
    return this;
  }

  /// Not In操作
  SqlBuilder notIn(String col, List value, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    if (null == value) {
      return this;
    }
    String _value;
    if (value is List<int> || value is List<double>) {
      _value = '${value.join(',')}';
    } else if (value is List<String>) {
      _value = '${value.map((v) => v != '?' ? '\'$v\'' : '?').join(',')}';
    } else {
      throw CustomError('Not support value:[$value] type');
    }
    _operations.add(SqlOp(col, 'not in', '($_value)', keepName: keepName));
    return this;
  }

  /// is not null
  SqlBuilder notNull(String col, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    _operations.add(SqlOp(col, 'is not', 'null', keepName: keepName));
    return this;
  }

  /// is null
  SqlBuilder isNull(String col, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    _operations.add(SqlOp(col, 'is', 'null', keepName: keepName));
    return this;
  }

  /// not empty
  SqlBuilder notEmpty(String col, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    _operations.add(SqlOp(
        'length(${keepName == true ? col : ModelUtils.toSqlColumnName(col)})',
        '>',
        '0',
        keepName: true));
    return this;
  }

  /// is empty
  SqlBuilder empty(String col, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    _operations.add(SqlOp(
        'length(${keepName == true ? col : ModelUtils.toSqlColumnName(col)})',
        '=',
        '0',
        keepName: true));
    return this;
  }

  /// 自定义操作
  SqlBuilder custom(Object ignoreIfEmpty, String sql) {
    if (isEmpty(ignoreIfEmpty)) {
      return this;
    }
    _operations.add(SqlOp('', '', sql));
    return this;
  }

  /// 模糊
  SqlBuilder like(String col, String value, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');
    if (isEmpty(value)) {
      return this;
    }
    _operations.add(SqlOp(col, 'like', '\'%$value%\'', keepName: keepName));
    return this;
  }

  /// 多个模糊
  SqlBuilder likeMulti(List<String> cols, String value,
      {bool keepName = false}) {
    assert(isNotEmpty(cols), 'Column must not be empty');
    if (isEmpty(value)) {
      return this;
    }
    List<String> colSqls = cols
        .map((col) => SqlOp(col, 'like', '\'%${value != '?' ? value : '?'}%\'',
                keepName: keepName)
            .toSql())
        .toList();
    _operations.add(SqlOp('', '', '(${colSqls.join(' OR ')})'));
    return this;
  }

  /// 排序
  SqlBuilder orderBy(String col,
      {bool descending = false, bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');

    _orders.add(SqlOrder(col, descending, keepName: keepName));
    return this;
  }

  /// 限制返回行数
  SqlBuilder limit({int offset = 0, int size = 1}) {
    assert(offset >= 0, 'Offset must not less than zero');
    assert(size > 0, 'Offset must not less than 1');

    _limit = SqlLimit(from: offset, size: size);
    return this;
  }

  /// 分组
  SqlBuilder groupBy(String col, {bool keepName = false}) {
    assert(isNotEmpty(col), 'Column must not be empty');

    _group = [];
    _group.add('${keepName == true ? col : ModelUtils.toSqlColumnName(col)}');
    return this;
  }

  /// 多个字段分组
  SqlBuilder groupByMulti(List<String> cols, {bool keepName = false}) {
    assert(isNotEmpty(cols), 'Column must not be empty');

    _group = [];
    cols.forEach((col) => _group
        .add('${keepName == true ? col : ModelUtils.toSqlColumnName(col)}'));
    return this;
  }

  SqlBuilder having(String cond) {
    assert(isNotEmpty(cond), 'Condition must not be empty');
    _having = '$cond';
    return this;
  }

  /// 追加sql
  SqlBuilder appendSql(String sql) {
    if (isNotEmpty(sql)) {
      _appendSqlSegments.add(sql);
    }
    return this;
  }

  /// 计数
  count({String col, bool keepName = false}) {
    assert(isNotEmpty(_tableName), 'Table name not present');

    String sql = 'SELECT COUNT(${isEmpty(col) ? '*' : col}) FROM $_tableName';
    if (_operations.isNotEmpty) {
      sql = '$sql WHERE ${_operations.map((op) => op.toSql()).join(' AND ')}';
    }
    if (_appendSqlSegments.isNotEmpty) {
      sql = '$sql ${_appendSqlSegments.join(' ')}';
    }
    return ModelUtils.formatSql(sql);
  }

  /// 构造查询语句
  String query() {
    assert(isNotEmpty(_tableName), 'Table name not present');
    var sql = 'SELECT ${_selects.join(', ')} FROM $_tableName';
    if (_operations.isNotEmpty) {
      sql =
          '$sql ${sql.toUpperCase().contains('WHERE') ? 'AND' : 'WHERE'} ${_operations.map((op) => op.toSql()).join(' AND ')}';
    }
    if (_group.isNotEmpty) {
      sql = '$sql GROUP BY ${_group.join(',')}';
      if (_having.isNotEmpty) {
        sql = '$sql having $_having';
      }
    }
    if (_appendSqlSegments.isNotEmpty) {
      sql = '$sql ${_appendSqlSegments.join(' ')}';
    }
    if (_orders.isNotEmpty) {
      sql = '$sql ORDER BY ${_orders.map((o) => o.toSql()).join(',')}';
    }
    if (null != _limit) {
      sql = '$sql LIMIT ${_limit.toSql()}';
    }
    return ModelUtils.formatSql(sql);
  }
}

abstract class _SqlSegment {
  String toSql();
}

/// SQL 操作
class SqlOp implements _SqlSegment {
  final String col;

  final String operation;

  final String value;

  final bool keepName;

  SqlOp(this.col, this.operation, this.value, {this.keepName = false});

  @override
  String toSql() =>
      '${keepName == true || isEmpty(col) ? col : ModelUtils.toSqlColumnName(col)} $operation $value';
}

/// SQL排序
class SqlOrder implements _SqlSegment {
  final String col;

  final bool descending;

  final bool keepName;

  SqlOrder(this.col, this.descending, {this.keepName = false});

  @override
  String toSql() =>
      '${keepName == true || isEmpty(col) ? col : ModelUtils.toSqlColumnName(col)} ${descending ? 'DESC' : 'ASC'}';
}

/// SQL排序
class SqlLimit implements _SqlSegment {
  final int from;

  final int size;

  SqlLimit({this.from = 0, this.size = 0});

  @override
  String toSql() => '$from,$size';
}
