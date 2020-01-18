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
import 'package:sass/src/importer/utils.dart';
import 'package:sass/src/import_cache.dart';
import 'package:sass/src/stylesheet_graph.dart';

import 'package:args/args.dart';
import 'package:collection/collection.dart';
import 'package:path/path.dart' as p;
import 'package:source_span/source_span.dart';
import 'package:tuple/tuple.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';
import 'module/member_declaration.dart';
import 'module/references.dart';

class MdcIndexMigrator extends Migrator {
  final name = "mdc-index";
  final description = "Migrate MDC Web to index files.";

  /// Runs the module migrator on [stylesheet] and returns a map of migrated
  /// contents.
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer) {
    var references = References(importCache, stylesheet, importer);
    var visitor = _MdcIndexMigrationVisitor(importCache, references);
    return visitor.run(stylesheet, importer);
  }
}

class _MdcIndexMigrationVisitor extends MigrationVisitor {
  // First set: hidden variables; second set: hidden mixins/functions. Includes
  // prefixes.
  final _forwards = <Uri, Map<String, Tuple2<Set<String>, Set<String>>>>{};

  final References _references;

  _MdcIndexMigrationVisitor(ImportCache importCache, this._references)
      : super(importCache, migrateDependencies: false);

  Map<Uri, String> run(Stylesheet stylesheet, Importer importer) {
    super.run(stylesheet, importer);

    var buffer = StringBuffer();
    for (var url in _topologicalSortForwards()) {
      var prefixes = _forwards[url];
      var urlWithoutIndex = p.url.dirname(url.toString());

      var materialIndex = urlWithoutIndex.indexOf("@material/");
      var friendlyUrl = materialIndex == -1
          ? "./index"
          : urlWithoutIndex.substring(materialIndex);

      prefixes.forEach((prefix, hides) {
        var allHides = [
          for (var hide in hides.item1) "\$$hide",
          for (var hide in hides.item2) hide
        ];

        buffer.write('@forward "$friendlyUrl"');
        if (prefix != null) buffer.write(' as $prefix*');
        if (allHides.isNotEmpty) buffer.write(' hide ${allHides.join(', ')}');
        buffer.writeln(';');
      });
    }

    return {stylesheet.span.sourceUrl: buffer.toString()};
  }

  void visitForwardRule(ForwardRule node) {
    var moduleUrl = importCache
        .canonicalize(node.url, baseImporter: importer, baseUrl: currentUrl)
        .item2;
    var moduleMembers = _references.moduleMembers[moduleUrl].where((member) {
      var set = member.member is VariableDeclaration
          ? node.hiddenVariables
          : node.hiddenMixinsAndFunctions;
      return !(set ?? const {}).contains((node.prefix ?? '') + member.name);
    }).toSet();

    var indexUrl = importCache
        .canonicalize(node.url.replace(path: p.url.dirname(node.url.path)),
            baseImporter: importer, baseUrl: currentUrl)
        .item2;

    var existingForward =
        _forwards.putIfAbsent(indexUrl, () => {})[node.prefix];
    if (existingForward == null) {
      var indexMembers = _references.moduleMembers[indexUrl];
      if (indexMembers == null) {
        throw "${p.prettyUri(indexUrl)} doesn't exist!";
      }

      var hiddenVariables = node.hiddenVariables?.toSet() ?? {};
      var hiddenMixinsAndFunctions =
          node.hiddenMixinsAndFunctions?.toSet() ?? {};
      for (var member in indexMembers) {
        if (moduleMembers
            .any((moduleMember) => moduleMember.member == member.member)) {
          continue;
        }

        if (member.member is VariableDeclaration) {
          hiddenVariables.add((node.prefix ?? '') + member.name);
        } else {
          hiddenMixinsAndFunctions.add((node.prefix ?? '') + member.name);
        }
      }

      _forwards[indexUrl][node.prefix] =
          Tuple2(hiddenVariables, hiddenMixinsAndFunctions);
    } else {
      for (var member in moduleMembers) {
        if (member.member is VariableDeclaration) {
          existingForward.item1.remove((node.prefix ?? '') + member.name);
        } else {
          existingForward.item2.remove((node.prefix ?? '') + member.name);
        }
      }
    }
  }

  Iterable<Uri> _topologicalSortForwards() {
    var graph = StylesheetGraph(importCache);
    var sorted = <Uri>[];
    var visited = <StylesheetNode>{};

    void visit(StylesheetNode node) {
      if (node == null) return;
      if (!visited.add(node)) return;

      node.upstream.values.forEach(visit);
      visited.add(node);
      if (_forwards.containsKey(node.canonicalUrl)) {
        sorted.add(node.canonicalUrl);
      }
    }

    for (var url in _forwards.keys) {
      var node = graph.addCanonical(FilesystemImporter('.'), url);
      visit(node);
    }

    return sorted;
  }
}
