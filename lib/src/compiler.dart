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

const _testMain = r'''
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:developer';
import 'dart:mirrors';

Future<Map<String, Object>> executeTest(String name, String libraryUri) async {
  final mirrorSystem = currentMirrorSystem();
  final library = mirrorSystem.libraries[Uri.parse(libraryUri)];

  var passed = false;
  var timeout = false;
  dynamic error;
  dynamic stackTrace;
  try {
    await Future(() => library.invoke(Symbol(name), <dynamic>[]))
      .timeout(const Duration(seconds: 15));
    passed = true;
  } on TimeoutException {
    timeout = true;
  } catch (err, st) {
    error = err;
    stackTrace = st;
  } finally {
    return <String, Object>{
      'test': name,
      'passed': passed,
      'timeout': timeout,
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
  ProjectFileInvalidator _projectFileInvalidator;
  Process _frontendServer;
  File _mainFile;

  /// Generate the synthetic entrypoint and bootstrap the compiler.
  Future<Uri> start() async {
    var workspace = Directory(config.workspacePath);
    if (!workspace.existsSync()) {
      workspace.createSync(recursive: true);
    }
    _mainFile = File(path.join(workspace.path, 'main.dart'));
    var contents = StringBuffer();
    for (var testPath in config.tests) {
      contents.writeln('import "${testPath}";');
    }
    contents.write(_testMain);
    _mainFile.writeAsStringSync(contents.toString());

    var dillOutput =
        File(path.join(config.packageRootPath, 'main.dart.dill')).absolute;

    _stdoutHandler = StdoutHandler();
    _projectFileInvalidator = ProjectFileInvalidator();
    var packagesUri = File(path.join(config.packageRootPath, '.packages')).uri;
    var args = <String>[
      config.frontendServerPath,
      ..._getArgsForCompilerMode,
      '--enable-asserts',
      '--packages=$packagesUri',
      '--no-link-platform',
      '--output-dill=${dillOutput.path}',
      '--incremental',
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
    _frontendServer.stdin.writeln('compile ${_mainFile.absolute.uri}');
    var result = await _stdoutHandler.compilerOutput.future;
    if (result.errorCount != 0) {
      return null;
    }
    _frontendServer.stdin.writeln('accept');
    _lastCompiledTime = DateTime.now();
    _dependencies = result.sources;
    return dillOutput.uri;
  }

  Future<Uri> recompile() async {
    _stdoutHandler.reset();
    var invalidated = await _projectFileInvalidator.findInvalidated(
      lastCompiled: _lastCompiledTime,
      urisToMonitor: _dependencies,
      packagesUri:
          Directory(path.join(config.packageRootPath, '.packages')).uri,
    );
    if (invalidated.isEmpty) {
      return null;
    }
    var pendingResult = _stdoutHandler.compilerOutput.future;
    var id = Uuid().v4();
    _frontendServer.stdin.writeln('recompile ${_mainFile.absolute.uri} $id');

    for (var uri in invalidated) {
      _frontendServer.stdin.writeln(uri.toString());
    }
    _frontendServer.stdin.writeln(id);
    var result = await pendingResult;
    if (result.errorCount != 0) {
      _frontendServer.stdin.writeln('reset');
      return null;
    }
    _frontendServer.stdin.writeln('accept');
    _lastCompiledTime = DateTime.now();
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
          '--platform=${config.platformDillUri}',
          '--no-link-platform',
          '--debugger-module-names',
        ];
    }
    throw StateError('_compilerMode was null');
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
  bool _expectSources;

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
    bool asyncScanning = false,
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
      var updatedAt = File(uri.toString()).statSync().modified;
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
