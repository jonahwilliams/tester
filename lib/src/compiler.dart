// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:tester/src/config.dart';
import 'package:uuid/uuid.dart';

const _testMain = r'''
import 'dart:async';
import 'dart:io';
import 'dart:developer';

Future<void> executeTest(dynamic testFn, String name) async {
  var passed = false;
  var timeout = false;
  dynamic error;
  dynamic stackTrace;
  try {
    await Future(testFn)
      .timeout(const Duration(seconds: 15));
    passed = true;
  } on TimeoutException {
    timeout = true;
  } catch (err, st) {
    error = err;
    stackTrace = st;
  } finally {
    postEvent('testResult', {
      'test': name,
      'passed': passed,
      'timeout': timeout,
      'error': error?.toString(),
      'stackTrace': stackTrace?.toString(),
    });
  }
}

Future<void> main() {
  stdin.listen((_) { });
}
''';

class Compiler {
  Compiler({
    @required ProcessManager processManager,
    @required Config config,
    @required FileSystem fileSystem,
    @required TargetPlatform compilerMode,
  })  : _processManager = processManager,
        _config = config,
        _fileSystem = fileSystem,
        _compilerMode = compilerMode;

  final ProcessManager _processManager;
  final Config _config;
  final FileSystem _fileSystem;
  final TargetPlatform _compilerMode;

  List<Uri> _dependencies;
  DateTime _lastCompiledTime;
  StdoutHandler _stdoutHandler;
  ProjectFileInvalidator _projectFileInvalidator;
  Process _frontendServer;
  File _mainFile;

  /// Generate the synthetic entrypoint and bootstrap the compiler.
  Future<Uri> start() async {
    var workspace = _fileSystem.directory(_config.workspacePath);
    if (!workspace.existsSync()) {
      workspace.createSync(recursive: true);
    }
    _mainFile = workspace.childFile('main.dart');
    var contents = StringBuffer();
    for (var testPath in _config.testPaths) {
      contents.writeln('import "${testPath}";');
    }
    contents.write(_testMain);
    _mainFile.writeAsStringSync(contents.toString());

    var dillOutput = _fileSystem
        .directory(_config.packageRootPath)
        .childFile('main.dart.dill');

    _stdoutHandler = StdoutHandler();
    _projectFileInvalidator = ProjectFileInvalidator(fileSystem: _fileSystem);
    var args = <String>[
      _config.dartPath,
      _config.frontendServerPath,
      ..._getArgsForCompilerMode,
      '--enable-asserts',
      '--packages=${_fileSystem.path.join(_config.packageRootPath, '.packages')}',
      '--no-link-platform',
      '--output-dill=${dillOutput.path}',
      '--incremental',
    ];
    _frontendServer = await _processManager.start(args);
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
      packagesPath: _fileSystem
          .directory(_config.packageRootPath)
          .childFile('.packages')
          .path,
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
    return _fileSystem.file(result.outputFilename).absolute.uri;
  }

  List<String> get _getArgsForCompilerMode {
    switch (_compilerMode) {
      case TargetPlatform.dart:
        return <String>[
          '--target=vm',
          '--sdk-root=${_config.dartSdkRoot}',
          '--platform=${_config.platformDillPath}',
          '--no-link-platform',
        ];
      case TargetPlatform.flutter:
        return <String>[
          '--target=flutter',
          '--sdk-root=${_config.flutterPatchedSdkRoot}',
          '-Ddart.vm.profile=false',
          '-Ddart.vm.product=false',
          '--track-widget-creation',
        ];
      case TargetPlatform.web:
        return <String>[
          '--target=dartdevc',
          '--sdk-root=${_config.dartSdkRoot}',
          '--platform=${_config.platformDillPath}',
          '--no-link-platform',
          '--debugger-module-names',
        ];
      case TargetPlatform.flutterWeb:
        return <String>[
          '--target=dartdevc',
          '--sdk-root=${_config.dartSdkRoot}',
          '--platform=${_config.platformDillPath}',
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
  ProjectFileInvalidator({
    @required FileSystem fileSystem,
  }) : _fileSystem = fileSystem;

  final FileSystem _fileSystem;

  static const String _pubCachePathLinuxAndMac = '.pub-cache';

  Future<List<Uri>> findInvalidated({
    @required DateTime lastCompiled,
    @required List<Uri> urisToMonitor,
    @required String packagesPath,
    bool asyncScanning = false,
  }) async {
    assert(urisToMonitor != null);
    assert(packagesPath != null);

    if (lastCompiled == null) {
      // Initial load.
      assert(urisToMonitor.isEmpty);
      return <Uri>[];
    }
    var urisToScan = <Uri>[
      // Don't watch pub cache directories to speed things up a little.
      for (var uri in urisToMonitor) if (_isNotInPubCache(uri)) uri,

      // We need to check the .packages file too since it is not used in compilation.
      _fileSystem.file(packagesPath).uri,
    ];
    var invalidatedFiles = <Uri>[];
    for (var uri in urisToScan) {
      var updatedAt = _fileSystem.statSync(uri.toFilePath()).modified;
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
