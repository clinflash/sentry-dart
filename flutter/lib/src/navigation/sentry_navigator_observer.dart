import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:meta/meta.dart';

import '../../sentry_flutter.dart';
import '../native/sentry_native.dart';
import 'navigation_timing_manager.dart';

/// This key must be used so that the web interface displays the events nicely
/// See https://develop.sentry.dev/sdk/event-payloads/breadcrumbs/
const _navigationKey = 'navigation';

typedef RouteNameExtractor = RouteSettings? Function(RouteSettings? settings);

typedef AdditionalInfoExtractor = Map<String, dynamic>? Function(
  RouteSettings? from,
  RouteSettings? to,
);

/// This is a navigation observer to record navigational breadcrumbs.
/// For now it only records navigation events and no gestures.
///
/// [Route]s can always be null and their [Route.settings] can also always be null.
/// For example, if the application starts, there is no previous route.
/// The [RouteSettings] is null if a developer has not specified any
/// RouteSettings.
///
/// The current route name will also be set to [SentryEvent]
/// `contexts.app.view_names` by [FlutterEnricherEventProcessor].
///
/// [SentryNavigatorObserver] must be added to the [navigation observer](https://api.flutter.dev/flutter/material/MaterialApp/navigatorObservers.html) of
/// your used app. This is an example for [MaterialApp](https://api.flutter.dev/flutter/material/MaterialApp/navigatorObservers.html),
/// but the integration for [CupertinoApp](https://api.flutter.dev/flutter/cupertino/CupertinoApp/navigatorObservers.html)
/// and [WidgetsApp](https://api.flutter.dev/flutter/widgets/WidgetsApp/navigatorObservers.html) is the same.
///
/// ```dart
/// import 'package:flutter/material.dart';
/// import 'package:sentry_flutter/sentry_flutter.dart';
///
/// MaterialApp(
///   navigatorObservers: [
///     SentryNavigatorObserver(),
///   ],
///   // other parameter ...
/// )
/// ```
///
/// The option [enableAutoTransactions] is enabled by default. For every new
/// route a transaction is started. It's automatically finished after
/// [autoFinishAfter] duration or when all child spans are finished,
/// if those happen to take longer. The transaction will be set to [Scope.span]
/// if the latter is empty.
///
/// Enabling the [setRouteNameAsTransaction] option overrides the current
/// [Scope.transaction] which will also override the name of the current
/// [Scope.span]. So be careful when this is used together with performance
/// monitoring.
///
/// See also:
///   - [RouteObserver](https://api.flutter.dev/flutter/widgets/RouteObserver-class.html)
///   - [Navigating with arguments](https://flutter.dev/docs/cookbook/navigation/navigate-with-arguments)
class SentryNavigatorObserver extends RouteObserver<PageRoute<dynamic>> {
  SentryNavigatorObserver({
    Hub? hub,
    bool enableAutoTransactions = true,
    Duration autoFinishAfter = const Duration(seconds: 3),
    bool setRouteNameAsTransaction = false,
    RouteNameExtractor? routeNameExtractor,
    AdditionalInfoExtractor? additionalInfoProvider,
  })  : _hub = hub ?? HubAdapter(),
        _enableAutoTransactions = enableAutoTransactions,
        _autoFinishAfter = autoFinishAfter,
        _setRouteNameAsTransaction = setRouteNameAsTransaction,
        _routeNameExtractor = routeNameExtractor,
        _additionalInfoProvider = additionalInfoProvider,
        _native = SentryFlutter.native {
    if (enableAutoTransactions) {
      // ignore: invalid_use_of_internal_member
      // _timingManager = NavigationTimingManager(
      //   hub: _hub,
      //   native: _native,
      //   autoFinishAfter: autoFinishAfter,
      // );
      _hub.options.sdk.addIntegration('UINavigationTracing');
    }
  }

  final Hub _hub;
  final bool _enableAutoTransactions;
  final Duration _autoFinishAfter;
  final bool _setRouteNameAsTransaction;
  final RouteNameExtractor? _routeNameExtractor;
  final AdditionalInfoExtractor? _additionalInfoProvider;
  final SentryNative? _native;
  static ISentrySpan? _transaction2;

