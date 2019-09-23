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
import 'package:sass/src/importer.dart';
import 'package:sass/src/import_cache.dart';
import 'package:sass/src/visitor/recursive_ast.dart';

import 'package:meta/meta.dart';
import 'package:source_span/source_span.dart';

import 'patch.dart';

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

  /// Cache used to load stylesheets.
  final ImportCache importCache;

  /// Map of missing dependency URLs to the spans that import/use them.
  Map<Uri, FileSpan> get missingDependencies =>
      UnmodifiableMapView(_missingDependencies);
  final _missingDependencies = <Uri, FileSpan>{};

  /// The patches to be applied to the stylesheet being migrated.
  List<Patch> get patches => UnmodifiableListView(_patches);
  List<Patch> _patches;

  /// URL of the stylesheet currently being migrated.
  Uri get currentUrl => _currentUrl;
  Uri _currentUrl;

  /// The importer that's currently being used to resolve relative imports.
  ///
  /// If this is `null`, relative imports aren't supported in the current
  /// stylesheet.
  Importer _importer;

  MigrationVisitor(this.importCache, {this.migrateDependencies = true});

  /// Runs a new migration on [stylesheet] (and its dependencies, if
  /// [migrateDependencies] is true) and returns a map of migrated contents.
  Map<Uri, String> run(Stylesheet stylesheet, Importer importer) {
    _importer = importer;
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
    var oldUrl = _currentUrl;
    _patches = [];
    _currentUrl = node.span.sourceUrl;
    super.visitStylesheet(node);
    var results = getMigratedContents();
    if (results != null) {
      _migrated[node.span.sourceUrl] = results;
    }
    _patches = oldPatches;
    _currentUrl = oldUrl;
  }

  @override
  void visitAtRootRule(AtRootRule node) {
    if (node.query != null) visitInterpolation(node.query);
    visitChildren(node);
  }

  /// Visits the stylesheet at [dependency], resolved based on the current
  /// stylesheet's URL and importer.
  @protected
  void visitDependency(Uri dependency, FileSpan context) {
    var result = importCache.import(dependency, _importer, _currentUrl);
    if (result != null) {
      _importer = result.item1;
      var stylesheet = result.item2;
      visitStylesheet(stylesheet);
    } else {
      handleMissingDependency(dependency, context);
    }
  }

  /// Adds the missing [dependency] within the stylesheet at [source] to the
  /// missing dependency list to warn after migration completes.
  ///
  /// Migrators should override this if they want a different behavior.
  @protected
  void handleMissingDependency(Uri dependency, FileSpan context) {
    _missingDependencies.putIfAbsent(
        context.sourceUrl.resolveUri(dependency), () => context);
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
          visitDependency(Uri.parse(import.url), import.span);
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
      if (node.url.scheme == 'sass') return;
      visitDependency(node.url, node.span);
    }
  }
}
