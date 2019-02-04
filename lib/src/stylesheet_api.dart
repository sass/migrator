// Copyright 2018 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

enum ApiType { variables, functions, mixins }

/// A Sass module namespace.
class Namespace {
  final String namespace;
  const Namespace(this.namespace);
  toString() => namespace;
  int get hashCode => namespace.hashCode;
  operator ==(other) => namespace == other.namespace;
}

/// The canonical path for a Sass file.
class Path {
  final String path;
  const Path(this.path);
  toString() => path;
  int get hashCode => path.hashCode;
  operator ==(other) => path == other.path;
}

/// Takes a URL from an import rule and returns its canonical path.
typedef PathResolver = Path Function(String importUrl, {Path from});

/// Returns the contents of the file at [path].
typedef FileLoader = String Function(Path path);

// The API of a stylesheet, which consists of its variables, functions, mixins,
// and imported dependencies.
class StylesheetApi {
  final Stylesheet sheet;

  Map<String, VariableDeclaration> variables = {};

  Map<String, FunctionRule> functions = {};

  Map<String, MixinRule> mixins = {};

  Map<Path, StylesheetApi> imports = {};

  StylesheetApi._(this.sheet);

  factory StylesheetApi(Path path, PathResolver resolver, FileLoader loader,
      {Map<Path, StylesheetApi> existingApis}) {
    existingApis ??= {};
    if (existingApis.containsKey(path)) return existingApis[path];
    var sheet = Stylesheet.parseScss(loader(path));
    var api = StylesheetApi._(sheet);
    existingApis[path] = api;
    for (var statement in sheet.children) {
      if (statement is VariableDeclaration) {
        api.variables[statement.name] = statement;
      } else if (statement is FunctionRule) {
        api.functions[statement.name] = statement;
      } else if (statement is MixinRule) {
        api.mixins[statement.name] = statement;
      } else if (statement is ImportRule) {
        for (var import in statement.imports) {
          if (import is DynamicImport) {
            var importedPath = resolver(import.url, from: path);
            api.imports[importedPath] = StylesheetApi(
                importedPath, resolver, loader,
                existingApis: existingApis);
          }
        }
      }
    }
    // TODO(jathak): Handle !global variable declarations in other contexts
    // TODO(jathak): Handle @forward-ed declarations
    return api;
  }

  Iterable<String> namesOfType(ApiType type) {
    if (type == ApiType.variables) return variables.keys;
    if (type == ApiType.functions) return functions.keys;
    if (type == ApiType.mixins) return mixins.keys;
    return null;
  }
}
