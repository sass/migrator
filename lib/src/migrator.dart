// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'package:path/path.dart' as p;

import 'base_visitor.dart';
import 'built_in_functions.dart';
import 'patch.dart';
import 'stylesheet_api.dart';

/// A visitor that can migrate a stylesheet and its dependencies to the new
/// module system.
class Migrator extends BaseVisitor {
  /// Maps canonical file paths to migrated source code.
  final Map<Path, String> _migrated = {};

  /// Maps canonical file paths to the API of that stylesheet.
  final Map<Path, StylesheetApi> _apis = {};

  /// The path of the current file.
  Path currentPath;

  /// The parsed stylesheet for the current file.
  Stylesheet get currentSheet => _apis[currentPath]?.sheet;

  /// The namespaces imported in the current file.
  Map<Namespace, Path> namespaces;

  /// The patches that will be applied to the current file.
  List<Patch> patches;

  /// Built-in modules that have already been imported.
  Set<String> builtInModules;

  /// Files that still need to be migrated.
  List<Path> _migrationQueue = [];

  /// If true, stylesheets will be recursively migrated with their dependencies.
  bool _migrateDependencies;

  /// Migrates [entrypoints] (and optionally dependencies), returning a map from
  /// canonical file paths to the migrated contents of that file.
  ///
  /// This does not actually write any changes to disk.
  Map<String, String> runMigrations(List<String> entrypoints,
      {bool migrateDependencies}) {
    _migrateDependencies = migrateDependencies;
    _migrated.clear();
    _apis.clear();
    var paths = entrypoints.map(resolveImport);
    for (var path in paths) {
      StylesheetApi(path, resolveImport, loadFile, existingApis: _apis);
    }
    _migrationQueue.addAll(paths);
    while (_migrationQueue.isNotEmpty) {
      migrate(_migrationQueue.removeAt(0));
    }
    return _migrated.map((path, contents) => MapEntry(path.path, contents));
  }

  /// Migrates [entrypoint], returning its migrated contents
  ///
  /// This does not actually write any changes to disk.
  String runMigration(String entrypoint) => runMigrations([entrypoint],
      migrateDependencies: false)[p.join(entrypointDirectory, entrypoint)];

  /// Migrates [path].
  ///
  /// This assumes that a migration has already been started. Use [runMigration]
  /// to start a new migration.
  void migrate(Path path) {
    if (_migrated.containsKey(path)) return;
    namespaces = {};
    patches = [];
    builtInModules = Set();
    currentPath = path;
    visitStylesheet(currentSheet);
    applyPatches(path);
  }

  /// Applies all patches to the file at [path] and stores the patched contents
  /// in _migrated.
  applyPatches(Path path) {
    var file = _apis[path].sheet.span.file;
    _migrated[path] = Patch.applyAll(file, patches);
  }

  /// Migrates an @import rule to @use.
  @override
  void visitImportRule(ImportRule importRule) {
    super.visitImportRule(importRule);
    if (importRule.imports.length != 1) {
      throw Exception("Multiple imports in single rule not supported yet");
    }
    if (importRule.imports.first is! DynamicImport) return;
    var import = importRule.imports.first as DynamicImport;

    var potentialOverrides = <VariableDeclaration>[];
    var isTopLevel = false;
    for (var statement in currentSheet.children) {
      if (statement == importRule) {
        isTopLevel = true;
        break;
      }
      if (statement is VariableDeclaration) {
        potentialOverrides.add(statement);
      }
    }
    if (!isTopLevel) {
      // TODO(jathak): Handle nested imports
      return;
    }
    var path = resolveImport(import.url, from: currentPath);
    var importedSheetApi = _apis[path];
    namespaces[findNamespace(import.url)] = path;

    var overrides = potentialOverrides.where((declaration) =>
        importedSheetApi.variables.containsKey(declaration.name) &&
        importedSheetApi.variables[declaration.name].isGuarded);
    var config = overrides
        .map((decl) => "\$${decl.name}: ${decl.expression}")
        .join(",\n  ");
    if (config != "") config = " with (\n  $config\n)";
    patches.add(Patch(importRule.span, '@use ${import.span.text}$config'));

    if (_migrateDependencies) _migrationQueue.add(path);
  }

  /// Adds a namespace to a function call if it is necessary.
  @override
  void visitFunctionExpression(FunctionExpression node) {
    super.visitFunctionExpression(node);
    if (node.name.contents.length != 1 || node.name.contents.first is! String) {
      // This is a plain CSS invocation if it is interpolated, so there's no
      // need to namespace.
      return;
    }
    var name = node.name.asPlain;
    var ns = findNamespaceFor(name, ApiType.functions);
    if (ns == null) {
      ns = makeImplicitDependencyExplicit(name, ApiType.functions);
      if (ns == null) {
        if (_apis[currentPath].functions.containsKey(name)) return;
        if (builtInFunctionModules.containsKey(name)) {
          ns = Namespace(builtInFunctionModules[name]);
          if (builtInFunctionNameChanges.containsKey(name)) {
            name = builtInFunctionNameChanges[name];
          }
          if (!builtInModules.contains(ns.namespace)) {
            builtInModules.add(ns.namespace);
            patches.add(Patch.prepend('@use "sass:$ns";\n'));
          }
        }
      }
    }
    patches.add(Patch(node.name.span, "$ns.$name"));
  }

