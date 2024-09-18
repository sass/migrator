// Copyright 2024 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';
import 'package:sass_migrator/src/migrators/module/reference_source.dart';

import 'module/references.dart';
import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';
import '../utils.dart';

/// Migrates off of legacy color functions.
class ColorMigrator extends Migrator {
  final name = "color";
  final description = "Migrates off of legacy color functions.";

  @override
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer) {
    var references = References(importCache, stylesheet, importer);
    var visitor =
        _ColorMigrationVisitor(references, importCache, migrateDependencies);
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

final _colorUrl = Uri(scheme: 'sass', path: 'color');

class _ColorMigrationVisitor extends MigrationVisitor {
  final References references;

  _ColorMigrationVisitor(
      this.references, super.importCache, super.migrateDependencies);

  String? _colorModuleNamespace;
  Set<String> _usedNamespaces = {};

  @override
  void visitStylesheet(Stylesheet node) {
    var oldColorModuleNamespace = _colorModuleNamespace;
    var oldUsedNamespaces = _usedNamespaces;
    _colorModuleNamespace = null;
    _usedNamespaces = {};
    // Check all the namespaces used by this file before visiting the
    // stylesheet, in case deprecated functions are called before all `@use`
    // rules.
    for (var useRule in node.uses) {
      if (_colorModuleNamespace != null || useRule.namespace == null) continue;
      if (useRule.url == _colorUrl) {
        _colorModuleNamespace = useRule.namespace;
      } else {
        _usedNamespaces.add(useRule.namespace!);
      }
    }
    super.visitStylesheet(node);
    _colorModuleNamespace = oldColorModuleNamespace;
    _usedNamespaces = oldUsedNamespaces;
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    var source = references.sources[node];
    if (source is! BuiltInSource || source.url != _colorUrl) return;
    var isMigrating = true;
    switch (node.name) {
      case 'red' || 'green' || 'blue':
        _patchChannel(node, 'rgb');
      case 'hue' || 'saturation' || 'lightness':
        _patchChannel(node, 'hsl');
      case 'whiteness' || 'blackness':
        _patchChannel(node, 'hwb');
      case 'alpha':
        _patchChannel(node);
      case 'adjust-hue':
        _patchAdjust(node, channel: 'hue', space: 'hsl');
      case 'saturate'
          when node.arguments.named.length + node.arguments.positional.length !=
              1:
        _patchAdjust(node, channel: 'saturation', space: 'hsl');
      case 'desaturate':
        _patchAdjust(node, channel: 'saturation', negate: true, space: 'hsl');
      case 'transparentize' || 'fade-out':
        _patchAdjust(node, channel: 'alpha', negate: true);
      case 'opacify' || 'fade-in':
        _patchAdjust(node, channel: 'alpha');
      case 'lighten':
        _patchAdjust(node, channel: 'lightness', space: 'hsl');
      case 'darken':
        _patchAdjust(node, channel: 'lightness', negate: true, space: 'hsl');
      default:
        isMigrating == false;
    }
    if (isMigrating && node.namespace == null) {
      if (_colorModuleNamespace == null) {
        _colorModuleNamespace = _findColorModuleNamespace();
        var asClause = _colorModuleNamespace == 'color'
            ? ''
            : ' as $_colorModuleNamespace';
        addPatch(Patch.insert(
            node.span.file.location(0), '@use "sass:color"$asClause;\n\n'));
      }
      addPatch(patchBefore(node, '$_colorModuleNamespace.'),
          beforeExisting: true);
    }
  }

  /// Find an unused namespace for the sass:color module.
  String _findColorModuleNamespace() {
    if (!_usedNamespaces.contains('color')) return 'color';
    if (!_usedNamespaces.contains('sass-color')) return 'sass-color';
    var count = 2;
    var namespace = 'color$count';
    while (_usedNamespaces.contains(namespace)) {
      namespace = 'color${++count}';
    }
    return namespace;
  }

  /// Patches a deprecated channel function to use `color.channel` instead.
  void _patchChannel(FunctionExpression node, [String? colorSpace]) {
    addPatch(Patch(node.nameSpan, 'channel'));

    if (node.arguments.named.isEmpty) {
      addPatch(patchAfter(node.arguments.positional.last,
          ", '${node.name}'${colorSpace == null ? '' : ', $colorSpace'}"));
    } else {
      addPatch(patchAfter(
          [...node.arguments.positional, ...node.arguments.named.values].last,
          ", \$channel: '${node.name}'"
          "${colorSpace == null ? '' : ', \$space: $colorSpace'}"));
    }
  }

  /// Patches a deprecated adjustment function to use `color.adjust` instead.
  void _patchAdjust(FunctionExpression node,
      {required String channel, bool negate = false, String? space}) {
    addPatch(Patch(node.nameSpan, 'adjust'));
    switch (node.arguments) {
      case ArgumentInvocation(positional: [_, var adjustment]):
        addPatch(patchBefore(adjustment, '\$$channel: ${negate ? '-' : ''}'));
        if (negate && adjustment.needsParens) {
          addPatch(patchBefore(adjustment, '('));
          addPatch(patchAfter(adjustment, ')'));
        }
        if (space != null) {
          addPatch(patchAfter(adjustment, ', \$space: $space'));
        }
      case ArgumentInvocation(
          named: {'amount': var adjustment} || {'degrees': var adjustment}
        ):
        var start = adjustment.span.start.offset - 1;
        while (adjustment.span.file.getText(start, start + 1) != r'$') {
          start--;
        }
        var argNameSpan = adjustment.span.file
            .location(start + 1)
            .pointSpan()
            .extendIfMatches('amount')
            .extendIfMatches('degrees');
        addPatch(Patch(argNameSpan, channel));
        if (negate) {
          addPatch(patchBefore(adjustment, '-'));
          if (adjustment.needsParens) {
            addPatch(patchBefore(adjustment, '('));
            addPatch(patchAfter(adjustment, ')'));
          }
        }
        if (space != null) {
          addPatch(patchAfter(adjustment, ', \$space: $space'));
        }
      default:
        warn(node.span.message('Cannot migrate unexpected arguments.'));
    }
  }
}

extension _NeedsParens on Expression {
  /// Returns true if this expression needs parentheses when it's negated.
  bool get needsParens => switch (this) {
        BinaryOperationExpression() ||
        UnaryOperationExpression() ||
        FunctionExpression() =>
          true,
        _ => false,
      };
}
