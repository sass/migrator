// Copyright 2022 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';

/// Migrates deprecated `$a -$b` construct to unambiguous `$a - $b`.
class StrictUnaryMigrator extends Migrator {
  @override
  final name = "strict-unary";
  @override
  final description =
      r"Migrates deprecated `$a -$b` syntax (and similar) to "
      r"unambiguous `$a - $b`";

  @override
  Map<Uri, String> migrateFile(
    ImportCache importCache,
    Stylesheet stylesheet,
    Importer importer,
  ) {
    var visitor = _UnaryMigrationVisitor(
      importCache,
      migrateDependencies: migrateDependencies,
    );
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

class _UnaryMigrationVisitor(
  super.importCache, {
  required super.migrateDependencies,
}) extends MigrationVisitor {
  @override
  void visitBinaryOperationExpression(BinaryOperationExpression node) {
    if (node.operator case .plus || .minus) {
      var betweenOperands = node.span.file
          .span(node.left.span.end.offset, node.right.span.start.offset)
          .text;
      if (betweenOperands.startsWith(RegExp(r'\s')) &&
          betweenOperands.endsWith(node.operator.operator)) {
        addPatch(Patch.insert(node.right.span.start, ' '));
      }
    }
    super.visitBinaryOperationExpression(node);
  }
}
