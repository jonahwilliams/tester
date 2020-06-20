// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:io';
import 'dart:math' as math;

import 'package:meta/meta.dart';
import 'package:dart_console/dart_console.dart';
import 'package:stack_trace/stack_trace.dart';

import 'isolate.dart';
import 'test_info.dart';
import 'package:path/path.dart' as path;

/// A class that outputs test results for humans or machines to interpret.
abstract class TestWriter {
  factory TestWriter({
    @required String projectRoot,
    @required bool verbose,
    @required bool ci,
    @required int testCount,
  }) {
    if (ci) {
      return CiTestWriter();
    }
    return TerminalTestWriter(
      projectRoot: projectRoot,
      verbose: verbose,
      testCount: testCount,
    );
  }

  /// Update the results of a test.
  void writeTest(TestResult result, TestInfo testInfo);

  /// Update the test header.
  void writeHeader() {}

  /// Update the test summary field.
  ///
  /// This method is called once all tests have finished.
  void writeSummary();

  /// The exit code for the test process.
  int get exitCode;
}

const int _kGreyColor = 241;

class CiTestWriter implements TestWriter {
  @override
  int get exitCode => failed == 0 ? 0 : 1;

  int passed = 0;
  int failed = 0;
  final stopwatch = Stopwatch();

  @override
  void writeHeader() {
    passed = 0;
    failed = 0;
    stopwatch.start();
  }

  @override
  void writeSummary() {
    print(
      '${passed} passed, ${failed} failed out of ${passed + failed}'
      ' in ${stopwatch.elapsedMilliseconds} ms',
    );
  }

  @override
  void writeTest(TestResult result, TestInfo testInfo) {
    if (result.passed) {
      passed += 1;
    } else {
      print(result.errorMessage);
      print(result.stackTrace);
      failed += 1;
    }
    print(
      '${result.testFileUri}${result.testName}:'
      ' ${result.passed ? 'PASS' : 'FAIL'}',
    );
  }
}

/// A [TestWriter] that outputs to a terminal.
class TerminalTestWriter implements TestWriter {
  TerminalTestWriter({
    @required this.projectRoot,
    @required this.verbose,
    @required this.testCount,
  });

  final bool verbose;
  final stopwatch = Stopwatch();
  final String projectRoot;
  final failedResults = <TestResult>[];
  final failedInfos = <TestInfo>[];
  final console = Console();
  final int testCount;
  int passed = 0;
  int failed = 0;
  int lastUpdate = -1;

  @override
  void writeHeader() {
    passed = 0;
    failed = 0;
    failedResults.clear();
    failedInfos.clear();
    stopwatch.start();
    lastUpdate = 0;
  }

  @override
  void writeTest(TestResult testResult, TestInfo testInfo) {
    if (testResult.passed) {
      passed += 1;
    } else {
      failedResults.add(testResult);
      failedInfos.add(testInfo);
      failed += 1;
    }
    if (stopwatch.elapsedMilliseconds - lastUpdate >= 16) {
      console
        ..setBackgroundColor(ConsoleColor.yellow)
        ..setForegroundColor(ConsoleColor.black)
        ..write(' RUNNING ')
        ..resetColorAttributes()
        ..setForegroundExtendedColor(_kGreyColor)
        ..write(' ${passed + failed}/ $testCount ')
        ..resetColorAttributes()
        ..write('\n');
      lastUpdate = stopwatch.elapsedMilliseconds;
    }
  }

  void writePassedTest(TestResult testResult, TestInfo testInfo) {
    var humanFileName = path.relative(
      testResult.testFileUri.toFilePath(),
      from: projectRoot,
    );
    console
      ..setBackgroundColor(ConsoleColor.brightGreen)
      ..setForegroundColor(ConsoleColor.black)
      ..write(' PASS ')
      ..resetColorAttributes()
      ..setForegroundExtendedColor(_kGreyColor)
      ..write(' $humanFileName ')
      ..resetColorAttributes()
      ..write(testInfo.name)
      ..write('\n');
    return;
  }

