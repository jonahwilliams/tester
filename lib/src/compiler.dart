// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:uuid/uuid.dart';

import 'config.dart';
import 'test_info.dart';

const _kVmTestMain = r'''
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:developer';

Future<Map<String, Object>> executeTest(String name, String libraryUri) async {
  var testFunction = testRegistry[libraryUri][name];

  var passed = false;
  dynamic error;
  dynamic stackTrace;
  try {
    await Future(() => testFunction());
    passed = true;
  } catch (err, st) {
    error = err;
    stackTrace = st;
  } finally {
    return <String, Object>{
      'test': name,
      'passed': passed,
      'timeout': false,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
    };
  }
}

Future<void> main() {
  registerExtension('ext.callTest', (String request, Map<String, String> args) async {
    var test = args['test'];
    var library = args['library'];
    final result = await executeTest(test, library);
    return ServiceExtensionResponse.result(json.encode(result));
  });
  stdin.listen((_) { });
}
''';

const String _kFlutterWebTestMain = '''
import 'dart:convert';
import 'dart:async';
import 'dart:developer';
import 'dart:ui' as ui;

Future<Map<String, Object>> executeTest(String name, String libraryUri) async {
  var testFunction = testRegistry[libraryUri][name];

  var passed = false;
  dynamic error;
  dynamic stackTrace;
  try {
    await Future(() => testFunction());
    passed = true;
  } catch (err, st) {
    error = err;
    stackTrace = st;
  } finally {
    return <String, Object>{
      'test': name,
      'passed': passed,
      'timeout': false,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
    };
  }
}

Future<void> main() async {
  registerExtension('ext.callTest', (String request, Map<String, String> args) async {
    var test = args['test'];
    var library = args['library'];
    final result = await executeTest(test, library);
    return ServiceExtensionResponse.result(json.encode(result));
  });
  await ui.webOnlyInitializePlatform();
}

''';

/// Abstraction for the frontend_server compiler process.
///
/// The frontend_server communicates to this tool over stdin and stdout.
class Compiler {
  Compiler({
    @required this.config,
    @required this.compilerMode,
  });

  final Config config;
  final TargetPlatform compilerMode;

  List<Uri> _dependencies;
  DateTime _lastCompiledTime;
  StdoutHandler _stdoutHandler;
  Process _frontendServer;
  File _mainFile;

  DateTime get lastCompiled => _lastCompiledTime;

  List<Uri> get dependencies => _dependencies;

  /// Generate the synthetic entrypoint and bootstrap the compiler.
  Future<Uri> start(Map<Uri, List<TestInfo>> testInformation) async {
    var workspace = Directory(config.workspacePath);
    if (!workspace.existsSync()) {
      workspace.createSync(recursive: true);
    }
    _mainFile = File(path.join(workspace.path, 'main.dart'));
    _regenerateMain(testInformation);

    var dillOutput =
        File(path.join(config.workspacePath, 'main.dart.dill')).absolute;

    _stdoutHandler = StdoutHandler();
    var packagesUri = File(path.join(config.packageRootPath, '.packages')).uri;
    var args = <String>[
      config.frontendServerPath,
      ..._getArgsForCompilerMode,
      '--enable-asserts',
      '--packages=$packagesUri',
      '--no-link-platform',
      '--output-dill=${dillOutput.path}',
      '--incremental',
      '--filesystem-root',
      Directory(config.workspacePath).absolute.path,
      '--filesystem-root',
      path.join(config.packageRootPath, 'test'),
      '--filesystem-scheme',
      'org-dartlang-app',
    ];
    _frontendServer = await Process.start(config.dartPath, args);
    _frontendServer.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(print);
    _frontendServer.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen(_stdoutHandler.handler);
    _frontendServer.stdin.writeln('compile org-dartlang-app:///main.dart');
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
    _regenerateMain(testInformation);
    _stdoutHandler.reset();
    var pendingResult = _stdoutHandler.compilerOutput.future;
    var id = Uuid().v4();
    _frontendServer.stdin
        .writeln('recompile org-dartlang-app:///main.dart $id');

    for (var uri in invalidated) {
      var relativePath = path.relative(
        uri.toFilePath(),
        from: path.join(config.packageRootPath, 'test'),
      );
      _frontendServer.stdin.writeln('org-dartlang-app:///$relativePath');
    }
    _frontendServer.stdin.writeln('org-dartlang-app:///main.dart');
    _frontendServer.stdin.writeln(id);
    var result = await pendingResult;
    if (result.errorCount != 0) {
      _frontendServer.stdin.writeln('reset');
      return null;
    }
    _frontendServer.stdin.writeln('accept');
    _lastCompiledTime = DateTime.now();
    _dependencies = result.sources;
    return File(result.outputFilename).absolute.uri;
  }

  List<String> get _getArgsForCompilerMode {
    switch (compilerMode) {
      case TargetPlatform.dart:
        return <String>[
          '--target=vm',
          '--sdk-root=${config.dartSdkRoot}',
          '--platform=${config.platformDillUri}',
          '--no-link-platform',
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
          '--platform=${config.platformDillUri}',
          '--no-link-platform',
          '--debugger-module-names',
        ];
      case TargetPlatform.flutterWeb:
        return <String>[
          '--target=dartdevc',
          '--sdk-root=${config.dartSdkRoot}',
          '--platform=${config.flutterWebPlatformDillUri}',
          '--no-link-platform',
          '--debugger-module-names',
        ];
    }
    throw StateError('_compilerMode was null');
  }

  void _regenerateMain(Map<Uri, List<TestInfo>> testInformation) {
    var contents = StringBuffer();
    for (var testFileUri in testInformation.keys) {
      var relativePath = path.relative(
        testFileUri.toFilePath(),
        from: path.join(config.packageRootPath, 'test'),
      );
      contents.writeln('import "org-dartlang-app:///$relativePath";');
    }
    switch (compilerMode) {
      case TargetPlatform.dart:
        contents.write(_kVmTestMain);
        break;
      case TargetPlatform.web:
        contents.write(_kVmTestMain);
        break;
      case TargetPlatform.flutter:
        contents.write(_kVmTestMain);
        break;
      case TargetPlatform.flutterWeb:
        contents.write(_kFlutterWebTestMain);
        break;
    }
    contents.writeln('var testRegistry = {');
    for (var testFileUri in testInformation.keys) {
      contents.writeln('"${testFileUri}": {');
      for (var testInfo in testInformation[testFileUri]) {
        contents.writeln('"${testInfo.name}": ${testInfo.name},');
      }
      contents.writeln('},');
    }
    contents.writeln('};');
    _mainFile.writeAsStringSync(contents.toString());
  }

  void dispose() {
    _frontendServer.kill();
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
      var updatedAt = File(uri.toFilePath()).statSync().modified;
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
