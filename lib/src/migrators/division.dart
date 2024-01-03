// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:args/args.dart';
import 'package:sass_api/sass_api.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';
import '../util/scope.dart';
import '../utils.dart';

/// The CSS calculation functions where slash-division is allowed (unless
/// there's a user-defined function with the same name).
const _calcFunctions = {
  'calc',
  'clamp',
  'min',
  'max',
  'round',
  'mod',
  'rem',
  'sin',
  'cos',
  'tan',
  'asin',
  'acos',
  'atan',
  'atan2',
  'pow',
  'sqrt',
  'hypot',
  'log',
  'exp',
  'abs',
  'sign',
};

/// Migrates stylesheets that use the `/` operator for division to use the
/// `divide` function instead.
class DivisionMigrator extends Migrator {
  final name = "division";
  final description = """
Use the math.div() function instead of the / division operator

More info: https://sass-lang.com/d/slash-div""";

  @override
  final argParser = ArgParser()
    ..addFlag('pessimistic',
        abbr: 'p',
        help: "Only migrate / expressions that are unambiguously division.",
        negatable: false)
    ..addFlag('multiplication',
        help: 'Migrate / expressions with certain constant divisors to use '
            'multiplication instead.',
        defaultsTo: true);

  bool get isPessimistic => argResults!['pessimistic'] as bool;
  bool get useMultiplication => argResults!['multiplication'] as bool;

