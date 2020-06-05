// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service;

import 'runner.dart';
import 'test_info.dart';
import 'web_runner.dart';

/// The isolate under test and manager of the [TestRunner] lifecycle.
abstract class TestIsolate {
  /// Start the test isolate.
  Future<void> start(Uri entrypoint, void Function() onExit);

  /// Tear down the test isolate.
  FutureOr<void> dispose();

  /// Execute [testInfo]
  Future<TestResult> runTest(TestInfo testInfo);

  /// Reload the application with the incremental file defined at `incrementalDill`.
  Future<void> reload(Uri incrementalDill);
}

/// The isolate under test and manager of the [TestRunner] lifecycle.
class VmTestIsolate extends TestIsolate {
  VmTestIsolate({
    @required TestRunner testRunner,
  }) : _testRunner = testRunner;

  final TestRunner _testRunner;
  vm_service.IsolateRef _testIsolateRef;
  vm_service.VmService _vmService;

  @override
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

    await _vmService.streamListen(vm_service.EventStreams.kStdout);
    _vmService.onStdoutEvent.listen((event) {
      var message = utf8.decode(base64.decode(event.bytes));
      print(message);
    });
    await _vmService.streamListen(vm_service.EventStreams.kLogging);
    _vmService.onStdoutEvent.listen((event) {
      var message = utf8.decode(base64.decode(event.bytes));
      print(message);
    });
  }

  @override
  FutureOr<void> dispose() {
    _vmService?.dispose();
    return _testRunner?.dispose();
  }

  @override
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

  @override
  Future<void> reload(Uri incrementalDill) async {
    await _vmService.reloadSources(
      _testIsolateRef.id,
      rootLibUri: incrementalDill.toString(),
    );
  }
}

class WebTestIsolate extends TestIsolate {
  WebTestIsolate({
    @required this.testRunner,
  });

  final ChromeTestRunner testRunner;
  vm_service.VmService _vmService;
  StreamSubscription<void> _logSubscription;

  @override
  Future<void> start(Uri entrypoint, void Function() onExit) async {
    var codeFile = File(entrypoint.toFilePath() + '.sources');
    var manifestFile = File(entrypoint.toFilePath() + '.json');
    var sourceMapFile = File(entrypoint.toFilePath() + '.map');

    testRunner.updateCode(codeFile, manifestFile, sourceMapFile);

    await testRunner.start(entrypoint, onExit);
    _vmService = testRunner.vmService;

    await _vmService.streamListen(vm_service.EventStreams.kStdout);
    _vmService.onStdoutEvent.listen((event) {
      var message = utf8.decode(base64.decode(event.bytes));
      print(message);
    });
    await _vmService.streamListen(vm_service.EventStreams.kLogging);
    _vmService.onStdoutEvent.listen((event) {
      var message = utf8.decode(base64.decode(event.bytes));
      print(message);
    });
  }

  @override
  FutureOr<void> dispose() async {
    await _logSubscription?.cancel();
    await testRunner.dispose();
  }

  @override
  Future<void> reload(Uri incrementalDill) async {
    var codeFile = File(incrementalDill.toFilePath() + '.sources');
    var manifestFile = File(incrementalDill.toFilePath() + '.json');
    var sourceMapFile = File(incrementalDill.toFilePath() + '.map');

    testRunner.updateCode(codeFile, manifestFile, sourceMapFile);

    try {
      await _vmService.callMethod('hotRestart');
    } catch (err, st) {
      print(err);
      print(st);
    }
  }

  @override
  Future<TestResult> runTest(TestInfo testInfo) async {
    Map<String, Object> result;
    try {
      result = (await _vmService.callServiceExtension(
        'ext.callTest',
        // isolateId: _testIsolateRef.id,
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
