// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

import 'dart:async';

// ignore_for_file: implementation_imports
import 'package:test_api/src/backend/declarer.dart';
import 'package:test_api/src/backend/group.dart';
import 'package:test_api/src/backend/group_entry.dart';
import 'package:test_api/src/backend/test.dart';
import 'package:test_api/src/backend/suite.dart';
import 'package:test_api/src/backend/live_test.dart';
import 'package:test_api/src/backend/suite_platform.dart';
import 'package:test_api/src/backend/runtime.dart';
import 'package:test_api/src/backend/message.dart';
import 'package:test_api/src/backend/invoker.dart';
import 'package:test_api/src/backend/state.dart';

Future<void> testCompat(FutureOr<void> Function() testFunction) async {
  var declarer = Declarer();
  var innerZone = Zone.current.fork(zoneValues: {#test.declarer: declarer});
  String errors;
  await innerZone.run(() async {
    await Invoker.guard<Future<void>>(() async {
      final _Reporter reporter = _Reporter();
      await testFunction();
      final Group group = declarer.build();
      final Suite suite = Suite(group, SuitePlatform(Runtime.vm));
      await _runGroup(suite, group, <Group>[], reporter);
      errors = reporter._onDone();
    });
  });
  if (errors != null) {
    throw Exception(errors);
  }
}

Future<void> _runGroup(Suite suiteConfig, Group group, List<Group> parents,
    _Reporter reporter) async {
  parents.add(group);
  try {
    final bool skipGroup = group.metadata.skip;
    bool setUpAllSucceeded = true;
    if (!skipGroup && group.setUpAll != null) {
      final LiveTest liveTest =
          group.setUpAll.load(suiteConfig, groups: parents);
      await _runLiveTest(suiteConfig, liveTest, reporter, countSuccess: false);
      setUpAllSucceeded = liveTest.state.result.isPassing;
    }
    if (setUpAllSucceeded) {
      for (final GroupEntry entry in group.entries) {
        if (entry is Group) {
          await _runGroup(suiteConfig, entry, parents, reporter);
        } else if (entry.metadata.skip) {
          await _runSkippedTest(suiteConfig, entry as Test, parents, reporter);
        } else {
          final Test test = entry as Test;
          await _runLiveTest(
              suiteConfig, test.load(suiteConfig, groups: parents), reporter);
        }
      }
    }
    // Even if we're closed or setUpAll failed, we want to run all the
    // teardowns to ensure that any state is properly cleaned up.
    if (!skipGroup && group.tearDownAll != null) {
      final LiveTest liveTest =
          group.tearDownAll.load(suiteConfig, groups: parents);
      await _runLiveTest(suiteConfig, liveTest, reporter, countSuccess: false);
    }
  } finally {
    parents.remove(group);
  }
}

Future<void> _runLiveTest(
    Suite suiteConfig, LiveTest liveTest, _Reporter reporter,
    {bool countSuccess = true}) async {
  reporter._onTestStarted(liveTest);
  await null;
  await liveTest.run();

  // Once the test finishes, use await null to do a coarse-grained event
  // loop pump to avoid starving non-microtask events.
  await null;
  final bool isSuccess = liveTest.state.result.isPassing;
  if (isSuccess) {
    reporter.passed.add(liveTest);
  } else {
    reporter.failed.add(liveTest);
  }
}

Future<void> _runSkippedTest(Suite suiteConfig, Test test, List<Group> parents,
    _Reporter reporter) async {
  final LocalTest skipped =
      LocalTest(test.name, test.metadata, () {}, trace: test.trace);
  final LiveTest liveTest = skipped.load(suiteConfig);
  reporter._onTestStarted(liveTest);
  reporter.skipped.add(skipped);
}

class _Reporter {
  final passed = <LiveTest>[];
  final failed = <LiveTest>[];
  final skipped = <Test>[];

  /// The set of all subscriptions to various streams.
  final Set<StreamSubscription<void>> _subscriptions =
      <StreamSubscription<void>>{};

  final failedErrors = <LiveTest, List<dynamic>>{};
  final failedStackTraces = <LiveTest, List<dynamic>>{};

  /// A callback called when the engine begins running [liveTest].
  void _onTestStarted(LiveTest liveTest) {
    _subscriptions.add(liveTest.onStateChange
        .listen((State state) => _onStateChange(liveTest, state)));
    _subscriptions.add(liveTest.onError.listen((AsyncError error) =>
        _onError(liveTest, error.error, error.stackTrace)));
    _subscriptions.add(liveTest.onMessage.listen((Message message) {}));
  }

  void _onStateChange(LiveTest liveTest, State state) {
    if (state.status != Status.complete) {
      return;
    }
  }

  void _onError(LiveTest liveTest, Object error, StackTrace stackTrace) {
    (failedErrors[liveTest] ??= <dynamic>[]).add(error);
    (failedStackTraces[liveTest] ??= <dynamic>[]).add(stackTrace);
  }

  /// A callback called when the engine is finished running tests.
  ///
  /// [success] will be `true` if all tests passed, `false` if some tests
  /// failed, and `null` if the engine was closed prematurely.
  String _onDone() {
    if (failed.isNotEmpty) {
      var buffer = StringBuffer();
      for (var fail in failed) {
        buffer.write(_description(fail));
        var errors = failedErrors[fail] ?? <dynamic>[];
        for (var i = 0; i < errors.length; i++) {
          buffer.writeln(errors[i]);
        }
      }
      return buffer.toString();
    }
    return null;
  }

  /// Returns a description of [liveTest].
  ///
  /// This differs from the test's own description in that it may also include
  /// the suite's name.
  String _description(LiveTest liveTest) {
    String name = liveTest.test.name;
    if (liveTest.suite.path != null) {
      name = '${liveTest.suite.path}: $name';
    }
    return name;
  }
}
