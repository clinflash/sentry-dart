// ignore_for_file: inference_failure_on_function_return_type

import 'package:flutter/services.dart';
import 'package:flutter/src/widgets/binding.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mockito/annotations.dart';
import 'package:mockito/mockito.dart';
import 'package:sentry/src/platform/platform.dart';
import 'package:sentry/src/sentry_tracer.dart';

import 'package:meta/meta.dart';
import 'package:sentry_flutter/sentry_flutter.dart';
import 'package:sentry_flutter/src/frames_tracking/sentry_delayed_frames_tracker.dart';
import 'package:sentry_flutter/src/renderer/renderer.dart';
import 'package:sentry_flutter/src/native/sentry_native_binding.dart';

import 'mocks.mocks.dart';
import 'no_such_method_provider.dart';

const fakeDsn = 'https://abc@def.ingest.sentry.io/1234567';
const fakeProguardUuid = '3457d982-65ef-576d-a6ad-65b5f30f49a5';

SentryFlutterOptions defaultTestOptions([PlatformChecker? checker]) {
  return SentryFlutterOptions(dsn: fakeDsn, checker: checker)
    ..automatedTestMode = true;
}

// https://github.com/dart-lang/mockito/blob/master/NULL_SAFETY_README.md#fallback-generators
ISentrySpan startTransactionShim(
  String? name,
  String? operation, {
  String? description,
  DateTime? startTimestamp,
  bool? bindToScope,
  bool? waitForChildren,
  Duration? autoFinishAfter,
  bool? trimEnd,
  Function(ISentrySpan)? onFinish,
  Map<String, dynamic>? customSamplingContext,
}) {
  return MockSentryTracer();
}

@GenerateMocks([
  Transport,
  // ignore: invalid_use_of_internal_member
  SentryTracer,
  SentryTransaction,
  SentrySpan,
  SentryClient,
  MethodChannel,
  SentryNativeBinding,
  SentryDelayedFramesTracker,
  BindingWrapper,
  WidgetsFlutterBinding,
], customMocks: [
  MockSpec<Hub>(fallbackGenerators: {#startTransaction: startTransactionShim})
])
void main() {}

class MockPlatform with NoSuchMethodProvider implements Platform {
  const MockPlatform(this.operatingSystem,
      {this.operatingSystemVersion = '', this.localHostname = ''});

  const MockPlatform.android() : this('android');
  const MockPlatform.iOs() : this('ios');
  const MockPlatform.macOs() : this('macos');
  const MockPlatform.windows() : this('windows');
  const MockPlatform.linux() : this('linux');
  const MockPlatform.fuchsia() : this('fuchsia');

  @override
  final String operatingSystem;

  @override
  final String operatingSystemVersion;

  @override
  final String localHostname;

  @override
  bool get isLinux => (operatingSystem == 'linux');

  @override
  bool get isMacOS => (operatingSystem == 'macos');

  @override
  bool get isWindows => (operatingSystem == 'windows');

  @override
  bool get isAndroid => (operatingSystem == 'android');

  @override
  bool get isIOS => (operatingSystem == 'ios');

  @override
  bool get isFuchsia => (operatingSystem == 'fuchsia');
}

class MockPlatformChecker with NoSuchMethodProvider implements PlatformChecker {
  MockPlatformChecker({
    this.isDebug = false,
    this.isProfile = false,
    this.isRelease = false,
    this.isWebValue = false,
    this.hasNativeIntegration = false,
    Platform? mockPlatform,
  }) : _mockPlatform = mockPlatform ?? MockPlatform('');

  final bool isDebug;
  final bool isProfile;
  final bool isRelease;
  final bool isWebValue;
  final Platform _mockPlatform;

  @override
  bool hasNativeIntegration = false;

  @override
  bool isDebugMode() => isDebug;

  @override
  bool isProfileMode() => isProfile;

  @override
  bool isReleaseMode() => isRelease;

  @override
  bool get isWeb => isWebValue;

  @override
  Platform get platform => _mockPlatform;
}

// Does nothing or returns default values.
// Useful for when a Hub needs to be passed but is not used.
class NoOpHub with NoSuchMethodProvider implements Hub {
  final _options = defaultTestOptions();

  @override
  @internal
  SentryOptions get options => _options;

  @override
  bool get isEnabled => false;
}

class MockRendererWrapper implements RendererWrapper {
  MockRendererWrapper(this._renderer);

  final FlutterRenderer? _renderer;

  @override
  FlutterRenderer? getRenderer() {
    return _renderer;
  }
}

class TestBindingWrapper implements BindingWrapper {
  bool ensureBindingInitializedCalled = false;
  bool getWidgetsBindingInstanceCalled = false;

  @override
  WidgetsBinding ensureInitialized() {
    ensureBindingInitializedCalled = true;
    return TestWidgetsFlutterBinding.ensureInitialized();
  }

  @override
  WidgetsBinding get instance {
    getWidgetsBindingInstanceCalled = true;
    return TestWidgetsFlutterBinding.instance;
  }
}

// All these values are based on the fakeFrameDurations list.
// The expected total frames is also based on the span duration of 1000ms and the slow and frozen frames.
const expectedTotalFrames = 18;
const expectedFramesDelay = 722;
const expectedSlowFrames = 2;
const expectedFrozenFrames = 1;

final fakeFrameDurations = [
  Duration(milliseconds: 0),
  Duration(milliseconds: 10),
  Duration(milliseconds: 20),
  Duration(milliseconds: 40),
  Duration(milliseconds: 710),
];

@GenerateMocks([Callbacks])
abstract class Callbacks {
  Future<Object?>? methodCallHandler(String method, [dynamic arguments]);
}

class NativeChannelFixture {
  late final MethodChannel channel;
  late final Future<Object?>? Function(String method, [dynamic arguments])
      handler;
  static TestDefaultBinaryMessenger get _messenger =>
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

  NativeChannelFixture() {
    TestWidgetsFlutterBinding.ensureInitialized();
    channel = MethodChannel('test.channel', StandardMethodCodec(), _messenger);
    handler = MockCallbacks().methodCallHandler;
    when(handler('initNativeSdk', any)).thenAnswer((_) => Future.value());
    when(handler('closeNativeSdk', any)).thenAnswer((_) => Future.value());
    _messenger.setMockMethodCallHandler(
        channel, (call) => handler(call.method, call.arguments));
  }

  // Mock this call as if it was invoked by the native side.
  Future<ByteData?> invokeFromNative(String method, [dynamic arguments]) async {
    final call =
        StandardMethodCodec().encodeMethodCall(MethodCall(method, arguments));
    return _messenger.handlePlatformMessage(
        channel.name, call, (ByteData? data) {});
  }
}

typedef EventProcessorFunction = SentryEvent? Function(
    SentryEvent event, Hint hint);

class FunctionEventProcessor implements EventProcessor {
  FunctionEventProcessor(this.applyFunction);

  final EventProcessorFunction applyFunction;

  @override
  SentryEvent? apply(SentryEvent event, Hint hint) {
    return applyFunction(event, hint);
  }
}
