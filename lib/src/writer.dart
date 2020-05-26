// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

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

/// A [TestWriter] that outputs to a terminal.
class TerminalTestWriter extends TestWriter {
  TerminalTestWriter({
    @required this.projectRoot,
    @required this.verbose,
  });

  final bool verbose;
  final stopwatch = Stopwatch();
  final String projectRoot;
  final console = Console();
  int passed = 0;
  int failed = 0;

  @override
  void writeHeader() {
    passed = 0;
    failed = 0;
    stopwatch.start();
  }

  @override
  void writeTest(TestResult testResult, TestInfo testInfo) {
    var humanFileName = path.relative(
      testResult.testFileUri.toFilePath(),
      from: projectRoot,
    );
    if (testResult.passed) {
      passed += 1;
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
    failed += 1;
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

      var index = startLine;
      var prefix = '';
      for (var line in testRange) {
        if (index == testFrame.line - 1) {
          console
            ..write(' ')
            ..setForegroundColor(ConsoleColor.brightRed)
            ..write('>')
            ..resetColorAttributes()
            ..setForegroundExtendedColor(_kGreyColor);
          prefix = '  $index| ';
          console.write(prefix);
          prefix = ' >' + prefix;
          console.resetColorAttributes();
        } else if (line.trim().isEmpty) {
          index += 1;
          continue;
        } else {
          prefix = '    $index| ';
          console
            ..setForegroundExtendedColor(_kGreyColor)
            ..write(prefix)
            ..resetColorAttributes();
        }
        console.writeLine(line);
        index += 1;
      }
      console
        ..setForegroundColor(ConsoleColor.brightRed)
        ..writeLine((' ' * (prefix.length + testFrame.column - 1)) + '^')
        ..resetColorAttributes()
        ..write('\n');
    }

    if (verbose) {
      for (var frame in trace.frames) {
        console.writeLine(_indent(frame.toString(), 4));
      }
      console.writeLine();
    }
  }

  @override
  void writeSummary() {
    stopwatch.stop();
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
