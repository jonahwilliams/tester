@ECHO off
REM Copyright 2014 The Flutter Authors. All rights reserved.
REM Use of this source code is governed by a BSD-style license that can be
REM found in the LICENSE file.

SETLOCAL ENABLEDELAYEDEXPANSION

FOR %%i IN ("%~dp0..") DO SET TESTER_ROOT=%%~fi

SET cache_dir=%TESTER_ROOT%\bin\cache
SET snapshot_path=%cache_dir%\tester.snapshot
SET version_stamp=%cache_dir%\compile.stamp
SET dart_stamp=%cache_dir%\dart.stamp
SET current_version=%cache_dir%\version
SET package_config=%TESTER_ROOT%\.dart_tool\package_config.json
SET temp_dart_ver=%cache_dir%\temp_stamp
SET program_entrypoint="package:tester/src/executable.dart"

:subroutine
    IF NOT EXIST "%cache_dir%" MKDIR "%cache_dir%"
    IF NOT EXIST "%version_stamp%" GOTO snapshot
    IF NOT EXIST "%dart_stamp%" GOTO snapshot
    IF NOT EXIST "%snapshot_path%" GOTO snapshot

    SET /P current_version=<"%current_version%"
    SET /P installed_version=<"%version_stamp%"
    SET /P dart_version=<"%dart_stamp%"
    CALL dart --disable-dart-dev --version 2> "%temp_dart_ver%"
    SET /P current_dart=<"%temp_dart_ver%"

    IF !current_version! NEQ !installed_version! GOTO snapshot
    IF !dart_version! NEQ !current_dart! GOTO snapshot

    GOTO run_program

    :snapshot
        ECHO precompiling tester snapshot...
        PUSHD "%TESTER_ROOT%"

        CALL dart pub get --no-precompile > nul
        CALL dart --disable-dart-dev --snapshot="%snapshot_path%" --snapshot-kind=app-jit --packages="%package_config%" --no-enable-mirrors "%program_entrypoint%" --no-debugger test/compiler_test.dart > NUL

        >"%version_stamp%" ECHO %current_version%
        CALL dart --disable-dart-dev --version 2> "%dart_stamp%"
        POPD
        GOTO run_program

    :run_program
        dart --disable-dart-dev --packages="%package_config%" "%snapshot_path%" %* & exit /B !ERRORLEVEL!
        REM Exit Subroutine
        EXIT /B
