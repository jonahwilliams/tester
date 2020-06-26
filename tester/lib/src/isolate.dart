// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:vm_service/vm_service.dart';
import 'package:vm_service/vm_service_io.dart';

import 'runner.dart';
import 'test_info.dart';
import 'web_runner.dart';

/// Typedef for inject expression compilation function.
///
/// This is used by the flutter_tester device, since it does not
/// have a kernel service to translate source for debuggers.
typedef CompileExpression = Future<String> Function(
  String isolateId,
  String expression,
  List<String> definitions,
  List<String> typeDefinitions,
  String libraryUri,
  String klass,
  bool isStatic,
);

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

  /// The active vm service instance for this runner.
  VmService get vmService;

  /// An http or ws address for external debuggers to connect to.
  Uri get vmServiceAddress;
}

/// The isolate under test and manager of the [TestRunner] lifecycle.
class VmTestIsolate extends TestIsolate {
  VmTestIsolate({
    @required TestRunner testRunner,
    @required CompileExpression compileExpression,
  })  : _testRunner = testRunner,
        _compileExpression = compileExpression;

  final TestRunner _testRunner;
  final CompileExpression _compileExpression;
  IsolateRef _testIsolateRef;
  VmService _vmService;

  @override
  Future<void> start(Uri entrypoint, void Function() onExit) async {
    var launchResult = await _testRunner.start(entrypoint, onExit);
    vmServiceAddress = launchResult.serviceUri;
    var websocketUrl =
        launchResult.serviceUri.replace(scheme: 'ws').toString() + 'ws';
    _vmService = await vmServiceConnectUri(websocketUrl);

    var vm = await _vmService.getVM();
    _testIsolateRef = vm.isolates.firstWhere(
        (element) => element.name.contains(launchResult.isolateName));
    var isolate = await _vmService.getIsolate(_testIsolateRef.id);
    if (isolate.pauseEvent == null ||
        (isolate.pauseEvent.kind != EventKind.kResume &&
            isolate.pauseEvent.kind != EventKind.kNone)) {
      await _vmService.resume(isolate.id);
    }
    await _registerExpressionCompilation();
    await Future.wait([
      _vmService.streamListen(EventStreams.kLogging),
    ]);
    void decodeMessage(Event event) {
      print(event.logRecord.message.valueAsString);
    }

    _vmService.onLoggingEvent.listen(decodeMessage);
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
    } on RPCError catch (err, st) {
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

  @override
  VmService get vmService => _vmService;

  @override
  Uri vmServiceAddress;

  Future<void> _registerExpressionCompilation() async {
    if (_compileExpression == null) {
      return;
    }
    vmService.registerServiceCallback('compileExpression',
        (Map<String, dynamic> params) async {
      var isolateId =
          _validateRpcStringParam('compileExpression', params, 'isolateId');
      var expression =
          _validateRpcStringParam('compileExpression', params, 'expression');
      var definitions =
          List<String>.from(params['definitions'] as List<dynamic>);
      var typeDefinitions =
          List<String>.from(params['typeDefinitions'] as List<dynamic>);
      var libraryUri = params['libraryUri'] as String;
      var klass = params['klass'] as String;
      var isStatic =
          _validateRpcBoolParam('compileExpression', params, 'isStatic');

      final String kernelBytesBase64 = await _compileExpression(
        isolateId,
        expression,
        definitions,
        typeDefinitions,
        libraryUri,
        klass,
        isStatic,
      );
      return <String, dynamic>{
        'type': 'Success',
        'result': <String, dynamic>{'kernelBytes': kernelBytesBase64},
      };
    });
    vmService.registerService('compileExpression', 'Tester');
  }
}

class WebTestIsolate extends TestIsolate {
  WebTestIsolate({
    @required this.testRunner,
  });

  final ChromeTestRunner testRunner;
  VmService _vmService;
  IsolateRef _testIsolateRef;

  @override
  Future<void> start(Uri entrypoint, void Function() onExit) async {
    var codeFile = File(entrypoint.toFilePath() + '.sources');
    var manifestFile = File(entrypoint.toFilePath() + '.json');
    var sourceMapFile = File(entrypoint.toFilePath() + '.map');

    testRunner.updateCode(codeFile, manifestFile, sourceMapFile);

    var runnerStartResult = await testRunner.start(entrypoint, onExit);
    vmServiceAddress = runnerStartResult.serviceUri;
    _vmService = testRunner.vmService;
    var vm = await _vmService.getVM();
    _testIsolateRef = vm.isolates.first;
    await _waitForExtension(_testIsolateRef);

    await Future.wait([
      _vmService.streamListen(EventStreams.kStdout),
      _vmService.streamListen(EventStreams.kStderr),
    ]);
    void decodeMessage(Event event) {
      var message = utf8.decode(base64.decode(event.bytes));
      print(message);
    }

    _vmService.onStdoutEvent.listen(decodeMessage);
    _vmService.onStderrEvent.listen(decodeMessage);
  }

  @override
  FutureOr<void> dispose() async {
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
        isolateId: _testIsolateRef.id,
        args: <String, String>{
          'test': testInfo.name,
          'library': testInfo.testFileUri.toString(),
        },
      ))
          .json;
    } on RPCError catch (err, st) {
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
  VmService get vmService => _vmService;

  @override
  Uri vmServiceAddress;

  Future<void> _waitForExtension(IsolateRef isolateRef) async {
    final Completer<void> completer = Completer<void>();
    await vmService.streamListen(EventStreams.kExtension);
    vmService.onExtensionEvent.listen((Event event) {
      if (event.json['extensionKind'] == 'Flutter.FrameworkInitialization') {
        completer.complete();
      }
    });
    final Isolate isolate = await vmService.getIsolate(isolateRef.id);
    if (isolate.extensionRPCs.contains('ext.callTest')) {
      return isolate;
    }
    await completer.future;
    return isolate;
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

/// The error codes for the JSON-RPC standard.
///
/// See also: https://www.jsonrpc.org/specification#error_object
abstract class RPCErrorCodes {
  /// The method does not exist or is not available.
  static const int kMethodNotFound = -32601;

  /// Invalid method parameter(s), such as a mismatched type.
  static const int kInvalidParams = -32602;

  /// Internal JSON-RPC error.
  static const int kInternalError = -32603;

  /// Application specific error codes.
  static const int kServerError = -32000;
}

String _validateRpcStringParam(
    String methodName, Map<String, dynamic> params, String paramName) {
  final dynamic value = params[paramName];
  if (value is! String || (value as String).isEmpty) {
    throw RPCError(
      methodName,
      RPCErrorCodes.kInvalidParams,
      "Invalid '$paramName': $value",
    );
  }
  return value as String;
}

bool _validateRpcBoolParam(
    String methodName, Map<String, dynamic> params, String paramName) {
  final dynamic value = params[paramName];
  if (value != null && value is! bool) {
    throw RPCError(
      methodName,
      RPCErrorCodes.kInvalidParams,
      "Invalid '$paramName': $value",
    );
  }
  return (value as bool) ?? false;
}
