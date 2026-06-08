// Copyright 2026 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';

import '../patch.dart';
import '../utils.dart';

/// Returns the source code of [node], patching any references to use the
/// namespace provided by [namespacer].
///
/// This is useful for copying/moving code from one while to another, changing
/// namespaces as necessary but avoiding changing whitespace and comments.
String copyNamespacedCode(
  SassNode node,
  String? Function(SassReference reference) namespacer,
) {
  var patches = _NamespacePatchingVisitor(namespacer).getPatchesFor(node);
  return Patch.applyAllToSpan(node.span, patches);
}

class _NamespacePatchingVisitor
    with RecursiveStatementVisitor, RecursiveAstVisitor {
  /// Called on every [SassReference] encountered, this should return the
  /// namespace that should be used for this reference, or null if the
  /// reference should be unnamespaced.
  final String? Function(SassReference reference) namespacer;

  late List<Patch> patches;

  _NamespacePatchingVisitor(this.namespacer);

  List<Patch> getPatchesFor(SassNode node) {
    patches = [];
    switch (node) {
      case Expression expression:
        expression.accept(this);
      case Statement statement:
        statement.accept(this);
      default:
        throw UnsupportedError('Expected Expression or Statement');
    }
    return patches;
  }

  @override
  void visitVariableExpression(VariableExpression node) {
    _patchNamespace(node);
    super.visitVariableExpression(node);
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _patchNamespace(node);
    super.visitFunctionExpression(node);
  }

  @override
  void visitIncludeRule(IncludeRule node) {
    _patchNamespace(node);
    super.visitIncludeRule(node);
  }

  void _patchNamespace(SassReference reference) {
    var namespace = namespacer(reference);
    if (namespace == reference.namespace) return;
    // Add new namespace
    if (namespace != null && reference.namespace == null) {
      patches.add(Patch.insert(reference.nameSpan.start, '$namespace.'));
      return;
    }
    // Remove existing namespace
    if (namespace == null && reference.namespace != null) {
      patches.add(
        Patch(reference.namespaceSpan!.extendIfMatches(RegExp(r'\s*\.')), ''),
      );
      return;
    }
    // Change existing namespace
    patches.add(Patch(reference.namespaceSpan!, namespace!));
  }
}
