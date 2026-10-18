import 'dart:async' show unawaited;
import 'package:flutter/material.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:get/get.dart';
import 'firebase_options.dart';
import 'core/auth/auth_lifecycle_cleanup.dart';
import 'core/firestore/firestore_parse.dart';
import 'core/observability/app_exception_handler.dart';
import 'core/observability/app_logger.dart';
import 'core/observability/error_reporter.dart';
import 'core/observability/error_ui.dart';
import 'core/observability/user_safe_error_mapper.dart';
import 'data/models/user_model.dart';
import 'modules/authentication/auth_controller.dart';
import 'modules/authentication/login_screen.dart';
import 'modules/authentication/inactivity_wrapper.dart';
import 'modules/authentication/session_manager.dart';
import 'modules/pos/controllers/cart_controller.dart';
import 'core/hardware/printer_service.dart';
import 'core/hardware/weighing_scale_service.dart';
import 'core/hardware/cfd_service.dart';
import 'routing/role_based_router.dart';
import 'routing/route_guard.dart';

void main() {
  AppExceptionHandler.runZonedApp(() async {
    WidgetsFlutterBinding.ensureInitialized();

    await Firebase.initializeApp(
      options: DefaultFirebaseOptions.currentPlatform,
    );

    await AppExceptionHandler.initialize();

    // Disable persistence to avoid stale cache issues
    FirebaseFirestore.instance.settings = const Settings(
      persistenceEnabled: false,
    );

    runApp(const MyApp());
  });
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    // Initialize GetX hardware services and cart controller
    Get.put(CartController());
    Get.put(PrinterService());
    Get.put(WeighingScaleService());
    Get.put(CfdService());

    return MaterialApp(
      title: 'Fruit POS System',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        useMaterial3: true,
        colorScheme: ColorScheme.fromSeed(
          seedColor: Colors.green,
          brightness: Brightness.light,
        ),
      ),
      // All route access is validated by RouteGuard before the page is built.
      // Protected routes require an authenticated user whose role matches the route.
      // Any mismatch → redirect to LoginScreen.
      onGenerateRoute: RouteGuard.onGenerateRoute,
      home: const InactivityWrapper(
        child: AuthWrapper(),
      ),
    );
  }
}

/// Wrapper widget that listens to authentication state and routes accordingly.
/// Enforces: account status check, role-based redirection, shop assignment validation.
class AuthWrapper extends StatefulWidget {
  const AuthWrapper({super.key});

  @override
  State<AuthWrapper> createState() => _AuthWrapperState();
}

