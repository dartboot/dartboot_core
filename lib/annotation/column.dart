/// 表的字段配置
class Column {
  /// 字段名称
  final String name;

  /// 是否为ID
  final bool id;

  /// 是否可以为空
  final bool nullable;

  /// 默认的值
  final Object defaultValue;

  /// 是否建立索引
  final bool indexed;

  const Column({
    this.name,
    this.nullable,
    this.defaultValue,
    this.id = false,
    this.indexed = false,
  });
}
