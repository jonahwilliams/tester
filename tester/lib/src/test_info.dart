// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:convert';
import 'dart:typed_data';

import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:file/file.dart';

import 'package:_fe_analyzer_shared/src/parser/parser.dart';
import 'package:_fe_analyzer_shared/src/scanner/token.dart';
import 'package:_fe_analyzer_shared/src/parser/listener.dart';
import 'package:_fe_analyzer_shared/src/scanner/utf8_bytes_scanner.dart';

import 'platform.dart';

/// An abstraction layer over the analyzer API.
class TestInformationProvider {
  TestInformationProvider({
    this.fileSystem = const LocalFileSystem(),
    this.platform = const LocalPlatform(),
    @required this.testCompatMode,
    @required this.packagesRootPath,
    @required this.testManifestPath,
  });

  final FileSystem fileSystem;
  final Platform platform;
  final String packagesRootPath;
  final String testManifestPath;
  final bool testCompatMode;

  final cachedData = <Uri, List<TestInfo>>{};
  final cachedStats = <Uri, DateTime>{};

  static const _version = 1;

  /// Load the info cache from disk.
  ///
  /// On failures the exception is caught and ignored.
  void loadTestInfos() {
    if (testManifestPath == null) {
      return;
    }
    File cacheFile;
    try {
      cacheFile = fileSystem.file(testManifestPath);
      if (!cacheFile.existsSync()) {
        return;
      }
      var rawManifest =
          json.decode(cacheFile.readAsStringSync()) as Map<String, Object>;
      if (rawManifest['v'] != _version) {
        cacheFile.deleteSync();
        return;
      }
      var files = rawManifest['f'] as List<dynamic>;
      for (var file in files) {
        var stat = file['s'] as String;
        var uri = Uri.parse(file['u'] as String);
        var newStat = fileSystem.file(uri).lastModifiedSync();
        if ((newStat.toIso8601String()) == stat && newStat != null) {
          var infos = <TestInfo>[];
          var datas = file['ds'] as List<dynamic>;
          for (var data in datas) {
            infos.add(TestInfo.fromJson(data as Map<String, Object>));
          }
          cachedData[uri] = infos;
          cachedStats[uri] = newStat;
        }
      }
    } catch (err) {
      // Do nothing, caching has failed.
      if (cacheFile != null && cacheFile.existsSync()) {
        cacheFile.deleteSync();
      }
    }
  }

  /// Persist the info cache to disk.
  ///
  /// On failures the exception is caught and ignored.
  void storeTestInfos() {
    if (testManifestPath == null) {
      return;
    }
    try {
      var cacheFile = fileSystem.file(testManifestPath);
      if (!cacheFile.parent.existsSync()) {
        cacheFile.parent.createSync(recursive: true);
      }
      cacheFile.writeAsStringSync(
        json.encode(<String, Object>{
          'v': _version,
          'f': [
            for (var uri in cachedData.keys)
              {
                's': cachedStats[uri]?.toIso8601String(),
                'u': uri.toString(),
                'ds': [
                  for (var info in cachedData[uri]) info.toJson(),
                ],
              },
          ],
        }),
      );
    } on Exception {
      // Do nothing, caching has failed.
    }
  }

  /// Collect all top-level methods that begin with 'test'.
  TestInfos collectTestInfos(List<Uri> testFileUris) {
    var result = TestInfos();
    for (var testFileUri in testFileUris) {
      var infos = _collectTestInfo(testFileUri);
      result.testCount += infos.length;
      result.testInformation[testFileUri] = infos;
    }
    return result;
  }

