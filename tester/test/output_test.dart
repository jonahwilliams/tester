// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:io';

import 'package:process/process.dart';
import 'package:expect/expect.dart';

/// Tests that a print statement in a test body shows up in the resulting
/// output of a vm test.
void testThatPrintShowsUpVm() async {
  var processManager = LocalProcessManager();
  var tester = File('bin/tester').absolute.path;
  var result = await processManager.run(
    <String>[tester, '--platform=dart', 'test/print_test.dart'],
    workingDirectory: '../test_project',
  );

  expect(result.exitCode, 0);
  expect(result.stdout, contains('TEST SENTINEL'));
}

/// Tests that a print statement in a test body shows up in the resulting
/// output of a vm test.
void testThatPrintShowsUpFlutter() async {
  var processManager = LocalProcessManager();
  var tester = File('bin/tester').absolute.path;
  var result = await processManager.run(
    <String>[tester, '--platform=flutter', 'test/print_test.dart'],
    workingDirectory: '../test_project',
  );

  expect(result.exitCode, 0);
  expect(result.stdout, contains('TEST SENTINEL'));
}
