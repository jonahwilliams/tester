// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'dart:isolate' as isolate;

import 'package:logging/logging.dart';
import 'package:package_config/package_config_types.dart';
import 'package:shelf/shelf_io.dart' as shelf;
import 'package:shelf/shelf.dart' as shelf;
import 'package:dwds/dwds.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:tester/src/isolate.dart';
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'config.dart';
import 'logging.dart';
import 'runner.dart';
import 'test_info.dart';

/// The expected executable name on linux.
const String kLinuxExecutable = 'google-chrome';

/// The expected executable name on macOS.
const String kMacOSExecutable =
    '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

/// The expected Chrome executable name on Windows.
const String kWindowsExecutable = r'Google\Chrome\Application\chrome.exe';

const String _kDefaultIndex = '''
<html>
  <body>
      <script src="main.dart.js"></script>
  </body>
</html>
''';

/// Shared logic between the chrome and no-debug test runner.
abstract class WebTestRunner implements TestRunner {
  final modules = <String, String>{};
  final digests = <String, String>{};
  final files = <String, Uint8List>{};
  final sourcemaps = <String, Uint8List>{};

  void updateCode(
    File codeFile,
    File manifestFile,
    File sourcemapFile,
  ) {
    var updatedModules = <String>[];
    var codeBytes = codeFile.readAsBytesSync();
    var sourcemapBytes = sourcemapFile.readAsBytesSync();
    var manifest =
        json.decode(manifestFile.readAsStringSync()) as Map<String, Object>;
    for (var filePath in manifest.keys) {
      if (filePath == null) {
        continue;
      }
      var offsets = manifest[filePath] as Map<String, Object>;
      var codeOffsets = (offsets['code'] as List<dynamic>).cast<int>();
      var sourcemapOffsets =
          (offsets['sourcemap'] as List<dynamic>).cast<int>();
      if (codeOffsets.length != 2 || sourcemapOffsets.length != 2) {
        continue;
      }
      var codeStart = codeOffsets[0];
      var codeEnd = codeOffsets[1];
      if (codeStart < 0 || codeEnd > codeBytes.lengthInBytes) {
        continue;
      }
      var byteView = Uint8List.view(
        codeBytes.buffer,
        codeStart,
        codeEnd - codeStart,
      );
      var fileName =
          filePath.startsWith('/') ? filePath.substring(1) : filePath;
      files[fileName] = byteView;

      var sourcemapStart = sourcemapOffsets[0];
      var sourcemapEnd = sourcemapOffsets[1];
      if (sourcemapStart < 0 || sourcemapEnd > sourcemapBytes.lengthInBytes) {
        continue;
      }
      var sourcemapView = Uint8List.view(
        sourcemapBytes.buffer,
        sourcemapStart,
        sourcemapEnd - sourcemapStart,
      );
      var sourcemapName = '$fileName.map';
      sourcemaps[sourcemapName] = sourcemapView;
      updatedModules.add(fileName);
    }
    for (var module in updatedModules) {
      // We skip computing the digest by using the hashCode of the underlying buffer.
      // Whenever a file is updated, the corresponding Uint8List.view it corresponds
      // to will change.
      var moduleName = module.startsWith('/') ? module.substring(1) : module;
      var name = moduleName.replaceAll('.lib.js', '');
      var path = moduleName.replaceAll('.js', '');
      modules[name] = path;
      digests[name] = files[moduleName].hashCode.toString();
    }
  }
}

/// A test runner that spawns chrome and a dwds process.
class ChromeTestRunner extends WebTestRunner implements AssetReader {
  ChromeTestRunner({
    @required this.dartSdkFile,
    @required this.dartSdkSourcemap,
    @required this.stackTraceMapper,
    @required this.requireJS,
    @required this.config,
    @required this.packagesRootPath,
    @required this.headless,
    @required this.packageConfig,
    @required this.expressionCompiler,
    @required this.logger,
  });

  Process _chromeProcess;
  Dwds _dwds;
  Directory _chromeTempProfile;
  HttpServer _httpServer;
  VmService vmService;

  final Config config;
  final File dartSdkFile;
  final File dartSdkSourcemap;
  final File stackTraceMapper;
  final File requireJS;
  final String packagesRootPath;
  final bool headless;
  final PackageConfig packageConfig;
  final ExpressionCompiler expressionCompiler;
  final Logger logger;

  @override
  FutureOr<void> dispose() async {
    await _dwds.stop();
    await _httpServer.close();
    _chromeProcess.kill();
    await _chromeProcess.exitCode;

    try {
      _chromeTempProfile.deleteSync(recursive: true);
    } on FileSystemException {
      // Oops...
    }
  }

