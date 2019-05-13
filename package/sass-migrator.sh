#!/bin/sh
# Copyright 2019 Google Inc. Use of this source code is governed by an MIT-style
# license that can be found in the LICENSE file or at
# https://opensource.org/licenses/MIT.

# This script drives the standalone Sass Migrator package, which bundles
# together a Dart executable and a snapshot of the Sass Migrator. It can be
# created with `pub run grinder package`.

follow_links() {
  file="$1"
  while [ -h "$file" ]; do
    # On Mac OS, readlink -f doesn't work.
    file="$(readlink "$file")"
  done
  echo "$file"
}

# Unlike $0, $BASH_SOURCE points to the absolute path of this file.
path=`dirname "$(follow_links "$0")"`
exec "$path/src/dart" "-Dversion=SASS_MIGRATOR_VERSION" "$path/src/sass_migrator.dart.snapshot" "$@"
