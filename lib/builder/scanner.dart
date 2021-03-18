import 'dart:async';

import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import '../annotation/annotation.dart';

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
  static Set<String> _annotationUris = Set();

  static List<String> get annotationUris => List.from(_annotationUris);

  SGenerator(Map options) {}

  @override
  FutureOr<String> generate(LibraryReader library, BuildStep buildStep) {
    for (ClassElement clazz in library.classes) {
      // 扫描注解类
      if (supportCheckers.any((c) => c.hasAnnotationOf(clazz))) {
        final source = clazz.librarySource ?? clazz.source;
        if (null != source && !source.isInSystemLibrary) {
          _annotationUris.add(source.uri.toString());
        }
      }
    }
    // null 即被忽略
    return null;
  }
}
