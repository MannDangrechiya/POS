import 'dart:async' show unawaited;

import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import '../../core/auth/auth_lifecycle_cleanup.dart';
import '../../core/observability/app_logger.dart';
import '../../core/observability/error_reporter.dart';
import '../../core/observability/error_ui.dart';
import '../../data/models/user_model.dart';

/// Controller for handling authentication operations.
///
/// PHASE 5 FIX:
/// - Uses a single callable name 'logAuthEvent' consistently for all audit events.
/// - Removed the duplicate LOGIN_SUCCESS log that was also firing from login_screen.dart.
///   auth_controller.dart is now the ONLY place that logs LOGIN_SUCCESS.
/// - login_screen.dart must be updated to REMOVE its duplicate logAuthEvent call.
/// - LOGIN_FAILURE is logged here in auth_controller.dart only.
/// - LOGOUT is logged here before signOut().
class AuthController {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  // Single callable reference for all auth audit events
  final HttpsCallable _logAuthEvent = FirebaseFunctions.instance.httpsCallable(
    'logAuthEvent',
  );

  // Login-failure lockout system (no-auth-required callables — see
  // firebase/functions/src/auth/loginLockout.ts).
  final HttpsCallable _checkLoginLockout = FirebaseFunctions.instance
      .httpsCallable('checkLoginLockout');
  final HttpsCallable _recordLoginFailure = FirebaseFunctions.instance
      .httpsCallable('recordLoginFailure');
  final HttpsCallable _resetLoginFailure = FirebaseFunctions.instance
      .httpsCallable('resetLoginFailure');