  /// Adds a namespace to a variable if it is necessary.
  @override
  void visitVariableExpression(VariableExpression node) {
    super.visitVariableExpression(node);
    if (_apis[currentPath].variables.containsKey(node.name)) return;
    if (isLocalVariable(node.name)) return;
    var ns = findNamespaceFor(node.name, ApiType.variables);
    if (ns == null) {
      ns = makeImplicitDependencyExplicit(node.name, ApiType.variables);
      if (ns == null) return;
    }
    patches.add(Patch(node.span, "\$$ns.${node.name}"));
  }

  /// Finds the namespace that corresponds to a given import URL.
  Namespace findNamespace(String importUrl) {
    return Namespace(importUrl.split('/').last.split('.').first);
  }

  /// Find the last namespace that contains a member [name] of [type].
  /// We return the last namespace here b/c a new import of the same member
  /// would override any previous ones.
  Namespace findNamespaceFor(String name, ApiType type) {
    Namespace lastValidNamespace;
    for (var ns in namespaces.keys) {
      var api = _apis[namespaces[ns]];
      if (api.namesOfType(type).contains(name)) lastValidNamespace = ns;
    }
    return lastValidNamespace;
  }

  /// Finds a transient import that contains a member [name] of [type] and
  /// makes it an explicit dependency so we can namespace [name].
  /// We use the last namespace here b/c a new import of the same member
  /// would override any previous ones.
  Namespace makeImplicitDependencyExplicit(String name, ApiType type) {
    Path lastImplicitPath;
    _dfs(Path path, StylesheetApi api) {
      api.imports.forEach(_dfs);
      if (api.namesOfType(type).contains(name)) {
        lastImplicitPath = path;
      }
    }

    _apis[currentPath].imports.forEach(_dfs);

    if (lastImplicitPath == null) return null;
    var normalized = p.withoutExtension(
        p.relative(lastImplicitPath.path, from: p.dirname(currentPath.path)));
    patches.add(Patch.prepend('@use "$normalized";\n'));
    var ns = findNamespace(lastImplicitPath.path);
    namespaces[ns] = lastImplicitPath;
    return ns;
  }

  /// Finds the canonical path for an import URL.
  Path resolveImport(String importUrl, {Path from}) {
    var absolutePath = importUrl;
    if (from != null && !p.isAbsolute(importUrl)) {
      absolutePath = p.join(p.dirname(from.path), importUrl);
    } else if (!p.isAbsolute(importUrl)) {
      absolutePath = p.join(entrypointDirectory, importUrl);
    }
    var result = _resolveRealPath(absolutePath);
    if (result == null) {
      throw Exception("Could not resolve $absolutePath");
    }
    return result;
  }

  Path _resolveRealPath(String absolutePath) {
    absolutePath = p.canonicalize(absolutePath);
    if (absolutePath.endsWith('.css')) {
      throw Exception("This should never happen $absolutePath");
    }
    if (absolutePath.endsWith('.scss') || absolutePath.endsWith('.sass')) {
      return _findPotentialPartials(absolutePath);
    } else {
      var sass = _findPotentialPartials(absolutePath + '.sass');
      var scss = _findPotentialPartials(absolutePath + '.scss');
      if (sass != null && scss != null) {
        throw Exception("$absolutePath exists as both .sass and .scss");
      }
      if (sass != null) return sass;
      if (scss != null) return scss;
      return _findPotentialPartials(absolutePath + '.css');
    }
  }

  Path _findPotentialPartials(String absolutePath) {
    var regular = Path(absolutePath);
    var partial =
        Path(p.join(p.dirname(absolutePath), '_' + p.basename(absolutePath)));
    var regularExists = exists(regular);
    var partialExists = exists(partial);
    if (regularExists && partialExists) {
      throw Exception("$regular and $partial both exist");
    }
    if (regularExists) return regular;
    if (partialExists) return partial;
    return null;
  }

  // Returns the absolute directory path the migrator is run from.
  String get entrypointDirectory => Directory.current.path;

  /// Returns whether or not a file at [path] exists.
  bool exists(Path path) => File(path.path).existsSync();

  /// Loads the file at the given canonical path.
  String loadFile(Path path) => File(path.path).readAsStringSync();

  void log(String text) => print(text);
}
