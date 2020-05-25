// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service;

import 'runner.dart';
import 'test_info.dart';

/// The isolate under test and manager of the [TestRunner] lifecycle.
class TestIsolate {
  TestIsolate({
    @required TestRunner testRunner,
  }) : _testRunner = testRunner;

  final TestRunner _testRunner;
  vm_service.IsolateRef _testIsolateRef;
  vm_service.VmService _vmService;
  StreamSubscription<void> _extensionSubscription;
  StreamSubscription<void> _logSubscription;

  /// Start the test isolate.
  Future<void> start(Uri entrypoint, void Function() onExit) async {
    var launchResult = await _testRunner.start(entrypoint, onExit);
    var websocketUrl =
        launchResult.serviceUri.replace(scheme: 'ws').toString() + 'ws';
    _vmService = await vm_service.vmServiceConnectUri(websocketUrl);

    var vm = await _vmService.getVM();
    _testIsolateRef = vm.isolates.firstWhere(
        (element) => element.name.contains(launchResult.isolateName));
    var isolate = await _vmService.getIsolate(_testIsolateRef.id);
    if (isolate.pauseEvent == null ||
        isolate.pauseEvent.kind != vm_service.EventKind.kResume) {
      await _vmService.resume(isolate.id);
    }

    await _vmService.streamListen('Stdout');
    _logSubscription = _vmService.onStdoutEvent.listen((event) {
      var message = utf8.decode(base64.decode(event.bytes));
      print(message);
    });
  }

  /// Tear down the test isolate.
  FutureOr<void> dispose() {
    _extensionSubscription.cancel();
    _logSubscription.cancel();
    _vmService.dispose();
    return _testRunner.dispose();
  }

  Future<TestResult> runTest(TestInfo testInfo) async {
    Map<String, Object> result;
    try {
      result = (await _vmService.callServiceExtension(
        'ext.callTest',
        isolateId: _testIsolateRef.id,
        args: <String, String>{
          'test': testInfo.name,
          'library': testInfo.testFileUri.toString(),
        },
      ))
          .json;
    } on vm_service.RPCError catch (err, st) {
      return TestResult(
        testFileUri: testInfo.testFileUri,
        testName: testInfo.name,
        passed: false,
        timeout: false,
        errorMessage: err.toString(),
        stackTrace: st.toString(),
      );
    }

    return TestResult.fromMessage(
      result,
      testInfo.testFileUri,
    );
  }

  /// Reload the application with the incremental file defined at `incrementalDill`.
  Future<void> reload(Uri incrementalDill) async {
    await _vmService.reloadSources(
      _testIsolateRef.id,
      rootLibUri: incrementalDill.toString(),
    );
  }
}

/// The result of a test execution.
class TestResult {
  const TestResult({
    @required this.testFileUri,
    @required this.testName,
    @required this.passed,
    @required this.timeout,
    @required this.errorMessage,
    @required this.stackTrace,
  });

  /// Create a [TestResult] from the raw JSON [message].
  factory TestResult.fromMessage(
      Map<dynamic, dynamic> message, Uri testFileUri) {
    return TestResult(
      testFileUri: testFileUri,
      testName: message['test'] as String,
      passed: message['passed'] as bool,
      timeout: message['timeout'] as bool,
      errorMessage: message['error'] as String,
      stackTrace: message['stackTrace'] as String,
    );
  }

  /// The absolute file URI of the test.
  final Uri testFileUri;

  /// The name of the test function.
  final String testName;

  /// Whether the test passed.
  final bool passed;

  /// Whether the test timed out.
  final bool timeout;

  /// The error message of the test failure.
  ///
  /// This field is always `null` for timeout failures.
  final String errorMessage;

  /// The stack trace of the test failure.
  ///
  /// This field is always `null` for timeout failures.
  final String stackTrace;
}
