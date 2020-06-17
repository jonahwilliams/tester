// Copyright (c) 2020, the Dart project authors.  Please see the AUTHORS file
// for details. All rights reserved. Use of this source code is governed by a
// BSD-style license that can be found in the LICENSE file.

import 'package:expect/expect.dart';

void shouldFail(value, Matcher matcher, expected) {
  var failed = false;
  try {
    expect(value, matcher);
  } catch (err) {
    failed = true;
    var errorString = err.toString();

    if (expected is String) {
      expect(errorString, equalsIgnoringWhitespace(expected));
    } else {
      expect(errorString.replaceAll('\n', ''), expected);
    }
  }

  expect(failed, isTrue, reason: 'Expected to fail.');
}

void shouldPass(value, Matcher matcher) {
  expect(value, matcher);
}

void doesNotThrow() {}
void doesThrow() {
  throw StateError('X');
}

class Widget {
  int price;
}

class SimpleIterable extends Iterable<int> {
  final int count;

  SimpleIterable(this.count);

  @override
  Iterator<int> get iterator => _SimpleIterator(count);
}

class _SimpleIterator implements Iterator<int> {
  int _count;
  int _current;

  _SimpleIterator(this._count);

  @override
  bool moveNext() {
    if (_count > 0) {
      _current = _count;
      _count--;
      return true;
    }
    _current = null;
    return false;
  }

  @override
  int get current => _current;
}
