// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:collection';

final builtInModuleUrls = UnmodifiableMapView({
  "color": Uri(scheme: "sass", host: "color"),
  "map": Uri(scheme: "sass", host: "map"),
  "selector": Uri(scheme: "sass", host: "selector"),
  "math": Uri(scheme: "sass", host: "math"),
  "list": Uri(scheme: "sass", host: "list"),
  "meta": Uri(scheme: "sass", host: "meta"),
  "string": Uri(scheme: "sass", host: "string"),
});

/// Mapping from existing built-in function name to the module it's now part of.
const builtInFunctionModules = {
  "red": "color",
  "blue": "color",
  "green": "color",
  "mix": "color",
  "hue": "color",
  "saturation": "color",
  "lightness": "color",
  "adjust-hue": "color",
  "lighten": "color",
  "darken": "color",
  "saturate": "color",
  "desaturate": "color",
  "grayscale": "color",
  "complement": "color",
  "invert": "color",
  "alpha": "color",
  "opacify": "color",
  "fade-in": "color",
  "transparentize": "color",
  "fade-out": "color",
  "adjust-color": "color",
  "scale-color": "color",
  "change-color": "color",
  "ie-hex-str": "color",
  "map-get": "map",
  "map-merge": "map",
  "map-remove": "map",
  "map-keys": "map",
  "map-values": "map",
  "map-has-key": "map",
  "keywords": "map",
  "selector-nest": "selector",
  "selector-append": "selector",
  "selector-replace": "selector",
  "selector-unify": "selector",
  "is-superselector": "selector",
  "simple-selectors": "selector",
  "selector-parse": "selector",
  "percentage": "math",
  "round": "math",
  "ceil": "math",
  "floor": "math",
  "abs": "math",
  "min": "math",
  "max": "math",
  "random": "math",
  "unit": "math",
  "unitless": "math",
  "comparable": "math",
  "length": "list",
  "nth": "list",
  "set-nth": "list",
  "join": "list",
  "append": "list",
  "zip": "list",
  "index": "list",
  "list-separator": "list",
  "feature-exists": "meta",
  "variable-exists": "meta",
  "global-variable-exists": "meta",
  "function-exists": "meta",
  "mixin-exists": "meta",
  "inspect": "meta",
  "get-function": "meta",
  "type-of": "meta",
  "call": "meta",
  "content-exists": "meta",
  "unquote": "string",
  "quote": "string",
  "str-length": "string",
  "str-insert": "string",
  "str-index": "string",
  "str-slice": "string",
  "to-upper-case": "string",
  "to-lower-case": "string",
  "unique-id": "string"
};

/// Mapping from old function name to new name, excluding namespace.
const builtInFunctionNameChanges = {
  "adjust-color": "adjust",
  "scale-color": "scale",
  "change-color": "change",
  "map-get": "get",
  "map-merge": "merge",
  "map-remove": "remove",
  "map-keys": "keys",
  "map-values": "values",
  "map-has-key": "has-key",
  "selector-nest": "nest",
  "selector-append": "append",
  "selector-replace": "replace",
  "selector-unify": "unify",
  "selector-parse": "parse",
  "unitless": "is-unitless",
  "comparable": "compatible",
  "list-separator": "separator",
  "str-length": "length",
  "str-insert": "insert",
  "str-index": "index",
  "str-slice": "slice"
};

/// Mapping from removed color function names to the parameter passed to
/// `adjust-color` for the same effect.
///
/// If the value from the removed function must be negated when passed to
/// `adjust-color`, the parameter ends with a `-`.
const removedColorFunctions = {
  "lighten": r"$lightness: ",
  "darken": r"$lightness: -",
  "saturate": r"$saturation: ",
  "desaturate": r"$saturation: -",
  "opacify": r"$alpha: ",
  "fade-in": r"$alpha: ",
  "transparentize": r"$alpha: -",
  "fade-out": r"$alpha: -"
};
