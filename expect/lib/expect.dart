// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'dart:async';

import 'package:matcher/matcher.dart';
export 'package:matcher/matcher.dart';

/// Assert that [actual] matches [matcher].
///
/// This is the main assertion function. [reason] is optional and is typically
/// not supplied, as a reason is generated from [matcher]; if [reason]
/// is included it is appended to the reason generated by the matcher.
///
/// [matcher] can be a value in which case it will be wrapped in an
/// [equals] matcher.
///
/// If the assertion fails a [String] is thrown.
void expect(dynamic actual, dynamic matcher, {String reason}) {
  var wrappedMatcher = wrapMatcher(matcher);
  var matchState = <dynamic, dynamic>{};
  try {
    if (wrappedMatcher.matches(actual, matchState)) {
      return null;
    }
  } catch (_) {
    // Do nothing
  }
  final String result = _errorMessage(
    wrappedMatcher,
    actual,
    matchState,
    reason,
  );
  throw result;
}

/// Assert that [actual] throws a synchronous error that matches [matcher].
///
/// [matcher] can be a value in which case it will be wrapped in an
/// [equals] matcher.
///
/// If the assertion fails a [String] is thrown.
void throws(void Function() actual, dynamic matcher, {String reason}) {
  var wrappedMatcher = wrapMatcher(matcher);
  var matchState = <dynamic, dynamic>{};
  dynamic error;
  try {
    var result = actual() as dynamic;
    assert(result is! Future,
        'use throwsAsync to ensure async errors are handled correctly.');
  } catch (err) {
    error = err;
  }
  if (wrappedMatcher.matches(error, matchState)) {
    return null;
  }
  var mismatchDescription = StringDescription();
  wrappedMatcher.describeMismatch(
    actual,
    mismatchDescription,
    matchState,
    false,
  );
  final String result = _errorMessage(
    wrappedMatcher,
    actual,
    matchState,
    reason,
  );
  throw result;
}

/// Assert that [actual] throws an asynchronous error that matches [matcher].
///
/// [matcher] can be a value in which case it will be wrapped in an
/// [equals] matcher.
///
/// If the assertion fails a [String] is thrown.
Future<void> throwsAsync(Future<void> Function() actual, dynamic matcher,
    {String reason}) async {
  var wrappedMatcher = wrapMatcher(matcher);
  var matchState = <dynamic, dynamic>{};
  dynamic error;
  try {
    await actual();
  } catch (err) {
    error = err;
  }
  if (wrappedMatcher.matches(error, matchState)) {
    return null;
  }
  final String result = _errorMessage(
    wrappedMatcher,
    actual,
    matchState,
    reason,
  );
  throw result;
}

String _errorMessage(
    Matcher wrappedMatcher, dynamic actual, Map matchState, String reason) {
  var mismatchDescription = StringDescription();
  wrappedMatcher.describeMismatch(
    actual,
    mismatchDescription,
    matchState,
    false,
  );
  var buffer = StringBuffer()
    ..write('Expected: ')
    ..writeln(_prettyPrint(wrappedMatcher))
    ..write('  Actual: ')
    ..writeln(_prettyPrint(actual));
  var which = mismatchDescription.toString();
  if (which.isNotEmpty) {
    buffer
      ..write('   Which: ')
      ..writeln(which);
  }
  if (reason != null) {
    buffer.writeln(reason);
  }
  return buffer.toString();
}

String _prettyPrint(dynamic value) =>
    StringDescription().addDescriptionOf(value).toString();