  /// Login with email and password.
  /// Returns UserModel if successful, throws exception on failure.
  Future<UserModel> login(String email, String password) async {
    final String trimmedEmail = email.trim();

    // Check lockout status before attempting sign-in at all — a locked
    // account is disabled at the Firebase Auth level, so attempting sign-in
    // would just fail with 'user-disabled' without a clear countdown message.
    try {
      final lockoutResult = await _checkLoginLockout.call(<String, dynamic>{
        'email': trimmedEmail,
      });
      final data = lockoutResult.data;
      if (data is Map && data['locked'] == true) {
        final lockedUntilMs = data['lockedUntil'];
        if (lockedUntilMs is int) {
          final until = DateTime.fromMillisecondsSinceEpoch(lockedUntilMs);
          final minutesLeft = until.difference(DateTime.now()).inMinutes + 1;
          throw Exception(
            'Too many failed attempts. Try again in $minutesLeft minute(s).',
          );
        }
        throw Exception(
          'Too many failed attempts. Please try again later.',
        );
      }
    } on FirebaseFunctionsException catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'AuthController.checkLockout');
      // Non-fatal — fall through and attempt sign-in normally.
    }

    try {
      final UserCredential userCredential = await _auth
          .signInWithEmailAndPassword(email: trimmedEmail, password: password);

      final String userId = userCredential.user!.uid;

      final DocumentSnapshot userDoc = await _firestore
          .collection('users')
          .doc(userId)
          .get();

      if (!userDoc.exists) {
        await _endSession();
        throw Exception(
          'User account not found. Please contact administrator.',
        );
      }

      final UserModel? user = UserModel.tryFromDocument(userDoc);
      if (user == null) {
        await _endSession();
        throw Exception(
          'User account data is invalid. Please contact administrator.',
        );
      }

      if (!user.isActive) {
        await _logRejectedLoginWhileAuthed(user, 'LOGIN_BLOCKED_STATUS');
        await _endSession();
        if (user.isSuspended) {
          throw Exception(
            'Your account has been suspended. Please contact administrator.',
          );
        }
        throw Exception(
          'Your account is inactive. Please contact administrator.',
        );
      }

      if (user.role.isEmpty) {
        await _logRejectedLoginWhileAuthed(user, 'LOGIN_BLOCKED_NO_ROLE');
        await _endSession();
        throw Exception('No role assigned. Please contact administrator.');
      }

      if (user.role != 'SuperAdmin' && user.shopId.isEmpty) {
        await _logRejectedLoginWhileAuthed(user, 'LOGIN_BLOCKED_NO_SHOP');
        await _endSession();
        throw Exception('No shop assigned. Please contact administrator.');
      }

      AppLogger.info(
        'Login successful: role=${user.role}',
        tag: 'AuthController',
      );

      unawaited(
        ErrorReporter.instance.setUserContext(
          userId: userId,
          role: user.role,
          shopId: user.shopId,
        ),
      );

      // PHASE 5 FIX: auth_controller.dart is the single source of LOGIN_SUCCESS audit.
      // login_screen.dart must NOT also call logAuthEvent for LOGIN_SUCCESS.
      try {
        await _logAuthEvent.call(<String, dynamic>{
          'action': 'LOGIN_SUCCESS',
          'shopId': user.shopId,
        });
      } catch (e, st) {
        reportCatch(e, stackTrace: st, tag: 'AuthController.loginAudit');
      }

      // Clear any accumulated failed-attempt counter now that sign-in
      // succeeded (also re-enables the Auth account if it had been disabled
      // by the lockout system and the window has since passed).
      try {
        await _resetLoginFailure.call();
      } catch (e, st) {
        reportCatch(e, stackTrace: st, tag: 'AuthController.resetLockout');
      }

      return user;
    } on FirebaseAuthException catch (e) {
      String errorMessage;
      switch (e.code) {
        case 'user-not-found':
          errorMessage = 'No account found with this email.';
          break;
        case 'wrong-password':
          errorMessage = 'Incorrect password. Please try again.';
          break;
        case 'invalid-email':
          errorMessage = 'Invalid email address.';
          break;
        case 'user-disabled':
          errorMessage = 'This account has been disabled.';
          break;
        case 'too-many-requests':
          errorMessage = 'Too many failed attempts. Please try again later.';
          break;
        case 'network-request-failed':
          errorMessage = 'Network error. Please check your connection.';
          break;
        case 'invalid-credential':
          errorMessage = 'Invalid email or password. Please try again.';
          break;
        default:
          errorMessage = 'Login failed. Please try again.';
      }

      reportCatch(e, tag: 'AuthController.login');

      // BUG FIX: `logAuthEvent` requires context.auth, but at this point sign-in
      // has just failed (wrong password / unknown user) so there is no
      // authenticated context — every call here used to throw 'unauthenticated'
      // and get silently swallowed, meaning failed logins were never audited.
      // `recordLoginFailure` requires no auth and also drives the account
      // lockout counter (see firebase/functions/src/auth/loginLockout.ts).
      try {
        final result = await _recordLoginFailure.call(<String, dynamic>{
          'email': trimmedEmail,
        });
        final data = result.data;
        if (data is Map && data['locked'] == true) {
          throw Exception(
            'Too many failed attempts. Your account has been temporarily locked.',
          );
        }
      } on FirebaseFunctionsException catch (auditError, st) {
        reportCatch(auditError, stackTrace: st, tag: 'AuthController.loginFailureAudit');
      }

      throw Exception(errorMessage);
    } catch (e, st) {
      if (e is Exception) rethrow;
      reportCatch(e, stackTrace: st, tag: 'AuthController.login');
      throw Exception('An unexpected error occurred. Please try again.');
    }
  }

  User? get currentUser => _auth.currentUser;

  bool get isAuthenticated => _auth.currentUser != null;

  Future<UserModel?> getCurrentUserModel() async {
    final user = currentUser;
    if (user == null) return null;
    final doc = await _firestore.collection('users').doc(user.uid).get();
    if (!doc.exists) return null;
    return UserModel.tryFromDocument(doc);
  }

  /// Logs an authentication rejection that happens AFTER Firebase Auth
  /// sign-in succeeded but BEFORE the app accepts the session (account
  /// inactive/suspended, no role, no shop assigned). Must run before
  /// `_endSession()` signs the user out, since `logAuthEvent` requires an
  /// authenticated context. Previously these rejections were not audited at
  /// all — §14.1 requires all login attempts, successful or not, be logged.
  Future<void> _logRejectedLoginWhileAuthed(UserModel user, String action) async {
    try {
      await _logAuthEvent.call(<String, dynamic>{
        'action': action,
        'shopId': user.shopId.isNotEmpty ? user.shopId : 'unknown',
      });
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'AuthController.rejectedLoginAudit');
    }
  }

  /// Clears caches/controllers and Firebase auth (no LOGOUT audit).
  Future<void> _endSession() async {
    await AuthLifecycleCleanup.run();
    await ErrorReporter.instance.clearUserContext();
    await _auth.signOut();
  }

  /// Sign out — audit BEFORE signing out so auth context is still valid.
  Future<void> signOut() async {
    try {
      final userModel = await getCurrentUserModel();
      final shopId = userModel?.shopId ?? '';
      await _logAuthEvent.call(<String, dynamic>{
        'action': 'LOGOUT',
        'shopId': shopId,
      });
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'AuthController.logoutAudit');
    }
    AppLogger.info('User signed out', tag: 'AuthController');
    await _endSession();
  }
}