  @override
  FutureOr<RunnerStartResult> start(
      Uri entrypoint, void Function() onExit) async {
    files['dart_sdk.js'] = dartSdkFile.readAsBytesSync();
    files['dart_sdk.js.map'] = dartSdkSourcemap.readAsBytesSync();
    files['require.js'] = requireJS.readAsBytesSync();
    files['stack_trace_mapper.js'] = stackTraceMapper.readAsBytesSync();
    files['main.dart.js'] = utf8.encode(generateBootstrapScript(
      requireUrl: 'require.js',
      mapperUrl: 'stack_trace_mapper.js',
    )) as Uint8List;
    files['main_module.bootstrap.js'] = utf8.encode(generateMainModule(
      entrypoint: 'tester/main.dart',
    )) as Uint8List;

    // Return the set of all active modules. This is populated by the
    // frontend_server update logic.
    Future<Map<String, String>> moduleProvider(String path) async {
      return modules;
    }

    // Return a version string for all active modules. This is populated
    // along with the `moduleProvider` update logic.
    Future<Map<String, String>> digestProvider(String path) async {
      return digests;
    }

    // Return the module name for a given server path. These are the names
    // used by the browser to request JavaScript files.
    String moduleForServerPath(String serverPath) {
      if (serverPath.endsWith('.lib.js')) {
        serverPath =
            serverPath.startsWith('/') ? serverPath.substring(1) : serverPath;
        return serverPath.replaceAll('.lib.js', '');
      }
      return null;
    }

    // Return the server path for modules. These are the JavaScript file names
    // output by the frontend_server.
    String serverPathForModule(String module) {
      return '$module.lib.js';
    }

    // Return the server path for modules or resources that have an
    // org-dartlang-app scheme.
    String serverPathForAppUri(String appUri) {
      if (appUri.startsWith('org-dartlang-app:')) {
        return Uri.parse(appUri).path.substring(1);
      }
      return null;
    }

    var chromeConnection = Completer<ChromeConnection>();
    _dwds = await Dwds.start(
        assetReader: this,
        buildResults: const Stream.empty(),
        chromeConnection: () {
          return chromeConnection.future;
        },
        expressionCompiler: expressionCompiler,
        serveDevTools: false,
        enableDebugging: true,
        useSseForDebugProxy: false,
        loadStrategy: RequireStrategy(
          ReloadConfiguration.none,
          '.lib.js',
          moduleProvider,
          digestProvider,
          moduleForServerPath,
          serverPathForModule,
          serverPathForAppUri,
        ),
        logWriter: (level, message) {});

    var serverPort = await findFreePort();
    _httpServer = await HttpServer.bind('localhost', serverPort);
    var pipeline = const shelf.Pipeline();
    pipeline = pipeline.addMiddleware(_dwds.middleware);
    var dwdsHandler = pipeline.addHandler(_handleRequest);
    var cascade = shelf.Cascade().add(_dwds.handler).add(dwdsHandler);
    shelf.serveRequests(_httpServer, cascade.handler);

    var port = await findFreePort();
    _chromeTempProfile = Directory.systemTemp.createTempSync('test_process')
      ..createSync();

    _chromeProcess = await measureCommand(
      () => Process.start(_findChromeExecutable(), <String>[
        // Using a tmp directory ensures that a new instance of chrome launches
        // allowing for the remote debug port to be enabled.
        '--user-data-dir=${_chromeTempProfile.path}',
        '--remote-debugging-port=${port}',
        // When the DevTools has focus we don't want to slow down the application.
        '--disable-background-timer-throttling',
        // Since we are using a temp profile, disable features that slow the
        // Chrome launch.
        '--disable-extensions',
        '--disable-popup-blocking',
        '--bwsi',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-default-apps',
        '--disable-translate',
        '--disable-web-security',
        if (headless) ...<String>[
          '--headless',
          '--disable-gpu',
        ],
        '--no-sandbox',
        '--window-size=2400,1800',
        'http://localhost:$serverPort',
      ]),
      'start_chrome',
      logger,
    );

    chromeConnection.complete(ChromeConnection('localhost', port));

    return measureCommand(() async {
      await for (var connection in _dwds.connectedApps) {
        connection.runMain();
        var debugConnection = await _dwds.debugConnection(connection);
        vmService = debugConnection.vmService;
        return RunnerStartResult(
          isolateName: '',
          serviceUri: Uri.parse(debugConnection.uri),
        );
      }
      throw Exception();
    }, 'dwds_connect', logger);
  }

  final uriContext = path.Context(style: path.Style.url);

