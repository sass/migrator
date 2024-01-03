// Copyright 2023 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';

/// Removes interpolation in calculation functions.
class CalculationInterpolationMigrator extends Migrator {
  final name = "calc-interpolation";
  final description = r"Removes interpolation in calculation functions"
      r"`calc()`, `clamp()`, `min()`, and `max()`";

  @override
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer) {
    var visitor =
        _CalculationInterpolationVisitor(importCache, migrateDependencies);
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

class _CalculationInterpolationVisitor extends MigrationVisitor {
  _CalculationInterpolationVisitor(
      ImportCache importCache, bool migrateDependencies)
      : super(importCache, migrateDependencies);

  @override
  void visitFunctionExpression(FunctionExpression node) {
    const calcFunctions = ['calc', 'clamp', 'min', 'max'];
    final interpolation = RegExp(r'\#{\s*[^}]+\s*}');
    final hasOperation = RegExp(r'[-+*/]+');
    if (calcFunctions.contains(node.name)) {
      for (var arg in node.arguments.positional) {
        var newArg = arg.toString();
        for (var match in interpolation.allMatches(arg.toString())) {
          var noInterpolation =
              match[0].toString().substring(2, match[0].toString().length - 1);
          if (hasOperation.hasMatch(noInterpolation)) {
            noInterpolation = '(' + noInterpolation + ')';
          }
          newArg = newArg
              .toString()
              .replaceAll(match[0].toString(), noInterpolation);
        }
        if (newArg != arg.toString()) {
          var interpolationSpan =
              node.span.file.span(arg.span.start.offset, arg.span.end.offset);
          addPatch(Patch(interpolationSpan, newArg));
          return;
        }
      }
    }
    super.visitFunctionExpression(node);
  }
}