  static ISentrySpan? get transaction2 => _transaction2;

  static final Map<Object, ISentrySpan> ttidSpanMap = {};
  static final Map<Object, ISentrySpan> ttfdSpanMap = {};

  ISentrySpan? _transaction;

  static String? _currentRouteName;

  @internal
  static String? get currentRouteName => _currentRouteName;
  static var startTime = DateTime.now();
  static ISentrySpan? ttidSpan;
  static ISentrySpan? ttfdSpan;
  static var ttfdStartTime = DateTime.now();
  static Stopwatch? ttfdStopwatch;

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPush(route, previousRoute);

    _setCurrentRouteName(route);
    _setCurrentRouteNameAsTransaction(route);

    _addBreadcrumb(
      type: 'didPush',
      from: previousRoute?.settings,
      to: route.settings,
    );

    _finishTransaction();
    // _startTransaction(route);

    NavigationTimingManager()
        .startMeasurement(_getRouteName(route) ?? 'Unknown');

    try {
      // ignore: invalid_use_of_internal_member
      _hub.options.sdk.addIntegration('UINavigationTracing');
    } on Exception catch (e) {
      print(e);
    }
  }

  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) {
    super.didReplace(newRoute: newRoute, oldRoute: oldRoute);

    _setCurrentRouteName(newRoute);
    _setCurrentRouteNameAsTransaction(newRoute);

    _addBreadcrumb(
      type: 'didReplace',
      from: oldRoute?.settings,
      to: newRoute?.settings,
    );
  }

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    super.didPop(route, previousRoute);

    _setCurrentRouteName(previousRoute);
    _setCurrentRouteNameAsTransaction(previousRoute);

    _addBreadcrumb(
      type: 'didPop',
      from: route.settings,
      to: previousRoute?.settings,
    );

    _finishTransaction();
    _startTransaction(previousRoute);
  }

  void _addBreadcrumb({
    required String type,
    RouteSettings? from,
    RouteSettings? to,
  }) {
    _hub.addBreadcrumb(RouteObserverBreadcrumb(
      navigationType: type,
      from: _routeNameExtractor?.call(from) ?? from,
      to: _routeNameExtractor?.call(to) ?? to,
      // ignore: invalid_use_of_internal_member
      timestamp: _hub.options.clock(),
      data: _additionalInfoProvider?.call(from, to),
    ));
  }

  String? _getRouteName(Route<dynamic>? route) {
    return (_routeNameExtractor?.call(route?.settings) ?? route?.settings)
        ?.name;
  }

  Future<void> _setCurrentRouteName(Route<dynamic>? route) async {
    _currentRouteName = _getRouteName(route);
  }

  Future<void> _setCurrentRouteNameAsTransaction(Route<dynamic>? route) async {
    final name = _getRouteName(route);
    if (name == null) {
      return;
    }
    if (_setRouteNameAsTransaction) {
      await _hub.configureScope((scope) {
        scope.transaction = name;
      });
    }
  }

  Future<void> _startTransaction(Route<dynamic>? route) async {
    if (!_enableAutoTransactions) {
      return;
    }

    String? name = _getRouteName(route);
    final arguments = route?.settings.arguments;

    if (name == null) {
      return;
    }

    if (name == '/') {
      name = 'root ("/")';
    }

    // final transactionContext2 = SentryTransactionContext(
    //   name,
    //   'ui.load',
    //   transactionNameSource: SentryTransactionNameSource.component,
    //   // ignore: invalid_use_of_internal_member
    //   origin: SentryTraceOrigins.autoNavigationRouteObserver,
    // );
    //
    // if (name != 'root ("/")') {
    //   _transaction2 = _hub.startTransactionWithContext(
    //     transactionContext2,
    //     waitForChildren: true,
    //     autoFinishAfter: _autoFinishAfter,
    //     trimEnd: true,
    //     onFinish: (transaction) async {
    //       final nativeFrames = await _native
    //           ?.endNativeFramesCollection(transaction.context.traceId);
    //       if (nativeFrames != null) {
    //         final measurements = nativeFrames.toMeasurements();
    //         for (final item in measurements.entries) {
    //           final measurement = item.value;
    //           transaction.setMeasurement(
    //             item.key,
    //             measurement.value,
    //             unit: measurement.unit,
    //           );
    //         }
    //       }
    //     },
    //   );
    // }

    // if _enableAutoTransactions is enabled but there's no traces sample rate
    if (_transaction is NoOpSentrySpan) {
      _transaction2 = null;
      return;
    }

    if (name == 'root ("/")') {
    } else {
      // startTime = DateTime.now();

      // final ttidSpan = _transaction2?.startChild('ui.load.initial_display',
      //     description: '$name initial display', startTimestamp: startTime);
      // ttidSpan?.origin = 'auto.ui.time_to_display';
      // ttidSpanMap[name] = ttidSpan!;
    }

    // TODO: Needs to finish max within 30 seconds
    // If timeout exceeds then it will finish with status deadline exceeded
    // What to do if root also has TTFD but it's not finished yet and we start navigating to another?
    // How to track the time that 30 sec have passed?
    //
    // temporarily disable ttfd for root since it somehow swallows other spans
    // e.g the complex operation span in autoclosescreen
    if ((_hub.options as SentryFlutterOptions).enableTimeToFullDisplayTracing &&
        name != 'root ("/")') {
      print('ttfd');
      ttfdStartTime = DateTime.now();
      ttfdSpan = _transaction2?.startChild('ui.load.full_display',
          description: '$name full display', startTimestamp: ttfdStartTime);
    }

    if (arguments != null) {
      _transaction2?.setData('route_settings_arguments', arguments);
    }

    await _hub.configureScope((scope) {
      scope.span ??= _transaction2;
    });

    await _native?.beginNativeFramesCollection();
  }

  Future<void> _finishTransaction({DateTime? endTimestamp}) async {
    _transaction2?.status ??= SpanStatus.ok();
    await _transaction2?.finish(endTimestamp: endTimestamp);
  }
}

