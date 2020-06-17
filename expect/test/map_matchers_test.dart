// Copyright (c) 2012, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';
import 'test_utils.dart';

testContains() {
  shouldPass({'a': 1}, contains('a'));
  shouldPass({null: 1}, contains(null));
  shouldFail(
    {'a': 1},
    contains(2),
    'Expected: contains <2> '
    'Actual: {\'a\': 1}',
  );
  shouldFail(
    {'a': 1},
    contains(null),
    'Expected: contains <null> '
    'Actual: {\'a\': 1}',
  );
}

testContainsValue() {
  shouldPass({'a': 1, 'null': null}, containsValue(1));
  shouldPass({'a': 1, 'null': null}, containsValue(null));
  shouldFail(
    {'a': 1, 'null': null},
    containsValue(2),
    'Expected: contains value <2> '
    "Actual: {'a': 1, 'null': null}",
  );
}

testContainsPair() {
  shouldPass({'a': 1, 'null': null}, containsPair('a', 1));
  shouldPass({'a': 1, 'null': null}, containsPair('null', null));
  shouldPass({null: null}, containsPair(null, null));
  shouldFail(
    {'a': 1, 'null': null},
    containsPair('a', 2),
    "Expected: contains pair 'a' => <2> "
    "Actual: {'a': 1, 'null': null} "
    "Which:  contains key 'a' but with value is <1>",
  );
  shouldFail(
    {'a': 1, 'null': null},
    containsPair('b', 1),
    "Expected: contains pair 'b' => <1> "
    "Actual: {'a': 1, 'null': null} "
    "Which:  doesn't contain key 'b'",
  );
  shouldFail(
    {'a': 1, 'null': null},
    containsPair('null', 2),
    "Expected: contains pair 'null' => <2> "
    "Actual: {'a': 1, 'null': null} "
    "Which:  contains key 'null' but with value is <null>",
  );
  shouldFail(
    {'a': 1, 'null': null},
    containsPair('2', null),
    "Expected: contains pair '2' => <null> "
    "Actual: {'a': 1, 'null': null} "
    "Which:  doesn't contain key '2'",
  );
  shouldFail(
    {'a': 1, 'null': null},
    containsPair('2', 'b'),
    "Expected: contains pair '2' => 'b' "
    "Actual: {'a': 1, 'null': null} "
    "Which:  doesn't contain key '2'",
  );
  shouldFail(
    {null: null},
    containsPair('not null', null),
    "Expected: contains pair 'not null' => <null> "
    'Actual: {null: null} '
    "Which:  doesn't contain key 'not null'",
  );
  shouldFail(
    {null: null},
    containsPair(null, 'not null'),
    'Expected: contains pair <null> => \'not null\' '
    'Actual: {null: null} '
    'Which: contains key <null> but with value not an '
    '<Instance of \'String\'>',
  );
  shouldFail(
    {null: null},
    containsPair('not null', 'not null'),
    'Expected: contains pair \'not null\' => \'not null\' '
    'Actual: {null: null} '
    'Which:  doesn\'t contain key \'not null\' ',
  );
}
