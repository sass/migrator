// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:collection';

import 'bidirectional_map.dart';

/// A map that allows you to efficiently find all keys associated with a
/// particular value.
///
/// Each key can be associated with at most one value, but each value can be
/// associated with more than one key.
///
/// This map also provides a mechanism for freezing its contents. Once [freeze]
/// is called, this map may no longer be modified.
class UnmodifiableBidirectionalMapView<K, V> extends MapView<K, V>
    implements BidirectionalMap<K, V> {
  final BidirectionalMap _map;

  UnmodifiableBidirectionalMapView(BidirectionalMap<K, V> map)
      : _map = map,
        super(map);

  @override
  Iterable<K> keysForValue(V value) => _map.keysForValue(value);
}
