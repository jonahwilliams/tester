// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:io';

import 'package:process/process.dart';
import 'package:expect/expect.dart';

/// Test that --enable-experiment=non-nullable is functioning
/// correctly.
void testThatNullSafetyCompiles() async {
  var processManager = LocalProcessManager();
  var tester = File('bin/tester').absolute.path;
  var result = await processManager.run(
    <String>[
      tester,
      '--platform=dart',
      '--enable-experiment=non-nullable',
      'test/null_safety_test.dart',
    ],
    workingDirectory: '../test_project',
  );

  expect(result.exitCode, 0);
}
