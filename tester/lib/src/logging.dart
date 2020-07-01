// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.

// @dart=2.8
import 'dart:async';
import 'package:logging/logging.dart';

Future<T> measureCommand<T>(
    FutureOr<T> Function() cb, String name, Logger logger) async {
  logger.log(Level.INFO, 'starting $name');
  var sw = Stopwatch()..start();
  var result = await cb();
  sw.stop();
  logger.log(Level.INFO, '$name: ${sw.elapsedMilliseconds} ms');
  return result;
}
