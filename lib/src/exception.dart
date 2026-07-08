// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:source_span/source_span.dart';
import 'package:sass_api/sass_api.dart';

/// An exception thrown by a migrator.
class MigrationException implements Exception {
  /// An explanation of why migration failed.
  final String message;

  MigrationException(this.message);

  String toString() => "Error: $message";
}

/// A [MigrationException] that has source span information associated with it.
///
/// This extends [SassException] to ensure that migrator exceptions are
/// formatted the same way as the syntax errors Sass throws.
class MigrationSourceSpanException extends SourceSpanException
    implements MigrationException {
  FileSpan get span => super.span as FileSpan;

  MigrationSourceSpanException(String message, FileSpan span)
    : super(message, span);

  String toString({Object? color}) =>
      // Match Dart Sass's exception formatting.
      SassException(message, span).toString(color: color);
}
