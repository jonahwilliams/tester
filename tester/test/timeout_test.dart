// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';

import 'package:process/process.dart';
import 'package:test_shim/test_shim.dart';

/// Spin up a tester process running a test that takes longer
/// than the configured timeout.
Future<void> testTimeoutConfigurationTimesout() async {
  if (!Platform.isWindows) {
    // TODO(jonahwilliams): add entrypoint for linux/mac
    return;
  }
  var processManager = LocalProcessManager();
  var tester = File('bin/tester').absolute.path;
  var result = await processManager.run(
      <String>[tester, '--timeout=1', 'test/timeout_test.dart'],
      workingDirectory: '../test_project');

  expect(result.exitCode, 1);
  expect(result.stdout, contains('TimeoutException'));
}