  String _readPackageFile(String serverPath) {
    var segments = Uri.parse(serverPath).pathSegments;
    if (segments.first == 'packages' && segments.length > 2) {
      var packageName = segments[1];
      var package = packageConfig[packageName];
      if (package != null) {
        var uri = package.packageUriRoot.resolve(segments.skip(2).join('/'));
        var packageFile = File(uri.toFilePath());
        if (packageFile.existsSync()) {
          return packageFile.readAsStringSync();
        }
      }
    }
    if (serverPath == 'tester/main.dart') {
      return File(
              path.join(packagesRootPath, '.dart_tool', 'tester', 'main.dart'))
          .readAsStringSync();
    }
    return null;
  }

  String _readEngineFile(String serverPath) {
    if (!serverPath.contains('cache/builder/src/out')) {
      return null;
    }
    var segments = uriContext
        .split(serverPath)
        .skipWhile((String segment) => segment != 'flutter_web_sdk')
        .skip(1);
    if (segments.isEmpty) {
      return null;
    }
    var contents =
        File(path.joinAll([config.flutterWebSdkSources, ...segments]));
    if (contents.existsSync()) {
      return contents.readAsStringSync();
    }
    return null;
  }

  @override
  Future<String> dartSourceContents(String serverPath) async {
    if (!serverPath.endsWith('.dart')) return null;
    var workspaceFile = File(path.joinAll([
      packagesRootPath,
      ...uriContext.split(serverPath),
    ]));
    if (workspaceFile.existsSync()) {
      return workspaceFile.readAsStringSync();
    }
    var result = _readPackageFile(serverPath);
    if (result != null) {
      return result;
    }
    result = _readEngineFile(serverPath);
    if (result != null) {
      return result;
    }
    return null;
  }

  @override
  Future<String> sourceMapContents(String serverPath) async {
    if (!serverPath.endsWith('lib.js.map')) return null;
    var result = sourcemaps[serverPath] ?? sourcemaps['/$serverPath'];
    return utf8.decode(result);
  }

  Future<shelf.Response> _handleRequest(shelf.Request request) async {
    var requestPath = request.url.path;
    if (requestPath.startsWith('/')) {
      requestPath = requestPath.substring(1);
    }
    var headers = <String, String>{};
    // If the response is `/`, then we are requesting the index file.
    if (request.url.path == '/' || request.url.path.isEmpty) {
      headers[HttpHeaders.contentTypeHeader] = 'text/html';
      headers[HttpHeaders.contentLengthHeader] =
          _kDefaultIndex.length.toString();
      return shelf.Response.ok(_kDefaultIndex, headers: headers);
    }

    if (files.containsKey(requestPath)) {
      final List<int> bytes = files[requestPath];
      headers[HttpHeaders.contentLengthHeader] = bytes.length.toString();
      headers[HttpHeaders.contentTypeHeader] = 'application/javascript';
      return shelf.Response.ok(bytes, headers: headers);
    }

    var bytes = sourcemaps['/' + requestPath] ?? sourcemaps[requestPath];
    if (bytes != null) {
      return shelf.Response.ok(bytes);
    }

    var result = _readPackageFile(requestPath);
    if (result != null) {
      return shelf.Response.ok(result);
    }

    if (request.url.path == 'packages/ui/assets/ahem.ttf') {
      var uri = await isolate.Isolate.resolvePackageUri(
          Uri.parse('package:tester/assets/Ahem.ttf'));
      return shelf.Response.ok(
        File.fromUri(uri).readAsBytesSync(),
        headers: <String, String>{
          HttpHeaders.contentTypeHeader: 'application/x-font-ttf'
        },
      );
    }
    result = _readEngineFile(requestPath);
    if (result != null) {
      return shelf.Response.ok(result);
    }

    print('found nothing main request for ${request.url}}');

    return shelf.Response.notFound('');
  }

  @override
  Future<String> metadataContents(String serverPath) {
    return null;
  }
}

class ChromeNoDebugTestRunner extends WebTestRunner {
  ChromeNoDebugTestRunner({
    @required this.dartSdkFile,
    @required this.dartSdkSourcemap,
    @required this.stackTraceMapper,
    @required this.requireJS,
    @required this.config,
    @required this.packagesRootPath,
    @required this.headless,
    @required this.packageConfig,
    @required this.logger,
  });

  Process _chromeProcess;
  Directory _chromeTempProfile;
  HttpServer _httpServer;
  ChromeConnection _chromeConnection;
  WipConnection _wipConnection;

