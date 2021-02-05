// Copyright 2021 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:args/args.dart';
import 'package:sass/sass.dart';
import 'package:source_span/source_span.dart';

// The sass package's API is not necessarily stable. It is being imported with
// the Sass team's explicit knowledge and approval. See
// https://github.com/sass/dart-sass/issues/236.
import 'package:sass/src/ast/sass.dart';
import 'package:sass/src/import_cache.dart';

import '../migration_visitor.dart';
import '../migrator.dart';
import '../patch.dart';
import '../exception.dart';
import '../utils.dart';
import '../renamer.dart';
import 'namespace/unreferenced_flag.dart';

/// Changes namespaces for `@use` rules within the file(s) being migrated.
class NamespaceMigrator extends Migrator {
  final name = "namespace";
  final description = "Change namespaces for `@use` rules.";

  @override
  final argParser = ArgParser()
    ..addMultiOption('rename',
        abbr: 'r',
        splitCommas: false,
        help: 'e.g. "old-namespace to new-namespace" or\n'
            '     "url my/url to new-namespace"\n'
            'See https://sass-lang.com/documentation/cli/migrator#rename.')
    ..addOption('unreferenced',
        abbr: 'u',
        help: 'Whether to change namespaces of unreferenced rules to '
            '"_unreferenced#".',
        allowed: ['conflicting', 'all', 'none'],
        allowedHelp: {
          'conflicting': 'Only when they conflict with other namespaces.',
          'all': 'All unreferenced rules will be renamed.',
          'none':
              'Unreferenced rules will be treated the same as referenced ones.'
        },
        defaultsTo: 'conflicting')
    ..addFlag('force',
        abbr: 'f',
        help: 'Force rename namespaces, adding numerical suffixes for '
            'conflicts.');

  @override
  Map<Uri, String> migrateFile(
      ImportCache importCache, Stylesheet stylesheet, Importer importer) {
    var renamer = Renamer<UseRule>(argResults['rename'].join('\n'),
        {'': (rule) => rule.namespace, 'url': (rule) => rule.url.toString()},
        sourceUrl: '--rename');
    var visitor = _NamespaceMigrationVisitor(
        renamer,
        UnreferencedFlag(argResults['unreferenced']),
        argResults['force'] as bool,
        importCache,
        migrateDependencies);
    var result = visitor.run(stylesheet, importer);
    missingDependencies.addAll(visitor.missingDependencies);
    return result;
  }
}

class _NamespaceMigrationVisitor extends MigrationVisitor {
  final Renamer<UseRule> renamer;
  final UnreferencedFlag unreferencedFlag;
  final bool forceRename;

  /// A set of spans for each *original* namespace in the current file.
  ///
  /// Each span covers just the namespace of a member reference.
  Map<String, Set<FileSpan>> _spansByNamespace;

  /// The set of namespaces used in the current file *after* renaming.
  Set<String> _usedNamespaces;

  _NamespaceMigrationVisitor(this.renamer, this.unreferencedFlag,
      this.forceRename, ImportCache importCache, bool migrateDependencies)
      : super(importCache, migrateDependencies);

  @override
  void visitStylesheet(Stylesheet node) {
    var oldSpansByNamespace = _spansByNamespace;
    var oldUsedNamespaces = _usedNamespaces;
    _spansByNamespace = {};
    _usedNamespaces = {};
    super.visitStylesheet(node);
    _spansByNamespace = oldSpansByNamespace;
    _usedNamespaces = oldUsedNamespaces;
  }

