#tester

An experimental test runner. To run:

```
dart bin/main.dart --flutter-root=/path/to/flutter  --project-root=/path/to/tester/test_project/

> READY. r/R to rerun tests, and q/Q to quit.
```

The tests in `test_project/test/a_test.dart` can be executed by pressing 'r'. This will also recompile and reload any changes to test files.

```
PASS    test/a_test.dart/testSomethingElse
FAIL    test/a_test.dart/testThatOneIsOne
Exception: bad222
#0      testThatOneIsOne (file:///Users/jonahwilliams/Documents/tester/test_project/test/a_test.dart:7:5)
#1      new Future.<anonymous closure> (dart:async/future.dart:176:37)
#2      Timer._createTimer.<anonymous closure> (dart:async-patch/timer_patch.dart:23:15)
#3      _Timer._runTimers (dart:isolate-patch/timer_impl.dart:398:19)
#4      _Timer._handleMessage (dart:isolate-patch/timer_impl.dart:429:5)
#5      _RawReceivePortImpl._handleMessage (dart:isolate-patch/isolate_patch.dart:168:12)

PASS    test/a_test.dart/testFoo
```

Currently this runner can only run Dart VM tests.
