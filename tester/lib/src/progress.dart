// Copyright 2014 The Flutter Authors. All rights reserved.
// Use of this source code is governed by a BSD-style license that can be
// found in the LICENSE file.
// @dart = 2.9

import 'dart:async';

import 'package:dart_console/dart_console.dart';

abstract class Progress {
  factory Progress({required bool ci}) {
    if (ci) {
      return CiProgress();
    }
    return StdoutProgress();
  }

  void start(String message);

  void stop();
}

class CiProgress implements Progress {
  @override
  void start(String message) {
    print(message);
  }

  @override
  void stop() {}
}

class StdoutProgress implements Progress {
  Timer? timer;
  String? message;
  final Console console = Console();
  static const kProgressChars = <String>[
    '⣾',
    '⣽',
    '⣻',
    '⢿',
    '⡿',
    '⣟',
    '⣯',
    '⣷',
  ];
  var index = 0;

  @override
  void start(String message) {
    if (timer?.isActive ?? false) {
      throw StateError('start called while timer was already pending');
    }
    index = 0;
    this.message = message;
    console.hideCursor();
    timer ??= Timer.periodic(const Duration(milliseconds: 45), _render);
  }

  @override
  void stop() {
    var localTimer = timer;
    if (localTimer == null || !localTimer.isActive) {
      throw StateError('stop called while timer was already stopped');
    }
    localTimer.cancel();
    timer = null;
    console.showCursor();
  }

  void _render(Timer _) {
    var position = console.cursorPosition;
    console
      ..setBackgroundColor(ConsoleColor.cyan)
      ..write(kProgressChars[index])
      ..write(' $message')
      ..resetColorAttributes()
      ..cursorPosition = position;
    index = (index + 1) % kProgressChars.length;
  }
}
