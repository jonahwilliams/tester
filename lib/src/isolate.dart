// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service;

import 'runner.dart';

/// The isolate under test and manager of the [TestRunner] lifecycle.
class TestIsolate {
  TestIsolate({
    @required TestRunner testRunner,
  }) : _testRunner = testRunner;

  final TestRunner _testRunner;
  final _libraries = <String, vm_service.Library>{};
  vm_service.Library _mainLibrary;
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

    await _reloadLibraries();
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

  /// Runs all tests defined and streams the results.
  ///
  /// The order of test invocation is not currently defined.
  Stream<TestResult> runAllTests() {
    var controller = StreamController<TestResult>();
    var pending = <Future<void>>[];
    for (var libraryEntry in _libraries.entries) {
      if (!libraryEntry.key.endsWith('_test.dart')) {
        continue;
      }
      for (var functionRef in libraryEntry.value.functions) {
        if (!functionRef.isStatic) {
          continue;
        }
        if (functionRef.name.startsWith('test')) {
          pending
              .add(runTest(functionRef.name, libraryEntry.key).then((result) {
            controller.add(result);
          }));
        }
      }
    }
    Future.wait(pending).whenComplete(controller.close);
    return controller.stream;
  }

  /// Execute [testName] within [testLibrary].
  ///
  /// Throws an [Exception] if either the [testName] does not exist in the
  /// [testLibrary], or if the [testLibrary] does not exist.
  // This should cache the [Library] objects so that runAll is more efficient.
  Future<TestResult> runTest(String testName, String libraryUri) async {
    var testLibrary = _libraries[libraryUri];
    if (testLibrary == null) {
      throw Exception('No library $libraryUri defined');
    }

    var funcRef = testLibrary.functions
        .firstWhere((element) => element.name == testName, orElse: () => null);
    if (funcRef == null) {
      throw Exception('No test $testName defined');
    }

    Map<String, Object> result;
    try {
      result = (await _vmService.callServiceExtension(
        'ext.callTest',
        isolateId: _testIsolateRef.id,
        args: <String, String>{'test': testName, 'library': libraryUri},
      ))
          .json;
    } on vm_service.RPCError catch (err, st) {
      return TestResult(
        testFile: libraryUri,
        testName: '',
        passed: false,
        timeout: false,
        errorMessage: err.toString(),
        stackTrace: st.toString(),
      );
    }

    return TestResult.fromMessage(
      result,
      libraryUri,
    );
  }

  /// Reload the application with the incremental file defined at `incrementalDill`.
  Future<void> reload(Uri incrementalDill) async {
    await _vmService.reloadSources(
      _testIsolateRef.id,
      rootLibUri: incrementalDill.toString(),
    );
    await _reloadLibraries();
  }

  Future<void> _reloadLibraries() async {
    _libraries.clear();
    _mainLibrary = null;
    var scripts = await _vmService.getScripts(_testIsolateRef.id);
    for (var scriptRef in scripts.scripts) {
      var uri = Uri.parse(scriptRef.uri);
      if (uri.scheme == 'dart') {
        continue;
      }
      var script = await _vmService.getObject(
        _testIsolateRef.id,
        scriptRef.id,
      ) as vm_service.Script;
      var testLibrary = await _vmService.getObject(
        _testIsolateRef.id,
        script.library.id,
      ) as vm_service.Library;
      if (script.library.uri.endsWith('main.dart')) {
        _mainLibrary = testLibrary;
      }
      _libraries[script.library.uri] = testLibrary;
    }

    if (_mainLibrary == null) {
      throw StateError('no main library found');
    }
  }
}

/// The result of a test execution.
class TestResult {
  const TestResult({
    @required this.testFile,
    @required this.testName,
    @required this.passed,
    @required this.timeout,
    @required this.errorMessage,
    @required this.stackTrace,
  });

  /// Create a [TestResult] from the raw JSON [message].
  factory TestResult.fromMessage(
      Map<dynamic, dynamic> message, String testFile) {
    return TestResult(
      testFile: testFile,
      testName: message['test'] as String,
      passed: message['passed'] as bool,
      timeout: message['timeout'] as bool,
      errorMessage: message['error'] as String,
      stackTrace: message['stackTrace'] as String,
    );
  }

  /// The absolute file URI of the test.
  final String testFile;

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
