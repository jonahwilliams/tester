// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:dwds/dwds.dart';
import 'package:meta/meta.dart';
import 'package:pedantic/pedantic.dart';
import 'package:path/path.dart' as path;
import 'package:webkit_inspection_protocol/webkit_inspection_protocol.dart';

/// The test runner manages the lifecycle of the platform under test.
abstract class TestRunner {
  /// Start the test runner, returning a [RunnerStartResult].
  ///
  /// [entrypoint] should be the generated entrypoint file for all
  /// bundled tests.
  ///
  /// [onExit] is invoked if the process exits before [dispose] is called.
  ///
  /// Throws a [StateError] if this method is called multiple times on
  /// the same instance.
  FutureOr<RunnerStartResult> start(Uri entrypoint, void Function() onExit);

  /// Perform cleanup necessary to tear down the test runner.
  ///
  /// Throws a [StateError] if this method is called multiple times on the same
  /// instance, or if it is called before [start].
  FutureOr<void> dispose();
}

Future<String> _pollForServiceFile(File file) async {
  while (true) {
    if (file.existsSync()) {
      var result = file.readAsStringSync();
      file.deleteSync();
      return result;
    }
    await Future<void>.delayed(const Duration(seconds: 1));
  }
}

/// The result of starting a [TestRunner].
class RunnerStartResult {
  const RunnerStartResult({
    @required this.serviceUri,
    @required this.isolateName,
  });

  /// The URI of the VM Service to connect to.
  final Uri serviceUri;

  /// A unique name for the isolate.
  final String isolateName;
}

/// A test runner which executes code on the Dart VM.
class VmTestRunner implements TestRunner {
  /// Create a new [VmTestRunner].
  VmTestRunner({
    @required this.dartExecutable,
  });

  final String dartExecutable;

  Process _process;
  var _disposed = false;

  @override
  Future<RunnerStartResult> start(
      Uri entrypoint, void Function() onExit) async {
    if (_process != null) {
      throw StateError('VmTestRunner already started');
    }
    if (_disposed) {
      throw StateError('VmTestRunner has already been disposed');
    }
    var uniqueFile = File(Object().hashCode.toString());
    if (uniqueFile.existsSync()) {
      uniqueFile.deleteSync();
    }
    _process = await Process.start(dartExecutable, <String>[
      '--enable-vm-service=0',
      '--write-service-info=${uniqueFile.path}',
      entrypoint.toString(),
    ]);
    unawaited(_process.exitCode.whenComplete(() {
      if (!_disposed) {
        onExit();
      }
    }));

    var serviceContents = await _pollForServiceFile(uniqueFile);

    return RunnerStartResult(
      isolateName: '',
      serviceUri: Uri.parse(json.decode(serviceContents)['uri'] as String),
    );
  }

  @override
  void dispose() {
    if (_process == null) {
      throw StateError('VmTestRunner has not been started');
    }
    if (_disposed) {
      throw StateError('VmTestRunner has already been disposed');
    }
    _disposed = true;
    _process.kill();
  }
}

/// A tester runner that delegates to a flutter_tester process.
class FlutterTestRunner extends TestRunner {
  /// Create a new [FlutterTestRunner].
  FlutterTestRunner({
    @required this.flutterTesterPath,
  });

  final String flutterTesterPath;

  static final _serviceRegex = RegExp(RegExp.escape('Observatory') +
      r' listening on ((http|//)[a-zA-Z0-9:/=_\-\.\[\]]+)');

  Process _process;
  bool _disposed = false;

  @override
  FutureOr<RunnerStartResult> start(
      Uri entrypoint, void Function() onExit) async {
    var uniqueFile = File(Object().hashCode.toString());
    if (uniqueFile.existsSync()) {
      uniqueFile.deleteSync();
    }
    _process = await Process.start(flutterTesterPath, <String>[
      '--enable-vm-service=0',
      '--enable-checked-mode',
      '--verify-entry-points',
      '--enable-software-rendering',
      '--skia-deterministic-rendering',
      '--enable-dart-profiling',
      '--non-interactive',
      '--use-test-fonts',
      entrypoint.toFilePath(),
    ]);
    unawaited(_process.exitCode.whenComplete(() {
      if (!_disposed) {
        onExit();
      }
    }));
    var serviceInfo = Completer<Uri>();
    StreamSubscription subscription;
    subscription = _process.stdout
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .listen((String line) {
      var match = _serviceRegex.firstMatch(line);
      if (match == null) {
        return;
      }
      serviceInfo.complete(Uri.parse(match[1]));
      subscription.cancel();
    });

    return RunnerStartResult(
        isolateName: '', serviceUri: await serviceInfo.future);
  }

