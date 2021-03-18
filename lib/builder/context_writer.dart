import 'package:analyzer/dart/element/element.dart';
import 'package:build/build.dart';
import 'package:build/src/builder/build_step.dart';
import 'package:source_gen/source_gen.dart';

import '../annotation/annotation.dart';
import 'scanner.dart';

/// [BuildContext] dart文件的编写器
///
/// 该Writer会扫描注解为BootContext的dart文件，然后创建一个.g.dart文件
///
/// @Author luodongseu
class ContextWriter extends GeneratorForAnnotation<BootContext> {
  @override
  generateForAnnotatedElement(
      Element element, ConstantReader annotation, BuildStep buildStep) {
    buildStep.inputId.changeExtension('.g.dart');
    final source = element.librarySource ?? element.source;
    if (null != source && !source.isInSystemLibrary) {
      StringBuffer buffer =
          StringBuffer('/// This is auto import holder file!!!\r\n');
      StringBuffer loadLibraryLines = StringBuffer('');
      buffer.writeln('');
      buffer.writeln('');
      for (int i = 0; i < Scanner.annotationUris.length; i++) {
        final ai = Scanner.annotationUris[i];
        buffer.writeln('import "$ai" deferred as clz$i;');
        loadLibraryLines.writeln('await clz$i.loadLibrary();');
      }
      buffer.writeln('');
      buffer.writeln('');
      buffer.writeln('/// Empty class [BuildContext] to import to main '
          'isolate');
      buffer.writeln('/// ');
      buffer.writeln('/// Builer created automaticly');
      // class start
      buffer.writeln('class BuildContext {');

      // load function start
      buffer.writeln('/// [load] function to load all annotated dart files');
      buffer.writeln('void load() async {');
      buffer.write(loadLibraryLines.toString());
      // load function end
      buffer.writeln('}');

      // class end
      buffer.writeln('}');
      return buffer.toString();
    }
    // 出错了
    throw ArgumentError('ApplicationContext not found!');
  }
}
