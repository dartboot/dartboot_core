/// ====================================================
/// @Annotation RestController
///
/// Rest接口类的控制器注解，使用该注解的类会自动加入到 [ApplicationContext] 中，
/// 然后可以通过 [mirrors] 扫描且应用
///
/// example:
/// ```dart
/// @RestController(basePath: '/api/v1')
/// class TestController {
///
/// }
///
/// ```
///
/// @author luodongseu
/// ====================================================
class RestController {
  /// 基本的路径
  ///
  /// 该路径会用于路由的前缀匹配，该类下所有的接口处理都会先匹配该[basePath]
  final String basePath;

  const RestController([this.basePath]);
}
