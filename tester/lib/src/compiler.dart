// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';
import 'package:process/process.dart';
import 'package:tester/src/platform.dart';
import 'package:uuid/uuid.dart';

import 'config.dart';
import 'test_info.dart';

String generateVmTestMain(int timeout, bool testCompatMode) =>
    '''
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:developer';

Future<Map<String, dynamic>> executeTest(String name, String libraryUri) async {
  var libraryTests = testRegistry[libraryUri];
  if (libraryTests == null) {
     throw Exception();
  }
  var testFunction = libraryTests[name];
  if (testFunction == null) {
    throw Exception();
  }

  var passed = false;
  var timeout = false;
  dynamic error;
  dynamic stackTrace;
  try {
''' +
    ((timeout == -1)
        ? 'await Future(() => testFunction());'
        : 'await Future(() => testFunction()).timeout(const Duration(seconds: $timeout));') +
    '''
    passed = true;
  } catch (err, st) {
    error = err;
    stackTrace = st;
    if (err is TimeoutException) {
      timeout = true;
    }
  } finally {
    return {
      'test': name,
      'passed': passed,
      'timeout': timeout,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    };
  }
}

main() async {
  var zone = Zone.current.fork(
    specification: ZoneSpecification(
      print: (self, parent, zone, line) {
        log(line);
      },
      handleUncaughtError: (self, parent, zone, error, stackTrace) {
        log('UNHANDLED EXCEPTION: \$error\\n\$stackTrace\\n');
      },
    ),
  );
  registerExtension('ext.callTest', (String request, Map<String, String> args) async {
    var test = args['test'];
    var library = args['library'];
    if (library == null || test == null) {
      return ServiceExtensionResponse.result(json.encode({}));
    }
    final result = await zone.run(() => executeTest(test, library));
    return ServiceExtensionResponse.result(json.encode(result));
  });
  while (true) {
    await Future.delayed(const Duration(hours: 1));
  }
}
''';

String generateFlutterWebTestMain(int timeout, bool testCompatMode) =>
    '''
import 'dart:convert';
import 'dart:async';
import 'dart:developer';
import 'dart:ui' as ui;

Future<Map<String, dynamic>> executeTest(String name, String libraryUri) async {
  var libraryTests = testRegistry[libraryUri];
  if (libraryTests == null) {
     throw Exception();
  }
  var testFunction = libraryTests[name];
  if (testFunction == null) {
    throw Exception();
  }

  var passed = false;
  var timeout = false;
  dynamic error;
  dynamic stackTrace;
  try {
''' +
    ((timeout == -1)
        ? 'await Future(() => testFunction());'
        : 'await Future(() => testFunction()).timeout(const Duration(seconds: $timeout));') +
    '''
    await Future(() => testFunction());
    passed = true;
  } catch (err, st) {
    error = err;
    stackTrace = st;
    if (err is TimeoutException) {
      timeout = true;
    }
  } finally {
    return {
      'test': name,
      'passed': passed,
      'timeout': timeout,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    };
  }
}

main() async {
  ui.debugEmulateFlutterTesterEnvironment = true;
  await ui.webOnlyInitializePlatform();
  (ui.window as dynamic).debugOverrideDevicePixelRatio(3.0);
  (ui.window as dynamic).webOnlyDebugPhysicalSizeOverride = const ui.Size(2400, 1800);

  registerExtension('ext.callTest', (String request, Map<String, String> args) async {
    var test = args['test'];
    var library = args['library'];
    if (library == null || test == null) {
      return ServiceExtensionResponse.result(json.encode({}));
    }
    final result = await executeTest(test, library);
    return ServiceExtensionResponse.result(json.encode(result));
  });
}

''';

String generateWebTestMain(int timeout, bool testCompatMode) =>
    '''
import 'dart:convert';
import 'dart:async';
import 'dart:developer';

Future<Map<String, dynamic>> executeTest(String name, String libraryUri) async {
  var libraryTests = testRegistry[libraryUri];
  if (libraryTests == null) {
     throw Exception();
  }
  var testFunction = libraryTests[name];
  if (testFunction == null) {
    throw Exception();
  }

  var passed = false;
  var timeout = false;
  dynamic error;
  dynamic stackTrace;
  try {
''' +
    ((timeout == -1)
        ? 'await Future(() => testFunction());'
        : 'await Future(() => testFunction()).timeout(const Duration(seconds: $timeout));') +
    '''
    await Future(() => testFunction());
    passed = true;
  } catch (err, st) {
    error = err;
    stackTrace = st;
    if (err is TimeoutException) {
      timeout = true;
    }
  } finally {
    return {
      'test': name,
      'passed': passed,
      'timeout': timeout,
      'error': error.toString(),
      'stackTrace': stackTrace.toString(),
    };
  }
}

main() async {
  registerExtension('ext.callTest', (String request, Map<String, String> args) async {
    var test = args['test'];
    var library = args['library'];
    if (library == null || test == null) {
      return ServiceExtensionResponse.result(json.encode({}));
    }
    final result = await executeTest(test, library);
    return ServiceExtensionResponse.result(json.encode(result));
  });
}

''';

