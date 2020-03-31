// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';
import 'dart:convert';
import 'dart:developer';
import 'dart:io';
import 'dart:isolate';

import 'package:file/file.dart';
import 'package:meta/meta.dart';
import 'package:process/process.dart';
import 'package:uuid/uuid.dart';
import 'package:vm_service/vm_service.dart' as vm_service;
import 'package:vm_service/vm_service_io.dart' as vm_service;

const testMain = r'''
import 'dart:async';
import 'dart:io';


Future<void> main() {
  stdin.listen((_) { });
}
''';

/// Configuration necessary to bootstrap the test runner.
class Config {
  const Config({
    @required this.dartPath,
    @required this.frontendServerPath,
    @required this.workspacePath,
    @required this.packageRootPath,
    @required this.testPaths,
    @required this.sdkRoot,
    @required this.platformDillPath,
  });

  /// The file path to the dart executable.
  final String dartPath;

  /// The file path to the frontend_server executable.
  final String frontendServerPath;

  /// The file path to a workspace directory.
  ///
  /// This is used to generated temporary files or other intermediate
  /// artifacts.
  final String workspacePath;

  /// The file path to the directory which contains `lib`, `test`, and
  /// `pubspec.yaml`.
  final String packageRootPath;

  /// The file path to the root of the current SDK.
  final String sdkRoot;

  /// The file path to the platform dill for the current SDK.
  final String platformDillPath;

  /// The file paths to the tests that should be executed.
  final List<String> testPaths;
}

/// The isolate which contains test code to be executed.
///
/// This currently only supports a vm target.
class TestIsolate {
  /// Create a test isolate from a dill file.
  TestIsolate(this._mainUri);

  final Uri _mainUri;
  final _libraries = <vm_service.LibraryRef>{};
  vm_service.VmService _vmService;
  vm_service.IsolateRef _testIsolateRef;

  /// Start the test isolate.
  Future<void> start() async {
    await Isolate.spawnUri(
      _mainUri,
      <String>[],
      null,
      debugName: 'testIsolate',
    );

    var info = await Service.getInfo();
    var url = info.serverUri.replace(scheme: 'ws').toString() + 'ws';
    _vmService = await vm_service.vmServiceConnectUri(url);

    // Step 6: Find test isolate;
    var vm = await _vmService.getVM();
    _testIsolateRef =
        vm.isolates.firstWhere((isolate) => isolate.name == 'testIsolate');
    var scripts = await _vmService.getScripts(_testIsolateRef.id);
    for (var scriptRef in scripts.scripts) {
      var uri = Uri.parse(scriptRef.uri);
      if (uri.scheme == 'dart') {
        continue;
      }
      var script = await _vmService.getObject(_testIsolateRef.id, scriptRef.id)
          as vm_service.Script;
      _libraries.add(script.library);
    }
  }

  Future<void> runAllTests() async {
    for (var libraryRef in _libraries) {
      var library = await _vmService.getObject(_testIsolateRef.id, libraryRef.id) as vm_service.Library;
      for (var function in library.functions) {
        if (!function.name.startsWith('test')) {
          continue;
        }
        var result = await runTest(function.name, libraryRef.uri);
        if (result) {
          print('${libraryRef.uri}/${function.name} PASSED');
        } else {
          print('${libraryRef.uri}/${function.name} FAILED');
        }
      }
    }
  }

  /// Invoke the test named [testName] defined in [libraryName].
  Future<bool> runTest(String testName, String libraryName) async {
    var testLibrary = _libraries
        .firstWhere((element) => element.uri.contains(libraryName ?? '_test'));
    var testResult = await _vmService
        .invoke(_testIsolateRef.id, testLibrary.id, testName, []);
    print(testResult?.toJson());
    if (testResult == null) {
      return true;
    }
    if (testResult is vm_service.InstanceRef) {
      return true;
    }
    if (testResult is vm_service.ErrorRef) {
      print(testResult.message);
      return false;
    }
    throw StateError('Bad Respone Type: $testResult');
  }

