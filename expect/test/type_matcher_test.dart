// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';

import 'test_utils.dart';

void main() {
  _test(isMap, {}, name: 'Map');
  _test(isList, [], name: 'List');
  _test(isArgumentError, ArgumentError());
  _test<Exception>(isException, const FormatException());
  _test(isFormatException, const FormatException());
  _test(isStateError, StateError('oops'));
  _test(isRangeError, RangeError('oops'));
  _test(isUnimplementedError, UnimplementedError('oops'));
  _test(isUnsupportedError, UnsupportedError('oops'));
  _test(isConcurrentModificationError, ConcurrentModificationError());
  _test(isCyclicInitializationError, CyclicInitializationError());
  _test<NoSuchMethodError>(isNoSuchMethodError, null);
  _test(isNullThrownError, NullThrownError());
  _test(const _StringMatcher(), 'hello');
  _test(const TypeMatcher<String>(), 'hello');
  _test(isA<String>(), 'hello');
}

void _test<T>(Matcher typeMatcher, T matchingInstance, {String name}) {
  name ??= T.toString();
  shouldPass(matchingInstance, typeMatcher);
  shouldFail(
    const _TestType(),
    typeMatcher,
    "Expected: <Instance of '$name'> Actual: <Instance of '_TestType'>"
    " Which: is not an instance of '$name'",
  );
}

// Validate that existing implementations continue to work.
class _StringMatcher extends TypeMatcher {
  const _StringMatcher();

  @override
  bool matches(item, Map matchState) => item is String;
}

class _TestType {
  const _TestType();
}