  void _writeFailedTest(TestResult testResult, TestInfo testInfo) {
    var humanFileName = path.relative(
      testResult.testFileUri.toFilePath(),
      from: projectRoot,
    );
    console
      ..setBackgroundColor(ConsoleColor.brightRed)
      ..setForegroundColor(ConsoleColor.black)
      ..write(' FAIL ')
      ..resetColorAttributes()
      ..setForegroundExtendedColor(_kGreyColor)
      ..write(' $humanFileName ')
      ..resetColorAttributes()
      ..write(testInfo.name)
      ..write('\n\n');
    if (testInfo.description != null) {
      console.write(_indent(testInfo.description, 2));
    }
    console
      ..writeLine()
      ..writeLine(_indent(testResult.errorMessage, 2))
      ..writeLine();

    var trace = Trace.parse(testResult.stackTrace);
    var testFrame = trace.frames.firstWhere(
      (Frame frame) {
        if (frame.uri == testInfo.testFileUri) {
          return true;
        }
        var relativePathTest = frame.uri.scheme == 'file'
            ? path.relative(
                frame.uri.toFilePath(),
                from: Directory.current.path,
              )
            : frame.uri.path;
        if (testResult.testFileUri.toString().endsWith(relativePathTest)) {
          return true;
        }
        return false;
      },
      orElse: () => null,
    );

    if (testFrame != null) {
      var testFile = File(testInfo.testFileUri.toFilePath());
      var testLines = testFile.readAsLinesSync();
      var startLine = math.max(0, testFrame.line - 4);
      var testRange = testLines.sublist(startLine, testFrame.line);
      var indentWidth = 4 + (startLine + 5).toString().length;

      var index = startLine + 1;
      var prefix = '';
      for (var line in testRange) {
        var spaces = indentWidth - index.toString().length;
        if (index == testFrame.line) {
          console
            ..write(' ')
            ..setForegroundColor(ConsoleColor.brightRed)
            ..write('>')
            ..resetColorAttributes()
            ..setForegroundExtendedColor(_kGreyColor);
          prefix = '${' ' * (spaces - 2)}$index| ';
          console.write(prefix);
          prefix = ' >' + prefix;
          console.resetColorAttributes();
        } else if (line.trim().isEmpty) {
          index += 1;
          continue;
        } else {
          prefix = '${' ' * (spaces)}$index| ';
          console
            ..setForegroundExtendedColor(_kGreyColor)
            ..write(prefix)
            ..resetColorAttributes();
        }
        console.writeLine(line);
        index += 1;
      }
      var spaces = indentWidth - index.toString().length;
      console
        ..setForegroundExtendedColor(_kGreyColor)
        ..write('${' ' * indentWidth}| ')
        ..setForegroundColor(ConsoleColor.brightRed)
        ..writeLine((' ' * (testFrame.column + spaces - 5)) + '^')
        ..resetColorAttributes();

      prefix = '${' ' * (spaces)}$index| ';
      if (testLines.length > index - 1) {
        console
          ..setForegroundExtendedColor(_kGreyColor)
          ..write(prefix)
          ..resetColorAttributes()
          ..writeLine(testLines[index - 1])
          ..writeLine();
      }
    }

    for (var frame in trace.frames) {
      console.writeLine(_indent(frame.toString(), 4));
      if (!verbose && frame == testFrame) {
        break;
      }
    }
    console.writeLine();
  }

  @override
  void writeSummary() {
    console.write('\n');
    stopwatch.stop();
    for (var i = 0; i < failedResults.length; i++) {
      _writeFailedTest(failedResults[i], failedInfos[i]);
    }
    if (failed > 0) {
      console
        ..write('  ')
        ..setForegroundColor(ConsoleColor.brightRed)
        ..write('$failed failed')
        ..resetColorAttributes()
        ..write(', ')
        ..setForegroundColor(ConsoleColor.brightGreen)
        ..write('$passed passed')
        ..resetColorAttributes();
    } else {
      console
        ..write('  ')
        ..setForegroundColor(ConsoleColor.brightGreen)
        ..writeLine('all tests passed.')
        ..resetColorAttributes();
    }
    console
      ..writeLine(
          '  ${failed + passed} test(s) in ${stopwatch.elapsedMilliseconds} ms elapsed.')
      ..writeLine();
  }

  @override
  int get exitCode => failed == 0 ? 0 : 1;

  String _indent(String content, int count) {
    return content
        .split('\n')
        .map((String line) => ' ' * count + line)
        .join('\n');
  }
}
