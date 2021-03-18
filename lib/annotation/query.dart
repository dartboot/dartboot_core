/// @Annotation Query
///
/// 查询参数的注解，用于获取接口携带的查询参数
///
/// example:
/// ``` @Query('limit', required=false) ```
///
/// @author luodong
class Query {
  /// 参数名称
  final String name;

  /// 是否必填，如果必填且客户端未传该参数，则响应错误信息
  final bool required;

  /// 默认值
  final Object defaultValue;

  const Query(
    this.name, {
    this.required = false,
    this.defaultValue,
  });
}