  final Config config;
  final File dartSdkFile;
  final File dartSdkSourcemap;
  final File stackTraceMapper;
  final File requireJS;
  final String packagesRootPath;
  final bool headless;
  final PackageConfig packageConfig;
  final Logger logger;
  final _loading = Completer<void>();

  @override
  FutureOr<void> dispose() async {
    await _httpServer.close();
    _chromeProcess.kill();
    await _chromeProcess.exitCode;

    try {
      _chromeTempProfile.deleteSync(recursive: true);
    } on FileSystemException {
      // Oops...
    }
  }

  Future<TestResult> runTest(TestInfo testInfo) async {
    await _loading.future;
    var response = await _wipConnection.debugger
        .sendCommand('Runtime.evaluate', params: <String, Object>{
      'expression':
          'window["\$dartRunTest"]("${testInfo.testFileUri}::${testInfo.name}");',
      'returnByValue': true,
      'awaitPromise': true,
      'timeout': 600000,
    });
    return TestResult.fromMessage(
      json.decode(response.json['result']['result']['value'] as String)
          as Map<String, Object>,
      testInfo.testFileUri,
    );
  }

  @override
  FutureOr<RunnerStartResult> start(
    Uri entrypoint,
    void Function() onExit,
  ) async {
    files['dart_sdk.js'] = dartSdkFile.readAsBytesSync();
    files['dart_sdk.js.map'] = dartSdkSourcemap.readAsBytesSync();
    files['require.js'] = requireJS.readAsBytesSync();
    files['stack_trace_mapper.js'] = stackTraceMapper.readAsBytesSync();
    files['main.dart.js'] = utf8.encode(generateBootstrapScript(
      requireUrl: 'require.js',
      mapperUrl: 'stack_trace_mapper.js',
    )) as Uint8List;
    files['main_module.bootstrap.js'] = utf8.encode(generateMainModule(
      entrypoint: 'tester/main.dart',
    )) as Uint8List;

    var serverPort = await findFreePort();
    _httpServer = await HttpServer.bind('localhost', serverPort);
    var cascade = shelf.Cascade().add((shelf.Request request) async {
      if (request.url.path == 'done-loading') {
        if (_loading.isCompleted) {
          return shelf.Response.ok('');
        }
        var chromeTab =
            (await _chromeConnection.getTabs()).firstWhere((ChromeTab tab) {
          return !tab.isBackgroundPage && !tab.isChromeExtension;
        });
        _wipConnection = await chromeTab.connect();
        await _wipConnection.log.enable();
        await _wipConnection.log.onEntryAdded.listen((m) {
          print(m.text);
        });
        _loading.complete();
        return shelf.Response.ok('');
      }
      if (request.url.path == '') {
        return shelf.Response.ok(_kDefaultIndex, headers: <String, String>{
          HttpHeaders.contentTypeHeader: 'text/html',
        });
      }
      var path = request.url.path;
      var bytes = files[path];
      if (bytes != null) {
        return shelf.Response.ok(bytes, headers: <String, String>{
          if (path.endsWith('.js'))
            HttpHeaders.contentTypeHeader: 'text/javascript',
        });
      }
      bytes = files[path.replaceFirst('.js', '.lib.js')];
      if (bytes != null) {
        return shelf.Response.ok(bytes, headers: <String, String>{
          HttpHeaders.contentTypeHeader: 'text/javascript',
        });
      }
      bytes = sourcemaps['/' + path] ?? sourcemaps[path];
      if (bytes != null) {
        return shelf.Response.ok(bytes);
      }
      if (path == 'packages/ui/assets/ahem.ttf') {
        var uri = await isolate.Isolate.resolvePackageUri(
            Uri.parse('package:tester/assets/Ahem.ttf'));
        return shelf.Response.ok(File.fromUri(uri).readAsBytesSync(),
            headers: <String, String>{
              HttpHeaders.contentTypeHeader: 'application/x-font-ttf'
            });
      }
      return shelf.Response.notFound('');
    });
    shelf.serveRequests(_httpServer, cascade.handler);

    var port = await findFreePort();
    _chromeTempProfile = Directory.systemTemp.createTempSync('test_process')
      ..createSync();

    _chromeProcess = await measureCommand(
      () => Process.start(_findChromeExecutable(), <String>[
        // Using a tmp directory ensures that a new instance of chrome launches
        // allowing for the remote debug port to be enabled.
        '--user-data-dir=${_chromeTempProfile.path}',
        '--remote-debugging-port=${port}',
        '--disable-background-timer-throttling',
        // Since we are using a temp profile, disable features that slow the
        // Chrome launch.
        '--disable-extensions',
        '--disable-popup-blocking',
        '--bwsi',
        '--no-first-run',
        '--no-default-browser-check',
        '--disable-default-apps',
        '--disable-translate',
        '--disable-web-security',
        if (headless) ...<String>[
          '--headless',
          '--disable-gpu',
        ],
        '--no-sandbox',
        '--window-size=2400,1800',
        'http://localhost:$serverPort',
      ]),
      'start_chrome',
      logger,
    );
    _chromeConnection = ChromeConnection('localhost', port);

    return RunnerStartResult(
      isolateName: '',
      serviceUri: null,
    );
  }
}

