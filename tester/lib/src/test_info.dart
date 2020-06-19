// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:typed_data';

import 'package:file/local.dart';
import 'package:meta/meta.dart';
import 'package:file/file.dart';

import 'package:_fe_analyzer_shared/src/parser/parser.dart';
import 'package:_fe_analyzer_shared/src/scanner/token.dart';
import 'package:_fe_analyzer_shared/src/parser/listener.dart';
import 'package:_fe_analyzer_shared/src/scanner/utf8_bytes_scanner.dart';

import 'config.dart';
import 'platform.dart';

/// An abstraction layer over the analyzer API.
class TestInformationProvider {
  TestInformationProvider({
    this.fileSystem = const LocalFileSystem(),
    this.platform = const LocalPlatform(),
    @required this.config,
  });

  final FileSystem fileSystem;
  final Platform platform;
  final Config config;

  /// Collect all top-level methods that begin with 'test'.
  List<TestInfo> collectTestInfo(Uri testFileUri) {
    var testUri = testFileUri.toFilePath(windows: platform.isWindows);
    var relativePath = fileSystem
        .file(fileSystem.path.relative(
          testUri,
          from: config.packageRootPath,
        ))
        .uri;
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
    );
    Parser(collector).parseUnit(firstToken);
    return collector.testInfo;
  }
}

class TestInfo {
  const TestInfo({
    this.name,
    this.description,
    this.testFileUri,
    this.testToken,
    this.multiRootUri,
    this.line,
    this.column,
  });

  final String name;
  final String description;
  final Uri testFileUri;
  final String multiRootUri;
  final Token testToken;
  final int line;
  final int column;
}

/// Collect the names of top level methods that begin with tests.
///
/// If there is a block comment prior to the test with a `[test]` string,
/// include that as the test description.
class TestNameCollector extends Listener {
  TestNameCollector(
      this.testFileUri, this.testToken, this.multiRootUri, this.offsetTable);

  final Uri testFileUri;
  final String multiRootUri;
  final Token testToken;
  final Map<int, int> offsetTable;

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
    if (!name.startsWith('test')) {
      return;
    }
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
      testToken: testToken,
      multiRootUri: multiRootUri,
      line: offsetTable[beginToken.offset],
    ));
  }
}
