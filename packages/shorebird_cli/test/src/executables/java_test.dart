import 'dart:io';

import 'package:mocktail/mocktail.dart';
import 'package:path/path.dart' as p;
import 'package:platform/platform.dart';
import 'package:scoped_deps/scoped_deps.dart';
import 'package:shorebird_cli/src/android_studio.dart';
import 'package:shorebird_cli/src/executables/executables.dart';
import 'package:shorebird_cli/src/os/os.dart';
import 'package:shorebird_cli/src/platform.dart';
import 'package:shorebird_cli/src/shorebird_flutter.dart';
import 'package:shorebird_cli/src/shorebird_process.dart';
import 'package:test/test.dart';

import '../mocks.dart';

void main() {
  group(Java, () {
    late AndroidStudio androidStudio;
    late OperatingSystemInterface osInterface;
    late Platform platform;
    late ShorebirdFlutter shorebirdFlutter;
    late ShorebirdProcess shorebirdProcess;
    late Java java;

    R runWithOverrides<R>(R Function() body) {
      return runScoped(
        () => body(),
        values: {
          androidStudioRef.overrideWith(() => androidStudio),
          osInterfaceRef.overrideWith(() => osInterface),
          processRef.overrideWith(() => shorebirdProcess),
          platformRef.overrideWith(() => platform),
          shorebirdFlutterRef.overrideWith(() => shorebirdFlutter),
        },
      );
    }

    Directory setUpAppTempDir() {
      final tempDir = Directory.systemTemp.createTempSync();
      Directory(p.join(tempDir.path, 'android')).createSync(recursive: true);
      return tempDir;
    }

    setUp(() {
      androidStudio = MockAndroidStudio();
      osInterface = MockOperatingSystemInterface();
      platform = MockPlatform();
      shorebirdFlutter = MockShorebirdFlutter();
      shorebirdProcess = MockShorebirdProcess();
      java = Java();

      when(() => platform.environment).thenReturn({});
      when(() => platform.isWindows).thenReturn(false);
      when(() => platform.isMacOS).thenReturn(false);
      when(() => platform.isLinux).thenReturn(false);

      when(() => osInterface.which(any())).thenReturn(null);

      when(shorebirdFlutter.getConfig).thenReturn({});
    });

    group('version', () {
      setUp(() {
        const javaHome = '/path/to/jdk';
        when(() => platform.isWindows).thenReturn(false);
        when(() => platform.environment).thenReturn({'JAVA_HOME': javaHome});

        final processResult = MockShorebirdProcessResult();
        when(
          () => shorebirdProcess.runSync(any(), any()),
        ).thenReturn(processResult);
        when(() => processResult.exitCode).thenReturn(0);
        when(() => processResult.stderr).thenReturn('java version "11.0.1"');
      });

      test('calls java -version and return the stderr', () {
        expect(
          runWithOverrides(() => java.version),
          equals('java version "11.0.1"'),
        );
      });

      group('when the command fails', () {
        setUp(() {
          final processResult = MockShorebirdProcessResult();
          when(
            () => shorebirdProcess.runSync(any(), any()),
          ).thenReturn(processResult);
          when(() => processResult.exitCode).thenReturn(1);
        });

        test('returns null', () {
          expect(runWithOverrides(() => java.version), isNull);
        });
      });

      group('when no jdk is found', () {
        setUp(() {
          when(() => platform.environment).thenReturn({});
        });

        test('returns null', () {
          expect(runWithOverrides(() => java.version), isNull);
        });
      });
    });

    group('executable', () {
      group('when on Windows', () {
        const javaHome = r'C:\Program Files\Java\jdk-11.0.1';
        setUp(() {
          when(() => platform.isWindows).thenReturn(true);
          when(() => platform.environment).thenReturn({'JAVA_HOME': javaHome});
        });

        test('returns correct executable on windows', () async {
          expect(
            runWithOverrides(() => java.executable),
            equals(p.join(javaHome, 'bin', 'java.exe')),
          );
        });
      }, testOn: 'windows');

      group('when on a non-Windows OS', () {
        setUp(() {
          const javaHome = '/path/to/jdk';
          when(() => platform.isWindows).thenReturn(false);
          when(() => platform.environment).thenReturn({'JAVA_HOME': javaHome});
        });

        test('returns correct executable on non-windows', () async {
          expect(
            runWithOverrides(() => java.executable),
            equals('/path/to/jdk/bin/java'),
          );
        });
      }, onPlatform: {'windows': const Skip()});

      group('when no jdk is found', () {
        setUp(() {
          when(() => osInterface.which('java')).thenReturn('/bin/java');
        });

        test('returns java found on path', () async {
          expect(runWithOverrides(() => java.executable), equals('/bin/java'));
        });
      });
    });

    group('home', () {
      group('when Android Studio is installed', () {
        late Directory jbrDir;

        group('on macOS', () {
          setUp(() {
            when(() => platform.isMacOS).thenReturn(true);

            final tempDir = setUpAppTempDir();
            final androidStudioDir = Directory(
              p.join(
                tempDir.path,
                'Applications',
                'Android Studio.app',
                'Contents',
              ),
            )..createSync(recursive: true);
            when(() => androidStudio.path).thenReturn(androidStudioDir.path);
            jbrDir = Directory(
              p.join(androidStudioDir.path, 'jbr', 'Contents', 'Home'),
            )..createSync(recursive: true);
            File(
              p.join(tempDir.path, 'android', 'gradlew'),
            ).createSync(recursive: true);
            when(() => platform.environment).thenReturn({'HOME': tempDir.path});
          });

          group('when flutter config contains jdk override', () {
            const jdkDirOverride = '/jdk';
            setUp(() {
              when(
                shorebirdFlutter.getConfig,
              ).thenReturn({'jdk-dir': jdkDirOverride});
            });

            test('returns value of jdk-dir', () {
              expect(runWithOverrides(() => java.home), equals(jdkDirOverride));
            });
          });

          test('returns correct path', () async {
            await expectLater(
              runWithOverrides(() => java.home),
              equals(jbrDir.path),
            );
          });

          test('does not check JAVA_HOME or PATH', () {
            runWithOverrides(() => java.home);

            verifyNever(() => osInterface.which(any()));
            verifyNever(() => platform.environment);
          });
        });

        group('on Windows', () {
          late Directory jbrDir;

          setUp(() {
            when(() => platform.isWindows).thenReturn(true);

            final tempDir = setUpAppTempDir();
            final androidStudioDir = Directory(
              p.join(tempDir.path, 'Android', 'Android Studio'),
            )..createSync(recursive: true);
            when(() => androidStudio.path).thenReturn(androidStudioDir.path);
            jbrDir = Directory(p.join(androidStudioDir.path, 'jbr'))
              ..createSync();
            File(
              p.join(tempDir.path, 'android', 'gradlew.bat'),
            ).createSync(recursive: true);
            when(() => platform.environment).thenReturn({
              'PROGRAMFILES': tempDir.path,
              'PROGRAMFILES(X86)': tempDir.path,
            });
          });

          test('returns correct path', () async {
            await expectLater(
              runWithOverrides(() => java.home),
              equals(jbrDir.path),
            );
          });

          test('does not check JAVA_HOME or PATH', () {
            runWithOverrides(() => java.home);

            verifyNever(() => osInterface.which(any()));
            verifyNever(() => platform.environment);
          });
        });

        group('on Linux', () {
          setUp(() {
            when(() => platform.isLinux).thenReturn(true);

            final tempDir = setUpAppTempDir();
            final androidStudioDir = Directory(
              p.join(tempDir.path, '.AndroidStudio'),
            )..createSync(recursive: true);
            when(() => androidStudio.path).thenReturn(androidStudioDir.path);
            jbrDir = Directory(p.join(androidStudioDir.path, 'jbr'))
              ..createSync(recursive: true);
            File(
              p.join(tempDir.path, 'android', 'gradlew'),
            ).createSync(recursive: true);

            when(() => platform.environment).thenReturn({'HOME': tempDir.path});
          });

          test('returns correct path', () async {
            await expectLater(
              runWithOverrides(() => java.home),
              equals(jbrDir.path),
            );
          });
        });
      });

      group('when Android Studio is not installed', () {
        group('when JAVA_HOME is set', () {
          const javaHome = r'C:\Program Files\Java\jdk-11.0.1';
          setUp(() {
            when(
              () => platform.environment,
            ).thenReturn({'JAVA_HOME': javaHome});
          });

          group('when flutter config contains jdk override', () {
            const jdkDirOverride = '/jdk';
            setUp(() {
              when(
                shorebirdFlutter.getConfig,
              ).thenReturn({'jdk-dir': jdkDirOverride});
            });

            test('returns value of jdk-dir', () {
              expect(runWithOverrides(() => java.home), equals(jdkDirOverride));
            });
          });

          test('returns value of JAVA_HOME', () {
            expect(runWithOverrides(() => java.home), equals(javaHome));
          });

          test('does not check PATH', () {
            runWithOverrides(() => java.home);

            verifyNever(() => osInterface.which(any()));
          });
        });

        group('when JAVA_HOME is not set', () {
          group('returns null', () {
            test('returns path to java', () {
              expect(runWithOverrides(() => java.home), isNull);
            });
          });

          group("when java is not on the user's path", () {
            setUp(() {
              when(() => osInterface.which('java')).thenReturn(null);
            });

            test('returns null', () {
              expect(runWithOverrides(() => java.home), isNull);
            });
          });
        });
      });
    });
  });
}