final String testCompatHeader = r'''
import 'dart:async';

// ignore_for_file: implementation_imports
import 'package:test_api/src/backend/declarer.dart';
import 'package:test_api/src/backend/group.dart';
import 'package:test_api/src/backend/group_entry.dart';
import 'package:test_api/src/backend/test.dart';
import 'package:test_api/src/backend/suite.dart';
import 'package:test_api/src/backend/live_test.dart';
import 'package:test_api/src/backend/suite_platform.dart';
import 'package:test_api/src/backend/runtime.dart';
import 'package:test_api/src/backend/message.dart';
import 'package:test_api/src/backend/invoker.dart';
import 'package:test_api/src/backend/state.dart';
''';

final String testCompatFooter = r'''
Future<void> testCompat(FutureOr<void> Function() testFunction) async {
  var declarer = Declarer();
  var innerZone = Zone.current.fork(zoneValues: {#test.declarer: declarer});
  String errors;
  await innerZone.run(() async {
    await Invoker.guard<Future<void>>(() async {
      final _Reporter reporter = _Reporter();
      await testFunction();
      final Group group = declarer.build();
      final Suite suite = Suite(group, SuitePlatform(Runtime.vm));
      await _runGroup(suite, group, <Group>[], reporter);
      errors = reporter._onDone();
    });
  });
  if (errors != null) {
    throw Exception(errors);
  }
}

Future<void> _runGroup(Suite suiteConfig, Group group, List<Group> parents,
    _Reporter reporter) async {
  parents.add(group);
  try {
    final bool skipGroup = group.metadata.skip;
    bool setUpAllSucceeded = true;
    if (!skipGroup && group.setUpAll != null) {
      final LiveTest liveTest =
          group.setUpAll.load(suiteConfig, groups: parents);
      await _runLiveTest(suiteConfig, liveTest, reporter, countSuccess: false);
      setUpAllSucceeded = liveTest.state.result.isPassing;
    }
    if (setUpAllSucceeded) {
      for (final GroupEntry entry in group.entries) {
        if (entry is Group) {
          await _runGroup(suiteConfig, entry, parents, reporter);
        } else if (entry.metadata.skip) {
          await _runSkippedTest(suiteConfig, entry as Test, parents, reporter);
        } else {
          final Test test = entry as Test;
          await _runLiveTest(
              suiteConfig, test.load(suiteConfig, groups: parents), reporter);
        }
      }
    }
    // Even if we're closed or setUpAll failed, we want to run all the
    // teardowns to ensure that any state is properly cleaned up.
    if (!skipGroup && group.tearDownAll != null) {
      final LiveTest liveTest =
          group.tearDownAll.load(suiteConfig, groups: parents);
      await _runLiveTest(suiteConfig, liveTest, reporter, countSuccess: false);
    }
  } finally {
    parents.remove(group);
  }
}

Future<void> _runLiveTest(
    Suite suiteConfig, LiveTest liveTest, _Reporter reporter,
    {bool countSuccess = true}) async {
  reporter._onTestStarted(liveTest);
  await null;
  await liveTest.run();

  // Once the test finishes, use await null to do a coarse-grained event
  // loop pump to avoid starving non-microtask events.
  await null;
  final bool isSuccess = liveTest.state.result.isPassing;
  if (isSuccess) {
    reporter.passed.add(liveTest);
  } else {
    reporter.failed.add(liveTest);
  }
}

Future<void> _runSkippedTest(Suite suiteConfig, Test test, List<Group> parents,
    _Reporter reporter) async {
  final LocalTest skipped =
      LocalTest(test.name, test.metadata, () {}, trace: test.trace);
  final LiveTest liveTest = skipped.load(suiteConfig);
  reporter._onTestStarted(liveTest);
  reporter.skipped.add(skipped);
}

class _Reporter {
  final passed = <LiveTest>[];
  final failed = <LiveTest>[];
  final skipped = <Test>[];

  /// The set of all subscriptions to various streams.
  final Set<StreamSubscription<void>> _subscriptions =
      <StreamSubscription<void>>{};

  final failedErrors = <LiveTest, List<dynamic>>{};
  final failedStackTraces = <LiveTest, List<dynamic>>{};

  /// A callback called when the engine begins running [liveTest].
  void _onTestStarted(LiveTest liveTest) {
    _subscriptions.add(liveTest.onStateChange
        .listen((State state) => _onStateChange(liveTest, state)));
    _subscriptions.add(liveTest.onError.listen((AsyncError error) =>
        _onError(liveTest, error.error, error.stackTrace)));
    _subscriptions.add(liveTest.onMessage.listen((Message message) {
      print(message.text);
    }));
  }

  void _onStateChange(LiveTest liveTest, State state) {
    if (state.status != Status.complete) {
      return;
    }
  }

  void _onError(LiveTest liveTest, Object error, StackTrace stackTrace) {
    (failedErrors[liveTest] ??= <dynamic>[]).add(error);
    (failedStackTraces[liveTest] ??= <dynamic>[]).add(stackTrace);
  }

  /// A callback called when the engine is finished running tests.
  ///
  /// [success] will be `true` if all tests passed, `false` if some tests
  /// failed, and `null` if the engine was closed prematurely.
  String _onDone() {
    if (failed.isNotEmpty) {
      var buffer = StringBuffer();
      for (var fail in failed) {
        buffer.write(_description(fail));
        var errors = failedErrors[fail] ?? <dynamic>[];
        for (var i = 0; i < errors.length; i++) {
          buffer.writeln(errors[i]);
          buffer.write('  ');
          buffer.writeln(failedStackTraces[fail][i]);
        }
      }
      return buffer.toString();
    }
    return null;
  }

  /// Returns a description of [liveTest].
  ///
  /// This differs from the test's own description in that it may also include
  /// the suite's name.
  String _description(LiveTest liveTest) {
    String name = liveTest.test.name;
    if (liveTest.suite.path != null) {
      name = '${liveTest.suite.path}: $name';
    }
    return name;
  }
}
''';