  /// Reload the application with the incremental file defined at `incrementalDill`.
  Future<void> reloadSources(String incrementalDill) async {
    await _vmService.reloadSources(_testIsolateRef.id,
        rootLibUri: incrementalDill);
  }
}

void runApplication({
  @required bool batchMode,
  @required Config config,
  @required ProcessManager processManager,
  @required FileSystem fileSystem,
}) async {
  // Step 1. Generate entrypoint file.
  var workspace = fileSystem.directory(config.workspacePath);
  if (!workspace.existsSync()) {
    workspace.createSync(recursive: true);
  }
  var mainFile = workspace.childFile('main.dart');
  var contents = StringBuffer();
  for (var testPath in config.testPaths) {
    contents.writeln('import "${testPath}";');
  }
  contents.write(testMain);
  mainFile.writeAsStringSync(contents.toString());

  // Step 2. Bootstrap compiler
  List<Uri> dependencies;
  DateTime lastCompiledTime;
  var stdoutHandler = StdoutHandler();
  var projectFileInvalidator = ProjectFileInvalidator(fileSystem: fileSystem);
  var args = <String>[
    config.dartPath,
    config.frontendServerPath,
    '--target=vm',
    '--packages=${fileSystem.path.join(config.packageRootPath, '.packages')}',
    '--sdk-root=${config.sdkRoot}',
    '--platform=${config.platformDillPath}',
    '--no-link-platform',
    '--output-dill=${fileSystem.directory(config.packageRootPath).childFile('main.dart.dill').path}',
    '--incremental',
  ];
  var process = await processManager.start(args);
  process.stderr
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(print);
  process.stdout
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen(stdoutHandler.handler);
  process.stdin.writeln('compile ${mainFile.absolute.uri}');
  var result = await stdoutHandler.compilerOutput.future;
  // check for errors!
  if (result.errorCount != 0) {
    return;
  }
  process.stdin.writeln('accept');
  lastCompiledTime = DateTime.now();
  dependencies = result.sources;

  // Step 3. Load test isolate.
  var testIsolate =
      TestIsolate(fileSystem.file(result.outputFilename).absolute.uri);
  await testIsolate.start();

  Future<void> recompileTests() async {
    stdoutHandler.reset();
    var pendingResult = stdoutHandler.compilerOutput.future;
    var id = Uuid().v4();
    process.stdin.writeln('recompile ${mainFile.absolute.uri} $id');
    var invalidated = await projectFileInvalidator.findInvalidated(
      lastCompiled: lastCompiledTime,
      urisToMonitor: dependencies,
      packagesPath: fileSystem
          .directory(config.packageRootPath)
          .childFile('.packages')
          .path,
    );
    for (var uri in invalidated) {
      process.stdin.writeln(uri.toString());
    }
    process.stdin.writeln(id);
    var result = await pendingResult;
    if (result.errorCount != 0) {
      process.stdin.writeln('reset');
      return;
    }
    process.stdin.writeln('accept');
    lastCompiledTime = DateTime.now();
    await testIsolate.reloadSources(
        fileSystem.file(result.outputFilename).absolute.uri.toString());
  }

  if (batchMode) {
    await testIsolate.runAllTests();
    return exit(0);
  }
  // Test loop
  print('READY.');
  String activeLibrary;
  String lastTest;
  stdin
      .transform(utf8.decoder)
      .transform(const LineSplitter())
      .listen((String line) async {
    var message = line.trim();
    if (message.isEmpty) {
      return;
    }
    switch (message[0]) {
      case 'l':
        activeLibrary = message.split(' ').last;
        print('set active library to $activeLibrary');
        break;
      case 'r':
        return recompileTests();
      case 'R':
        await recompileTests();
        var response = await testIsolate.runTest(lastTest, activeLibrary);
        if (response) {
          print('PASSED');
        } else {
          print('FAILED');
        }
        break;
      case 't':
        var test = message.split(' ').last;
        lastTest = test;
        var response = await testIsolate.runTest(test, activeLibrary);
        if (response) {
          print('PASSED');
        } else {
          print('FAILED');
        }
    }
  });
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
