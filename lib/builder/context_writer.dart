import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build/src/builder/build_step.dart';
import 'package:dartboot_annotation/dartboot_annotation.dart';
import 'package:source_gen/source_gen.dart';

import 'scanner.dart';

/// [BuildContext] dart文件的编写器
///
/// 该Writer会扫描注解为BootContext的dart文件，然后创建一个.g.dart文件
///
/// @Author luodongseu
class ContextWriter extends GeneratorForAnnotation<DartBootApplication> {
  static bool initializerLoaded = false;

  @override
  String generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    if (initializerLoaded) {
      return '';
    }

    buildStep.inputId.changeExtension('.g.dart');
    final source = element.librarySource ?? element.source;
    if (null != source && !source.isInSystemLibrary) {
      var buffer = StringBuffer(
          '/// This is auto import holder file: ${Scanner.annotationUris.length} ${Scanner.annotationUris}!!!\r\n');
      var loadLibraryLines = StringBuffer('');
      buffer.writeln('');
      buffer.writeln('');
      for (var i = 0; i < Scanner.annotationUris.length; i++) {
        final ai = Scanner.annotationUris[i];
        buffer.writeln('import "$ai" deferred as clz$i;');
        loadLibraryLines.writeln('clz$i.loadLibrary();');
      }
      buffer.writeln('');
      buffer.writeln('');
      buffer.writeln('/// Empty class [DartBootInitializer] to import to main '
          'isolate');
      buffer.writeln('/// ');
      buffer.writeln('/// Created by build_runner and source_gen');
      // class start
      buffer.writeln('class DartBootInitializer {');

      // load function start
      buffer.writeln('/// [load] function to load all annotated dart files');
      buffer.writeln('DartBootInitializer() {');
      buffer.write(loadLibraryLines.toString());
      // load function end
      buffer.writeln('}');

      // class end
      buffer.writeln('}');

      // class init segment
      buffer.writeln('');
      buffer.writeln('/// Load constructor to load packages');
      buffer.writeln('var i = DartBootInitializer();');
      buffer.writeln('');
      buffer.writeln('/// File end');

      // Set loaded
      initializerLoaded = true;

      return buffer.toString();
    }
    // 出错了
    throw ArgumentError('DartBootInitializer not found!');
  }
}
