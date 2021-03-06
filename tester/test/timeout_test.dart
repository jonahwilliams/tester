// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:io';

import 'package:process/process.dart';
import 'package:expect/expect.dart';

/// Spin up a tester process running a test that takes longer
/// than the configured timeout.
Future<void> testTimeoutConfigurationTimesout() async {
  var processManager = LocalProcessManager();
  var tester = File('bin/tester').absolute.path;
  var result = await processManager.run(
      <String>[tester, '--timeout=1', 'test/timeout_test.dart'],
      workingDirectory: '../test_project');

  expect(result.exitCode, isNot(0));
  expect(result.stdout, contains('TimeoutException'));
}
