import 'request.dart';
import 'response_type.dart';
import 'request_method.dart';
/// @Annotation Get
///
/// 查询请求的注解
///
/// example:
/// ``` @Get('/submitForm') ```
///
/// @author luodongseu
class Get extends Request {
  const Get([String path = '/', ResponseType responseType = ResponseType.json])
      : super(HttpMethod.GET, path: path, responseType: responseType);
}
