// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:convert';
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:logging/logging.dart';
import 'package:package_config/package_config_types.dart';
import 'package:shelf/shelf_io.dart' as shelf;
import 'package:shelf/shelf.dart' as shelf;
import 'package:dwds/dwds.dart';
import 'package:meta/meta.dart';
import 'package:path/path.dart' as path;
import 'package:vm_service/vm_service.dart';
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

import 'config.dart';
import 'logging.dart';
import 'runner.dart';

/// A test runner that spawns chrome and a dwds process.
class ChromeTestRunner extends TestRunner implements AssetReader {
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

  /// The expected executable name on linux.
  static const String kLinuxExecutable = 'google-chrome';

  /// The expected executable name on macOS.
  static const String kMacOSExecutable =
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

  /// The expected Chrome executable name on Windows.
  static const String kWindowsExecutable =
      r'Google\Chrome\Application\chrome.exe';

  static const String _kDefaultIndex = '''
<html>
    <body>
        <script src="main.dart.js"></script>
    </body>
</html>
''';

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
  final modules = <String, String>{};
  final digests = <String, String>{};
  final files = <String, Uint8List>{};
  final sourcemaps = <String, Uint8List>{};

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
              if (headless) ...<String>[
                '--headless',
                '--disable-gpu',
              ],
              '--no-sandbox',
              '--window-size=2400,1800',
              'http://localhost:$serverPort',
            ]),
        'start_chrome',
        logger);

    chromeConnection.complete(ChromeConnection('localhost', port));

    return measureCommand(() async {
      await for (var connection in _dwds.connectedApps) {
        connection.runMain();
        DebugConnection debugConnection;
        try {
          debugConnection = await _dwds.debugConnection(connection);
        } on AppConnectionException {
          continue;
        }
        vmService = debugConnection.vmService;
        return RunnerStartResult(
          isolateName: '',
          serviceUri: Uri.parse(debugConnection.uri),
        );
      }
      throw Exception();
    }, 'dwds_connect', logger);
  }

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

  @override
  Future<String> dartSourceContents(String serverPath) async {
    if (!serverPath.endsWith('.dart')) return null;
    var workspaceFile = File(path.join(packagesRootPath, serverPath));
    if (workspaceFile.existsSync()) {
      return workspaceFile.readAsStringSync();
    }
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
    return shelf.Response.notFound('');
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

  // /// Returns the full URL of the Chrome remote debugger for the main page.
  // ///
  // /// This takes the [base] remote debugger URL (which points to a browser-wide
  // /// page) and uses its JSON API to find the resolved URL for debugging the host
  // /// page.
  // Future<Uri> _getRemoteDebuggerUrl(Uri base) async {
  //   try {
  //     var client = HttpClient();
  //     var request = await client.getUrl(base.resolve('/json/list'));
  //     var response = await request.close();
  //     var jsonObject =
  //         await json.fuse(utf8).decoder.bind(response).single as List<dynamic>;
  //     if (jsonObject == null || jsonObject.isEmpty) {
  //       return base;
  //     }
  //     return base.resolve(jsonObject.first['devtoolsFrontendUrl'] as String);
  //   } on Exception {
  //     // If we fail to talk to the remote debugger protocol, give up and return
  //     // the raw URL rather than crashing.
  //     return base;
  //   }
  // }

  @override
  Future<String> metadataContents(String serverPath) {
    return null;
  }
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
  window.\$dartLoader = {};
  window.\$dartLoader.rootDirectories = [];
  if (window.\$requireLoader) {
    window.\$requireLoader.getModuleLibraries = dart_sdk.dart.getModuleLibraries;
    if (window.\$dartStackTraceUtility && !window.\$dartStackTraceUtility.ready) {
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
    }
  }
});
''';
}
