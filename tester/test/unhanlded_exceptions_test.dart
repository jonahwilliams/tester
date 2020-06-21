// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:expect/expect.dart';
import 'package:process/process.dart';

/// In the flutter_tester, unhandled expcetions will assert in the shell,
/// causing the test to stop. Validate that the Zone override is working
/// as expected.
void testUnhandledExceptionsCaught() async {
  var processManager = LocalProcessManager();
  var tester = File('bin/tester').absolute.path;
  var result = await processManager.run(
    <String>[
      tester,
      '--platform=dart',
      'test/unhandled_exception_test.dart',
    ],
    workingDirectory: '../test_project',
  );

  expect(result.stdout, contains('UNHANDLED EXCEPTION'));
  expect(result.exitCode, 0);
}
