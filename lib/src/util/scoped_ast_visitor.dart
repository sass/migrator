// Copyright 2024 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:meta/meta.dart';
import 'package:sass_api/sass_api.dart';

import 'member_declaration.dart';
import 'scope.dart';

/// A recursive AST visitor that tracks the Sass members declared in the
/// current scope.
abstract class ScopedAstVisitor
    with RecursiveStatementVisitor, RecursiveAstVisitor {
  /// The current scope, containing any visible without a namespace to the
  /// current point in the AST.
  ///
  /// Subclasses that visit multiple modules should update this when changing
  /// the module being visited.
  @protected
  var currentScope = Scope();

  /// A callback called when the visitor closes a local scope.
  ///
  /// Subclasses should override this if they need to do something with the
  /// current local scope before it is closed.
  @protected
  void onScopeClose() {}

  /// Evaluates [inScope] in a new child scope of the current scope.
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
    visitChildren(node.children, withScope: false);
  }

  /// Visits each child in [children] sequentially.
  ///
  /// When [withScope] is true, the children will be visited with a shared
  /// local scope.
  @override
  void visitChildren(List<Statement> children, {bool withScope = true}) {
    visit() {
      super.visitChildren(children);
    }

    return withScope ? scoped(visit) : visit();
  }

  /// Creates a new child scope, declares [node]'s arguments within it and
  /// then visits [node]'s children.
  @override
  void visitCallableDeclaration(CallableDeclaration node) {
    scoped(() {
      for (var argument in node.arguments.arguments) {
        currentScope.variables[argument.name] = MemberDeclaration(argument);
        var defaultValue = argument.defaultValue;
        if (defaultValue != null) visitExpression(defaultValue);
      }
      visitChildren(node.children, withScope: false);
    });
  }

  /// Adds [node] to the current scope and then visits it.
  @override
  void visitFunctionRule(FunctionRule node) {
    currentScope.functions[node.name] = MemberDeclaration(node);
    super.visitFunctionRule(node);
  }

  /// Adds [node] to the current scope and then visits it.
  @override
  void visitMixinRule(MixinRule node) {
    currentScope.mixins[node.name] = MemberDeclaration(node);
    super.visitMixinRule(node);
  }

  /// Visits [node] and then adds it to the current or the global scope.
  ///
  /// If [node] is namespaced, no scope will be updated.
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
