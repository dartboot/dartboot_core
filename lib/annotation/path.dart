/// @Annotation Path
///
/// 在接口函数的参数中获取路径参数，[name]表示参数名称
///
/// example:
/// ``` func(@Path('username') String username,...)```
///
/// @author luodongseu
class Path {

  /// 参数名称
  final String name;

  const Path(this.name);
}