  @override
  void beforePatch(Stylesheet node) {
    // Pass each `@use` rule through the renamer.
    var newNamespaces = <String, Set<UseRule>>{};
    for (var rule in node.children.whereType<UseRule>()) {
      if (rule.namespace == null) continue;
      newNamespaces
          .putIfAbsent(renamer.rename(rule) ?? rule.namespace, () => {})
          .add(rule);
    }
    // Contains `@use` rules that will get renamed to `_unreferenced#`.
    var unreferencedRules = <UseRule>{};

    // Goes through each new namespace, resolving conflicts if necessary.
    for (var entry in newNamespaces.entries) {
      var newNamespace = entry.key;
      var rules = entry.value;
      if (rules.length == 1) {
        // If --unreferenced=all, add to [unreferencedRules] even if there's
        // no conflict.
        if (unreferencedFlag == UnreferencedFlag.all &&
            !_spansByNamespace.containsKey(rules.first.namespace)) {
          unreferencedRules.add(rules.first);
        } else {
          // Otherwise, give this rule its preferred namespace.
          _patchNamespace(rules.first, newNamespace);
        }
        continue;
      }

      // Since there's a conflict, check for unreferenced rules unless
      // --unreferenced=none
      if (unreferencedFlag != UnreferencedFlag.none) {
        for (var rule in rules.toSet()) {
          if (!_spansByNamespace.containsKey(rule.namespace)) {
            unreferencedRules.add(rule);
            rules.remove(rule);
          }
        }
      }

      // If removing unreferenced rules resolves the conflict, give the
      // remaining rule its preferred namespace.
      if (rules.length == 1) {
        _patchNamespace(rules.first, newNamespace);
        continue;
      }

      // If there's still a conflict, fail unless --force is passed.
      if (!forceRename) {
        throw MultiSpanSassException(
            'Rename failed. ${rules.length} rules would use namespace '
                '"$newNamespace".\n'
                'Run with --force to rename with numerical suffixes.',
            rules.first.span,
            '',
            {for (var rule in rules.skip(1)) rule.span: ''});
      }

      // With --force, give the first rule its preferred namespace and then
      // add numerical suffixes to the rest.
      var suffix = 2;
      for (var rule in rules) {
        var forcedNamespace = newNamespace;
        while (_usedNamespaces.contains(forcedNamespace)) {
          forcedNamespace = '$newNamespace$suffix';
          suffix++;
        }
        _patchNamespace(rule, forcedNamespace);
      }
    }

    // Now assign _unreferenced# to each rule
    var suffix = 1;
    for (var rule in unreferencedRules) {
      var namespace = '_unreferenced$suffix';
      while (_usedNamespaces.contains(namespace)) {
        namespace = '_unreferenced$suffix';
        suffix++;
      }
      _patchNamespace(rule, namespace);
    }
  }

  /// Patch [rule] and all references to it with [newNamespace].
  void _patchNamespace(UseRule rule, String newNamespace) {
    _usedNamespaces.add(newNamespace);
    if (rule.namespace == newNamespace) return;
    var asClause =
        RegExp('\\s*as\\s+(${rule.namespace})').firstMatch(rule.span.text);
    if (asClause == null) {
      // Add an `as` clause to a rule that previously lacked one.
      var end = RegExp(r"""@use\s("|').*?\1""").firstMatch(rule.span.text).end;
      addPatch(
          Patch.insert(rule.span.subspan(0, end).end, ' as $newNamespace'));
    } else if (namespaceForPath(rule.url.toString()) == newNamespace) {
      // Remove an `as` clause that is no longer necessary.
      addPatch(
          patchDelete(rule.span, start: asClause.start, end: asClause.end));
    } else {
      // Change the namespace of an existing `as` clause.
      addPatch(Patch(
          rule.span.subspan(asClause.end - rule.namespace.length, asClause.end),
          newNamespace));
    }
    for (FileSpan span in _spansByNamespace[rule.namespace] ?? {}) {
      addPatch(Patch(span, newNamespace));
    }
  }

  /// If [namespace] is not null, add its span to [_spansByNamespace].
  void _addNamespaceSpan(String namespace, FileSpan span) {
    if (namespace != null) {
      assert(span.text.startsWith(namespace));
      _spansByNamespace
          .putIfAbsent(namespace, () => {})
          .add(subspan(span, end: namespace.length));
    }
  }

  @override
  void visitFunctionExpression(FunctionExpression node) {
    _addNamespaceSpan(node.namespace, node.span);
    var name = node.name.asPlain;
    if (name == 'get-function') {
      var moduleArg = node.arguments.named['module'];
      if (node.arguments.positional.length == 3) {
        moduleArg ??= node.arguments.positional[2];
      }
      if (moduleArg is StringExpression) {
        var namespace = moduleArg.text.asPlain;
        if (namespace != null) {
          var span = moduleArg.hasQuotes
              ? moduleArg.span.subspan(1, moduleArg.span.length - 1)
              : moduleArg.span;
          _addNamespaceSpan(namespace, span);
        }
      }
    }
    super.visitFunctionExpression(node);
  }

  @override
  void visitIncludeRule(IncludeRule node) {
    if (node.namespace != null) {
      var startNamespace = node.span.text.indexOf(
          node.namespace, node.span.text[0] == '+' ? 1 : '@include'.length);
      _addNamespaceSpan(node.namespace, node.span.subspan(startNamespace));
    }
    super.visitIncludeRule(node);
  }

  @override
  void visitVariableDeclaration(VariableDeclaration node) {
    _addNamespaceSpan(node.namespace, node.span);
    super.visitVariableDeclaration(node);
  }

  @override
  void visitVariableExpression(VariableExpression node) {
    _addNamespaceSpan(node.namespace, node.span);
    super.visitVariableExpression(node);
  }
}
