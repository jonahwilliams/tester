// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:file/file.dart';
import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:package_config/package_config.dart';
import 'package:process/process.dart';
import 'package:tester/src/platform.dart';
import 'package:uuid/uuid.dart';

import 'config.dart';
import 'test_info.dart';

String generateVmTestMain(int timeout) =>
    '''
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:developer';

Future<Map<String, Object>> executeTest(String name, String libraryUri) async {
  var testFunction = testRegistry[libraryUri][name];

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
  var zone = Zone.current.fork(
    specification: ZoneSpecification(
      print: (self, parent, zone, line) {
        log(line);
      },
    ),
  );
  registerExtension('ext.callTest', (String request, Map<String, String> args) async {
    var test = args['test'];
    var library = args['library'];
    final result = await zone.run(() => executeTest(test, library));
    return ServiceExtensionResponse.result(json.encode(result));
  });
}
''';

String generateFlutterWebTestMain(int timeout) =>
    '''
import 'dart:convert';
import 'dart:async';
import 'dart:developer';
import 'dart:ui' as ui;

Future<Map<String, Object>> executeTest(String name, String libraryUri) async {
  var testFunction = testRegistry[libraryUri][name];

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
    return <String, Object>{
      'test': name,
      'passed': passed,
      'timeout': timeout,
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

String generateWebTestMain(int timeout) =>
    '''
import 'dart:convert';
import 'dart:async';
import 'dart:developer';

Future<Map<String, Object>> executeTest(String name, String libraryUri) async {
  var testFunction = testRegistry[libraryUri][name];

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
    return <String, Object>{
      'test': name,
      'passed': passed,
      'timeout': timeout,
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
}

''';

/// Abstraction for the frontend_server compiler process.
///
/// The frontend_server communicates to this tool over stdin and stdout.
class Compiler {
  Compiler({
    @required this.config,
    @required this.compilerMode,
    @required this.timeout,
    @required this.enabledExperiments,
    @required this.soundNullSafety,
    this.fileSystem = const LocalFileSystem(),
    this.processManager = const LocalProcessManager(),
    this.platform = const LocalPlatform(),
  });

  final FileSystem fileSystem;
  final ProcessManager processManager;
  final Config config;
  final TargetPlatform compilerMode;
  final Platform platform;
  final int timeout;
  final List<String> enabledExperiments;
  final bool soundNullSafety;

  List<Uri> _dependencies;
  DateTime _lastCompiledTime;
  StdoutHandler _stdoutHandler;
  Process _frontendServer;
  File _mainFile;
  PackageConfig _packageConfig;

  DateTime get lastCompiled => _lastCompiledTime;

  List<Uri> get dependencies => _dependencies;

  /// Generate the synthetic entrypoint and bootstrap the compiler.
  Future<Uri> start(Map<Uri, List<TestInfo>> testInformation) async {
    var workspace = fileSystem.directory(config.workspacePath);
    if (!workspace.existsSync()) {
      workspace.createSync(recursive: true);
    }
    var packagesUri = fileSystem
        .file(fileSystem.path.join(config.packageRootPath, '.packages'))
        .absolute
        .uri;
    _packageConfig = await loadPackageConfigUri(packagesUri, loader: (Uri uri) {
      var file = fileSystem.file(uri);
      if (file.existsSync()) {
        return file.readAsBytes();
      }
      return null;
    });
    var package = testInformation.isNotEmpty
        ? _packageConfig.packageOf(testInformation.keys.first)
        : null;

    _mainFile =
        fileSystem.file(fileSystem.path.join(workspace.path, 'main.dart'));
    _regenerateMain(testInformation, timeout, package);

    var dillOutput = fileSystem
        .file(fileSystem.path
            .join(config.workspacePath, 'main.${compilerMode}.dart.dill'))
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
      fileSystem.file(config.workspacePath).parent.absolute.path,
      '--filesystem-root',
      fileSystem.path.join(config.packageRootPath),
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
            from: config.packageRootPath,
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
            from: config.packageRootPath,
          ))
          .uri;
      contents.writeln(
          'import "org-dartlang-app:///$relativePath" as i$importNumber;');
      importNumber += 1;
    }
    switch (compilerMode) {
      case TargetPlatform.dart:
        contents.write(generateVmTestMain(
          timeout,
        ));
        break;
      case TargetPlatform.web:
        contents.write(generateWebTestMain(
          timeout,
        ));
        break;
      case TargetPlatform.flutter:
        contents.write(generateVmTestMain(
          timeout,
        ));
        break;
      case TargetPlatform.flutterWeb:
        contents.write(generateFlutterWebTestMain(
          timeout,
        ));
        break;
    }
    contents.writeln('var testRegistry = {');
    for (var testFileUri in testInformation.keys) {
      contents.writeln('"${testFileUri}": {');
      for (var testInfo in testInformation[testFileUri]) {
        contents.writeln(
          '"${testInfo.name}": '
          'i${importNumbers[testFileUri]}.${testInfo.name},',
        );
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
