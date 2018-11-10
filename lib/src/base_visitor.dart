// Copyright 2018 Google LLC. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/visitor/interface/expression.dart';
import 'package:sass/src/visitor/interface/statement.dart';

/// Base class for [Migrator] that traverses the stylesheet to ensure the
/// code of the actual Migrator class is focused on migration.
abstract class BaseVisitor
    implements StatementVisitor<bool>, ExpressionVisitor<bool> {
  bool _notImplemented(SassNode node) {
    print("${node.runtimeType} not implemented");
    return false;
  }

  @override
  bool visitAtRootRule(AtRootRule node) {
    bool pass = node.query == null || _visitInterpolation(node.query);
    for (var child in node.children) {
      pass = child.accept(this) && pass;
    }
    return pass;
  }

  @override
  bool visitAtRule(AtRule node) {
    return _notImplemented(node);
  }

  @override
  bool visitBinaryOperationExpression(BinaryOperationExpression node) {
    bool passLeft = node.left.accept(this);
    bool passRight = node.right.accept(this);
    return passLeft && passRight;
  }

  @override
  bool visitBooleanExpression(BooleanExpression node) {
    return _notImplemented(node);
  }

  @override
  bool visitColorExpression(ColorExpression node) {
    return _notImplemented(node);
  }

  @override
  bool visitContentRule(ContentRule node) {
    return _notImplemented(node);
  }

  @override
  bool visitDebugRule(DebugRule node) {
    return node.expression.accept(this);
  }

  @override
  bool visitDeclaration(Declaration node) {
    // TODO(jathak): Visit and test children.
    bool passName = _visitInterpolation(node.name);
    bool passValue = node.value.accept(this);
    return passName && passValue;
  }

  @override
  bool visitEachRule(EachRule node) {
    bool pass = node.list.accept(this);
    for (var child in node.children) {
      pass = child.accept(this) && pass;
    }
    return pass;
  }

  @override
  bool visitErrorRule(ErrorRule node) {
    return node.expression.accept(this);
  }

  @override
  bool visitExtendRule(ExtendRule node) {
    return _visitInterpolation(node.selector);
  }

  @override
  bool visitForRule(ForRule node) {
    var pass = node.from.accept(this);
    pass = node.to.accept(this) && pass;
    for (var child in node.children) {
      pass = child.accept(this) && pass;
    }
    return pass;
  }

  @override
  bool visitFunctionExpression(FunctionExpression node) {
    return _notImplemented(node);
  }

  @override
  bool visitFunctionRule(FunctionRule node) {
    // TODO(jathak): visit and test `arguments`.
    bool pass = true;
    for (var child in node.children) {
      pass = child.accept(this) && pass;
    }
    return pass;
  }

  @override
  bool visitIfExpression(IfExpression node) {
    return _notImplemented(node);
  }

  @override
  bool visitIfRule(IfRule node) {
    var pass = true;
    for (var clause in node.clauses) {
      pass = clause.expression.accept(this) && pass;
      for (var child in clause.children) {
        pass = child.accept(this) && pass;
      }
    }
    if (node.lastClause != null) {
      for (var child in node.lastClause.children) {
        pass = child.accept(this) && pass;
      }
    }
    return pass;
  }

  @override
  bool visitImportRule(ImportRule node) {
    return _notImplemented(node);
  }

  @override
  bool visitIncludeRule(IncludeRule node) {
    return _notImplemented(node);
  }

  @override
  bool visitListExpression(ListExpression node) {
    var pass = true;
    for (var value in node.contents) {
      pass = value.accept(this) && pass;
    }
    return pass;
  }

  @override
  bool visitLoudComment(LoudComment node) {
    return _visitInterpolation(node.text);
  }

  @override
  bool visitMapExpression(MapExpression node) {
    bool pass = true;
    for (var pair in node.pairs) {
      pass = pair.item1.accept(this) && pass;
      pass = pair.item2.accept(this) && pass;
    }
    return pass;
  }

  @override
  bool visitMediaRule(MediaRule node) {
    return _notImplemented(node);
  }

  @override
  bool visitMixinRule(MixinRule node) {
    return _notImplemented(node);
  }

  @override
  bool visitNullExpression(NullExpression node) {
    return true;
  }

  @override
  bool visitNumberExpression(NumberExpression node) {
    return true;
  }

  @override
  bool visitParenthesizedExpression(ParenthesizedExpression node) {
    return node.expression.accept(this);
  }

  @override
  bool visitReturnRule(ReturnRule node) {
    return node.expression.accept(this);
  }

  @override
  bool visitSelectorExpression(SelectorExpression node) {
    return _notImplemented(node);
  }

  @override
  bool visitSilentComment(SilentComment node) {
    return true;
  }

  @override
  bool visitStringExpression(StringExpression node) {
    // TODO(jathak): visit and test `text`.
    return true;
  }

  @override
  bool visitStyleRule(StyleRule node) {
    bool pass = _visitInterpolation(node.selector);
    for (var child in node.children) {
      pass = child.accept(this) && pass;
    }
    return pass;
  }

  @override
  bool visitStylesheet(Stylesheet node) {
    var pass = true;
    for (var child in node.children) {
      pass = child.accept(this) && pass;
    }
    return pass;
  }

  @override
  bool visitSupportsRule(SupportsRule node) {
    return _notImplemented(node);
  }

  @override
  bool visitUnaryOperationExpression(UnaryOperationExpression node) {
    return _notImplemented(node);
  }

  @override
  bool visitValueExpression(ValueExpression node) {
    return _notImplemented(node);
  }

  @override
  bool visitVariableDeclaration(VariableDeclaration node) {
    return node.expression.accept(this);
  }

  @override
  bool visitVariableExpression(VariableExpression node) {
    return true;
  }

  @override
  bool visitWarnRule(WarnRule node) {
    return node.expression.accept(this);
  }

  @override
  bool visitWhileRule(WhileRule node) {
    return _notImplemented(node);
  }

  bool _visitInterpolation(Interpolation node) {
    var pass = true;
    for (var value in node.contents) {
      if (value is String) continue;
      pass = (value as Expression).accept(this) && pass;
    }
    return pass;
  }
}
