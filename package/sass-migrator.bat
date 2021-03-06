@echo off
REM Copyright 2016 Google Inc. Use of this source code is governed by an
REM MIT-style license that can be found in the LICENSE file or at
REM https://opensource.org/licenses/MIT.

REM This script drives the standalone Sass Migrator package, which bundles
REM together a Dart executable and a snapshot of the Sass Migrator. It can be
REM created with `pub run grinder package`.

set SCRIPTPATH=%~dp0
set arguments=%*
"%SCRIPTPATH%\src\dart.exe" "-Dversion=SASS_MIGRATOR_VERSION" "%SCRIPTPATH%\src\sass_migrator.dart.snapshot" %arguments%
