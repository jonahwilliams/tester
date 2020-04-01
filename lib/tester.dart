// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:tester/src/compiler.dart';
import 'package:tester/src/config.dart';
import 'package:tester/src/isolate.dart';
import 'package:tester/src/resident.dart';
import 'package:tester/src/runner.dart';

void runApplication({
  @required bool batchMode,
  @required Config config,
  @required ProcessManager processManager,
  @required FileSystem fileSystem,
}) async {
  var compiler = Compiler(
    fileSystem: fileSystem,
    config: config,
    processManager: processManager,
  );
  var result = await compiler.start();
  if (result == null) {
    return;
  }

  // Step 3. Load test isolate.
  var vmTestRunner = VmTestRunner(
    fileSystem: fileSystem,
    processManager: processManager,
    dartSdkPath: config.sdkRoot,
  );
  var testIsolate = TestIsolate(testRunner: vmTestRunner);
  await testIsolate.start(result.toString(), () {
    exit(1);
  });

  if (batchMode) {
    await for (var testResult in testIsolate.runAllTests()) {
      if (testResult.passed) {
        print('pass ${testResult.testName}');
      } else {
        print('fail ${testResult.testName}');
      }
    }
    return exit(0);
  }
  var resident = Resident(
    compiler: compiler,
    testIsolate: testIsolate,
    config: config,
    fileSystem: fileSystem,
  );
  if (!stdin.hasTerminal) {
    exit(1);
  }

  // The order of setting lineMode and echoMode is important on Windows.
  stdin.echoMode = false;
  stdin.lineMode = false;
  var pending = false;
  print('READY. r/R to rerun tests, and q/Q to quit.');
  stdin
      .transform(const AsciiDecoder(allowInvalid: true))
      .listen((String line) async {
    if (pending) {
      print('BUSY');
    }
    switch (line) {
      case 'r':
      case 'R':
        pending = true;
        await resident.rerun();
        pending = false;
        break;
      case 'q':
      case 'Q':
        await resident.dispose();
        exit(0);
    }
  });
}
