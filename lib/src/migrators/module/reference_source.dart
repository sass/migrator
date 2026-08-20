// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:path/path.dart' as p;
import 'package:sass_api/sass_api.dart';

import '../../utils.dart';

/// A [ReferenceSource] is used to track where a referenced member came from.
sealed class ReferenceSource {
  /// The canonical URL that contains the declaration being referenced.
  Uri get url;

  /// Returns the ideal namespace to use for this source, or null if the source
  /// doesn't have a namespace.
  String? get preferredNamespace;
}

/// A source for references that should be migrated like an `@import` rule.
///
/// This includes both sources that directly come from an `@import` rule and
/// those from a `@forward` rule within an import-only file.
final class ImportSource extends ReferenceSource {
  @override
  final Uri url;

  /// The URL of the `@import` rule that loaded this member, or null if this
  /// is for an indirect dependency forwarded in an import-only file.
  final Uri? originalRuleUrl;

  /// Creates an [ImportSource] for [url] from [import].
  ///
  /// Note: This is the import that directly loaded the stylesheet defining
  /// the referenced member, not the immediate import within the referencing
  /// stylesheet.
  ///
  /// For example, if A imports B and B imports C, and a member of C is
  /// referenced in A, than that reference's source should be the import in B
  /// that imports C, not the import in A that imports B.
  new(this.url, DynamicImport import) : originalRuleUrl = import.url;

  /// Creates an [ImportSource] from an [ImportOnlySource].
  new fromImportOnlyForward(ImportOnlySource source)
    : url = source.realSourceUrl,
      originalRuleUrl = source.originalRuleUrl;

  /// Returns the preferred namespace to use for this module, based on
  /// [originalRuleUrl].
  @override
  String get preferredNamespace {
    var path = (originalRuleUrl ?? url).path;
    var basename = p.url.basenameWithoutExtension(path);
    if (basename == 'index' || basename == '_index') path = p.url.dirname(path);
    return namespaceForPath(path);
  }

  @override
  operator ==(other) =>
      other is ImportSource &&
      url == other.url &&
      originalRuleUrl == other.originalRuleUrl;
  @override
  int get hashCode => url.hashCode;
}

/// A source for references to members loaded by a `@use` rule.
final class UseSource extends ReferenceSource {
  @override
  final Uri url;

  /// The `@use` rule that made the referenced member available in the
  /// referencing stylesheet.
  ///
  /// Note: This is the opposite of how import sources work. If A uses B, and B
  /// imports or forwards C, and a member originally defined in C is referenced
  /// in A, than that reference's source should be the `@use` rule in A that
  /// loads B, not the import or `@forward` rule in B that loads C.
  final UseRule use;

  new(this.url, this.use);

  @override
  String? get preferredNamespace => use.namespace;

  @override
  operator ==(other) =>
      other is UseSource && url == other.url && use == other.use;
  @override
  int get hashCode => use.hashCode;
}

/// A source for references to built-in functions that are now part of a
/// built-in module.
final class BuiltInSource extends ReferenceSource {
  @override
  final Uri url;

  /// Constructs a [BuiltInSource] for a [module].
  new(String module) : url = Uri.parse("sass:$module");

  @override
  String get preferredNamespace => url.path;

  @override
  operator ==(other) => other is BuiltInSource && url == other.url;
  @override
  int get hashCode => url.hashCode;
}

/// A source for references to members declared in the same stylesheet.
final class CurrentSource extends ReferenceSource {
  @override
  final Uri url;
  new(this.url);

  @override
  String? get preferredNamespace => null;

  @override
  operator ==(other) => other is CurrentSource && url == other.url;
  @override
  int get hashCode => url.hashCode;
}

/// A source for members forwarded by a `@forward` rule.
///
/// This source is used by [_ReferenceVisitor] to track members forwarded in a
/// stylesheet. It is then replaced by an [ImportSource] or [UseSource] when
/// that stylesheet is loaded by a `@use` or `@import` rule.
///
/// It should not be present in the final [sources] property of [References],
/// since forwarded members cannot be referenced in the stylesheet that forwards
/// them, and this will be replaced by an [ImportSource] or [UseSource] in any
/// context where a forwarded member can be referenced.
///
/// Members forwarded from an import-only file should use [ImportOnlySource]
/// instead of this.
final class ForwardSource extends ReferenceSource {
  @override
  final Uri url;

  /// The `@forward` rule the forwarded a member through the current stylesheet.
  final ForwardRule forward;

  new(this.url, this.forward);

  @override
  String? get preferredNamespace => null;

  @override
  operator ==(other) =>
      other is ForwardSource && url == other.url && forward == other.forward;
  @override
  int get hashCode => forward.hashCode;
}

/// A source for members forwarded through an import-only file.
///
/// This source is similar to [ForwardSource] in that it is only used by
/// [_ReferenceVisitor] to track sources internally, and should not be present
/// in the final [sources] property of [References].
final class ImportOnlySource extends ReferenceSource {
  /// The canonical URL of the outermost import-only file in the member's
  /// forward chain.
  @override
  final Uri url;

  /// The canonical URL of the outermost non-import-only file in the member's
  /// forward chain.
  final Uri realSourceUrl;

  /// If [url] is the import-only file for [realSourceUrl], this is the text of
  /// the URL of the `@import` rule that loaded that import-only file.
  ///
  /// Otherwise, this will be null.
  final Uri? originalRuleUrl;

  new(this.url, this.realSourceUrl, this.originalRuleUrl);

  @override
  String? get preferredNamespace => null;

  @override
  operator ==(other) =>
      other is ImportOnlySource &&
      url == other.url &&
      realSourceUrl == other.realSourceUrl &&
      originalRuleUrl == other.originalRuleUrl;
  @override
  int get hashCode => realSourceUrl.hashCode;
}