  List<TestInfo> _collectTestInfo(Uri testFileUri) {
    var cachedInfos = cachedData[testFileUri];
    if (cachedInfos != null) {
      return cachedInfos;
    }
    var testUri = testFileUri.toFilePath(windows: platform.isWindows);
    var relativePath = fileSystem
        .file(fileSystem.path.relative(
          testUri,
          from: packagesRootPath,
        ))
        .uri;
    var lastModified = fileSystem.file(testUri).lastModifiedSync();
    var rawBytes = fileSystem.file(testUri).readAsBytesSync();
    var bytes = Uint8List(rawBytes.length + 1);
    bytes.setRange(0, rawBytes.length, rawBytes);
    var scanner = Utf8BytesScanner(
      bytes,
      includeComments: true,
    );
    var firstToken = scanner.tokenize();

    var offsetTable = <int, int>{};
    var offset = 0;
    var line = 0;
    for (var byte in rawBytes) {
      offsetTable[offset] = line;
      if (byte == 0xA) {
        line += 1;
      }
      offset += 1;
    }
    var collector = TestNameCollector(
      testFileUri,
      firstToken,
      'org-dartlang-app:///$relativePath',
      offsetTable,
      testCompatMode,
    );
    Parser(collector).parseUnit(firstToken);
    cachedStats[testFileUri] = lastModified;
    return cachedData[testFileUri] = collector.testInfo;
  }
}

class TestInfos {
  var testCount = 0;
  final testInformation = <Uri, List<TestInfo>>{};
}

class TestInfo {
  const TestInfo({
    this.name,
    this.description,
    this.testFileUri,
    this.multiRootUri,
    this.line,
    this.column,
    this.compatTest,
  });

  /// Create a [TestInfo] from a JSON object.
  factory TestInfo.fromJson(Map<String, Object> json) {
    return TestInfo(
      name: json['n'] as String,
      description: json['d'] as String,
      testFileUri: Uri.parse(json['u'] as String),
      multiRootUri: json['s'] as String,
      line: json['l'] as int,
      column: json['c'] as int,
      compatTest: json['ct'] as bool,
    );
  }

  final String name;
  final String description;
  final Uri testFileUri;
  final String multiRootUri;
  final int line;
  final int column;
  final bool compatTest;

  /// Convert [TestInfo] to a JSON serializable object.
  Map<String, Object> toJson() {
    return <String, Object>{
      'n': name,
      'd': description,
      'u': testFileUri.toString(),
      's': multiRootUri,
      'l': line,
      'c': column,
      'ct': compatTest,
    };
  }
}

/// Collect the names of top level methods that begin with tests.
///
/// If there is a block comment prior to the test with a `[test]` string,
/// include that as the test description.
class TestNameCollector extends Listener {
  TestNameCollector(
    this.testFileUri,
    this.testToken,
    this.multiRootUri,
    this.offsetTable,
    this.testCompatMode,
  );

  final Uri testFileUri;
  final String multiRootUri;
  final Token testToken;
  final Map<int, int> offsetTable;
  final bool testCompatMode;

  final testInfo = <TestInfo>[];

  @override
  void endTopLevelMethod(Token beginToken, Token getOrSet, Token endToken) {
    // Locate the identifier for a top level method by looking for the start
    // of the formal parmaeters:
    // void <NAME> (
    //             ^
    var nameToken = beginToken;
    while (nameToken.next.type != TokenType.OPEN_PAREN && !nameToken.isEof) {
      nameToken = nameToken.next;
    }
    var name = nameToken.toString();
    if (!name.startsWith('test') && (name != 'main')) {
      return;
    }

    if (!testCompatMode && name == 'main') {
      return;
    }
    var compatTest = name == 'main';

    // Check the previous token for a comment and include if  a doc comment `///`
    // is present.
    var description = StringBuffer();
    var comment = beginToken.precedingComments;
    while (comment != null) {
      var content = comment.toString();
      if (content.startsWith('///')) {
        description.writeln(content.substring(3).trim());
      }
      comment = comment.next as CommentToken;
    }
    testInfo.add(TestInfo(
      name: name,
      description: description.toString(),
      testFileUri: testFileUri,
      multiRootUri: multiRootUri,
      line: offsetTable[beginToken.offset],
      compatTest: compatTest,
    ));
  }
}