  @override
  FutureOr<void> dispose() {
    if (_process == null) {
      throw StateError('VmTestRunner has not been started');
    }
    if (_disposed) {
      throw StateError('VmTestRunner has already been disposed');
    }
    _disposed = true;
    _process.kill();
  }
}

/// A test runner that spawns chrome and a dwds process.
class ChromeTestRunner extends TestRunner {
  ChromeTestRunner();

  /// The expected executable name on linux.
  static const String kLinuxExecutable = 'google-chrome';

  /// The expected executable name on macOS.
  static const String kMacOSExecutable =
      '/Applications/Google Chrome.app/Contents/MacOS/Google Chrome';

  /// The expected Chrome executable name on Windows.
  static const String kWindowsExecutable =
      r'Google\Chrome\Application\chrome.exe';

  Process _chromeProcess;
  Dwds _dwds;
  Directory _chromeTempProfile;
  HttpServer _httpServer;

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
    var chromeConnection = Completer<ChromeConnection>();

    var serverPort = await findFreePort();
    _httpServer = await HttpServer.bind('localhost', serverPort);
    _httpServer.listen((HttpRequest request) {
      request.response.write('''
<html>
    <body>
        <script src="main.dart.js"></script>
    </body>
</html>
''');
      request.response.close();
    });

    var port = await findFreePort();

    _chromeTempProfile = Directory.systemTemp.createTempSync('test_process')
      ..createSync();

    _chromeProcess = await Process.start(_findChromeExecutable(), <String>[
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
      // '--headless',
      '--disable-gpu',
      '--no-sandbox',
      '--window-size=2400,1800',
      'http://localhost:$serverPort',
    ]);

    await _chromeProcess.stderr
        .transform(utf8.decoder)
        .transform(const LineSplitter())
        .firstWhere((String line) => line.startsWith('DevTools listening'),
            orElse: () {
      return 'Failed to spawn stderr';
    });
    await _getRemoteDebuggerUrl(Uri.parse('http://localhost:$port'));
    chromeConnection.complete(ChromeConnection('localhost', port));

    _dwds = await Dwds.start(
      assetReader: FrontendServerAssetReader(
          entrypoint.toString(), File(entrypoint.toFilePath()).parent.path),
      buildResults: const Stream.empty(),
      chromeConnection: () {
        return chromeConnection.future;
      },
      serveDevTools: false,
      enableDebugging: true,
      loadStrategy: RequireStrategy(
        ReloadConfiguration.none,
        '',
        null,
        null,
        null,
        null,
        null,
      ),
    );

    await for (var connection in _dwds.connectedApps) {
      connection.runMain();
      var debugConnection = await _dwds.debugConnection(connection);
      return RunnerStartResult(
        isolateName: '',
        serviceUri: Uri.parse(debugConnection.uri),
      );
    }
    throw Exception();
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

  /// Returns the full URL of the Chrome remote debugger for the main page.
  ///
  /// This takes the [base] remote debugger URL (which points to a browser-wide
  /// page) and uses its JSON API to find the resolved URL for debugging the host
  /// page.
  Future<Uri> _getRemoteDebuggerUrl(Uri base) async {
    try {
      var client = HttpClient();
      var request = await client.getUrl(base.resolve('/json/list'));
      var response = await request.close();
      var jsonObject =
          await json.fuse(utf8).decoder.bind(response).single as List<dynamic>;
      if (jsonObject == null || jsonObject.isEmpty) {
        return base;
      }
      return base.resolve(jsonObject.first['devtoolsFrontendUrl'] as String);
    } on Exception {
      // If we fail to talk to the remote debugger protocol, give up and return
      // the raw URL rather than crashing.
      return base;
    }
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