/// Find the chrome executable on the current platform.
///
/// Does not verify whether the executable exists.
String _findChromeExecutable() {
  if (Platform.isLinux) {
    return kLinuxExecutable;
  }
  if (Platform.isMacOS) {
    return kMacOSExecutable;
  }
  if (Platform.isWindows) {
    /// The possible locations where the chrome executable can be located on windows.
    var kWindowsPrefixes = <String>[
      Platform.environment['LOCALAPPDATA'],
      Platform.environment['PROGRAMFILES'],
      Platform.environment['PROGRAMFILES(X86)'],
    ];
    var windowsPrefix = kWindowsPrefixes.firstWhere((String prefix) {
      if (prefix == null) {
        return false;
      }
      var exePath = path.join(prefix, kWindowsExecutable);
      return File(exePath).existsSync();
    }, orElse: () => '.');
    return path.join(windowsPrefix, kWindowsExecutable);
  }
  assert(false);
  return null;
}

Future<int> findFreePort({bool ipv6 = false}) async {
  var port = 0;
  ServerSocket serverSocket;
  var loopback =
      ipv6 ? InternetAddress.loopbackIPv6 : InternetAddress.loopbackIPv4;
  try {
    serverSocket = await ServerSocket.bind(loopback, 0);
    port = serverSocket.port;
  } on SocketException {
    // If ipv4 loopback bind fails, try ipv6.
    if (!ipv6) {
      return findFreePort(ipv6: true);
    }
  } on Exception {
    // Failures are signaled by a return value of 0 from this function.
  } finally {
    if (serverSocket != null) {
      await serverSocket.close();
    }
  }
  return port;
}

/// The JavaScript bootstrap script to support in-browser hot restart.
///
/// The [requireUrl] loads our cached RequireJS script file. The [mapperUrl]
/// loads the special Dart stack trace mapper. The [entrypoint] is the
/// actual main.dart file.
String generateBootstrapScript({
  @required String requireUrl,
  @required String mapperUrl,
}) {
  return '''
"use strict";
// Attach source mapping.
var mapperEl = document.createElement("script");
mapperEl.defer = true;
mapperEl.async = false;
mapperEl.src = "$mapperUrl";
document.head.appendChild(mapperEl);
// Attach require JS.
var requireEl = document.createElement("script");
requireEl.defer = true;
requireEl.async = false;
requireEl.src = "$requireUrl";
// This attribute tells require JS what to load as main (defined below).
requireEl.setAttribute("data-main", "main_module.bootstrap");
document.head.appendChild(requireEl);
''';
}

/// Generate a synthetic main module which captures the application's main
/// method.
String generateMainModule({@required String entrypoint}) {
  return '''/* ENTRYPOINT_EXTENTION_MARKER */
// Create the main module loaded below.
define("main_module.bootstrap", ["$entrypoint", "dart_sdk"], function(app, dart_sdk) {
  dart_sdk.dart.setStartAsyncSynchronously(true);
  dart_sdk._debugger.registerDevtoolsFormatter();
  // See the generateMainModule doc comment.
  var child = {};
  child.main = app[Object.keys(app)[0]].main;
  /* MAIN_EXTENSION_MARKER */
  child.main();
  window.\$mainEntrypoint = child.main;
  window.\$dartLoader = {};
  window.\$dartLoader.rootDirectories = [];

  if (window.\$requireLoader) {
    window.\$requireLoader.getModuleLibraries = dart_sdk.dart.getModuleLibraries;
  }
  if (window.\$dartStackTraceUtility && !window.\$dartStackTraceUtility.ready) {
    try {
      window.\$dartStackTraceUtility.ready = true;
      let dart = dart_sdk.dart;
      window.\$dartStackTraceUtility.setSourceMapProvider(function(url) {
        var baseUrl = window.location.protocol + '//' + window.location.host;
        url = url.replace(baseUrl + '/', '');
        if (url == 'dart_sdk.js') {
          return dart.getSourceMap('dart_sdk');
        }
        url = url.replace(".lib.js", "");
        return dart.getSourceMap(url);
      });
    } catch (err) {
      return null;
    }
  }
});
''';
}
