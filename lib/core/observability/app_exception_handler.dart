import 'dart:async';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';

import 'error_reporter.dart';

/// Installs global Flutter/Dart/async error handlers.
class AppExceptionHandler {
  AppExceptionHandler._();

  static Future<void> initialize() async {
    final bool isCrashlyticsSupported = !kIsWeb &&
        (defaultTargetPlatform == TargetPlatform.android ||
            defaultTargetPlatform == TargetPlatform.iOS ||
            defaultTargetPlatform == TargetPlatform.macOS);

    if (isCrashlyticsSupported) {
      try {
        await FirebaseCrashlytics.instance.setCrashlyticsCollectionEnabled(
          kReleaseMode,
        );
        ErrorReporter.instance.markCrashlyticsReady();
      } catch (_) {
        // Non-fatal if Crashlytics fails to bind or is not supported
      }
    }

    FlutterError.onError = (FlutterErrorDetails details) {
      if (kReleaseMode && isCrashlyticsSupported) {
        try {
          FirebaseCrashlytics.instance.recordFlutterFatalError(details);
        } catch (_) {}
      }
      ErrorReporter.instance.report(
        details.exception,
        stackTrace: details.stack,
        tag: 'FlutterError',
        fatal: true,
      );
      if (kDebugMode) {
        FlutterError.presentError(details);
      }
    };

    PlatformDispatcher.instance.onError = (Object error, StackTrace stack) {
      ErrorReporter.instance.report(
        error,
        stackTrace: stack,
        tag: 'PlatformDispatcher',
        fatal: true,
      );
      return true;
    };
  }

  /// Wraps [runApp] zone for uncaught async errors outside Flutter framework.
  static R runZonedApp<R>(R Function() body, {void Function()? onZoneError}) {
    return runZonedGuarded<R>(
      body,
      (Object error, StackTrace stack) {
        ErrorReporter.instance.report(
          error,
          stackTrace: stack,
          tag: 'runZonedGuarded',
          fatal: true,
        );
        onZoneError?.call();
      },
    )!;
  }
}