/// Abstraction for the frontend_server compiler process.
///
/// The frontend_server communicates to this tool over stdin and stdout.
class Compiler implements ExpressionCompiler {
  Compiler({
    @required this.config,
    @required this.compilerMode,
    @required this.timeout,
    @required this.enabledExperiments,
    @required this.soundNullSafety,
    @required this.testCompatMode,
    @required this.workspacePath,
    @required this.packagesRootPath,
    @required this.packagesUri,
    @required PackageConfig packageConfig,
    this.fileSystem = const LocalFileSystem(),
    this.processManager = const LocalProcessManager(),
    this.platform = const LocalPlatform(),
  }) : _packageConfig = packageConfig;

  final FileSystem fileSystem;
  final ProcessManager processManager;
  final Config config;
  final TargetPlatform compilerMode;
  final Platform platform;
  final int timeout;
  final List<String> enabledExperiments;
  final bool soundNullSafety;
  final bool testCompatMode;
  final String workspacePath;
  final String packagesRootPath;
  final Uri packagesUri;

  List<Uri> _dependencies;
  DateTime _lastCompiledTime;
  StdoutHandler _stdoutHandler;
  Process _frontendServer;
  File _mainFile;
  final PackageConfig _packageConfig;

  DateTime get lastCompiled => _lastCompiledTime;

  List<Uri> get dependencies => _dependencies;

