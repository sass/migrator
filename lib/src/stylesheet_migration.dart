// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:path/path.dart' as p;

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/syntax.dart';

import 'local_scope.dart';
import 'patch.dart';
import 'utils.dart';

/// Represents an in-progress migration for a stylesheet.
class StylesheetMigration {
  /// The stylesheet this migration is for.
  final Stylesheet stylesheet;

  /// The canonical path of this stylesheet.
  final String path;

  /// The original contents of this stylesheet, prior to migration.
  final String contents;

  /// The syntax used in this stylesheet.
  final Syntax syntax;

  /// Namespaces of modules used in this stylesheet.
  final p.PathMap<String> namespaces = p.PathMap();

  /// List of additional use rules necessary for referencing members of
  /// implicit dependencies / built-in modules.
  ///
  /// This list contains the path provided in the use rule, not the canonical
  /// path (e.g. "a" rather than "dir/a.scss").
  final List<String> additionalUseRules = [];

  /// List of patches to be applied to this file.
  final List<Patch> patches = [];

  /// Global variables in this stylesheet and its dependencies.
  final Map<String, VariableDeclaration> variables = normalizedMap();

  /// Global variables declared with !default that could be configured.
  final Set<String> configurableVariables = normalizedSet();

  /// Global mixins in this stylesheet and its dependencies.
  final Map<String, MixinRule> mixins = normalizedMap();

  /// Global functions in this stylesheet and its dependencies.
  final Map<String, FunctionRule> functions = normalizedMap();

  /// Local variables, mixins, and functions for migrations in progress.
  ///
  /// The migrator will modify this as it traverses the stylesheet. When at the
  /// top-level of the stylesheet, this will be null.
  LocalScope localScope;

  StylesheetMigration._(this.stylesheet, this.path, this.contents, this.syntax);

  /// Creates a new migration for the stylesheet at [path].
  factory StylesheetMigration(String path) {
    var contents = File(path).readAsStringSync();
    var syntax = Syntax.forPath(path);
    var stylesheet = Stylesheet.parse(contents, syntax, url: path);
    return StylesheetMigration._(stylesheet, path, contents, syntax);
  }

  /// Returns the migrated contents of this file, based on [additionalUseRules]
  /// and [patches].
  String get migratedContents {
    var semicolon = syntax == Syntax.sass ? "" : ";";
    var uses = additionalUseRules.map((use) => '@use "$use"$semicolon\n');
    var contents = Patch.applyAll(stylesheet.span.file, patches);
    return uses.join("") + contents;
  }

  /// Declares a variable within this stylesheet, in the current local scope if
  /// it exists, or as a global variable otherwise.
  void declareVariable(VariableDeclaration node) {
    if (localScope == null || node.isGlobal) {
      variables[node.name] = node;
      if (node.isGuarded) configurableVariables.add(node.name);
    } else {
      localScope.variables.add(node.name);
    }
  }

  /// Declares a mixin within this stylesheet, in the current local scope if
  /// it exists, or as a global mixin otherwise.
  void declareMixin(MixinRule node) {
    if (localScope == null) {
      mixins[node.name] = node;
    } else {
      localScope.mixins.add(node.name);
    }
  }

  /// Declares a function within this stylesheet, in the current local scope if
  /// it exists, or as a global function otherwise.
  void declareFunction(FunctionRule node) {
    if (localScope == null) {
      functions[node.name] = node;
    } else {
      localScope.functions.add(node.name);
    }
  }

  /// Finds the namespace for the stylesheet containing [node], adding a new use
  /// rule if necessary.
  String namespaceForNode(SassNode node) {
    var nodePath = node.span.sourceUrl.path;
    if (p.equals(nodePath, path)) return null;
    if (!namespaces.containsKey(nodePath)) {
      /// Add new use rule for indirect dependency
      var relativePath = p.relative(nodePath, from: p.dirname(path));
      var basename = p.basenameWithoutExtension(relativePath);
      if (basename.startsWith('_')) basename = basename.substring(1);
      var simplePath = p.relative(p.join(p.dirname(relativePath), basename));
      additionalUseRules.add(simplePath);
      namespaces[nodePath] = namespaceForPath(nodePath);
    }
    return namespaces[nodePath];
  }
}
