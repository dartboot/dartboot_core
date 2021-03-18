import './response_type.dart';
import './request_method.dart';
/// @Annotation Request
///
/// 超类：请求的注解
///
/// 在此基础上可以衍生多种接口类型
/// 如：[Get]
/// @author luodongseu
class Request {
  /// 路由的路径
  final String path;

  /// 请求方式
  final HttpMethod method;

  /// 响应类型
  ///
  /// 默认json
  final ResponseType responseType;

  const Request(this.method,
      {this.path = '/', this.responseType = ResponseType.json});
}