  /// Generate the synthetic entrypoint and bootstrap the compiler.
  Future<Uri> start(TestInfos testInfos) async {
    var workspace = fileSystem.directory(workspacePath);
    if (!workspace.existsSync()) {
      workspace.createSync(recursive: true);
    }
    var package = testInfos.testInformation.isNotEmpty
        ? _packageConfig.packageOf(testInfos.testInformation.keys.first)
        : null;

    _mainFile =
        fileSystem.file(fileSystem.path.join(workspace.path, 'main.dart'));
    _regenerateMain(testInfos.testInformation, timeout, package);

    var dillOutput = fileSystem
        .file(fileSystem.path
            .join(workspacePath, 'main.${compilerMode}.dart.dill'))
        .absolute;

    _stdoutHandler = StdoutHandler();

    var args = <String>[
      config.dartPath,
      '--disable-dart-dev',
      config.frontendServerPath,
      ..._getArgsForCompilerMode,
      '--enable-asserts',
      '--packages=$packagesUri',
      '--no-link-platform',
      '--output-dill=${dillOutput.path}',
      '--incremental',
      '--filesystem-root',
      fileSystem.file(workspacePath).parent.absolute.path,
      '--filesystem-root',
      fileSystem.path.join(packagesRootPath),
      '--filesystem-scheme',
      'org-dartlang-app',
      if (soundNullSafety == true) '--null-safety',
      if (soundNullSafety == false) '--no-null-safety',
      for (var experiment in enabledExperiments)
        '--enable-experiment=$experiment',
    ];
    _frontendServer = await processManager.start(args);
    _frontendServer.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(print);
    _frontendServer.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_stdoutHandler.handler);
    _frontendServer.stdin
        .writeln('compile org-dartlang-app:///tester/main.dart');
    var result = await _stdoutHandler.compilerOutput.future;
    if (result.errorCount != 0) {
      return null;
    }
    _frontendServer.stdin.writeln('accept');
    _lastCompiledTime = DateTime.now();
    _dependencies = result.sources;
    return dillOutput.uri;
  }

  Future<Uri> recompile(
    List<Uri> invalidated,
    Map<Uri, List<TestInfo>> testInformation,
  ) async {
    var package = testInformation.isNotEmpty
        ? _packageConfig.packageOf(testInformation.keys.first)
        : null;
    _regenerateMain(testInformation, timeout, package);
    _stdoutHandler.reset();
    var pendingResult = _stdoutHandler.compilerOutput.future;
    var id = Uuid().v4();
    _frontendServer.stdin
        .writeln('recompile org-dartlang-app:///tester/main.dart $id');

    for (var uri in invalidated) {
      var relativePath = fileSystem
          .file(fileSystem.path.relative(
            uri.toFilePath(windows: platform.isWindows),
            from: packagesRootPath,
          ))
          .uri;
      _frontendServer.stdin.writeln('org-dartlang-app:///$relativePath');
    }
    _frontendServer.stdin.writeln('org-dartlang-app:///tester/main.dart');
    _frontendServer.stdin.writeln(id);
    var result = await pendingResult;
    if (result.errorCount != 0) {
      _frontendServer.stdin.writeln('reset');
      return null;
    }
    _frontendServer.stdin.writeln('accept');
    _lastCompiledTime = DateTime.now();
    _dependencies = result.sources;
    return fileSystem.file(result.outputFilename).absolute.uri;
  }

  List<String> get _getArgsForCompilerMode {
    switch (compilerMode) {
      case TargetPlatform.dart:
        return <String>[
          '--target=vm',
          '--sdk-root=${config.dartSdkRoot}',
          '--platform=${config.platformDillUri}',
        ];
      case TargetPlatform.flutter:
        return <String>[
          '--target=flutter',
          '--sdk-root=${config.flutterPatchedSdkRoot}',
          '-Ddart.vm.profile=false',
          '-Ddart.vm.product=false',
          '--track-widget-creation',
        ];
      case TargetPlatform.web:
        return <String>[
          '--target=dartdevc',
          '--sdk-root=${config.dartSdkRoot}',
          '--platform=${config.dartWebPlatformDillUri}',
          '--debugger-module-names',
        ];
      case TargetPlatform.flutterWeb:
        return <String>[
          '--target=dartdevc',
          '-Ddart.vm.profile=false',
          '-Ddart.vm.product=false',
          '--sdk-root=${config.dartSdkRoot}',
          '--platform=${config.flutterWebPlatformDillUri}',
          '--debugger-module-names',
          '--track-widget-creation',
        ];
    }
    throw StateError('_compilerMode was null');
  }

  void _regenerateMain(
      Map<Uri, List<TestInfo>> testInformation, int timeout, Package package) {
    var contents = StringBuffer();
    var langaugeVersion = package != null
        ? '// @dart=${package.languageVersion.major}'
            '.${package.languageVersion.minor}'
        : '';
    contents.writeln(langaugeVersion);
    var importNumber = 0;
    var importNumbers = <Uri, int>{};
    for (var testFileUri in testInformation.keys) {
      importNumbers[testFileUri] = importNumber;
      var relativePath = fileSystem
          .file(fileSystem.path.relative(
            testFileUri.toFilePath(windows: platform.isWindows),
            from: packagesRootPath,
          ))
          .uri;
      contents.writeln(
          'import "org-dartlang-app:///$relativePath" as i$importNumber;');
      importNumber += 1;
    }
    if (testCompatMode) {
      contents.writeln(testCompatHeader);
    }
    switch (compilerMode) {
      case TargetPlatform.dart:
        contents.write(generateVmTestMain(
          timeout,
          testCompatMode,
        ));
        break;
      case TargetPlatform.web:
        contents.write(generateWebTestMain(
          timeout,
          testCompatMode,
        ));
        break;
      case TargetPlatform.flutter:
        contents.write(generateVmTestMain(
          timeout,
          testCompatMode,
        ));
        break;
      case TargetPlatform.flutterWeb:
        contents.write(generateFlutterWebTestMain(
          timeout,
          testCompatMode,
        ));
        break;
    }
    if (testCompatMode) {
      contents.writeln(testCompatFooter);
    }
    contents.writeln('var testRegistry = {');
    for (var testFileUri in testInformation.keys) {
      contents.writeln('"${testFileUri}": {');
      for (var testInfo in testInformation[testFileUri]) {
        if (testInfo.compatTest) {
          contents.writeln(
            '"${testInfo.name}": '
            '() => testCompat(i${importNumbers[testFileUri]}.${testInfo.name}),',
          );
        } else {
          contents.writeln(
            '"${testInfo.name}": '
            'i${importNumbers[testFileUri]}.${testInfo.name},',
          );
        }
      }
      contents.writeln('},');
    }
    contents.writeln('};');
    _mainFile.writeAsStringSync(contents.toString());
  }

  void dispose() {
    _frontendServer.kill();
  }

  /// An expression compilation service to provide the flutter_tester with debugger
  /// support.
  Future<String> compileExpression(
    String isolateId,
    String expression,
    List<String> definitions,
    List<String> typeDefinitions,
    String libraryUri,
    String klass,
    bool isStatic,
  ) async {
    _stdoutHandler.reset(suppressCompilerMessages: true, expectSources: false);

    // 'compile-expression' should be invoked after compiler has been started,
    // program was compiled.
    if (_frontendServer == null) {
      return null;
    }

    var inputKey = Uuid().v4();
    _frontendServer.stdin
      ..writeln('compile-expression $inputKey')
      ..writeln(expression);
    definitions?.forEach(_frontendServer.stdin.writeln);
    _frontendServer.stdin.writeln(inputKey);
    typeDefinitions?.forEach(_frontendServer.stdin.writeln);
    _frontendServer.stdin
      ..writeln(inputKey)
      ..writeln(libraryUri ?? '')
      ..writeln(klass ?? '')
      ..writeln(isStatic ?? false);

    var compilerOutput = await _stdoutHandler.compilerOutput.future;
    if (compilerOutput != null && compilerOutput.outputFilename != null) {
      return base64.encode(
          fileSystem.file(compilerOutput.outputFilename).readAsBytesSync());
    }
    throw Exception('Failed to compile: "$expression"');
  }

  /// Expression compilation service to provide the web and flutter_web platforms
  /// with debugger support via dwds.
  Future<ExpressionCompilationResult> compileExpressionToJs(
    String isolateId,
    String libraryUri,
    int line,
    int column,
    Map<String, String> jsModules,
    Map<String, String> jsFrameValues,
    String moduleName,
    String expression,
  ) async {
    _stdoutHandler.reset(suppressCompilerMessages: true, expectSources: false);

    // 'compile-expression-to-js' should be invoked after compiler has been started,
    // program was compiled.
    if (_frontendServer == null) {
      return null;
    }

    var inputKey = Uuid().v4();
    _frontendServer.stdin
      ..writeln('compile-expression-to-js $inputKey')
      ..writeln(libraryUri ?? '')
      ..writeln(line)
      ..writeln(column);
    jsModules?.forEach((String k, String v) {
      _frontendServer.stdin.writeln('$k:$v');
    });
    _frontendServer.stdin.writeln(inputKey);
    jsFrameValues?.forEach((String k, String v) {
      _frontendServer.stdin.writeln('$k:$v');
    });
    _frontendServer.stdin
      ..writeln(inputKey)
      ..writeln(moduleName ?? '')
      ..writeln(expression ?? '');

    var compilerOutput = await _stdoutHandler.compilerOutput.future;
    if (compilerOutput != null && compilerOutput.outputFilename != null) {
      var content = utf8.decode(
          fileSystem.file(compilerOutput.outputFilename).readAsBytesSync());
      return ExpressionCompilationResult(
          content, compilerOutput.errorCount > 0);
    }

    return ExpressionCompilationResult(
        'InternalError: frontend server failed to compile \'$expression\'',
        true);
  }
}

