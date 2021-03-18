part of server;

/// 路径节点，每个'/'符号分割的内容
///
/// 是否为变量[isVar]表示，如果是变量则test为'{varName}'，[varName]是定义的变量名
///
/// @author luodongseu
class PathNode {
  /// 是否是变量
  bool isVar = false;

  /// 变量名
  String varName;

  /// 文本内容（原始内容，如果是变量，则包含{}）
  String text;

  @override
  String toString() {
    return '[isVar=$isVar, varName=$varName, text=$text]';
  }
}

/// 请求的路径信息，包含了原始路径和路径变量
///
/// @author luodong
class RequestPath {
  /// 基础路径，在controller上定义的
  ///
  /// ``` @RestController('/api/v2') ```
  String basePath;

  /// 原始路径，由basePath + path拼接
  ///
  /// example:
  /// ``` /api/v1/test/{id}/sample ```
  String originPath;

  /// 请求方式
  HttpMethod method;

  /// 响应类型
  ///
  /// 默认json [ResponseType.json]
  ResponseType responseType = ResponseType.json;

  /// 带正则的路径，将originPath中的变量替换为[^/]+
  ///
  /// example:
  /// ``` /api/v1/test/[^/]+/sample ```
  RegExp regexPath;

  /// 由['/']分割的节点，包含变量信息
  List<PathNode> nodes;

  /// 控制器反射
  InstanceMirror controllerMirror;

  /// 方法反射
  MethodMirror methodMirror;

  @override
  String toString() {
    return '[basePath=$basePath, originPath=$originPath, httpMethod=$method]';
  }
}
