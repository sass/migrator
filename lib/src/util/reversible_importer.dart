// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:sass/sass.dart';

/// An [Importer] interface that supports converting canonical URLs back into
/// their non-canonical forms.
abstract class ReversibleImporter implements Importer {
  /// Converts [canonicalUrl] into a non-canonical form.
  ///
  /// Callers should only call this with [canonicalUrl]s returned by this
  /// importer. Implementors must guarantee that calling
  /// `canonicalize(decanonicalize(url))` will return the original `url`.
  Uri decanonicalize(Uri canonicalUrl);
}
