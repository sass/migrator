// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:collection';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/visitor/recursive_ast.dart';

import 'package:meta/meta.dart';

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
/// `@import` or `@use` rule.
abstract class MigrationVisitor extends RecursiveAstVisitor {
  /// The stylesheet being migrated.
  final Stylesheet stylesheet;

  /// A mapping from URLs to migrated contents for stylesheets already migrated.
  final Map<Uri, String> migrated;

  /// True if dependencies should be migrated as well.
  final bool migrateDependencies;

  /// The patches to be applied to the stylesheet being migrated.
  UnmodifiableListView<Patch> get patches => UnmodifiableListView(_patches);
  final List<Patch> _patches = [];

  /// Constructs a new migration visitor, parsing the stylesheet at [url].
  MigrationVisitor(Uri url, this.migrateDependencies,
      {Map<Uri, String> migrated})
      : stylesheet = parseStylesheet(url),
        this.migrated = migrated ?? {};

  /// Returns a new instance of this MigrationVisitor with the same [migrated]
  /// and [migrateDependencies] and the new [url].
  @protected
  MigrationVisitor newInstance(Uri url);

  /// Adds a new patch that should be applied as part of this migration.
  @protected
  void addPatch(Patch patch) {
    _patches.add(patch);
  }

  /// Runs the migrator and returns the map of migrated contents.
  Map<Uri, String> run() {
    visitStylesheet(stylesheet);
    var results = getMigratedContents();
    if (results != null) {
      migrated[stylesheet.span.file.url] = results;
    }
    return migrated;
  }

  /// Returns the migrated contents of this file, or null if the file does not
  /// change.
  ///
  /// This will be called by [run] and the results will be stored in
  /// `migrator.migrated`.
  @protected
  String getMigratedContents() => patches.isNotEmpty
      ? Patch.applyAll(patches.first.selection.file, patches)
      : null;

  /// Resolves [relativeUrl] relative to the current stylesheet's URL.
  @protected
  Uri resolveRelativeUrl(Uri relativeUrl) =>
      stylesheet.span.file.url.resolveUri(relativeUrl);

  /// If [migrateDependencies] is enabled, any dynamic imports within
  /// this [node] will be migrated before continuing.
  @override
  visitImportRule(ImportRule node) {
    super.visitImportRule(node);
    if (migrateDependencies) {
      for (var import in node.imports) {
        if (import is DynamicImport) {
          newInstance(resolveRelativeUrl(Uri.parse(import.url))).run();
        }
      }
    }
  }

  /// If [migrateDependencies] is enabled, this dependency will be
  /// migrated before continuing.
  @override
  visitUseRule(UseRule node) {
    super.visitUseRule(node);
    if (migrateDependencies) {
      newInstance(resolveRelativeUrl(node.url)).run();
    }
  }
}
