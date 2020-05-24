// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:io';
import 'dart:typed_data';

import 'package:_fe_analyzer_shared/src/parser/parser.dart';
import 'package:_fe_analyzer_shared/src/scanner/token.dart';
import 'package:_fe_analyzer_shared/src/parser/listener.dart';
import 'package:_fe_analyzer_shared/src/scanner/utf8_bytes_scanner.dart';

/// An abstraction layer over the analyzer API.
class TestInformationProvider {
  const TestInformationProvider();

  /// Collect all top-level methods that begin with 'test'.
  List<TestInfo> collectTestInfo(Uri testFileUri) {
    var rawBytes = File(testFileUri.toFilePath()).readAsBytesSync();
    var bytes = Uint8List(rawBytes.length + 1);
    bytes.setRange(0, rawBytes.length, rawBytes);
    var scanner = Utf8BytesScanner(
      bytes,
      includeComments: true,
    );
    var firstToken = scanner.tokenize();
    var collector = TestNameCollector(testFileUri);
    Parser(collector).parseUnit(firstToken);
    return collector.testInfo;
  }
}

class TestInfo {
  const TestInfo({
    this.name,
    this.description,
    this.testFileUri,
  });

  final String name;
  final String description;
  final Uri testFileUri;
}

/// Collect the names of top level methods that begin with tests.
///
/// If there is a block comment prior to the test with a `[test]` string,
/// include that as the test description.
class TestNameCollector extends Listener {
  TestNameCollector(this.testFileUri);

  final Uri testFileUri;

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
    ));
  }
}
