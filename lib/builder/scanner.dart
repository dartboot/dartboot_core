import 'dart:async';

import 'package:build/build.dart';
import 'package:dartboot_annotation/dartboot_annotation.dart';
import 'package:source_gen/source_gen.dart';

/// [RestController]Rest API控制器的扫描器
const TypeChecker restControllerChecker =
    TypeChecker.fromRuntime(RestController);

/// [Bean]Bean类的扫描器
const TypeChecker beanControllerChecker = TypeChecker.fromRuntime(Bean);

/// 支持的扫描器
const supportCheckers = [restControllerChecker, beanControllerChecker];

/// 扫描器
///
/// 负责扫描所有内置注解下的类，然后记录类的包路径
/// 用于 [ContextWriter] 写入import代码到 [g.dart] 文件中
///
/// @author luodongseu
class Scanner implements Generator {
  /// 注解扫描到的全部dart文件的路径
  static final Set<String> _annotationUris = {};

  static List<String> get annotationUris => List.from(_annotationUris);

  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) {
    for (var clazz in library.classes) {
      // 扫描注解类
      if (supportCheckers.any((c) => c.hasAnnotationOf(clazz))) {
        final source = clazz.librarySource ?? clazz.source;
        if (null != source && !source.isInSystemLibrary) {
          print(library.pathToUrl(source.uri));
          _annotationUris.add(library.pathToUrl(source.uri).toString());
        }
      }
    }
    // null 即被忽略
    return null;
  }
}
