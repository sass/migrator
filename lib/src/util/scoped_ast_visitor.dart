// Copyright 2024 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:meta/meta.dart';
import 'package:sass_api/sass_api.dart';

import 'member_declaration.dart';
import 'scope.dart';

class ScopedAstVisitor with RecursiveStatementVisitor, RecursiveAstVisitor {
  /// The current global scope.
  ///
  /// [ScopedAstVisitor] automatically handles creating child scopes within a
  /// single file.
  @protected
  var currentScope = Scope();

  @protected
  void onScopeClose() {}

  @protected
  void scoped(void Function() inScope) {
    var oldScope = currentScope;
    currentScope = Scope(currentScope);
    inScope();
    onScopeClose();
    currentScope = oldScope;
  }

  @override
  void visitStylesheet(Stylesheet node) {
    var oldScope = currentScope;
    currentScope = Scope();
    super.visitStylesheet(node);
    onScopeClose();
    currentScope = oldScope;
  }

  @override
  void visitCallableDeclaration(CallableDeclaration node) {
    for (var argument in node.arguments.arguments) {
      currentScope.variables[argument.name] = MemberDeclaration(argument);
      var defaultValue = argument.defaultValue;
      if (defaultValue != null) visitExpression(defaultValue);
    }
    super.visitChildren(node.children);
  }

  @override
  void visitChildren(List<Statement> children) {
    scoped(() {
      super.visitChildren(children);
    });
  }

  @override
  void visitFunctionRule(FunctionRule node) {
    currentScope.functions[node.name] = MemberDeclaration(node);
    scoped(() {
      super.visitFunctionRule(node);
    });
  }

  @override
  void visitMixinRule(MixinRule node) {
    currentScope.mixins[node.name] = MemberDeclaration(node);
    scoped(() {
      super.visitMixinRule(node);
    });
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    super.visitVariableDeclaration(node);
    var scope = switch (node) {
      VariableDeclaration(isGlobal: true) => currentScope.global,
      VariableDeclaration(namespace: null) => currentScope,
      _ => null
    };
    scope?.variables[node.name] = MemberDeclaration(node);
  }
}
