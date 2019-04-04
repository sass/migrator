// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/syntax.dart';
import 'package:sass/src/visitor/recursive_ast.dart';

import 'package:path/path.dart' as p;

import 'migrator.dart';
import 'patch.dart';
import 'utils.dart';

/// A visitor that migrates a stylesheet.
///
/// When [run] is called, this visitor traverses a stylesheet's AST, allowing
/// subclasses to override one or more methods and add to [patches]. Once the
/// stylesheet has been visited, the migrated contents (based on [patches]) will
/// be stored in [migrator]'s [migrated] map.
///
/// If [migrateDependencies] is enabled, this visitor will construct and run a
/// new instance of itself (using [newInstance]) each time it encounters an
/// @import or @use rule.
abstract class MigrationVisitor extends RecursiveAstVisitor {
  /// The migrator running on this stylesheet.
  Migrator get migrator;

  /// The canonical path of the stylesheet being migrated.
  String get path;

  /// The stylesheet being migrated.
  Stylesheet stylesheet;

  /// The syntax this stylesheet uses.
  Syntax syntax;

  /// The patches to be applied to the stylesheet being migrated.
  final List<Patch> patches = [];

  /// Returns a new instance of this MigrationVisitor with the same migrator
  /// and [newPath].
  MigrationVisitor newInstance(String newPath);

  /// Runs the migrator and stores the migrated contents in `migrator.migrated`.
  void run() {
    var contents = File(path).readAsStringSync();
    syntax = Syntax.forPath(path);
    stylesheet = Stylesheet.parse(contents, syntax, url: path);
    visitStylesheet(stylesheet);
    var results = getMigratedContents();
    if (results != null) {
      migrator.migrated[path] = results;
    }
  }

  /// Returns the migrated contents of this file, or null if the file does not
  /// change.
  ///
  /// This will be called by [run] and the results will be stored in
  /// `migrator.migrated`.
  String getMigratedContents() => patches.isNotEmpty
      ? Patch.applyAll(patches.first.selection.file, patches)
      : null;

  /// Returns the canonical path of [url] when resolved relative to the current
  /// path.
  String resolveImportUrl(String url) =>
      canonicalizePath(p.join(p.dirname(path), url));

  /// If [migrator.migrateDependencies] is enabled, any dynamic imports within
  /// this [node] will be migrated before continuing.
  @override
  visitImportRule(ImportRule node) {
    super.visitImportRule(node);
    for (var import in node.imports) {
      if (import is DynamicImport) {
        if (migrator.migrateDependencies) {
          newInstance(resolveImportUrl(import.url)).run();
        }
      }
    }
  }

  /// If [migrator.migrateDependencies] is enabled, this dependency will be
  /// migrated before continuing.
  @override
  visitUseRule(UseRule node) {
    super.visitUseRule(node);
    if (migrator.migrateDependencies) {
      newInstance(resolveImportUrl(node.url.toString())).run();
    }
  }
}