  @override
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer) {
    var visitor = _DivisionMigrationVisitor(
        importCache, isPessimistic, useMultiplication, migrateDependencies);
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

/// The set of constant divisors that should be migrated to multiplication.
const _allowedDivisors = {2, 4, 5, 8, 10, 20, 40, 50, 80, 100, 1000};

class _DivisionMigrationVisitor extends MigrationVisitor {
  final bool isPessimistic;
  final bool useMultiplication;

  _DivisionMigrationVisitor(ImportCache importCache, this.isPessimistic,
      this.useMultiplication, bool migrateDependencies)
      : super(importCache, migrateDependencies);

  /// True when division is allowed by the context the current node is in.
  var _isDivisionAllowed = false;

  /// True when the current node is expected to evaluate to a number.
  var _expectsNumericResult = false;

  /// True when the current node is in calc context, so division should be
  /// left unchanged.
  var _inCalcContext = false;

  /// The namespaces that already exist in the current stylesheet.
  Map<Uri, String?> get _existingNamespaces =>
      assertInStylesheet(__existingNamespaces, '_existingNamespaces');
  Map<Uri, String?>? __existingNamespaces;

  /// A list of `@use` rules to insert at [_useRuleInsertionPoint];
  List<String> get _useRulesToInsert =>
      assertInStylesheet(__useRulesToInsert, '_useRulesToInsert');
  List<String>? __useRulesToInsert;

  @override
  void visitStylesheet(Stylesheet node) {
    var oldNamespaces = __existingNamespaces;
    var oldUseRules = __useRulesToInsert;
    var oldScope = currentScope;
    __existingNamespaces = {
      for (var rule in node.uses) rule.url: rule.namespace
    };
    __useRulesToInsert = [];
    currentScope = Scope();
    super.visitStylesheet(node);
    __existingNamespaces = oldNamespaces;
    __useRulesToInsert = oldUseRules;
    currentScope = oldScope;
  }

  /// Inserts [_useRulesToInsert] before the first existing dependency (or at
  /// the start of the stylesheet if none exist).
  @override
  void beforePatch(Stylesheet node) {
    if (_useRulesToInsert.isEmpty) return;
    var useRules = _useRulesToInsert.join('\n');
    var insertionPoint = node.span.start;
    for (var child in node.children) {
      if (child is LoudComment || child is SilentComment) continue;
      insertionPoint = child.span.start;
      break;
    }
    addPatch(Patch.insert(insertionPoint, '$useRules\n\n'));
  }

  /// Returns the prefix that should be used before a built-in from [module].
  ///
  /// This will usually be the namespace for [module] followed by a period, but
  /// will be an empty string if [module] is already used with no namespace.
  ///
  /// If [module] is not already used in this file, a new `@use` rule will be
  /// added to [_useRulesToInsert].
  String _builtInPrefix(String module) {
    var url = Uri.parse('sass:$module');
    if (_existingNamespaces.containsKey(url)) {
      return _existingNamespaces[url].andThen((ns) => '$ns.') ?? '';
    }
    Iterable<String> options() sync* {
      yield module;
      yield 'sass-$module';
      var i = 2;
      while (true) {
        yield '$module${i++}';
      }
    }

    var namespace = options()
        .firstWhere((option) => !_existingNamespaces.containsValue(option));
    _existingNamespaces[url] = namespace;
    var asClause = module == namespace ? '' : ' as $namespace';
    _useRulesToInsert.add('@use "sass:$module"$asClause$semicolon');
    return '$namespace.';
  }

  /// Allows division within this argument invocation.
  @override
  void visitArgumentInvocation(ArgumentInvocation invocation,
      {bool inCalcContext = false}) {
    _withContext(() => super.visitArgumentInvocation(invocation),
        isDivisionAllowed: true, inCalcContext: inCalcContext);
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
  /// for calc functions and new-syntax color functions.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (_tryColorFunction(node)) return;
    var validCalcs = _calcFunctions.difference(currentScope.allFunctionNames);
    visitArgumentInvocation(node.arguments,
        inCalcContext:
            node.namespace == null && validCalcs.contains(node.name));
  }

  /// Visits interpolation with [_isDivisionAllowed] and [_inCalcContext] set
  /// to false.
  @override
  void visitInterpolation(Interpolation node) {
    _withContext(() {
      super.visitInterpolation(node);
    }, isDivisionAllowed: false, inCalcContext: false);
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
  /// function call and [negated] is false, the now-unnecessary parentheses
  /// will be removed.
  @override
  void visitParenthesizedExpression(ParenthesizedExpression node,
      {bool negated = false}) {
    _withContext(() {
      if (node.expression
          case BinaryOperationExpression(operator: BinaryOperator.dividedBy) &&
              var expression) {
        if (_visitSlashOperation(expression) && !negated) {
          addPatch(patchDelete(node.span, end: 1));
          addPatch(patchDelete(node.span, start: node.span.length - 1));
        }
      } else {
        super.visitParenthesizedExpression(node);
      }
    }, isDivisionAllowed: true);
  }

  /// Sets [_negatedParenthesized] to true when about to visit a negated
  /// parenthesized expression.
  @override
  void visitUnaryOperationExpression(UnaryOperationExpression node) {
    if (node
        case UnaryOperationExpression(
          operator: UnaryOperator.minus,
          :ParenthesizedExpression operand
        )) {
      visitParenthesizedExpression(operand, negated: true);
      return;
    }
    super.visitUnaryOperationExpression(node);
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
    if (!["rgb", "rgba", "hsl", "hsla"].contains(node.name)) {
      return false;
    }

    var channels = switch (node.arguments) {
      ArgumentInvocation(positional: [ListExpression arg, ...], named: Map()) =>
        arg,
      ArgumentInvocation(
        positional: [],
        named: {r'$channels': ListExpression arg}
      ) =>
        arg,
      _ => null,
    };

    if (channels
        case ListExpression(
          hasBrackets: false,
          separator: ListSeparator.space,
          contents: [_, _, BinaryOperationExpression last]
        )) {
      // Handles cases like `rgb(10 20 30/2 / 0.5)`, since converting `30/2`
      // to `div(30, 20)` would cause `/ 0.5` to be interpreted as division.
      switch (last) {
        case BinaryOperationExpression(
            left: NumberExpression _,
            right: NumberExpression _
          ):
          break;
        default:
          _patchSpacesToCommas(channels);
          _patchOperatorToComma(last);
      }
      _withContext(() {
        // Non-null assertion is required because of dart-lang/language#1536.
        channels.contents[0].accept(this);
        channels.contents[1].accept(this);
        last.left.accept(this);
      }, isDivisionAllowed: true);
      last.right.accept(this);
      return true;
    }
    return false;
  }

  /// Visits a `/` operation [node] and migrates it to either the `division`
  /// function or the `slash-list` function.
  ///
  /// Returns true the `/` was migrated to either function call (indicating that
  /// parentheses surrounding this operation should be removed).
  bool _visitSlashOperation(BinaryOperationExpression node) {
    if (_inCalcContext) {
      node.left.accept(this);
      node.right.accept(this);
      return false;
    }
    var status = _NumberStatus.of(node);

    if ((!_isDivisionAllowed && _onlySlash(node)) ||
        status == _NumberStatus.no) {
      // Definitely not division
      if (_isDivisionAllowed || _containsInterpolation(node)) {
        // We only want to convert a non-division slash operation to a
        // slash-list call when it's in a non-plain-CSS context to avoid
        // unnecessary function calls within plain CSS.
        addPatch(patchBefore(node, "${_builtInPrefix('list')}slash("));
        addPatch(patchAfter(node, ")"));
        _visitSlashListArguments(node);
      }
      return true;
    }
    if (_expectsNumericResult ||
        status == _NumberStatus.yes ||
        !isPessimistic) {
      // Definitely division
      _withContext(() => super.visitBinaryOperationExpression(node),
          expectsNumericResult: true);
      if (_tryMultiplication(node)) return false;
      addPatch(patchBefore(node, "${_builtInPrefix('math')}div("));
      addPatch(patchAfter(node, ")"));
      _patchParensIfAny(node.left);
      _patchOperatorToComma(node);
      _patchParensIfAny(node.right);
      return true;
    } else {
      emitWarning("Could not determine whether this is division", node.span);
      super.visitBinaryOperationExpression(node);
      return false;
    }
  }

  /// Given a division operation [node], patches it to use multiplication
  /// instead if the reciprocal of the divisor can be accurately represented as
  /// a decimal.
  ///
  /// Returns true if patched and false otherwise.
  bool _tryMultiplication(BinaryOperationExpression node) {
    if (!useMultiplication) return false;
    if (node.right case NumberExpression(unit: null, value: var divisor)) {
      if (!_allowedDivisors.contains(divisor)) return false;
      var operatorSpan = node.left.span
          .extendThroughWhitespace()
          .end
          .pointSpan()
          .extendIfMatches('/');
      addPatch(Patch(operatorSpan, '*'));
      addPatch(Patch(node.right.span, '${1 / divisor}'));
      return true;
    }
    return false;
  }

  /// Visits the arguments of a `/` operation that is being converted into a
  /// call to `slash-list`, converting slashes to commas and removing
  /// unnecessary interpolation.
  void _visitSlashListArguments(Expression node) {
    switch (node) {
      case BinaryOperationExpression(operator: BinaryOperator.dividedBy):
        _visitSlashListArguments(node.left);
        _patchOperatorToComma(node);
        _visitSlashListArguments(node.right);
      case StringExpression(text: Interpolation(contents: [Expression item])):
        // Remove `#{` and `}`
        addPatch(patchDelete(node.span, end: 2));
        addPatch(patchDelete(node.span, start: node.span.length - 1));
        item.accept(this);
      default:
        node.accept(this);
    }
  }

  /// Returns true if we assume that [operator] always operators on numbers.
  ///
  /// This is true for `*`, `%`, `<`, `<=`, `>`, and `>=`.
  bool _operatesOnNumbers(BinaryOperator operator) => {
        BinaryOperator.times,
        BinaryOperator.modulo,
        BinaryOperator.lessThan,
        BinaryOperator.lessThanOrEquals,
        BinaryOperator.greaterThan,
        BinaryOperator.greaterThanOrEquals
      }.contains(operator);

  /// Returns true if [node] is entirely composed of number literals and slash
  /// operations.
  bool _onlySlash(Expression node) {
    switch (node) {
      case NumberExpression():
        return true;
      case BinaryOperationExpression(
          operator: BinaryOperator.dividedBy,
          :var left,
          :var right
        ):
        return _onlySlash(left) && _onlySlash(right);
      default:
        return false;
    }
  }

  /// Returns true if [node] contains an interpolation.
  bool _containsInterpolation(Expression node) {
    switch (node) {
      case ParenthesizedExpression(:var expression):
      case UnaryOperationExpression(operand: var expression):
        return _containsInterpolation(expression);
      case BinaryOperationExpression(:var left, :var right):
        return _containsInterpolation(left) || _containsInterpolation(right);
      case StringExpression(text: Interpolation(asPlain: null)):
        return true;
      default:
        return false;
    }
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
    if (node.expression
        case BinaryOperationExpression(operator: BinaryOperator.dividedBy)) {
      return;
    }
    addPatch(patchDelete(node.span, end: 1));
    addPatch(patchDelete(node.span, start: node.span.length - 1));
  }

  /// Runs [operation] with the given context.
  void _withContext(void operation(),
      {bool? isDivisionAllowed,
      bool? expectsNumericResult,
      bool? inCalcContext}) {
    var previousDivisionAllowed = _isDivisionAllowed;
    var previousNumericResult = _expectsNumericResult;
    var previousCalcContext = _inCalcContext;
    _isDivisionAllowed = isDivisionAllowed ?? _isDivisionAllowed;
    _expectsNumericResult = expectsNumericResult ?? _expectsNumericResult;
    _inCalcContext = inCalcContext ?? _inCalcContext;
    operation();
    _isDivisionAllowed = previousDivisionAllowed;
    _expectsNumericResult = previousNumericResult;
    _inCalcContext = previousCalcContext;
  }
}

/// Represents whether an expression is definitely a number, definitely not a
/// number, or unknown.
enum _NumberStatus {
  yes,
  no,
  maybe;

  /// Returns [yes] if [node] is definitely a number, [no] if [node] is
  /// definitely not a number, and [maybe] otherwise.
  static _NumberStatus of(Expression node) {
    switch (node) {
      case NumberExpression():
      case BinaryOperationExpression(
          operator: BinaryOperator.times || BinaryOperator.modulo
        ):
        return yes;
      case BooleanExpression():
      case ColorExpression():
      case ListExpression():
      case MapExpression():
      case NullExpression():
      case StringExpression():
        return no;
      case ParenthesizedExpression(:var expression):
      case UnaryOperationExpression(operand: var expression):
        return of(expression);
      case BinaryOperationExpression(:var left, :var right):
        return switch ((of(left), of(right))) {
          (yes, yes) => yes,
          (no, _) || (_, no) => no,
          _ => maybe
        };
      default:
        return maybe;
    }
  }
}
