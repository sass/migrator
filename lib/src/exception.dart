// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass/sass.dart';
import 'package:source_span/source_span.dart';

/// An exception thrown by a migrator.
class MigrationException implements Exception {
  /// An explanation of why migration failed.
  final String message;

  MigrationException(this.message);

  String toString() => "Error: $message";
}

// TODO(jathak): Stop extending [SassException] here.
// ignore_for_file: subtype_of_sealed_class

/// A [MigrationException] that has source span information associated with it.
///
/// This extends [SassException] to ensure that migrator exceptions are
/// formatted the same way as the syntax errors Sass throws.
class MigrationSourceSpanException extends SassException
    implements MigrationException {
  MigrationSourceSpanException(String message, FileSpan span)
      : super(message, span);
}
