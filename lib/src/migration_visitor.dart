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
import 'package:source_span/source_span.dart';

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
  /// A mapping from URLs to migrated contents for stylesheets already migrated.
  final _migrated = <Uri, String>{};

  /// True if dependencies should be migrated as well.
  final bool migrateDependencies;

  /// Map of missing dependency URLs to the spans that import/use them.
  Map<Uri, FileSpan> get missingDependencies =>
      UnmodifiableMapView(_missingDependencies);
  final _missingDependencies = <Uri, FileSpan>{};

  /// The patches to be applied to the stylesheet being migrated.
  List<Patch> get patches => UnmodifiableListView(_patches);
  List<Patch> _patches;

  MigrationVisitor({this.migrateDependencies = true});

  /// Runs a new migration on [url] (and its dependencies, if
  /// [migrateDependencies] is true) and returns a map of migrated contents.
  Map<Uri, String> run(Uri url) => runWithStylesheet(parseStylesheet(url));

  /// Runs a new migration of [stylesheet] (and its dependencies, if
  /// [migrateDependencies] is true) and returns a map of migrated contents.
  Map<Uri, String> runWithStylesheet(Stylesheet stylesheet) {
    visitStylesheet(stylesheet);
    return _migrated;
  }

  /// Visits stylesheet starting with an empty [_patches], adds the migrated
  /// contents (if any) to [_migrated], and then restores the previous value of
  /// [_patches].
  ///
  /// Migrators with per-file state should override this to store the current
  /// file's state before calling the super method and restore it afterwards.
  @override
  void visitStylesheet(Stylesheet node) {
    var oldPatches = _patches;
    _patches = [];
    super.visitStylesheet(node);
    var results = getMigratedContents();
    if (results != null) {
      _migrated[node.span.sourceUrl] = results;
    }
    _patches = oldPatches;
  }

  /// Visits the stylesheet at [dependency], resolved relative to [source].
  @protected
  void visitDependency(Uri dependency, Uri source, [FileSpan context]) {
    var url = source.resolveUri(dependency);
    var stylesheet = parseStylesheet(url);
    if (stylesheet != null) {
      visitStylesheet(stylesheet);
    } else {
      _missingDependencies.putIfAbsent(url, () => context);
    }
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

  /// Adds a new patch that should be applied to the current stylesheet.
  @protected
  void addPatch(Patch patch) {
    _patches.add(patch);
  }

  /// If [migrateDependencies] is enabled, any dynamic imports within
  /// this [node] will be migrated before continuing.
  @override
  visitImportRule(ImportRule node) {
    super.visitImportRule(node);
    if (migrateDependencies) {
      for (var import in node.imports) {
        if (import is DynamicImport) {
          visitDependency(
              Uri.parse(import.url), node.span.sourceUrl, import.span);
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
      visitDependency(node.url, node.span.sourceUrl, node.span);
    }
  }
}
