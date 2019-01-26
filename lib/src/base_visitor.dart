// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/visitor/interface/expression.dart';
import 'package:sass/src/visitor/interface/statement.dart';

/// Base class for [Migrator] that traverses the stylesheet to ensure the
/// code of the actual Migrator class is focused on migration.
abstract class BaseVisitor implements StatementVisitor, ExpressionVisitor {
  List<String> _localVarsInScope = [];
  List<int> _counts = [];

  void newScope() {
    _counts.add(0);
  }

  void addInNewScope(Iterable<String> names) {
    _counts.add(names.length);
    _localVarsInScope.addAll(names);
  }

  void addInScope(String name) {
    _counts.last += 1;
    _localVarsInScope.add(name);
  }

  void exitScope() {
    while (_counts.last > 0) {
      _localVarsInScope.removeLast();
      _counts.last--;
    }
  }

  bool isLocalVariable(String name) => _localVarsInScope.contains(name);

  @override
  void visitAtRootRule(AtRootRule node) {
    if (node.query != null) _visitInterpolation(node.query);
    _visitChildren(node);
  }

  @override
  void visitAtRule(AtRule node) {
    _notImplemented(node);
  }

  @override
  void visitBinaryOperationExpression(BinaryOperationExpression node) {
    node.left.accept(this);
    node.right.accept(this);
  }

  @override
  void visitBooleanExpression(BooleanExpression node) {}

  @override
  void visitColorExpression(ColorExpression node) {}

  @override
  void visitContentBlock(ContentBlock node) {
    _visitParametersAndScope(node.arguments);
    _visitChildren(node);
    exitScope();
  }

  @override
  void visitContentRule(ContentRule node) {
    _visitArguments(node.arguments);
  }

  @override
  void visitDebugRule(DebugRule node) {
    node.expression.accept(this);
  }

  @override
  void visitDeclaration(Declaration node) {
    _visitInterpolation(node.name);
    node.value.accept(this);
    _visitChildren(node);
  }

  @override
  void visitEachRule(EachRule node) {
    node.list.accept(this);
    addInNewScope(node.variables);
    _visitChildren(node);
    exitScope();
  }

  @override
  void visitErrorRule(ErrorRule node) {
    node.expression.accept(this);
  }

  @override
  void visitExtendRule(ExtendRule node) {
    _visitInterpolation(node.selector);
  }

  @override
  void visitForRule(ForRule node) {
    node.from.accept(this);
    node.to.accept(this);
    addInNewScope([node.variable]);
    _visitChildren(node);
    exitScope();
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _visitInterpolation(node.name);
    _visitArguments(node.arguments);
  }

  @override
  void visitFunctionRule(FunctionRule node) {
    _visitParametersAndScope(node.arguments);
    _visitChildren(node);
    exitScope();
  }

  @override
  void visitIfExpression(IfExpression node) {
    _visitArguments(node.arguments);
  }

  @override
  void visitIfRule(IfRule node) {
    for (var clause in node.clauses) {
      clause.expression.accept(this);
      newScope();
      for (var child in clause.children) {
        child.accept(this);
      }
      exitScope();
    }
    if (node.lastClause != null) {
      newScope();
      for (var child in node.lastClause.children) {
        child.accept(this);
      }
      exitScope();
    }
  }

  @override
  void visitImportRule(ImportRule node) {}

  @override
  void visitIncludeRule(IncludeRule node) {
    _visitArguments(node.arguments);
    node.content?.accept(this);
  }

  @override
  void visitListExpression(ListExpression node) {
    for (var value in node.contents) {
      value.accept(this);
    }
  }

  @override
  void visitLoudComment(LoudComment node) {
    _visitInterpolation(node.text);
  }

  @override
  void visitMapExpression(MapExpression node) {
    for (var pair in node.pairs) {
      pair.item1.accept(this);
      pair.item2.accept(this);
    }
  }

  @override
  void visitMediaRule(MediaRule node) {
    _visitInterpolation(node.query);
    newScope();
    _visitChildren(node);
    exitScope();
  }

  @override
  void visitMixinRule(MixinRule node) {
    _visitParametersAndScope(node.arguments);
    _visitChildren(node);
    exitScope();
  }

  @override
  void visitNullExpression(NullExpression node) {}

  @override
  void visitNumberExpression(NumberExpression node) {}

  @override
  void visitParenthesizedExpression(ParenthesizedExpression node) {
    node.expression.accept(this);
  }

  @override
  void visitReturnRule(ReturnRule node) {
    node.expression.accept(this);
  }

  @override
  void visitSelectorExpression(SelectorExpression node) {}

  @override
  void visitSilentComment(SilentComment node) {}

  @override
  void visitStringExpression(StringExpression node) {
    _visitInterpolation(node.asInterpolation());
  }

  @override
  void visitStyleRule(StyleRule node) {
    _visitInterpolation(node.selector);
    newScope();
    _visitChildren(node);
    exitScope();
  }

  @override
  void visitStylesheet(Stylesheet node) {
    _visitChildren(node);
  }

  @override
  void visitSupportsRule(SupportsRule node) {
    _notImplemented(node);
  }

  @override
  void visitUnaryOperationExpression(UnaryOperationExpression node) {
    node.operand.accept(this);
  }

  @override
  void visitValueExpression(ValueExpression node) {
    _notImplemented(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    node.expression.accept(this);
    if (_counts.isNotEmpty) addInScope(node.name);
  }

  @override
  void visitVariableExpression(VariableExpression node) {}

  @override
  void visitWarnRule(WarnRule node) {
    node.expression.accept(this);
  }

  @override
  void visitWhileRule(WhileRule node) {
    node.condition.accept(this);
    newScope();
    _visitChildren(node);
    exitScope();
  }

  void _notImplemented(SassNode node) {
    throw Exception("${node.runtimeType} not implemented");
  }

  void _visitParametersAndScope(ArgumentDeclaration args) {
    for (var arg in args.arguments) {
      arg.defaultValue?.accept(this);
    }
    addInNewScope(args.arguments.map((a) => a.name));
    addInScope(args.restArgument);
  }

  void _visitArguments(ArgumentInvocation args) {
    for (var expression in args.positional) {
      expression.accept(this);
    }
    for (var expression in args.named.values) {
      expression.accept(this);
    }
    args.rest?.accept(this);
    args.keywordRest?.accept(this);
  }

  void _visitChildren(ParentStatement node) {
    for (var child in node.children ?? []) {
      child.accept(this);
    }
  }

  void _visitInterpolation(Interpolation node) {
    for (var value in node.contents) {
      if (value is String) continue;
      (value as Expression).accept(this);
    }
  }
}