/// This class makes it easier to record breadcrumbs for events of Flutters
/// NavigationObserver by accepting
/// [RouteSettings].
///
/// See also:
///   - [Navigating with arguments](https://flutter.dev/docs/cookbook/navigation/navigate-with-arguments)
class RouteObserverBreadcrumb extends Breadcrumb {
  factory RouteObserverBreadcrumb({
    /// This should correspond to Flutters navigation events.
    /// See https://api.flutter.dev/flutter/widgets/RouteObserver-class.html
    required String navigationType,
    RouteSettings? from,
    RouteSettings? to,
    SentryLevel? level,
    DateTime? timestamp,
    Map<String, dynamic>? data,
  }) {
    final dynamic fromArgs = _formatArgs(from?.arguments);
    final dynamic toArgs = _formatArgs(to?.arguments);
    return RouteObserverBreadcrumb._(
      from: from?.name,
      fromArgs: fromArgs,
      to: to?.name,
      toArgs: toArgs,
      navigationType: navigationType,
      level: level,
      timestamp: timestamp,
      data: data,
    );
  }

  RouteObserverBreadcrumb._({
    required String navigationType,
    String? from,
    dynamic fromArgs,
    String? to,
    dynamic toArgs,
    super.level,
    super.timestamp,
    Map<String, dynamic>? data,
  }) : super(
            category: _navigationKey,
            type: _navigationKey,
            data: <String, dynamic>{
              'state': navigationType,
              if (from != null) 'from': from,
              if (fromArgs != null) 'from_arguments': fromArgs,
              if (to != null) 'to': to,
              if (toArgs != null) 'to_arguments': toArgs,
              if (data != null) 'data': data,
            });

  static dynamic _formatArgs(Object? args) {
    if (args == null) {
      return null;
    }
    if (args is Map<String, dynamic>) {
      return args.map<String, dynamic>((key, dynamic value) =>
          MapEntry<String, String>(key, value.toString()));
    }
    return args.toString();
  }
}

extension NativeFramesMeasurement on NativeFrames {
  Map<String, SentryMeasurement> toMeasurements() {
    final total = SentryMeasurement.totalFrames(totalFrames);
    final slow = SentryMeasurement.slowFrames(slowFrames);
    final frozen = SentryMeasurement.frozenFrames(frozenFrames);
    return {
      total.name: total,
      slow.name: slow,
      frozen.name: frozen,
    };
  }
}
