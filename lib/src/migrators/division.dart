// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:args/args.dart';
import 'package:sass/sass.dart';

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
  final description = """
Migrates from the / division operator to the divide() function

More info: https://sass-lang.com/d/slash-div""";

  @override
  final argParser = ArgParser()
    ..addFlag('pessimistic',
        abbr: 'p',
        help: "Only migrate / expressions that are unambiguously division.",
        negatable: false);

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

  /// Allows division within this argument invocation.
  @override
  void visitArgumentInvocation(ArgumentInvocation invocation) {
    _withContext(() => super.visitArgumentInvocation(invocation),
        isDivisionAllowed: true);
  }

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

  /// Allows division within a function call's arguments, with special handling
  /// for new-syntax color functions.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    visitInterpolation(node.name);
    if (_tryColorFunction(node)) return;
    visitArgumentInvocation(node.arguments);
  }

  /// Disallows division within this list.
  @override
  void visitListExpression(ListExpression node) {
    _withContext(() => super.visitListExpression(node),
        isDivisionAllowed: false, expectsNumericResult: false);
  }

  /// Allows division within this parenthesized expression.
  ///
  /// If these parentheses contain a `/` operation that is migrated to a
  /// function call, the now-unnecessary parentheses will be removed.
  @override
  void visitParenthesizedExpression(ParenthesizedExpression node) {
    _withContext(() {
      var expression = node.expression;
      if (expression is BinaryOperationExpression &&
          expression.operator == BinaryOperator.dividedBy) {
        if (_visitSlashOperation(expression)) {
          addPatch(patchDelete(node.span, end: 1));
          addPatch(patchDelete(node.span, start: node.span.length - 1));
        }
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

  /// Migrates [node] and returns true if it is a new-syntax color function or
  /// returns false if it is any other function.
  bool _tryColorFunction(FunctionExpression node) {
    if (!["rgb", "rgba", "hsl", "hsla"].contains(node.name.asPlain)) {
      return false;
    }

    ListExpression channels;
    if (node.arguments.positional.length == 1 &&
        node.arguments.named.isEmpty &&
        node.arguments.positional.first is ListExpression) {
      channels = node.arguments.positional.first;
    } else if (node.arguments.positional.isEmpty &&
        node.arguments.named.containsKey(r'$channels') &&
        node.arguments.named.length == 1 &&
        node.arguments.named[r'$channels'] is ListExpression) {
      channels = node.arguments.named[r'$channels'];
    }
    if (channels == null ||
        channels.hasBrackets ||
        channels.separator != ListSeparator.space ||
        channels.contents.length != 3 ||
        channels.contents.last is! BinaryOperationExpression) {
      return false;
    }

    var last = channels.contents.last as BinaryOperationExpression;
    if (last.left is! NumberExpression || last.right is! NumberExpression) {
      // Handles cases like `rgb(10 20 30/2 / 0.5)`, since converting `30/2` to
      // `divide(30, 20)` would cause `/ 0.5` to be interpreted as division.
      _patchSpacesToCommas(channels);
      _patchOperatorToComma(last);
    }
    _withContext(() {
      channels.contents[0].accept(this);
      channels.contents[1].accept(this);
      last.left.accept(this);
    }, isDivisionAllowed: true);
    last.right.accept(this);
    return true;
  }

  /// Visits a `/` operation [node] and migrates it to either the `division`
  /// function or the `slash-list` function.
  ///
  /// Returns true the `/` was migrated to either function call, and false if
  /// the `/` is ambiguous and a warning was emitted instead (pessimistic mode
  /// only).
  bool _visitSlashOperation(BinaryOperationExpression node) {
    if ((!_isDivisionAllowed && _onlySlash(node)) ||
        _isDefinitelyNotNumber(node)) {
      // Definitely not division
      if (_isDivisionAllowed || _containsInterpolation(node)) {
        // We only want to convert a non-division slash operation to a
        // slash-list call when it's in a non-plain-CSS context to avoid
        // unnecessary function calls within plain CSS.
        addPatch(patchBefore(node, "slash-list("));
        addPatch(patchAfter(node, ")"));
        _visitSlashListArguments(node);
      }
      return true;
    } else if (_expectsNumericResult ||
        _isDefinitelyNumber(node) ||
        !isPessimistic) {
      // Definitely division
      addPatch(patchBefore(node, "divide("));
      addPatch(patchAfter(node, ")"));
      _patchParensIfAny(node.left);
      _patchOperatorToComma(node);
      _patchParensIfAny(node.right);
      _withContext(() => super.visitBinaryOperationExpression(node),
          expectsNumericResult: true);
      return true;
    } else {
      emitWarning("Could not determine whether this is division", node.span);
      super.visitBinaryOperationExpression(node);
      return false;
    }
  }

  /// Visits the arguments of a `/` operation that is being converted into a
  /// call to `slash-list`, converting slashes to commas and removing
  /// unnecessary interpolation.
  void _visitSlashListArguments(Expression node) {
    if (node is BinaryOperationExpression &&
        node.operator == BinaryOperator.dividedBy) {
      _visitSlashListArguments(node.left);
      _patchOperatorToComma(node);
      _visitSlashListArguments(node.right);
    } else if (node is StringExpression &&
        node.text.contents.length == 1 &&
        node.text.contents.first is Expression) {
      // Remove `#{` and `}`
      addPatch(patchDelete(node.span, end: 2));
      addPatch(patchDelete(node.span, start: node.span.length - 1));
      (node.text.contents.first as Expression).accept(this);
    } else {
      node.accept(this);
    }
  }

  /// Returns true if we assume that [operator] always returns a number.
  ///
  /// This is true for `*` and `%`.
  bool _returnsNumbers(BinaryOperator operator) =>
      operator == BinaryOperator.times || operator == BinaryOperator.modulo;

  /// Returns true if we assume that [operator] always operators on numbers.
  ///
  /// This is true for `*`, `%`, `<`, `<=`, `>`, and `>=`.
  bool _operatesOnNumbers(BinaryOperator operator) =>
      _returnsNumbers(operator) ||
      operator == BinaryOperator.lessThan ||
      operator == BinaryOperator.lessThanOrEquals ||
      operator == BinaryOperator.greaterThan ||
      operator == BinaryOperator.greaterThanOrEquals;

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

  /// Returns true if [node] is known to always evaluate to a number.
  bool _isDefinitelyNumber(Expression node) {
    if (node is NumberExpression) return true;
    if (node is ParenthesizedExpression) {
      return _isDefinitelyNumber(node.expression);
    } else if (node is UnaryOperationExpression) {
      return _isDefinitelyNumber(node.operand);
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

  /// Returns true if [node] contains an interpolation.
  bool _containsInterpolation(Expression node) {
    if (node is ParenthesizedExpression) return _containsInterpolation(node);
    if (node is BinaryOperationExpression) {
      return _containsInterpolation(node.left) ||
          _containsInterpolation(node.right);
    }
    return node is StringExpression && node.text.asPlain == null;
  }

  /// Converts a space-separated list [node] to a comma-separated list.
  void _patchSpacesToCommas(ListExpression node) {
    for (var i = 0; i < node.contents.length - 1; i++) {
      var start = node.contents[i].span.end;
      var end = node.contents[i + 1].span.start;
      addPatch(Patch(start.file.span(start.offset, end.offset), ", "));
    }
  }

  /// Adds a patch replacing the operator of [node] with ", ".
  void _patchOperatorToComma(BinaryOperationExpression node) {
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
    addPatch(patchDelete(node.span, end: 1));
    addPatch(patchDelete(node.span, start: node.span.length - 1));
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
