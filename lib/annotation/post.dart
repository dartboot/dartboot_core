import 'request.dart';
import 'response_type.dart';
import 'request_method.dart';
/// @Annotation Post
///
/// 提交请求的注解
///
/// example:
/// ``` @Post('/submitForm') ```
///
/// @author luodongseu
class Post extends Request {
  const Post([String path = '/', ResponseType responseType = ResponseType.json])
      : super(HttpMethod.POST, path: path, responseType: responseType);
}
