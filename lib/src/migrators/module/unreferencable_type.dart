// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:sass_api/sass_api.dart';

import '../../exception.dart';

/// An enum of reasons why a member is unreferencable.
@sealed
class UnreferencableType {
  /// For members of the importing stylesheet within a nested import.
  static const fromImporter = UnreferencableType._('fromImporter');

  /// For members from a nested import.
  static const fromNestedImport = UnreferencableType._('fromNestedImport');

  /// Identifier for this unreferencable type.
  final String id;

  const UnreferencableType._(this.id);

  /// Returns a MigrationException for a [reference] to a member defined in
  /// [source] of this type.
  MigrationException toException(SassNode reference, Uri source) {
    var type = reference is IncludeRule
        ? 'mixin'
        : reference is FunctionExpression
            ? 'function'
            : 'variable';
    var url = p.prettyUri(source);
    switch (this) {
      case fromImporter:
        return MigrationSourceSpanException(
            "This stylesheet was loaded by a nested import in $url. The module "
            "system only supports loading nested CSS using the load-css() "
            "mixin, which doesn't allow access to ${type}s from the outer "
            "stylesheet.",
            reference.span);
      case fromNestedImport:
        return MigrationSourceSpanException(
            "This $type was loaded from a nested import of $url. The module "
            "system only supports loading nested CSS using the load-css() "
            "mixin, which doesn't load ${type}s.",
            reference.span);
      default:
        throw StateError('Invalid UnreferencableType');
    }
  }
}
