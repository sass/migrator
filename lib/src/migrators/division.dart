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
    ..addFlag('pessimistic',
        abbr: 'p',
        help: "Only migrate / expressions that are unambiguously division.");

  bool get isPessimistic => argResults['pessimistic'] as bool;

  @override
  Map<Uri, String> migrateFile(Uri entrypoint) =>
      _DivisionMigrationVisitor(this.isPessimistic, migrateDependencies)
          .run(entrypoint);
}

class _DivisionMigrationVisitor extends MigrationVisitor {
  final bool isPessimistic;

  _DivisionMigrationVisitor(this.isPessimistic, bool migrateDependencies)
      : super(migrateDependencies: migrateDependencies);

  /// True when division is allowed by the context the current node is in.
  var _isDivisionAllowed = false;

  /// True when the current node is expected to evaluate to a number.
  var _expectsNumericResult = false;

  /// If this is a division operation, migrates it.
  ///
  /// If this is any other operator, allows division within its left and right
  /// operands.
  @override
  void visitBinaryOperationExpression(BinaryOperationExpression node) {
    if (node.operator == BinaryOperator.dividedBy) {
      _visitSlashOperation(node);
    } else {
      _withContext(() => super.visitBinaryOperationExpression(node),
          isDivisionAllowed: true,
          expectsNumericResult:
              _expectsNumericResult || _operatesOnNumbers(node.operator));
    }
  }

  /// Disallows division within this list.
  @override
  void visitListExpression(ListExpression node) {
    _withContext(() => super.visitListExpression(node),
        isDivisionAllowed: false, expectsNumericResult: false);
  }

  /// If this parenthesized expression contains a division operation, migrates
  /// it using the parentheses that already exist.
  @override
  void visitParenthesizedExpression(ParenthesizedExpression node) {
    _withContext(() {
      var expression = node.expression;
      if (expression is BinaryOperationExpression &&
          expression.operator == BinaryOperator.dividedBy) {
        _visitSlashOperation(expression, surroundingParens: node);
      } else {
        super.visitParenthesizedExpression(node);
      }
    }, isDivisionAllowed: true);
  }

  /// Allows division within this return rule.
  @override
  void visitReturnRule(ReturnRule node) {
    _withContext(() => super.visitReturnRule(node), isDivisionAllowed: true);
  }