enum StdoutState {
  CollectDiagnostic,
  CollectDependencies,
}

class StdoutHandler {
  StdoutHandler({this.consumer = print}) {
    reset();
  }

  bool compilerMessageReceived = false;
  final void Function(String) consumer;
  String boundaryKey;
  StdoutState state = StdoutState.CollectDiagnostic;
  Completer<CompilerOutput> compilerOutput;
  final List<Uri> sources = <Uri>[];

  bool _suppressCompilerMessages;
  bool _expectSources = true;

  void handler(String message) {
    const kResultPrefix = 'result ';
    if (boundaryKey == null && message.startsWith(kResultPrefix)) {
      boundaryKey = message.substring(kResultPrefix.length);
      return;
    }
    if (message.startsWith(boundaryKey)) {
      if (_expectSources) {
        if (state == StdoutState.CollectDiagnostic) {
          state = StdoutState.CollectDependencies;
          return;
        }
      }
      if (message.length <= boundaryKey.length) {
        compilerOutput.complete(null);
        return;
      }
      var spaceDelimiter = message.lastIndexOf(' ');
      compilerOutput.complete(CompilerOutput(
          message.substring(boundaryKey.length + 1, spaceDelimiter),
          int.parse(message.substring(spaceDelimiter + 1).trim()),
          sources));
      return;
    }
    if (state == StdoutState.CollectDiagnostic) {
      if (!_suppressCompilerMessages) {
        if (compilerMessageReceived == false) {
          consumer('\nCompiler message:');
          compilerMessageReceived = true;
        }
        consumer(message);
      }
    } else {
      assert(state == StdoutState.CollectDependencies);
      switch (message[0]) {
        case '+':
          sources.add(Uri.parse(message.substring(1)));
          break;
        case '-':
          sources.remove(Uri.parse(message.substring(1)));
          break;
        default:
      }
    }
  }

