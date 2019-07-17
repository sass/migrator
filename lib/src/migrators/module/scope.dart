// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_migrator/src/utils.dart';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

/// Keeps track of the scope of any members declared at the current level of
/// the stylesheet.
class Scope {
  /// The parent of this scope, or null if this scope is global.
  final Scope parent;

  /// Variables defined in this scope.
  ///
  /// These are usually VariableDeclarations, but can also be Arguments from
  /// a CallableDeclaration.
  final variables = normalizedMap<SassNode /*VariableDeclaration|Argument*/ >();

  /// Mixins defined in this scope.
  final mixins = normalizedMap<MixinRule>();

  /// Functions defined in this scope.
  final functions = normalizedMap<FunctionRule>();

  /// Nested imports from this scope.
  ///
  /// Note: For the purposes of migration, any imports that come after a rule
  /// other than @import, @use, @forward, or @charset are considered nested, since
  /// they can't be migrated to @use.
  final nestedImports = <Uri>{};

  Scope(this.parent);

  /// The global scope this scope descends from.
  Scope get global => parent?.global ?? this;

  /// Returns whether a variable [name] exists in a non-global scope.
  bool isLocalVariable(String name) =>
      parent != null &&
      (variables.containsKey(name) || parent.isLocalVariable(name));

  /// Returns whether a mixin [name] exists in a non-global scope.
  bool isLocalMixin(String name) =>
      parent != null && (mixins.containsKey(name) || parent.isLocalMixin(name));

  /// Returns whether a function [name] exists in a non-global scope.
  bool isLocalFunction(String name) =>
      parent != null &&
      (functions.containsKey(name) || parent.isLocalFunction(name));

  /// Constructs and throws a MigrationException for a reference to a member
  /// from a nested import.
  void _errorNestedImport(String type, Uri importUrl, FileSpan reference) {
    throw MigrationException(
        "Can't reference $type from ${p.prettyUri(importUrl)}, "
        "as load-css() does not load ${type}s.",
        span: reference);
  }

  /// Checks that [node] does not reference a variable from a nested import,
  /// throwing a MigrationException if it does.
  void checkNestedImportVariable(VariableExpression node) {
    if (variables.containsKey(node.name)) {
      var url = variables[node.name].span.sourceUrl;
      if (nestedImports.contains(url)) {
        _errorNestedImport('variable', url, node.span);
      }
    } else {
      parent?.checkNestedImportVariable(node);
    }
  }

  /// Checks that [node] does not reference a mixin from a nested import,
  /// throwing a MigrationException if it does.
  void checkNestedImportMixin(IncludeRule node) {
    if (mixins.containsKey(node.name)) {
      var url = mixins[node.name].span.sourceUrl;
      if (nestedImports.contains(url)) {
        _errorNestedImport('mixin', url, node.span);
      }
    } else {
      parent?.checkNestedImportMixin(node);
    }
  }

  /// Checks that [node] does not reference a function from a nested import,
  /// throwing a MigrationException if it does.
  void checkNestedImportFunction(FunctionExpression node) {
    if (node.name.asPlain == null) return;
    if (functions.containsKey(node.name.asPlain)) {
      var url = functions[node.name.asPlain].span.sourceUrl;
      if (nestedImports.contains(url)) {
        _errorNestedImport('function', url, node.span);
      }
    } else {
      parent?.checkNestedImportFunction(node);
    }
  }

  /// Create a flattened version of this scope, combining all members from all
  /// ancestors into one level.
  ///
  /// This is used for migrating nested imports, allowing the migrator to treat
  /// local members from the upstream stylesheet as global ones while migrating
  /// the nested import.
  Scope flatten() {
    var flattened = Scope(null);
    var current = this;
    while (current != null) {
      flattened.insertFrom(current);
      current = current.parent;
    }
    return flattened;
  }

  /// Inserts all direct members of [other] into this scope, excluding any members
  /// that also existing in [excluding].
  void insertFrom(Scope other, {Scope excluding}) {
    insertFromMap<T>(Map<String, T> target, Map<String, T> source,
        Map<String, T> excluding) {
      for (var key in source.keys) {
        if (!excluding.containsKey(key)) target[key] = source[key];
      }
    }

    insertFromMap(this.variables, other.variables, excluding?.variables ?? {});
    insertFromMap(this.mixins, other.mixins, excluding?.mixins ?? {});
    insertFromMap(this.functions, other.functions, excluding?.functions ?? {});
  }
}
