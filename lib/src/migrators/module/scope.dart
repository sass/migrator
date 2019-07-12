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

/// Keeps track of the scope of any members declared at the current level of
/// the stylesheet.
class Scope {
  /// The parent of this scope, or null if this scope is global.
  final Scope parent;

  /// Variables defined in this scope.
  final variables = normalizedMap<VariableDeclaration>();

  /// Mixins defined in this scope.
  final mixins = normalizedMap<MixinRule>();

  /// Functions defined in this scope.
  final functions = normalizedMap<FunctionRule>();

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
