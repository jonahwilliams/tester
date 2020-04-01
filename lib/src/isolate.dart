// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

import 'package:meta/meta.dart';
import 'package:tester/src/runner.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service;

/// The isolate under test and manager of the [TestRunner] lifecycle.
class TestIsolate {
  TestIsolate({
    @required TestRunner testRunner,
  }) : _testRunner = testRunner;

  final TestRunner _testRunner;
  final _libraries = <String, vm_service.Library>{};
  final _pendingTests = <String, Completer<Map<dynamic, dynamic>>>{};
  vm_service.Library _mainLibrary;
  vm_service.IsolateRef _testIsolateRef;
  vm_service.VmService _vmService;
  StreamSubscription<void> _extensionSubscription;

  /// Start the test isolate.
  Future<void> start(String entrypoint, void Function() onExit) async {
    var serviceUrl = await _testRunner.start(entrypoint, onExit);
    var websocketUrl = serviceUrl.replace(scheme: 'ws').toString() + 'ws';
    _vmService = await vm_service.vmServiceConnectUri(websocketUrl);

    // TODO: support multiple test isolates using the same VM.
    var vm = await _vmService.getVM();
    _testIsolateRef = vm.isolates.single;

    await _reloadLibraries();
    await _vmService.streamListen('Extension');
    _extensionSubscription = _vmService.onExtensionEvent.listen((event) {
      var data = event.extensionData.data;
      var testName = data['test'] as String;
      var completer = _pendingTests[testName];
      if (completer == null) {
        throw StateError('$testName completed but was unexpected.');
      }
      completer.complete(data);
    });
  }

  /// Tear down the test isolate.
  FutureOr<void> dispose() {
    _extensionSubscription.cancel();
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
      for (var functionRef in libraryEntry.value.functions) {
        if (functionRef.name.startsWith('test')) {
          pending.add(runTest(functionRef.name, libraryEntry.key).then((result) {
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

    var completer =
        _pendingTests[testName] = Completer<Map<dynamic, dynamic>>();
    await _vmService.evaluate(
      _testIsolateRef.id,
      _mainLibrary.id,
      'executeTest($testName, "$testName")',
    );

    return TestResult.fromMessage(
      await completer.future,
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