class _AuthWrapperState extends State<AuthWrapper> {
  String? _cachedUid;
  Future<UserModel>? _userLoadFuture;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<User?>(
      stream: FirebaseAuth.instance.authStateChanges(),
      builder: (context, snapshot) {
        // Show loading while checking auth state
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }

        final User? user = snapshot.data;

        // User is not authenticated, show login screen
        if (user == null) {
          _cachedUid = null;
          _userLoadFuture = null;
          unawaited(ErrorReporter.instance.clearUserContext());
          AuthLifecycleCleanup.onAuthStateSignedOut();
          return const LoginScreen();
        }

        // User is authenticated, fetch user data and navigate
        if (_cachedUid != user.uid) {
          if (_cachedUid != null) {
            AuthLifecycleCleanup.onAuthStateSignedOut();
          }
          _cachedUid = user.uid;
          _userLoadFuture = _fetchUserData(user.uid);
        }
        return FutureBuilder<UserModel>(
          future: _userLoadFuture,
          builder: (context, userSnapshot) {
            if (userSnapshot.connectionState == ConnectionState.waiting) {
              return const Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      CircularProgressIndicator(),
                      SizedBox(height: 16),
                      Text('Loading your dashboard...'),
                    ],
                  ),
                ),
              );
            }

            if (userSnapshot.hasError) {
              final error = userSnapshot.error!;
              final stackTrace = userSnapshot.stackTrace;
              reportCatch(
                error,
                stackTrace: stackTrace,
                tag: 'AuthWrapper.fetchUser',
              );

              // Determine error type
              bool isUserSpecificError = false;
              bool isAccountStatusError = false;
              final errorMessage = UserSafeErrorMapper.messageFor(error);

              if (error is Exception) {
                final errorStr = error.toString().toLowerCase();
                if (errorStr.contains('user document not found') ||
                    errorStr.contains('user role is empty')) {
                  isUserSpecificError = true;
                } else if (errorStr.contains('account is inactive') ||
                    errorStr.contains('account has been suspended') ||
                    errorStr.contains('no shop assigned')) {
                  isAccountStatusError = true;
                }
              }

              // Sign out for user-specific and account status errors (logLogout + signOut)
              if (isUserSpecificError || isAccountStatusError) {
                AuthController().signOut();
                if (isAccountStatusError) {
                  // Show a message before returning to login
                  return Scaffold(
                    body: Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          const Icon(
                            Icons.block,
                            size: 64,
                            color: Colors.orange,
                          ),
                          const SizedBox(height: 16),
                          const Text(
                            'Account Access Denied',
                            style: TextStyle(
                              fontSize: 18,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 32),
                            child: Text(
                              errorMessage,
                              textAlign: TextAlign.center,
                              style: const TextStyle(color: Colors.grey),
                            ),
                          ),
                          const SizedBox(height: 24),
                          ElevatedButton(
                            onPressed: () async {
                              await AuthController().signOut();
                              if (mounted) setState(() {});
                            },
                            child: const Text('Back to Login'),
                          ),
                        ],
                      ),
                    ),
                  );
                }
                return const LoginScreen();
              }

              // For database/infrastructure errors, show retry UI
              return Scaffold(
                body: Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(
                        Icons.error_outline,
                        size: 64,
                        color: Colors.red,
                      ),
                      const SizedBox(height: 16),
                      const Text(
                        'Database Connection Error',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 32),
                        child: Text(
                          errorMessage,
                          textAlign: TextAlign.center,
                          style: const TextStyle(color: Colors.grey),
                        ),
                      ),
                      const SizedBox(height: 24),
                      ElevatedButton(
                        onPressed: () {
                          setState(() {
                            _userLoadFuture = _fetchUserData(user.uid);
                          });
                        },
                        child: const Text('Retry'),
                      ),
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: () async {
                          await AuthController().signOut();
                          if (mounted) setState(() {});
                        },
                        child: const Text('Sign Out'),
                      ),
                    ],
                  ),
                ),
              );
            }

            if (!userSnapshot.hasData) {
              return const LoginScreen();
            }

            final UserModel userData = userSnapshot.data!;
            unawaited(
              ErrorReporter.instance.setUserContext(
                userId: user.uid,
                role: userData.role,
                shopId: userData.shopId,
              ),
            );
            final String route = RoleBasedRouter.getInitialRoute(userData.role);

            // Navigate to the appropriate dashboard.
            // IMPORTANT: pass userData as arguments so RouteGuard can
            // validate the role synchronously without an async Firestore call.
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!context.mounted) return;
              Navigator.of(context).pushReplacementNamed(
                route,
                arguments: userData,
              );
            });

            return const Scaffold(
              body: Center(child: CircularProgressIndicator()),
            );
          },
        );
      },
    );
  }

  /// Fetches user data from Firestore and validates account status.
  /// Returns UserModel if valid, throws appropriate exceptions on failure.
  /// Uses bootstrapFirstUser callable when inactive and no other active user exists.
  Future<UserModel> _fetchUserData(String userId) async {
    try {
      DocumentSnapshot userDoc;
      try {
        userDoc = await FirebaseFirestore.instance
            .collection('users')
            .doc(userId)
            .get();
      } on FirebaseException catch (e) {
        if (e.code == 'permission-denied') {
          final result = await FirebaseFunctions.instance
              .httpsCallable('bootstrapFirstUser')
              .call<Map<String, dynamic>>();
          final data = result.data;
          if (data['activated'] == true) {
            userDoc = await FirebaseFirestore.instance
                .collection('users')
                .doc(userId)
                .get();
          } else {
            rethrow;
          }
        } else {
          rethrow;
        }
      }

      if (!userDoc.exists) {
        throw Exception('User document not found');
      }

      final data = UserModel.tryFromDocument(userDoc);
      if (data == null) {
        throw Exception('User document data is invalid');
      }

      // Concurrent login restriction (optional advanced): if a remote
      // activeSessionId exists and does not match this device, treat as invalid.
      final remoteSessionId = FirestoreParse.stringField(
        FirestoreParse.documentData(userDoc)?['activeSessionId'],
      );
      final isActiveHere = await SessionManager.isCurrentDeviceActive(
        userId,
        remoteSessionId.isEmpty ? null : remoteSessionId,
      );
      if (!isActiveHere) {
        throw Exception(
          'Your session has been closed because your account was used on another device.',
        );
      }

      UserModel user = data;

      // Check account status
      if (!user.isActive) {
        if (user.isSuspended) {
          throw Exception(
            'Your account has been suspended. Contact administrator.',
          );
        }
        // Bootstrap via callable: server activates this account if no other user is Active
        try {
          final result = await FirebaseFunctions.instance
              .httpsCallable('bootstrapFirstUser')
              .call<Map<String, dynamic>>();
          final data = result.data;
          if (data['activated'] == true) {
            AppLogger.info(
              'Bootstrap: account activated (no other active users)',
              tag: 'AuthWrapper',
            );
            user = user.copyWith(status: 'Active');
          } else {
            // Callable ran successfully but chose NOT to activate this user.
            // This is an intentional account-status decision.
            throw Exception('Your account is inactive. Contact administrator.');
          }
        } on FirebaseFunctionsException catch (e, st) {
          reportCatch(e, stackTrace: st, tag: 'AuthWrapper.bootstrapFirstUser');
          // Treat callable failures (e.g. INTERNAL) as infrastructure issues,
          // not as "account inactive" so that AuthWrapper shows the retry UI
          // instead of auto-signing the user out.
          throw Exception(
            'Unable to verify account status. Please try again or contact administrator.',
          );
        }
      }

      // Validate role exists
      if (user.role.isEmpty) {
        throw Exception('User role is empty');
      }

      // Validate shopId for non-SuperAdmin (canonical role)
      if (user.role != 'SuperAdmin' && user.shopId.isEmpty) {
        throw Exception('No shop assigned. Contact administrator.');
      }

      AppLogger.info(
        'User loaded: role=${user.role} shop=${user.shopId.isEmpty ? "(none)" : "set"}',
        tag: 'AuthWrapper',
      );

      return user;
    } on FirebaseException catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'AuthWrapper._fetchUserData');
      rethrow;
    } catch (e, st) {
      reportCatch(e, stackTrace: st, tag: 'AuthWrapper._fetchUserData');
      rethrow;
    }
  }
}

