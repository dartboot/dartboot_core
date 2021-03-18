/// @Annotation Api
///
/// 接口描述的注解
///
/// example:
/// ```
/// @Api('新建文章接口')
/// @Post('/newArticle')
/// void addArticle(@body dynamic article) {
///   // ...
/// }
/// ```
///
/// @author luodongseu
class Api {
  /// 描述
  final String description;

  const Api(this.description);
}
