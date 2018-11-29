// Copyright 2018 Google LLC. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

import 'package:path/path.dart' as p;

import 'base_visitor.dart';
import 'patch.dart';
import 'stylesheet_api.dart';

/// A visitor that can migrate a stylesheet and its dependencies to the new
/// module system.
class Migrator extends BaseVisitor {
  /// Maps absolute file paths to migrated source code.
  final Map<Path, String> _migrated = {};

  /// Maps absolute file paths to the API of that stylesheet.
  final Map<Path, StylesheetApi> _apis = {};

  /// Stores a list of patches to be applied to each in-progress file.
  final Map<Path, List<Patch>> _patches = {};

  /// Stores a mapping of namespaces to file paths for each file.
  /// i.e Map<path, Map<namespace, path>>
  final Map<Path, Map<Namespace, Path>> _allNamespaces = {};

  /// Stack of files whose migration is in progress (last item is current).
  final List<Path> _migrationStack = [];

  /// The path of the file that is currently being migrated.
  Path get currentPath => _migrationStack.isEmpty ? null : _migrationStack.last;

  /// The parsed stylesheet for the file that is currently being migrated.
  Stylesheet get currentSheet => _apis[currentPath]?.sheet;

  /// The namespaces imported in the file that is currently being migrated
  Map<Namespace, Path> get namespaces => _allNamespaces[currentPath];

  /// Migrates [entrypoint] and all of its dependencies, returning a map from
  /// absolute file paths to the migrated contents of that file.
  ///
  /// This does not actually write any changes to disk.
  Map<String, String> runMigration(String entrypoint) =>
      runMigrations([entrypoint]);

  /// Migrates [entrypoints] and all of their dependencies, returning a map from
  /// absolute file paths to the migrated contents of that file.
  ///
  /// This does not actually write any changes to disk.
  Map<String, String> runMigrations(List<String> entrypoints) {
    _migrated.clear();
    _apis.clear();
    _patches.clear();
    _allNamespaces.clear();
    _migrationStack.clear();
    for (var entrypoint in entrypoints) {
      if (!migrate(resolvePath(entrypoint))) {
        print("Failure when migrating $entrypoint");
        return null;
      }
    }
    return _migrated.map((path, contents) => MapEntry(path.path, contents));
  }

  /// Migrates [path].
  ///
  /// This assumes that a migration has already been started. Use [runMigration]
  /// to start a new migration.
  bool migrate(Path path) {
    if (_apis.containsKey(path)) {
      log("Already migrated $path");
      return true;
    }
    var sheet = new Stylesheet.parseScss(loadFile(path), url: path.path);
    _migrationStack.add(path);
    _patches[path] = [];
    _allNamespaces[path] = {};
    _apis[path] = StylesheetApi(sheet);
    if (!visitStylesheet(sheet)) {
      log("FAILURE: Could not migrate $path");
      return false;
    }
    if (applyPatches(path)) {
      log("Successfully migrated $path");
    } else {
      log("Nothing to migrate in $path");
    }
    _patches.remove(path);
    _migrationStack.removeLast();
    // TODO(jathak): Eventually, it might make sense to update the sheet's API
    //   after migration, but we can't do that yet since @use won't parse.
    return true;
  }

  /// Applies all patches to the file at [path] and stores the patched contents
  /// in _migrated. Returns false if there are no patches to apply.
  bool applyPatches(Path path) {
    if (_patches[path].isEmpty) {
      return false;
    }
    var file = _patches[path].first.selection.file;
    _migrated[path] = Patch.applyAll(file, _patches[path]);
    return true;
  }

  /// Migrates an @import rule to @use, in the process migrating the imported
  /// file.
  @override
  bool visitImportRule(ImportRule importRule) {
    if (importRule.imports.length != 1) {
      log("Multiple imports in single rule not supported yet");
      return false;
    }
    if (importRule.imports.first is! DynamicImport) return true;
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
      return true;
    }
    var path = resolveImport(import.url);
    bool pass = migrate(path);
    namespaces[findNamespace(import.url)] = path;

    var overrides = potentialOverrides.where((declaration) =>
        _apis[path].variables.containsKey(declaration.name) &&
        _apis[path].variables[declaration.name].isGuarded);
    var config = overrides
        .map((decl) => "\$${decl.name}: ${decl.expression}")
        .join(",\n  ");
    if (config != "") config = " with (\n  $config\n)";
    _patches[currentPath]
        .add(Patch(importRule.span, '@use ${import.span.text}$config'));
    return pass;
  }

  /// Adds a namespace to a variable if it is necessary.
  @override
  bool visitVariableExpression(VariableExpression node) {
    var ns = findNamespaceFor(node.name, ApiType.variables);
    if (ns == null) {
      ns = makeImplicitDependencyExplicit(node.name, ApiType.variables);
      if (ns == null) return true;
    }
    // TODO(jathak): Confirm that this isn't a local variable before namespacing
    _patches[currentPath].add(Patch(node.span, "\$$ns.${node.name}"));
    return true;
  }

  /// Finds the namespace that corresponds to a given import URL.
  Namespace findNamespace(String importUrl) {
    return Namespace(importUrl.split('/').last.split('.').first);
  }

  /// Finds the absolute path for an import URL.
  Path resolveImport(String importUrl) {
    // TODO(jathak): Actually handle this robustly
    if (!importUrl.endsWith('.scss')) importUrl += '.scss';
    return resolvePath(importUrl);
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
    Namespace lastImplicitNamespace;
    Path lastImplicitPath;
    _dfs(Namespace namespace, Path path) {
      for (var ns in _allNamespaces[path].keys) {
        var nsPath = _allNamespaces[path][ns];
        _allNamespaces[nsPath].forEach(_dfs);
        var api = _apis[nsPath];
        if (api.namesOfType(type).contains(name)) {
          lastImplicitNamespace = ns;
          lastImplicitPath = nsPath;
        }
      }
    }

    namespaces.forEach(_dfs);
    if (lastImplicitPath != null) {
      var normalized = p.withoutExtension(
          p.relative(lastImplicitPath.path, from: p.dirname(currentPath.path)));
      _patches[currentPath].add(Patch.prepend('@use "$normalized";\n'));
      namespaces[lastImplicitNamespace] = lastImplicitPath;
    }
    return lastImplicitNamespace;
  }

  /// Resolves a relative path into an absolute path.
  Path resolvePath(String rawPath) => Path(File(rawPath).absolute.path);

  /// Loads the file at the given absolute path.
  String loadFile(Path path) => File(path.path).readAsStringSync();

  void log(String text) => print(text);
}

/// This only wraps a string to make the typing more explicit.
/// Do not use outside of the file and its tests.
class Namespace {
  final String namespace;
  const Namespace(this.namespace);
  toString() => namespace;
  int get hashCode => namespace.hashCode;
  operator ==(other) => namespace == other.namespace;
}

/// This only wraps a string to make the typing more explicit.
/// Do not use outside of the file and its tests.
class Path {
  final String path;
  const Path(this.path);
  toString() => path;
  int get hashCode => path.hashCode;
  operator ==(other) => path == other.path;
}
