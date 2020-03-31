#tester

An experimental test runner. To run:

```
dart --observe --no-pause-isolates-on-unhandled-exceptions bin/main.dart --flutter-root=path/to/flutter_root
> Observatory listening on http://127.0.0.1:8181/slHh-84SqF8=/
> READY.
```

The tests in `test_project/test/a_test.dart` can be executed by typing their name:

```
testThatOneIsOne
> PASSED
```

The tests can be modified and hot reloaded by updating the source code and pressing `r`, or to reload and rerun the last test by pressing `R`.

Currently this runner can only run Dart VM tests in a single test file.