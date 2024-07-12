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
    var visitor = _CalculationInterpolationVisitor(importCache,
        migrateDependencies: migrateDependencies);
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

class _CalculationInterpolationVisitor extends MigrationVisitor {
  _CalculationInterpolationVisitor(super.importCache,
      {required super.migrateDependencies});

  @override
  void visitFunctionExpression(FunctionExpression node) {
    const calcFunctions = ['calc', 'clamp', 'min', 'max'];
    final interpolation = RegExp(r'\#{\s*[^}]+\s*}');
    final hasOperation = RegExp(r'\s+[-+*/]+\s+');
    final isVarFunc = RegExp(
        r'var\(#{[a-zA-Z0-9#{$}-]+}\)|var\(\-\-[a-zA-Z0-9\$\#\{\}\-]+\)');
    if (calcFunctions.contains(node.name)) {
      for (var arg in node.arguments.positional) {
        var newArg = arg.toString();
        var varFuncArgs = isVarFunc.allMatches(newArg);
        if (varFuncArgs.isNotEmpty) {
          newArg = newArg.replaceAll(isVarFunc, 'var()');
        }

        for (var match in interpolation.allMatches(newArg)) {
          var noInterpolation = match[0]!.substring(2, match[0]!.length - 1);
          if (hasOperation.hasMatch(noInterpolation)) {
            noInterpolation = '(' + noInterpolation + ')';
          }
          newArg = newArg.toString().replaceAll(match[0]!, noInterpolation);
        }

        for (var match in varFuncArgs) {
          newArg = newArg.replaceFirst('var()', match[0]!);
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
