// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:io';

import 'package:path/path.dart' as p;

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/syntax.dart';

import 'patch.dart';
import 'utils.dart';

/// Represents an in-progress migration for a stylesheet.
class StylesheetMigration {
  /// The stylesheet this migration is for.
  final Stylesheet stylesheet;

  /// The canonical path of this stylesheet.
  final String path;

  /// The original contents of this stylesheet, prior to migration.
  final String contents;

  /// The syntax used in this stylesheet.
  final Syntax syntax;

  /// Namespaces of modules used in this stylesheet.
  final namespaces = p.PathMap<String>();

  /// Set of additional use rules necessary for referencing members of
  /// implicit dependencies / built-in modules.
  ///
  /// This set contains the path provided in the use rule, not the canonical
  /// path (e.g. "a" rather than "dir/a.scss").
  final additionalUseRules = Set<String>();

  /// List of patches to be applied to this file.
  final patches = <Patch>[];

  /// Global variables declared with !default that could be configured.
  final configurableVariables = normalizedSet();

  StylesheetMigration._(this.stylesheet, this.path, this.contents, this.syntax);

  /// Creates a new migration for the stylesheet at [path].
  factory StylesheetMigration(String path) {
    var contents = File(path).readAsStringSync();
    var syntax = Syntax.forPath(path);
    var stylesheet = Stylesheet.parse(contents, syntax, url: path);
    return StylesheetMigration._(stylesheet, path, contents, syntax);
  }

  /// Returns the migrated contents of this file, based on [additionalUseRules]
  /// and [patches].
  String get migratedContents {
    var semicolon = syntax == Syntax.sass ? "" : ";";
    var uses = additionalUseRules.map((use) => '@use "$use"$semicolon\n');
    var contents = Patch.applyAll(stylesheet.span.file, patches);
    return uses.join("") + contents;
  }

  /// Finds the namespace for the stylesheet containing [node], adding a new use
  /// rule if necessary.
  String namespaceForNode(SassNode node) {
    var nodePath = p.fromUri(node.span.sourceUrl);
    if (p.equals(nodePath, path)) return null;
    if (!namespaces.containsKey(nodePath)) {
      /// Add new use rule for indirect dependency
      var relativePath = p.relative(nodePath, from: p.dirname(path));
      var basename = p.basenameWithoutExtension(relativePath);
      if (basename.startsWith('_')) basename = basename.substring(1);
      var simplePath = p.relative(p.join(p.dirname(relativePath), basename));
      additionalUseRules.add(simplePath);
      namespaces[nodePath] = namespaceForPath(nodePath);
    }
    return namespaces[nodePath];
  }
}
