// Copyright 2019 Google Inc. Use of this source code is governed by an
// MIT-style license that can be found in the LICENSE file or at
// https://opensource.org/licenses/MIT.

import 'package:grinder/grinder.dart';

export 'grind/chocolatey.dart';
export 'grind/npm.dart';
export 'grind/github.dart';
export 'grind/sanity_check.dart';
export 'grind/standalone.dart';

main(List<String> args) => grind(args);
