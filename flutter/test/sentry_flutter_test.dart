// ignore_for_file: invalid_use_of_internal_member

import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/mockito.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:sentry/src/platform/platform.dart';
import 'package:sentry/src/dart_exception_type_identifier.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_flutter/src/file_system_transport.dart';
import 'package:sentry_flutter/src/flutter_exception_type_identifier.dart';
import 'package:sentry_flutter/src/integrations/connectivity/connectivity_integration.dart';
import 'package:sentry_flutter/src/integrations/integrations.dart';
import 'package:sentry_flutter/src/integrations/screenshot_integration.dart';
import 'package:sentry_flutter/src/profiling.dart';
import 'package:sentry_flutter/src/renderer/renderer.dart';
import 'package:sentry_flutter/src/version.dart';
import 'package:sentry_flutter/src/view_hierarchy/view_hierarchy_integration.dart';
import 'mocks.dart';
import 'mocks.mocks.dart';
import 'sentry_flutter_util.dart';

/// These are the integrations which should be added on every platform.
/// They don't depend on the underlying platform.
final platformAgnosticIntegrations = [
  WidgetsFlutterBindingIntegration,
  FlutterErrorIntegration,
  LoadReleaseIntegration,
  DebugPrintIntegration,
  SentryViewHierarchyIntegration,
];

final webIntegrations = [
  ConnectivityIntegration,
];

final nonWebIntegrations = [
  OnErrorIntegration,
];

// These should be added to Android
final androidIntegrations = [
  LoadImageListIntegration,
  LoadContextsIntegration,
];

// These should be added to iOS and macOS
final iOsAndMacOsIntegrations = [
  LoadImageListIntegration,
  LoadContextsIntegration,
];

