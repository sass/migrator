// Copyright 2021 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:args/args.dart';
import 'package:sass_api/sass_api.dart';
import 'package:source_span/source_span.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';
import '../utils.dart';
import '../renamer.dart';

/// Changes namespaces for `@use` rules within the file(s) being migrated.
class NamespaceMigrator extends Migrator {
  @override
  final name = "namespace";
  @override
  final description = "Change namespaces for `@use` rules.";

  @override
  final argParser = ArgParser()
    ..addMultiOption(
      'rename',
      abbr: 'r',
      splitCommas: false,
      help:
          'e.g. "old-namespace to new-namespace" or\n'
          '     "url my/url to new-namespace"\n'
          'See https://sass-lang.com/documentation/cli/migrator#rename.',
    )
    ..addFlag(
      'force',
      abbr: 'f',
      help:
          'Force rename namespaces, adding numerical suffixes for '
          'conflicts.',
    );

  @override
  Map<Uri, String> migrateFile(
    ImportCache importCache,
    Stylesheet stylesheet,
    Importer importer,
  ) {
    var renamer = Renamer<UseRule>(
      (argResults!['rename'] as List<String>).join('\n'),
      {'': ((rule) => rule.namespace!), 'url': (rule) => rule.url.toString()},
      sourceUrl: '--rename',
    );
    var visitor = _NamespaceMigrationVisitor(
      renamer,
      argResults!['force'] as bool,
      importCache,
      migrateDependencies: migrateDependencies,
    );
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

class _NamespaceMigrationVisitor(
  final Renamer<UseRule> renamer,
  final bool forceRename,
  super.importCache, {
  required super.migrateDependencies,
}) extends MigrationVisitor {
  /// A map from the semantic values of namespaces before renaming to those
  /// after renaming.
  Map<String, String> get _renamedNamespaces =>
      assertInStylesheet(__renamedNamespaces, '_renamedNamespaces');
  Map<String, String>? __renamedNamespaces;

  @override
  void visitStylesheet(Stylesheet node) {
    assert(__renamedNamespaces == null);
    __renamedNamespaces = _chooseNamespaces(node);
    super.visitStylesheet(node);
    __renamedNamespaces = null;
  }

  /// Computes [_renamedNamespaces] for a given stylesheet based on [renamer].
  Map<String, String> _chooseNamespaces(Stylesheet node) {
    // A map from the semantic values of namespaces *after* renaming to all use
    // rules that were renamed to that value.
    var newNamespaces = <String, List<UseRule>>{};
    for (var rule in node.uses) {
      var namespace = rule.namespace;
      if (namespace == null) continue;
      newNamespaces
          .putIfAbsent(renamer.rename(rule) ?? namespace, () => [])
          .add(rule);
    }

    var renamedNamespaces = <String, String>{};
    // Goes through each new namespace, resolving conflicts if necessary.
    for (var entry in newNamespaces.entries) {
      var newNamespace = entry.key;
      var rules = entry.value;
      if (rules case [var rule]) {
        renamedNamespaces[rule.namespace!] = newNamespace;
        continue;
      }

      // If there's still a conflict, fail unless --force is passed.
      if (!forceRename) {
        throw MultiSourceSpanException(
          'Rename failed. ${rules.length} rules would use namespace '
              '"$newNamespace".\n'
              'Run with --force to rename with numerical suffixes.',
          rules.first.span,
          '',
          {for (var rule in rules.skip(1)) rule.span: ''},
        );
      }

      // With --force, give the first rule its preferred namespace and then
      // add numerical suffixes to the rest.
      renamedNamespaces[rules.first.namespace!] = newNamespace;
      var suffix = 2;
      for (var rule in rules.skip(1)) {
        renamedNamespaces[rule.namespace!] = '$newNamespace$suffix';
        suffix++;
      }
    }
    return renamedNamespaces;
  }

  @override
  void visitUseRule(UseRule rule) {
    var newNamespace = _renamedNamespaces[rule.namespace];
    if (newNamespace == null) return;
    if (rule.namespace == newNamespace) return;

    // TODO: Use `UseRule.namespaceSpan` once such a thing is added to support
    // sass-parser. This RegExp approach fails if there are extra comments or if
    // the namespace isn't in normalized form in the document.
    var spanAfterUrl = rule.span.after(rule.urlSpan);
    if (rule.namespace.andThen(
          (namespace) => RegExp(
            '^(\\s*as\\s+)${RegExp.escape(toCssIdentifier(namespace))}',
          ).firstMatch(spanAfterUrl.text),
        )
        case var asClause?) {
      if (namespaceForPath(rule.url.toString()) == newNamespace) {
        // Remove an `as` clause that is no longer necessary.
        addPatch(patchDelete(spanAfterUrl, end: asClause.end));
      } else {
        // Change the namespace of an existing `as` clause.
        addPatch(
          Patch(
            spanAfterUrl.subspan(
              asClause.start + asClause[1]!.length,
              asClause.end,
            ),
            toCssIdentifier(newNamespace),
          ),
        );
      }
    } else {
      addPatch(
        Patch.insert(
          spanAfterUrl.start,
          ' as ${toCssIdentifier(newNamespace)}',
        ),
      );
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    if (_renamedNamespaces[node.namespace] case var newNamespace?) {
      addPatches(patchNamespace(node, newNamespace));
    }

    _visitModuleArg(switch (node) {
      FunctionExpression(
        name: 'get-function' ||
            'function-exists' ||
            'get-mixin' ||
            'global-variable-exists' ||
            'mixin-exists' ||
            'get-module' ||
            'module-functions' ||
            'module-mixins' ||
            'module-variables',
        arguments: ArgumentList(named: {'module': var arg}),
      ) ||
      FunctionExpression(
        name: 'get-function',
        arguments: ArgumentList(positional: [_, _, var arg]),
      ) ||
      FunctionExpression(
        name: 'function-exists' ||
            'get-mixin' ||
            'global-variable-exists' ||
            'mixin-exists',
        arguments: ArgumentList(positional: [_, var arg]),
      ) ||
      FunctionExpression(
        name: 'get-module' ||
            'module-functions' ||
            'module-mixins' ||
            'module-variables',
        arguments: ArgumentList(positional: [var arg]),
      ) => arg,

      _ => null,
    });
    super.visitFunctionExpression(node);
  }

  @override
  void visitIncludeRule(IncludeRule node) {
    if (_renamedNamespaces[node.namespace] case var newNamespace?) {
      addPatches(patchNamespace(node, newNamespace));
    }

    if (node case IncludeRule(
      name: 'css',
      arguments: ArgumentList(named: {'module': var arg}) ||
          ArgumentList(positional: [var arg]),
    )) {
      _visitModuleArg(arg);
    }

    super.visitIncludeRule(node);
  }

  /// Patches the value of the `$module` argument for a module reference
  /// `sass:meta` function.
  void _visitModuleArg(Expression? moduleArg) {
    // TODO(sass/sass#4268): Use the semantic value of quoted strings once
    // Sass supports those semantics.
    if (moduleArg
        case StringExpression(text: Interpolation(asPlain: var oldNamespace?))
        when isIdentifier(oldNamespace)) {
      if (_renamedNamespaces[parseIdentifier(oldNamespace)]
          case var newNamespace?) {
        addPatch(Patch(moduleArg.span, toSassIdentString(newNamespace)));
      }
    }
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    if (_renamedNamespaces[node.namespace] case var newNamespace?) {
      addPatches(patchNamespace(node, newNamespace));
    }
    super.visitVariableDeclaration(node);
  }

  @override
  void visitVariableExpression(VariableExpression node) {
    if (_renamedNamespaces[node.namespace] case var newNamespace?) {
      addPatches(patchNamespace(node, newNamespace));
    }
    super.visitVariableExpression(node);
  }
}
