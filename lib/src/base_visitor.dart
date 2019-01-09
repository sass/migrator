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
    _notImplemented(node);
  }

  @override
  void visitContentRule(ContentRule node) {
    _notImplemented(node);
  }

  @override
  void visitDebugRule(DebugRule node) {
    node.expression.accept(this);
  }

  @override
  void visitDeclaration(Declaration node) {
    // TODO(jathak): Visit and test children.
    _visitInterpolation(node.name);
    node.value.accept(this);
  }

  @override
  void visitEachRule(EachRule node) {
    node.list.accept(this);
    _visitChildren(node);
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
    _visitChildren(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _notImplemented(node);
  }

  @override
  void visitFunctionRule(FunctionRule node) {
    // TODO(jathak): visit and test `arguments`.
    _visitChildren(node);
  }

  @override
  void visitIfExpression(IfExpression node) {
    _notImplemented(node);
  }

  @override
  void visitIfRule(IfRule node) {
    for (var clause in node.clauses) {
      clause.expression.accept(this);
      for (var child in clause.children) {
        child.accept(this);
      }
    }
    if (node.lastClause != null) {
      for (var child in node.lastClause.children) {
        child.accept(this);
      }
    }
  }

  @override
  void visitImportRule(ImportRule node) {
    _notImplemented(node);
  }

  @override
  void visitIncludeRule(IncludeRule node) {
    _notImplemented(node);
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
    _notImplemented(node);
  }

  @override
  void visitMixinRule(MixinRule node) {
    _notImplemented(node);
  }

  @override
  void visitNullExpression(NullExpression node) {}

  @override
  void visitNumberExpression(NumberExpression node) {}

  @override
  void visitParenthesizedExpression(ParenthesizedExpression node) {
    return node.expression.accept(this);
  }

  @override
  void visitReturnRule(ReturnRule node) {
    return node.expression.accept(this);
  }

  @override
  void visitSelectorExpression(SelectorExpression node) {
    _notImplemented(node);
  }

  @override
  void visitSilentComment(SilentComment node) {}

  @override
  void visitStringExpression(StringExpression node) {
    // TODO(jathak): visit and test `text`.
  }

  @override
  void visitStyleRule(StyleRule node) {
    _visitInterpolation(node.selector);
    _visitChildren(node);
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
    _notImplemented(node);
  }

  @override
  void visitValueExpression(ValueExpression node) {
    _notImplemented(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    node.expression.accept(this);
  }

  @override
  void visitVariableExpression(VariableExpression node) {}

  @override
  void visitWarnRule(WarnRule node) {
    node.expression.accept(this);
  }

  @override
  void visitWhileRule(WhileRule node) {
    _notImplemented(node);
  }

  void _notImplemented(SassNode node) {
    throw Exception("${node.runtimeType} not implemented");
  }

  void _visitChildren(ParentStatement node) {
    for (var child in node.children) {
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