// These should be added to every platform which has a native integration.
final nativeIntegrations = [
  NativeSdkIntegration,
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late NativeChannelFixture native;

  setUp(() async {
    native = NativeChannelFixture();
    SentryFlutter.native = null;
  });

  group('Test platform integrations', () {
    setUp(() async {
      loadTestPackage();
      await Sentry.close();
      SentryFlutter.native = null;
    });

    test('Android', () async {
      late final SentryFlutterOptions options;
      late final Transport transport;

      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(platform: MockPlatform.android()))
        ..methodChannel = native.channel;

      await SentryFlutter.init(
        (o) async {
          o.dsn = fakeDsn;
          o.profilesSampleRate = 1.0;
          options = o;
          transport = o.transport;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(transport, isA<FileSystemTransport>());

      testScopeObserver(
          options: sentryFlutterOptions, expectedHasNativeScopeObserver: true);

      testConfiguration(
        integrations: options.integrations,
        shouldHaveIntegrations: [
          ...androidIntegrations,
          ...nativeIntegrations,
          ...platformAgnosticIntegrations,
          ...nonWebIntegrations,
        ],
        shouldNotHaveIntegrations: [
          ...iOsAndMacOsIntegrations,
          ...nonWebIntegrations,
        ],
      );

      options.integrations
          .indexWhere((element) => element is WidgetsFlutterBindingIntegration);

      testBefore(
          integrations: options.integrations,
          beforeIntegration: WidgetsFlutterBindingIntegration,
          afterIntegration: OnErrorIntegration);

      expect(
          options.eventProcessors.indexOfTypeString('IoEnricherEventProcessor'),
          greaterThan(options.eventProcessors
              .indexOfTypeString('_LoadContextsIntegrationEventProcessor')));

      expect(SentryFlutter.native, isNotNull);
      expect(Sentry.currentHub.profilerFactory, isNull);

      await Sentry.close();
    }, testOn: 'vm');

    test('iOS', () async {
      late final SentryFlutterOptions options;
      late final Transport transport;

      final sentryFlutterOptions =
          defaultTestOptions(getPlatformChecker(platform: MockPlatform.iOs()))
            ..methodChannel = native.channel;

      await SentryFlutter.init(
        (o) async {
          o.dsn = fakeDsn;
          o.profilesSampleRate = 1.0;
          options = o;
          transport = o.transport;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(transport, isA<FileSystemTransport>());

      testScopeObserver(
          options: sentryFlutterOptions, expectedHasNativeScopeObserver: true);

      testConfiguration(
        integrations: options.integrations,
        shouldHaveIntegrations: [
          ...iOsAndMacOsIntegrations,
          ...nativeIntegrations,
          ...platformAgnosticIntegrations,
          ...nonWebIntegrations,
        ],
        shouldNotHaveIntegrations: [
          ...androidIntegrations,
          ...nonWebIntegrations,
        ],
      );

      testBefore(
          integrations: options.integrations,
          beforeIntegration: WidgetsFlutterBindingIntegration,
          afterIntegration: OnErrorIntegration);

      expect(SentryFlutter.native, isNotNull);
      expect(Sentry.currentHub.profilerFactory,
          isInstanceOf<SentryNativeProfilerFactory>());

      expect(
          options.eventProcessors.indexOfTypeString('IoEnricherEventProcessor'),
          greaterThan(options.eventProcessors
              .indexOfTypeString('_LoadContextsIntegrationEventProcessor')));

      await Sentry.close();
    }, testOn: 'vm');

    test('macOS', () async {
      List<Integration> integrations = [];
      Transport transport = MockTransport();
      final sentryFlutterOptions =
          defaultTestOptions(getPlatformChecker(platform: MockPlatform.macOs()))
            ..methodChannel = native.channel;

      await SentryFlutter.init(
        (options) async {
          options.dsn = fakeDsn;
          options.profilesSampleRate = 1.0;
          integrations = options.integrations;
          transport = options.transport;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(transport, isA<FileSystemTransport>());

      testScopeObserver(
          options: sentryFlutterOptions, expectedHasNativeScopeObserver: true);

      testConfiguration(integrations: integrations, shouldHaveIntegrations: [
        ...iOsAndMacOsIntegrations,
        ...nativeIntegrations,
        ...platformAgnosticIntegrations,
        ...nonWebIntegrations,
      ], shouldNotHaveIntegrations: [
        ...androidIntegrations,
        ...nonWebIntegrations,
      ]);

      testBefore(
          integrations: integrations,
          beforeIntegration: WidgetsFlutterBindingIntegration,
          afterIntegration: OnErrorIntegration);

      expect(SentryFlutter.native, isNotNull);
      expect(Sentry.currentHub.profilerFactory,
          isInstanceOf<SentryNativeProfilerFactory>());

      await Sentry.close();
    }, testOn: 'vm');

    test('Windows', () async {
      List<Integration> integrations = [];
      Transport transport = MockTransport();
      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(platform: MockPlatform.windows()))
        // We need to disable native init because sentry.dll is not available here.
        ..autoInitializeNativeSdk = false;

      await SentryFlutter.init(
        (options) async {
          options.dsn = fakeDsn;
          options.profilesSampleRate = 1.0;
          integrations = options.integrations;
          transport = options.transport;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(transport, isNot(isA<FileSystemTransport>()));

      testScopeObserver(
          options: sentryFlutterOptions, expectedHasNativeScopeObserver: true);

      testConfiguration(
        integrations: integrations,
        shouldHaveIntegrations: [
          ...platformAgnosticIntegrations,
          ...nonWebIntegrations,
        ],
        shouldNotHaveIntegrations: [
          ...androidIntegrations,
          ...iOsAndMacOsIntegrations,
          ...nativeIntegrations,
          ...webIntegrations,
        ],
      );

      testBefore(
          integrations: integrations,
          beforeIntegration: WidgetsFlutterBindingIntegration,
          afterIntegration: OnErrorIntegration);

      expect(SentryFlutter.native, isNotNull);
      expect(Sentry.currentHub.profilerFactory, isNull);
    }, testOn: 'vm');

    test('Linux', () async {
      List<Integration> integrations = [];
      Transport transport = MockTransport();
      final sentryFlutterOptions =
          defaultTestOptions(getPlatformChecker(platform: MockPlatform.linux()))
            ..methodChannel = native.channel
            // We need to disable native init because libsentry.so is not available here.
            ..autoInitializeNativeSdk = false;

      await SentryFlutter.init(
        (options) async {
          options.dsn = fakeDsn;
          options.profilesSampleRate = 1.0;
          integrations = options.integrations;
          transport = options.transport;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(transport, isNot(isA<FileSystemTransport>()));

      testScopeObserver(
          options: sentryFlutterOptions, expectedHasNativeScopeObserver: true);

      testConfiguration(
        integrations: integrations,
        shouldHaveIntegrations: [
          ...platformAgnosticIntegrations,
          ...nonWebIntegrations,
        ],
        shouldNotHaveIntegrations: [
          ...androidIntegrations,
          ...iOsAndMacOsIntegrations,
          ...nativeIntegrations,
          ...webIntegrations,
        ],
      );

      testBefore(
          integrations: integrations,
          beforeIntegration: WidgetsFlutterBindingIntegration,
          afterIntegration: OnErrorIntegration);

      expect(SentryFlutter.native, isNotNull);
      expect(Sentry.currentHub.profilerFactory, isNull);

      await Sentry.close();
    }, testOn: 'vm');

    test('Web', () async {
      List<Integration> integrations = [];
      Transport transport = MockTransport();
      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(isWeb: true, platform: MockPlatform.linux()))
        ..methodChannel = native.channel;

      await SentryFlutter.init(
        (options) async {
          options.profilesSampleRate = 1.0;
          integrations = options.integrations;
          transport = options.transport;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(transport, isNot(isA<FileSystemTransport>()));

      testScopeObserver(
          options: sentryFlutterOptions, expectedHasNativeScopeObserver: false);

      testConfiguration(
        integrations: integrations,
        shouldHaveIntegrations: [
          ...platformAgnosticIntegrations,
          ...webIntegrations,
        ],
        shouldNotHaveIntegrations: [
          ...androidIntegrations,
          ...iOsAndMacOsIntegrations,
          ...nativeIntegrations,
          ...nonWebIntegrations,
        ],
      );

      testBefore(
          integrations: Sentry.currentHub.options.integrations,
          beforeIntegration: RunZonedGuardedIntegration,
          afterIntegration: WidgetsFlutterBindingIntegration);

      expect(SentryFlutter.native, isNull);
      expect(Sentry.currentHub.profilerFactory, isNull);

      await Sentry.close();
    });

    test('Web && (iOS || macOS)', () async {
      List<Integration> integrations = [];
      Transport transport = MockTransport();
      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(isWeb: true, platform: MockPlatform.iOs()))
        ..methodChannel = native.channel;

      // Tests that iOS || macOS integrations aren't added on a browser which
      // runs on iOS or macOS
      await SentryFlutter.init(
        (options) async {
          integrations = options.integrations;
          transport = options.transport;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(transport, isNot(isA<FileSystemTransport>()));

      testConfiguration(
        integrations: integrations,
        shouldHaveIntegrations: [
          ...platformAgnosticIntegrations,
          ...webIntegrations,
        ],
        shouldNotHaveIntegrations: [
          ...androidIntegrations,
          ...iOsAndMacOsIntegrations,
          ...nativeIntegrations,
          ...nonWebIntegrations,
        ],
      );

      testBefore(
          integrations: Sentry.currentHub.options.integrations,
          beforeIntegration: RunZonedGuardedIntegration,
          afterIntegration: WidgetsFlutterBindingIntegration);

      await Sentry.close();
    });

    test('Web && (macOS)', () async {
      List<Integration> integrations = [];
      Transport transport = MockTransport();
      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(isWeb: true, platform: MockPlatform.macOs()))
        ..methodChannel = native.channel;

      // Tests that iOS || macOS integrations aren't added on a browser which
      // runs on iOS or macOS
      await SentryFlutter.init(
        (options) async {
          integrations = options.integrations;
          transport = options.transport;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(transport, isNot(isA<FileSystemTransport>()));

      testConfiguration(
        integrations: integrations,
        shouldHaveIntegrations: [
          ...platformAgnosticIntegrations,
          ...webIntegrations,
        ],
        shouldNotHaveIntegrations: [
          ...androidIntegrations,
          ...iOsAndMacOsIntegrations,
          ...nativeIntegrations,
          ...nonWebIntegrations,
        ],
      );

      testBefore(
          integrations: Sentry.currentHub.options.integrations,
          beforeIntegration: RunZonedGuardedIntegration,
          afterIntegration: WidgetsFlutterBindingIntegration);

      expect(Sentry.currentHub.profilerFactory, isNull);

      await Sentry.close();
    });

    test('Web && Android', () async {
      List<Integration> integrations = [];
      Transport transport = MockTransport();
      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(isWeb: true, platform: MockPlatform.android()))
        ..methodChannel = native.channel;

      // Tests that Android integrations aren't added on an Android browser
      await SentryFlutter.init(
        (options) async {
          integrations = options.integrations;
          transport = options.transport;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(transport, isNot(isA<FileSystemTransport>()));

      testConfiguration(
        integrations: integrations,
        shouldHaveIntegrations: [
          ...platformAgnosticIntegrations,
          ...webIntegrations,
        ],
        shouldNotHaveIntegrations: [
          ...androidIntegrations,
          ...iOsAndMacOsIntegrations,
          ...nativeIntegrations,
          ...nonWebIntegrations,
        ],
      );

      testBefore(
          integrations: Sentry.currentHub.options.integrations,
          beforeIntegration: RunZonedGuardedIntegration,
          afterIntegration: WidgetsFlutterBindingIntegration);

      await Sentry.close();
    });
  });

  group('Test ScreenshotIntegration', () {
    setUp(() async {
      await Sentry.close();
    });

    test('installed on io platforms', () async {
      List<Integration> integrations = [];

      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(platform: MockPlatform.iOs(), isWeb: false))
        ..methodChannel = native.channel
        ..rendererWrapper = MockRendererWrapper(FlutterRenderer.skia)
        ..release = ''
        ..dist = '';

      await SentryFlutter.init(
        (options) async {
          integrations = options.integrations;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(
          integrations
              .map((e) => e.runtimeType)
              .contains(ScreenshotIntegration),
          true);

      await Sentry.close();
    }, testOn: 'vm');

    test('installed with canvasKit renderer', () async {
      List<Integration> integrations = [];

      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(platform: MockPlatform.iOs(), isWeb: true))
        ..rendererWrapper = MockRendererWrapper(FlutterRenderer.canvasKit)
        ..release = ''
        ..dist = '';

      await SentryFlutter.init(
        (options) async {
          integrations = options.integrations;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(
          integrations
              .map((e) => e.runtimeType)
              .contains(ScreenshotIntegration),
          true);

      await Sentry.close();
    }, testOn: 'vm');

    test('not installed with html renderer', () async {
      List<Integration> integrations = [];

      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(platform: MockPlatform.iOs(), isWeb: true))
        ..rendererWrapper = MockRendererWrapper(FlutterRenderer.html)
        ..release = ''
        ..dist = '';

      await SentryFlutter.init(
        (options) async {
          integrations = options.integrations;
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      expect(
          integrations
              .map((e) => e.runtimeType)
              .contains(ScreenshotIntegration),
          false);

      await Sentry.close();
    }, testOn: 'vm');
  });

  group('initial values', () {
    setUp(() async {
      loadTestPackage();
      await Sentry.close();
    });

    test('test that initial values are set correctly', () async {
      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(platform: MockPlatform.android(), isWeb: true));

      await SentryFlutter.init(
        (options) {
          expect(false, options.debug);
          expect('debug', options.environment);
          expect(sdkName, options.sdk.name);
          expect(sdkVersion, options.sdk.version);
          expect('pub:sentry_flutter', options.sdk.packages.last.name);
          expect(sdkVersion, options.sdk.packages.last.version);
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      await Sentry.close();
    });

    test(
        'enablePureDartSymbolication is set to false during SentryFlutter init',
        () async {
      final sentryFlutterOptions = defaultTestOptions(
          getPlatformChecker(platform: MockPlatform.android(), isWeb: true));
      SentryFlutter.native = mockNativeBinding();
      await SentryFlutter.init(
        (options) {
          expect(options.enableDartSymbolication, false);
        },
        appRunner: appRunner,
        options: sentryFlutterOptions,
      );

      await Sentry.close();
    });
  });

  test('resumeAppHangTracking calls native method when available', () async {
    SentryFlutter.native = mockNativeBinding();
    when(SentryFlutter.native?.resumeAppHangTracking())
        .thenAnswer((_) => Future.value());

    await SentryFlutter.resumeAppHangTracking();

    verify(SentryFlutter.native?.resumeAppHangTracking()).called(1);

    SentryFlutter.native = null;
  });

  test('resumeAppHangTracking does nothing when native is null', () async {
    SentryFlutter.native = null;

    // This should complete without throwing an error
    await expectLater(SentryFlutter.resumeAppHangTracking(), completes);
  });

  test('pauseAppHangTracking calls native method when available', () async {
    SentryFlutter.native = mockNativeBinding();
    when(SentryFlutter.native?.pauseAppHangTracking())
        .thenAnswer((_) => Future.value());

    await SentryFlutter.pauseAppHangTracking();

    verify(SentryFlutter.native?.pauseAppHangTracking()).called(1);

    SentryFlutter.native = null;
  });

  test('pauseAppHangTracking does nothing when native is null', () async {
    SentryFlutter.native = null;

    // This should complete without throwing an error
    await expectLater(SentryFlutter.pauseAppHangTracking(), completes);
  });

  group('exception identifiers', () {
    setUp(() async {
      loadTestPackage();
      await Sentry.close();
    });

    test(
        'should add DartExceptionTypeIdentifier and FlutterExceptionTypeIdentifier by default',
        () async {
      final actualOptions = defaultTestOptions(
          getPlatformChecker(platform: MockPlatform.android(), isWeb: true));
      await SentryFlutter.init(
        (options) {},
        appRunner: appRunner,
        options: actualOptions,
      );

      expect(actualOptions.exceptionTypeIdentifiers.length, 2);
      // Flutter identifier should be first as it's more specific
      expect(
        actualOptions.exceptionTypeIdentifiers.first,
        isA<CachingExceptionTypeIdentifier>().having(
          (c) => c.identifier,
          'wrapped identifier',
          isA<FlutterExceptionTypeIdentifier>(),
        ),
      );
      expect(
        actualOptions.exceptionTypeIdentifiers[1],
        isA<CachingExceptionTypeIdentifier>().having(
          (c) => c.identifier,
          'wrapped identifier',
          isA<DartExceptionTypeIdentifier>(),
        ),
      );

      await Sentry.close();
    });
  });
}

MockSentryNativeBinding mockNativeBinding() {
  final result = MockSentryNativeBinding();
  when(result.supportsLoadContexts).thenReturn(true);
  when(result.supportsCaptureEnvelope).thenReturn(true);
  when(result.captureEnvelope(any, any)).thenReturn(null);
  when(result.init(any)).thenReturn(null);
  when(result.close()).thenReturn(null);
  return result;
}

void appRunner() {}

void loadTestPackage() {
  PackageInfo.setMockInitialValues(
    appName: 'appName',
    packageName: 'packageName',
    version: 'version',
    buildNumber: 'buildNumber',
    buildSignature: '',
    installerStore: null,
  );
}

PlatformChecker getPlatformChecker({
  required Platform platform,
  bool isWeb = false,
}) {
  final platformChecker = PlatformChecker(
    isWeb: isWeb,
    platform: platform,
  );
  return platformChecker;
}
