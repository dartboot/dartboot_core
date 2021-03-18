/// 表的Annotation
class Table {
  /// 表名称
  final String tableName;

  /// 分区表达式
  final String partitionBy;

  const Table(this.tableName, {this.partitionBy});
}
