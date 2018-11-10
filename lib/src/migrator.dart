// Copyright 2018 Google LLC. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/visitor/interface/expression.dart';
import 'package:sass/src/visitor/interface/statement.dart';

import 'package:source_span/source_span.dart';

import 'base_visitor.dart';
import 'patch.dart';
import 'stylesheet_api.dart';

class Migrator extends BaseVisitor {
  /// Maps absolute file paths to migrated source code.
  final Map<String, String> migrated = {};

  /// Maps absolute file paths to the API of that stylesheet.
  final Map<String, StylesheetApi> _apis = {};

  /// Stores a list of patches to be applied to each in-progress file.
  final Map<String, List<Patch>> _patches = {};

  /// Stores a mapping of namespaces to file paths for each in-progress file.
  final Map<String, Map<String, String>> _allNamespaces = {};

  /// Stack of files whose migration is in progress (last item is current).
  final List<String> _migrationStack = [];

  FileLoader loader = (path) => File(path).readAsStringSync();
  AbsolutePathResolver pathResolver = (rawPath) => File(rawPath).absolute.path;

  String get currentPath =>
      _migrationStack.isEmpty ? null : _migrationStack.last;

  Map<String, String> get namespaces => _allNamespaces[currentPath];

  bool migrate(String path) {
    if (_apis.containsKey(path)) {
      print("Already migrated $path");
      return true;
    }
    var sheet = new Stylesheet.parseScss(loader(path), url: path);
    _migrationStack.add(path);
    _patches[path] = [];
    _allNamespaces[path] = {};
    _apis[path] = StylesheetApi(sheet);
    if (!visitStylesheet(sheet)) {
      print("FAILURE: Could not migrate $path");
      return false;
    }
    if (applyPatches(path)) {
      print("Successfully migrated $path");
    } else {
      print("Nothing to migrate in $path");
    }
    _patches.remove(path);
    _allNamespaces.remove(path);
    _migrationStack.removeLast();
    // TODO(jathak): Eventually, it might make sense to update the sheet's API
    //   after migration, but we can't do that yet since @use won't parse.
    return true;
  }

  bool applyPatches(String path) {
    if (_patches[path].isEmpty) {
      return false;
    }
    var file = _patches[path].first.selection.file;
    migrated[path] = Patch.applyAll(file, _patches[path]);
    return true;
  }

  @override
  bool visitImportRule(ImportRule importRule) {
    if (importRule.imports.length != 1) {
      print("Multiple imports in single rule not supported yet");
      return false;
    }
    var import = importRule.imports.first;
    if (import is DynamicImport) {
      var path = resolveImport(import.url);
      bool pass = migrate(path);
      if (!pass) return false;
      namespaces[findNamespace(import.url)] = path;
      _patches[currentPath]
          .add(Patch(importRule.span, '@use ${import.span.text};'));
    }
    return true;
  }

  @override
  bool visitVariableExpression(VariableExpression node) {
    var validNamespaces = resolveVariableNamespaces(node.name);
    if (validNamespaces.isEmpty) return true;
    // TODO(jathak): Give user a choice of namespaces
    var ns = validNamespaces.first;
    _patches[currentPath].add(Patch(node.span, "\$$ns.${node.name}"));
    return true;
  }

  String findNamespace(String importUrl) {
    return importUrl.split('/').last.split('.').last;
  }

  String resolveImport(String importUrl) {
    // TODO(jathak): Actually handle this robustly
    if (!importUrl.endsWith('.scss')) importUrl += '.scss';
    return pathResolver(importUrl);
  }

  List<String> resolveVariableNamespaces(String varName) {
    var validNamespaces = <String>[];
    for (var ns in namespaces.keys) {
      var api = _apis[namespaces[ns]];
      if (api.variables.containsKey(varName)) validNamespaces.add(ns);
    }
    return validNamespaces;
  }
}

typedef FileLoader = String Function(String path);
typedef AbsolutePathResolver = String Function(String rawPath);