  // This is needed to get ready to process next compilation result output,
  // with its own boundary key and new completer.
  void reset(
      {bool suppressCompilerMessages = false, bool expectSources = true}) {
    boundaryKey = null;
    compilerMessageReceived = false;
    compilerOutput = Completer<CompilerOutput>();
    _suppressCompilerMessages = suppressCompilerMessages;
    _expectSources = expectSources;
    state = StdoutState.CollectDiagnostic;
  }
}

class CompilerOutput {
  const CompilerOutput(
    this.outputFilename,
    this.errorCount,
    this.sources,
  );

  final String outputFilename;
  final int errorCount;
  final List<Uri> sources;
}

class ProjectFileInvalidator {
  ProjectFileInvalidator({
    this.fileSystem = const LocalFileSystem(),
    this.platform = const LocalPlatform(),
  });

  final FileSystem fileSystem;
  final Platform platform;

  static const _pubCachePathLinuxAndMac = '.pub-cache';

  Future<List<Uri>> findInvalidated({
    @required DateTime lastCompiled,
    @required List<Uri> urisToMonitor,
    @required Uri packagesUri,
  }) async {
    if (lastCompiled == null) {
      assert(urisToMonitor.isEmpty);
      return <Uri>[];
    }
    var urisToScan = <Uri>[
      // Don't watch pub cache directories to speed things up a little.
      for (var uri in urisToMonitor)
        if (_isNotInPubCache(uri)) uri,

      // We need to check the .packages file too since it is not used in compilation.
      packagesUri,
    ];
    var invalidatedFiles = <Uri>[];
    for (var uri in urisToScan) {
      var updatedAt = fileSystem
          .file(uri.toFilePath(windows: platform.isWindows))
          .statSync()
          .modified;
      if (updatedAt != null && updatedAt.isAfter(lastCompiled)) {
        invalidatedFiles.add(uri);
      }
    }
    return invalidatedFiles;
  }

  bool _isNotInPubCache(Uri uri) {
    return !uri.path.contains(_pubCachePathLinuxAndMac);
  }
}
