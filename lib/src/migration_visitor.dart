// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:collection';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/importer.dart';
import 'package:sass/src/import_cache.dart';
import 'package:sass/src/visitor/recursive_ast.dart';

import 'exception.dart';
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
  @protected
  final bool migrateDependencies;

  /// Cache used to load stylesheets.
  @protected
  final ImportCache importCache;

  /// Map of missing dependency URLs to the spans that import/use them.
  Map<Uri, FileSpan> get missingDependencies =>
      UnmodifiableMapView(_missingDependencies);
  final _missingDependencies = <Uri, FileSpan>{};

  /// The patches to be applied to the stylesheet being migrated.
  @protected
  List<Patch> get patches => UnmodifiableListView(_patches);
  List<Patch> _patches;

  /// URL of the stylesheet currently being migrated.
  @protected
  Uri get currentUrl => _currentUrl;
  Uri _currentUrl;

  /// The importer that's being used to resolve relative imports.
  ///
  /// If this is `null`, relative imports aren't supported in the current
  /// stylesheet.
  @protected
  Importer get importer => _importer;
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
    beforePatch(node);
    var results = patches.isNotEmpty
        ? Patch.applyAll(patches.first.selection.file, patches)
        : null;
    if (results != null) {
      var existingResults = _migrated[_currentUrl];
      if (existingResults != null && existingResults != results) {
        throw MigrationException(
            "The migrator has found multiple possible migrations for "
            "${p.prettyUri(_currentUrl)}, depending on the context in which "
            "it's loaded.");
      }

      _migrated[_currentUrl] = results;
    }

    _patches = oldPatches;
    _currentUrl = oldUrl;
  }

  /// Called after visiting [node], but before patches are applied.
  ///
  /// A migrator should override this if it needs to add any additional patches
  /// after a stylesheet is visited.
  @protected
  void beforePatch(Stylesheet node) {}

  /// Visits the stylesheet at [dependency], resolved based on the current
  /// stylesheet's URL and importer.
  @protected
  void visitDependency(Uri dependency, FileSpan context,
      {bool forImport = false}) {
    var result = importCache.import(dependency,
        baseImporter: _importer, baseUrl: _currentUrl, forImport: forImport);
    if (result != null) {
      // If [dependency] comes from a non-relative import, don't migrate it,
      // because it's likely to be outside the user's repository and may even be
      // authored by a different person.
      //
      // TODO(nweiz): Add a flag to override this behavior for load paths
      // (#104).
      if (result.item1 != _importer) return;

      var oldImporter = _importer;
      _importer = result.item1;
      var stylesheet = result.item2;
      visitStylesheet(stylesheet);
      _importer = oldImporter;
    } else {
      _missingDependencies.putIfAbsent(
          context.sourceUrl.resolveUri(dependency), () => context);
    }
  }

  /// Adds a new patch that should be applied to the current stylesheet.
  ///
  /// If [beforeExisting] is true, this patch will be added to the beginning of
  /// the patch list. This should be used for insertion patches that should be
  /// inserted before any existing insertion patches at the same location.
  @protected
  void addPatch(Patch patch, {bool beforeExisting = false}) {
    if (beforeExisting) {
      _patches.insert(0, patch);
    } else {
      _patches.add(patch);
    }
  }

  /// If [migrateDependencies] is enabled, any dynamic imports within
  /// this [node] will be migrated before continuing.
  @override
  visitImportRule(ImportRule node) {
    super.visitImportRule(node);
    if (migrateDependencies) {
      for (var import in node.imports) {
        if (import is DynamicImport) {
          visitDependency(Uri.parse(import.url), import.span, forImport: true);
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
      visitDependency(node.url, node.span);
    }
  }
}