  /// Allows division within this variable declaration.
  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _withContext(() => super.visitVariableDeclaration(node),
        isDivisionAllowed: true);
  }

  /// Visits a `/` operation [node] and migrates it to either the `division`
  /// function or the `slash-list` function.
  ///
  /// If [surroundingParens] is provided, this will reuse the existing parens
  /// instead of creating new ones.
  void _visitSlashOperation(BinaryOperationExpression node,
      {ParenthesizedExpression surroundingParens}) {
    if ((!_isDivisionAllowed && _onlySlash(node)) ||
        _isDefinitelyNotNumber(node)) {
      // Definitely not division
      if (surroundingParens != null) {
        addPatch(patchBefore(surroundingParens, "slash-list"));
      } else {
        addPatch(patchBefore(node, "slash-list("));
        addPatch(patchAfter(node, ")"));
      }
      _visitSlashListArguments(node);
    } else if (_expectsNumericResult || _isDefinitelyNumber(node)) {
      // Definitely division
      if (surroundingParens != null) {
        addPatch(patchBefore(surroundingParens, "divide"));
      } else {
        addPatch(patchBefore(node, "divide("));
        addPatch(patchAfter(node, ")"));
      }
      _patchParensIfAny(node.left);
      _patchSlashToComma(node);
      _patchParensIfAny(node.right);
      _withContext(() => super.visitBinaryOperationExpression(node),
          expectsNumericResult: true);
    } else {
      warn("Could not determine whether this is division", node.span);
      super.visitBinaryOperationExpression(node);
    }
  }

  /// Visits the arguments of a `/` operation that is being converted into a
  /// call to `slash-list`, converting slashes to commas and removing
  /// unnecessary interpolation.
  void _visitSlashListArguments(Expression node) {
    if (node is BinaryOperationExpression &&
        node.operator == BinaryOperator.dividedBy) {
      _visitSlashListArguments(node.left);
      _patchSlashToComma(node);
      _visitSlashListArguments(node.right);
    } else if (node is StringExpression &&
        node.text.contents.length == 1 &&
        node.text.contents.first is Expression) {
      var start = node.text.span.start.offset;
      var end = node.text.span.end.offset;
      // Remove `#{` and `}`
      addPatch(Patch(node.span.file.span(start, start + 2), ""));
      addPatch(Patch(node.span.file.span(end - 1, end), ""));
      node.text.contents.first.accept(this);
    } else {
      node.accept(this);
    }
  }

  /// Returns true if we assume that [operator] always returns a number.
  ///
  /// This is always true for `*` and `%`, and it's true for `+` and `-` as long
  /// as the aggressive option is enabled.
  bool _returnsNumbers(BinaryOperator operator) =>
      operator == BinaryOperator.times ||
      operator == BinaryOperator.modulo ||
      !isPessimistic &&
          (operator == BinaryOperator.plus || operator == BinaryOperator.minus);

  /// Returns true if we assume that [operator] always operators on numbers.
  ///
  /// This is always true for `*`, `%`, `<`, `<=`, `>`, and `>=`, and it's true
  /// for `+`, `-`, `==`, and `!=` as long as the aggressive option is enabled.
  bool _operatesOnNumbers(BinaryOperator operator) =>
      _returnsNumbers(operator) ||
      operator == BinaryOperator.lessThan ||
      operator == BinaryOperator.lessThanOrEquals ||
      operator == BinaryOperator.greaterThan ||
      operator == BinaryOperator.greaterThanOrEquals ||
      !isPessimistic &&
          (operator == BinaryOperator.equals ||
              operator == BinaryOperator.notEquals);

  /// Returns true if [node] is entirely composed of number literals and slash
  /// operations.
  bool _onlySlash(Expression node) {
    if (node is NumberExpression) return true;
    if (node is BinaryOperationExpression) {
      return node.operator == BinaryOperator.dividedBy &&
          _onlySlash(node.left) &&
          _onlySlash(node.right);
    }
    return false;
  }

  /// Returns true if [node] is believed to always evaluate to a number.
  bool _isDefinitelyNumber(Expression node) {
    if (node is NumberExpression) return true;
    if (node is ParenthesizedExpression) {
      return _isDefinitelyNumber(node.expression);
    } else if (node is UnaryOperationExpression) {
      return _isDefinitelyNumber(node.operand);
    } else if (node is FunctionExpression || node is VariableExpression) {
      return !isPessimistic;
    } else if (node is BinaryOperationExpression) {
      return _returnsNumbers(node.operator) ||
          (_isDefinitelyNumber(node.left) && _isDefinitelyNumber(node.right));
    }
    return false;
  }

  /// Returns true if [node] contains a subexpression known to not be a number.
  bool _isDefinitelyNotNumber(Expression node) {
    if (node is ParenthesizedExpression) {
      return _isDefinitelyNotNumber(node.expression);
    }
    if (node is BinaryOperationExpression) {
      return _isDefinitelyNotNumber(node.left) ||
          _isDefinitelyNotNumber(node.right);
    }
    return node is BooleanExpression ||
        node is ColorExpression ||
        node is ListExpression ||
        node is MapExpression ||
        node is NullExpression ||
        node is StringExpression;
  }

  /// Adds a patch replacing the operator of [node] with ", ".
  void _patchSlashToComma(BinaryOperationExpression node) {
    var start = node.left.span.end;
    var end = node.right.span.start;
    addPatch(Patch(start.file.span(start.offset, end.offset), ", "));
  }

  /// Adds patches removing unnecessary parentheses around [node] if it is a
  /// ParenthesizedExpression.
  void _patchParensIfAny(SassNode node) {
    if (node is! ParenthesizedExpression) return;
    var expression = (node as ParenthesizedExpression).expression;
    if (expression is BinaryOperationExpression &&
        expression.operator == BinaryOperator.dividedBy) {
      return;
    }
    var start = node.span.start;
    var end = node.span.end;
    addPatch(Patch(start.file.span(start.offset, start.offset + 1), ""));
    addPatch(Patch(start.file.span(end.offset - 1, end.offset), ""));
  }

  /// Runs [operation] with the given context.
  void _withContext(void operation(),
      {bool isDivisionAllowed, bool expectsNumericResult}) {
    var previousDivisionAllowed = _isDivisionAllowed;
    var previousNumericResult = _expectsNumericResult;
    if (isDivisionAllowed != null) _isDivisionAllowed = isDivisionAllowed;
    if (expectsNumericResult != null) {
      _expectsNumericResult = expectsNumericResult;
    }
    operation();
    _isDivisionAllowed = previousDivisionAllowed;
    _expectsNumericResult = previousNumericResult;
  }
}
