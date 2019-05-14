@echo off
REM Copyright 2019 Google Inc. Use of this source code is governed by an
REM MIT-style license that can be found in the LICENSE file or at
REM https://opensource.org/licenses/MIT.

set SCRIPTPATH=%~dp0
set arguments=%*
dart.exe "-Dversion=SASS_MIGRATOR_VERSION" "%SCRIPTPATH%\sass_migrator.dart.snapshot" %arguments%
