// Copyright 2022 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';
import 'package:source_span/source_span.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';

/// Migrates deprecated `@media` query syntax to use interpolation.
class MediaLogicMigrator extends Migrator {
  final name = 'media-logic';
  final description = r'Migrates deprecated `@media` query syntax.\n'
      'See https://sass-lang.com/d/media-logic.';

  /// For each stylesheet URL, the set of relevant spans that require migration.
  final _expressionsToMigrate = <Uri, Set<FileSpan>>{};

  @override
  void handleDeprecation(String message, FileSpan? span) {
    if (span == null) return;
    if (!message.startsWith('Starting a @media query with ')) return;
    _expressionsToMigrate.putIfAbsent(span.sourceUrl!, () => {}).add(span);
  }

  @override
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer) {
    var visitor = _MediaLogicVisitor(
        importCache, migrateDependencies, _expressionsToMigrate);
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

class _MediaLogicVisitor extends MigrationVisitor {
  /// For each stylesheet URL, the set of relevant spans that require migration.
  final Map<Uri, Set<FileSpan>> _expressionsToMigrate;

  _MediaLogicVisitor(ImportCache importCache, bool migrateDependencies,
      this._expressionsToMigrate)
      : super(importCache, migrateDependencies);

  @override
  void beforePatch(Stylesheet node) {
    var expressions = _expressionsToMigrate[node.span.sourceUrl] ?? {};
    for (var expression in expressions) {
      addPatch(Patch.insert(expression.start, '#{'));
      addPatch(Patch.insert(expression.end, '}'));
    }
  }
}
