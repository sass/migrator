// Copyright 2018 Google LLC. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';

enum ApiType { variables, functions, mixins }

class StylesheetApi {
  final Stylesheet sheet;

  Map<String, VariableDeclaration> variables = {};

  Map<String, FunctionRule> functions = {};

  Map<String, MixinRule> mixins = {};

  StylesheetApi._(this.sheet);

  factory StylesheetApi(Stylesheet sheet) {
    var api = StylesheetApi._(sheet);
    for (var statement in sheet.children) {
      if (statement is VariableDeclaration) {
        api.variables[statement.name] = statement;
      } else if (statement is FunctionRule) {
        api.functions[statement.name] = statement;
      } else if (statement is MixinRule) {
        api.mixins[statement.name] = statement;
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
  }
}
