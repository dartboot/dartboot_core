/// ====================================================
/// @Annotation Bean
///
/// 实例注解，使用该注解的类会自动加入到 [ApplicationContext] 中，无参的构造函数会在启动时被系统调用
/// 然后可以通过 [mirrors] 扫描且应用
///
/// example:
/// ```dart
/// @bean
/// class TestService {
///
///   /// default constructor will be invoked automatic
///   TestService() {
///
///   }
/// }
///
/// ```
///
/// @author luodongseu
/// ====================================================
///
class Bean {
  /// 实例化条件：当存在指定的配置key
  final String conditionOnProperty;

  /// 依赖的类名
  final List<String> dependencies;

  /// 别名
  final String name;

  const Bean({
    this.name,
    this.conditionOnProperty,
    this.dependencies,
  });
}
