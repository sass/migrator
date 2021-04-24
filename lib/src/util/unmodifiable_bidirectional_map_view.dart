// Copyright 2019 Google LLC
//
// Use of this source code is governed by an MIT-style
// license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'dart:collection';

import 'bidirectional_map.dart';

/// A unmodifiable view of [BidirectionalMap].
class UnmodifiableBidirectionalMapView<K, V> extends UnmodifiableMapView<K, V>
    implements BidirectionalMap<K, V> {
  final BidirectionalMap<K, V> _map;

  UnmodifiableBidirectionalMapView(BidirectionalMap<K, V> map)
      : _map = map,
        super(map);

  @override
  Iterable<K> keysForValue(V value) => _map.keysForValue(value);
}
