// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:io';

void main() async {
  var result = await Process.run(
      'dart', <String>['bin/main.dart', '--project-root=test_project']);

  expect(
      result.stdout,
      (dynamic line) => line.contains(
            'Tests that a sync function that returns an object completes normally.',
          ),
      'prints message from doc comment');

  expect(
      result.stdout,
      (dynamic line) =>
          line.contains(
              '// Copyright 2014 The Flutter Authors. All rights reserved.\n'
              '// Use of this source code is governed by a BSD-style license that can be\n'
              '// found in the LICENSE file.') ==
          false,
      'does not include license header');

  expect(
      result.stdout,
      (dynamic line) => line.contains('This is not included') == false,
      'does not include code comment');

  expect(
      result.stdout,
      (dynamic line) => line.contains(
            '4/9 tests passed.',
          ),
      'all expected tests pass and fail');
}

void expect(dynamic a, dynamic Function(dynamic) predicate, String cause) {
  if (predicate(a) == false) {
    stderr.write('FAIL');
    stderr.writeln(cause);
    exit(1);
  } else {
    stderr.writeln('PASS');
  }
}
