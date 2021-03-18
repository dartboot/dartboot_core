/// @Annotation Header
///
/// 请求头的注解，用于接口函数的参数中接收请求头
///
/// example:
/// ``` func(@Header('Authorization') String token,...) ```
///
/// @author luodongseu
class Header {
  /// 请求头的名称
  final String name;

  const Header(this.name);
}
