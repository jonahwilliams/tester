# tester

<img width="650" src="https://user-images.githubusercontent.com/8975114/83311624-9b562f00-a1c4-11ea-9716-92cd3c455b9e.PNG">


An experimental test runner with no runtime dependencies. Precompiled binaries for windows, linux, and macOS can be found in the releases tab.

This should be run from the root of a dart project containing `pubspec.yaml`. By default, it will run all files in `test/` ending in `_test.dart`. It also accepts multiple positional arguments for one or more individual test files.

```
macos_tester

// Or

macos_tester test/a_test.dart test/b_test.dart
```

Currently this runner can execute Dart, Dart Web, Flutter, and Flutter Web tests using `--platform`. By default, it runs `dart` tests, which corresponds to the dart vm. Other options are `flutter`, `web`, and `flutter_web`. Neither of the web options work when running in AOT mode.

```
macos_tester --platform=dart test/dart_test.dart
macos_tester --platform=flutter test/flutter_test.dart
```


This tool requires the Flutter SDK to be on the path. Running Web or Flutter Web tests requires Chrome to be available, and Flutter Web additionally requires that web is enabled in the Flutter SDK with:


```
flutter config --enable-web
```

By default, tester runs all tests and then exits. It can also be configured with `--watch`, and will rerun any updated tests and stay resident.
