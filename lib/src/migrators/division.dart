// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:args/args.dart';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'package:sass_migrator/src/migration_visitor.dart';
import 'package:sass_migrator/src/migrator.dart';
import 'package:sass_migrator/src/patch.dart';
import 'package:sass_migrator/src/utils.dart';

/// Migrates stylesheets that use the `/` operator for division to use the
/// `divide` function instead.
class DivisionMigrator extends Migrator {
  final name = "division";
  final description =
      "Migrates from the / division operator to the divide function";

  @override
  final argParser = ArgParser()
    ..addFlag('aggressive',
        abbr: 'a',
        help: r"If set, expressions like '$x/3 + 1', '$x/3 - 1', and 'fn()/3' "
            "will be migrated.");

  bool get isAggressive => argResults['aggressive'] as bool;

  Map<Uri, String> migrateFile(Uri entrypoint) =>
      _DivisionMigrationVisitor(this.isAggressive, migrateDependencies)
          .run(entrypoint);
}

class _DivisionMigrationVisitor extends MigrationVisitor {
  final bool isAggressive;

  _DivisionMigrationVisitor(this.isAggressive, bool migrateDependencies)
      : super(migrateDependencies: migrateDependencies);

  /// True when division is allowed by the context the current node is in.
  bool _isDivisionAllowed = false;

  /// True when the current node is expected to evaluate to a number.
  bool _expectsNumericResult = false;

  /// If this is a division operation, migrates it.
  ///
  /// If this is any other operator, allows division within its left and right
  /// operands.
  @override
  void visitBinaryOperationExpression(BinaryOperationExpression node) {
    if (node.operator == BinaryOperator.dividedBy) {
      if (shouldMigrate(node)) {
        addPatch(patchBefore(node, "divide("));
        patchSlashToComma(node);
        addPatch(patchAfter(node, ")"));
      }
      super.visitBinaryOperationExpression(node);
    } else {
      withContext(
          true,
          _expectsNumericResult || operatesOnNumbers(node.operator),
          () => super.visitBinaryOperationExpression(node));
    }
  }

  /// Disallows division within this list.
  @override
  void visitListExpression(ListExpression node) {
    withContext(
        false, _expectsNumericResult, () => super.visitListExpression(node));
  }

  /// If this parenthesized expression contains a division operation, migrates
  /// it using the parentheses that already exist.
  @override
  void visitParenthesizedExpression(ParenthesizedExpression node) {
    var expression = node.expression;
    if (expression is BinaryOperationExpression &&
        expression.operator == BinaryOperator.dividedBy) {
      withContext(true, _expectsNumericResult, () {
        if (shouldMigrate(expression)) {
          addPatch(patchBefore(node, "divide"));
          patchSlashToComma(expression);
        }
        super.visitBinaryOperationExpression(expression);
      });
      return;
    }
    withContext(true, _expectsNumericResult,
        () => super.visitParenthesizedExpression(node));
  }

  /// Allows division within this return rule.
  @override
  void visitReturnRule(ReturnRule node) {
    withContext(true, _expectsNumericResult, () => super.visitReturnRule(node));
  }

  /// Allows division within this variable declaration.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    withContext(true, _expectsNumericResult,
        () => super.visitVariableDeclaration(node));
  }

  /// Returns true if we assume that [operator] always returns a number.
  ///
  /// This is always true for * and %, and it's true for + and - as long as the
  /// aggressive option is enabled.
  bool returnsNumbers(BinaryOperator operator) =>
      operator == BinaryOperator.times ||
      operator == BinaryOperator.modulo ||
      isAggressive &&
          (operator == BinaryOperator.plus || operator == BinaryOperator.minus);

  /// Returns true if we assume that [operator] always operators on numbers.
  ///
  /// This is always true for *, %, <, <=, >, and >=, and it's true for +, -,
  /// ==, and != as long as the aggressive option is enabled.
  bool operatesOnNumbers(BinaryOperator operator) =>
      returnsNumbers(operator) ||
      operator == BinaryOperator.lessThan ||
      operator == BinaryOperator.lessThanOrEquals ||
      operator == BinaryOperator.greaterThan ||
      operator == BinaryOperator.greaterThanOrEquals ||
      isAggressive &&
          (operator == BinaryOperator.equals ||
              operator == BinaryOperator.notEquals);

  /// Returns true if [node] should be treated as division and migrated.
  ///
  /// Warns if division is allowed but it's unclear whether or not all types
  /// are numeric.
  bool shouldMigrate(BinaryOperationExpression node) {
    if (!_isDivisionAllowed && onlySlash(node)) {
      return false;
    }
    if (hasNonNumber(node)) return false;
    if (_expectsNumericResult || _allNumeric(node)) return true;
    warn("Could not determine whether this is division", node.span);
    return false;
  }

  /// Returns true if [node] is entirely composed of number literals and slash
  /// operations.
  bool onlySlash(Expression node) {
    if (node is NumberExpression) return true;
    if (node is BinaryOperationExpression) {
      return node.operator == BinaryOperator.dividedBy &&
          onlySlash(node.left) &&
          onlySlash(node.right);
    }
    return false;
  }

  /// Returns true if [node] is believed to always evaluate to a number.
  bool _allNumeric(Expression node) {
    if (node is NumberExpression) return true;
    if (node is ParenthesizedExpression) return _allNumeric(node.expression);
    if (node is UnaryOperationExpression) return _allNumeric(node.operand);
    if (node is FunctionExpression) return isAggressive;
    if (node is BinaryOperationExpression) {
      return returnsNumbers(node.operator) ||
          (_allNumeric(node.left) && _allNumeric(node.right));
    }
    return false;
  }

  /// Returns true if [node] contains a subexpression known to not be a number.
  bool hasNonNumber(Expression node) {
    if (node is ParenthesizedExpression) return hasNonNumber(node.expression);
    if (node is BinaryOperationExpression) {
      return hasNonNumber(node.left) || hasNonNumber(node.right);
    }
    return node is BooleanExpression ||
        node is ColorExpression ||
        node is ListExpression ||
        node is MapExpression ||
        node is NullExpression ||
        node is StringExpression;
  }

  /// Adds a patch replacing the operator of [node] with ", ".
  void patchSlashToComma(BinaryOperationExpression node) {
    var start = node.left.span.end;
    var end = node.right.span.start;
    addPatch(Patch(start.file.span(start.offset, end.offset), ", "));
  }

  /// Runs [operation] with the given context.
  void withContext(
      bool isDivisionAllowed, bool expectsNumericResult, void operation()) {
    var previousDivisionAllowed = _isDivisionAllowed;
    var previousNumericResult = _expectsNumericResult;
    _isDivisionAllowed = isDivisionAllowed;
    _expectsNumericResult = expectsNumericResult;
    operation();
    _isDivisionAllowed = previousDivisionAllowed;
    _expectsNumericResult = previousNumericResult;
  }
}
