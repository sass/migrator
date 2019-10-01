// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:source_span/source_span.dart';

/// Stores per-stylesheet state for _ModuleMigrationVisitor.
class StylesheetState {
  /// Namespaces of modules used in this stylesheet.
  final Map<Uri, String> namespaces;

  /// Set of canonical URLs that have a `@use` rule in the current stylesheet.
  ///
  /// This includes both `@use` rules migrated from `@import` rules and
  /// additional `@use` rules in the set below.
  final usedUrls = <Uri>{};

  /// Set of additional `@use` rules for built-in modules.
  final builtInUseRules = <String>{};

  /// Set of additional `@use` rules for stylesheets at a load path.
  final additionalLoadPathUseRules = <String>{};

  /// Set of additional `@use` rules for stylesheets relative to the current
  /// one.
  final additionalRelativeUseRules = <String>{};

  /// The first `@import` rule in this stylesheet that was converted to a `@use`
  /// or `@forward` rule, or null if none has been visited yet.
  FileLocation beforeFirstImport;

  /// The last `@import` rule in this stylesheet that was converted to a `@use`
  /// or `@forward` rule, or null if none has been visited yet.
  FileLocation afterLastImport;

  /// Whether @use and @forward are allowed in the current context.
  var useAllowed = true;

  StylesheetState(this.namespaces);
}
