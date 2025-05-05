// Copyright 2024 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass_api/sass_api.dart';
import 'package:sass_migrator/src/migrators/module/reference_source.dart';
import 'package:source_span/source_span.dart';

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
    var visitor = _ColorMigrationVisitor(references, importCache,
        migrateDependencies: migrateDependencies);
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

/// URL for the sass:color module.
final _colorUrl = Uri(scheme: 'sass', path: 'color');

class _ColorMigrationVisitor extends MigrationVisitor {
  final References references;

  _ColorMigrationVisitor(this.references, super.importCache,
      {required super.migrateDependencies});

  /// The namespace of an existing `@use "sass:color"` rule in the current
  /// file, if any.
  String? _colorModuleNamespace;

  /// The set of all other namespaces already used in the current file.
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
    if (source is BuiltInSource && source.url == _colorUrl) {
      var colorPatches = _makeColorPatches(node);
      if (colorPatches.isNotEmpty && node.namespace == null) {
        addPatch(patchBefore(
            node, '${_getOrAddColorModuleNamespace(node.span.file)}.'));
      }
      colorPatches.forEach(addPatch);
    }
    super.visitFunctionExpression(node);
  }

  /// Returns the patches necessary to convert legacy color functions to
  /// `color.adjust` or `color.channel`.
  Iterable<Patch> _makeColorPatches(FunctionExpression node) {
    switch (node.name) {
      case 'red' || 'green' || 'blue':
        return _makeChannelPatches(node, 'rgb');
      case 'hue' || 'saturation' || 'lightness':
        return _makeChannelPatches(node, 'hsl');
      case 'whiteness' || 'blackness':
        return _makeChannelPatches(node, 'hwb');
      case 'alpha':
        return _makeChannelPatches(node);
      case 'adjust-hue':
        return _makeAdjustPatches(node, channel: 'hue', space: 'hsl');
      case 'saturate'
          when node.arguments.named.length + node.arguments.positional.length !=
              1:
        return _makeAdjustPatches(node, channel: 'saturation', space: 'hsl');
      case 'desaturate':
        return _makeAdjustPatches(node,
            channel: 'saturation', negate: true, space: 'hsl');
      case 'transparentize' || 'fade-out':
        return _makeAdjustPatches(node, channel: 'alpha', negate: true);
      case 'opacify' || 'fade-in':
        return _makeAdjustPatches(node, channel: 'alpha');
      case 'lighten':
        return _makeAdjustPatches(node, channel: 'lightness', space: 'hsl');
      case 'darken':
        return _makeAdjustPatches(node,
            channel: 'lightness', negate: true, space: 'hsl');
      default:
        return [];
    }
  }

  /// Returns the namespace used for the color module, adding a new `@use` rule
  /// if necessary.
  String _getOrAddColorModuleNamespace(SourceFile file) {
    if (_colorModuleNamespace == null) {
      _colorModuleNamespace = _chooseColorModuleNamespace();
      var asClause =
          _colorModuleNamespace == 'color' ? '' : ' as $_colorModuleNamespace';
      addPatch(
          Patch.insert(file.location(0), '@use "sass:color"$asClause;\n\n'));
    }
    return _colorModuleNamespace!;
  }

  /// Find an unused namespace for the sass:color module.
  String _chooseColorModuleNamespace() {
    if (!_usedNamespaces.contains('color')) return 'color';
    if (!_usedNamespaces.contains('sass-color')) return 'sass-color';
    var count = 2;
    var namespace = 'color$count';
    while (_usedNamespaces.contains(namespace)) {
      namespace = 'color${++count}';
    }
    return namespace;
  }

  /// Returns the patches to make a deprecated channel function use
  /// `color.channel` instead.
  Iterable<Patch> _makeChannelPatches(FunctionExpression node,
      [String? colorSpace]) sync* {
    yield Patch(node.nameSpan, 'channel');
    if (node.arguments.named.isEmpty) {
      yield patchAfter(
          node.arguments.positional.last,
          ", '${node.name}'"
          "${colorSpace == null ? '' : ', \$space: $colorSpace'}");
    } else {
      yield patchAfter(
          [...node.arguments.positional, ...node.arguments.named.values].last,
          ", \$channel: '${node.name}'"
          "${colorSpace == null ? '' : ', \$space: $colorSpace'}");
    }
  }

  /// Returns the patches to make a deprecated adjustment function use
  /// `color.adjust` instead.
  Iterable<Patch> _makeAdjustPatches(FunctionExpression node,
      {required String channel, bool negate = false, String? space}) sync* {
    yield Patch(node.nameSpan, 'adjust');
    switch (node.arguments) {
      case ArgumentList(positional: [_, var adjustment]):
        yield patchBefore(adjustment, '\$$channel: ${negate ? '-' : ''}');
        if (negate && adjustment.needsParens) {
          yield patchBefore(adjustment, '(');
          yield patchAfter(adjustment, ')');
        }
        if (space != null) {
          yield patchAfter(adjustment, ', \$space: $space');
        }

      case ArgumentList(
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
        yield Patch(argNameSpan, channel);
        if (negate) {
          yield patchBefore(adjustment, '-');
          if (adjustment.needsParens) {
            yield patchBefore(adjustment, '(');
            yield patchAfter(adjustment, ')');
          }
        }
        if (space != null) {
          yield patchAfter(adjustment, ', \$space: $space');
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
