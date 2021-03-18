import 'package:build/build.dart';
import 'package:source_gen/source_gen.dart';

import 'context_writer.dart';
import 'scanner.dart';

/// Scan all class annotated with inner annotations
Builder scan(BuilderOptions options) {
  return LibraryBuilder(
    Scanner(),
    generatedExtension: '.g.ignore.dart',
  );
}

/// Write [BuildContext] class to application_context.g.dart
Builder write(BuilderOptions options) {
  return LibraryBuilder(
    ContextWriter(),
    generatedExtension: '.g.dart',
  );
}
