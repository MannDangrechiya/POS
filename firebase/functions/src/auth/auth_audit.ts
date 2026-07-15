/**
 * Authentication Audit Logging Cloud Functions
 * 
 * LOCATION: firebase/functions/src/auth/auth_audit.ts
 * 
 * RESPONSIBILITIES:
 * - Log login success
 * - Log login failure
 * - Log logout
 * - Log password reset
 * - Log user status change
 * - Write immutable audit_logs
 * 
 * CRITICAL BUSINESS RULES ENFORCED:
 * - All authentication events are logged
 * - Audit logs are immutable (append-only)
 * - Login success/failure tracking for security
 * - Password reset events logged for audit
 * - User status changes tracked
 * 
 * Based on TECHNICAL REQUIREMENTS IN DETAIL.md - Module 10: AUDIT LOGS
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { User, UserStatus } from '../types';
import { validateRequiredString } from '../utils/validation';
import { isValidRole, Role } from '../types/canonicalEnums';

const db = admin.firestore();

/**
 * Creates an immutable audit log entry for authentication events
 * Audit logs are append-only and cannot be modified or deleted
 */
async function createAuthAuditLog(
  userId: string,
  role: string,
  shopId: string,
  action: string,
  success: boolean,
  additionalData?: Record<string, any>
): Promise<string> {
  const logId = db.collection('audit_logs').doc().id;
  const timestamp = admin.firestore.Timestamp.now();

  const auditLog: any = {
    logId,
    userId,
    role,
    shopId,
    action,
    entityType: 'authentication',
    entityId: userId,
    timestamp, // Immutable timestamp
    success,
  };

  // Add additional data if provided
  if (additionalData) {
    Object.assign(auditLog, additionalData);
  }

  // Write immutable audit log - append-only
  await db.collection('audit_logs').doc(logId).set(auditLog);

  return logId;
}

/**
 * Callable function to log login success
 * Called from client after successful Firebase Authentication
 */
export const logLoginSuccess = functions.https.onCall(async (data, context) => {
  // User must be authenticated to log login success
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated to log login success'
    );
  }

  const userId = context.auth.uid;

  try {
    // Get user data from Firestore
    const userDoc = await db.collection('users').doc(userId).get();

    if (!userDoc.exists) {
      // User exists in Firebase Auth but not in Firestore - log with minimal data
      await createAuthAuditLog(
        userId,
        'unknown',
        'unknown',
        'login_success',
        true,
        {
          note: 'User authenticated but not found in Firestore users collection',
        }
      );

      console.warn(`Login success logged for user not in Firestore: ${userId}`);
      return { success: true, logId: 'unknown' };
    }

    const user = userDoc.data() as User;

    // Create immutable audit log
    const logId = await createAuthAuditLog(
      user.userId,
      user.role,
      user.shopId,
      'login_success',
      true,
      {
        email: user.email,
        loginTime: admin.firestore.Timestamp.now(),
      }
    );

    console.log(`Login success logged: ${userId} (${user.email})`);
    return { success: true, logId };
  } catch (error: any) {
    console.error('Error logging login success:', error);
    // Don't throw - logging failure shouldn't break login flow
    return { success: false, error: error.message };
  }
});

/**
 * Callable function to log login failure
 * Called from client after failed authentication attempt
 */
export const logLoginFailure = functions.https.onCall(async (data, context) => {
  // No authentication required - we're logging a failure
  const { email, phone, errorMessage } = data || {};

  try {
    let userId = 'unknown';
    let role = 'unknown';
    let shopId = 'unknown';
    let userEmail = email || 'unknown';

    // Try to find user by email or phone
    if (email) {
      const usersByEmail = await db
        .collection('users')
        .where('email', '==', email)
        .limit(1)
        .get();

      if (!usersByEmail.empty) {
        const user = usersByEmail.docs[0].data() as User;
        userId = user.userId;
        role = user.role;
        shopId = user.shopId;
        userEmail = user.email;
      }
    } else if (phone) {
      const usersByPhone = await db
        .collection('users')
        .where('phone', '==', phone)
        .limit(1)
        .get();

      if (!usersByPhone.empty) {
        const user = usersByPhone.docs[0].data() as User;
        userId = user.userId;
        role = user.role;
        shopId = user.shopId;
        userEmail = user.email;
      }
    }

    // Create immutable audit log for failed login
    const logId = await createAuthAuditLog(
      userId,
      role,
      shopId,
      'login_failure',
      false,
      {
        attemptedEmail: email || null,
        attemptedPhone: phone || null,
        errorMessage: errorMessage || 'Unknown error',
        failureTime: admin.firestore.Timestamp.now(),
      }
    );

    console.log(`Login failure logged: ${userEmail || phone || 'unknown'}`);
    return { success: true, logId };
  } catch (error: any) {
    console.error('Error logging login failure:', error);
    // Don't throw - logging failure shouldn't break error handling
    return { success: false, error: error.message };
  }
});

/**
 * Callable function to log logout
 * Called from client when user logs out
 */
export const logLogout = functions.https.onCall(async (data, context) => {
  // User must be authenticated to log logout
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated to log logout'
    );
  }

  const userId = context.auth.uid;

  try {
    // Get user data from Firestore
    const userDoc = await db.collection('users').doc(userId).get();

    if (!userDoc.exists) {
      // User exists in Firebase Auth but not in Firestore
      await createAuthAuditLog(
        userId,
        'unknown',
        'unknown',
        'logout',
        true,
        {
          note: 'User logged out but not found in Firestore users collection',
        }
      );

      console.warn(`Logout logged for user not in Firestore: ${userId}`);
      return { success: true, logId: 'unknown' };
    }

    const user = userDoc.data() as User;

    // Create immutable audit log
    const logId = await createAuthAuditLog(
      user.userId,
      user.role,
      user.shopId,
      'logout',
      true,
      {
        email: user.email,
        logoutTime: admin.firestore.Timestamp.now(),
      }
    );

    console.log(`Logout logged: ${userId} (${user.email})`);
    return { success: true, logId };
  } catch (error: any) {
    console.error('Error logging logout:', error);
    // Don't throw - logging failure shouldn't break logout flow
    return { success: false, error: error.message };
  }
});

/**
 * Callable function to log password reset request
 * Called from client when user requests password reset
 */
export const logPasswordResetRequest = functions.https.onCall(async (data, context) => {
  // No authentication required - user is resetting password
  const { email } = data || {};

  try {
    const userEmail = validateRequiredString(email, 'email');

    // Try to find user by email
    const usersSnapshot = await db
      .collection('users')
      .where('email', '==', userEmail)
      .limit(1)
      .get();

    let userId = 'unknown';
    let role = 'unknown';
    let shopId = 'unknown';

    if (!usersSnapshot.empty) {
      const user = usersSnapshot.docs[0].data() as User;
      userId = user.userId;
      role = user.role;
      shopId = user.shopId;
    }

    // Create immutable audit log
    const logId = await createAuthAuditLog(
      userId,
      role,
      shopId,
      'password_reset_request',
      true,
      {
        email: userEmail,
        requestTime: admin.firestore.Timestamp.now(),
      }
    );

    console.log(`Password reset request logged: ${userEmail}`);
    return { success: true, logId };
  } catch (error: any) {
    console.error('Error logging password reset request:', error);
    return { success: false, error: error.message };
  }
});

/**
 * Callable function to log password reset completion
 * Called from client after user successfully resets password
 */
export const logPasswordResetComplete = functions.https.onCall(async (data, context) => {
  // User must be authenticated after password reset
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated to log password reset completion'
    );
  }

  const userId = context.auth.uid;

  try {
    // Get user data from Firestore
    const userDoc = await db.collection('users').doc(userId).get();

    if (!userDoc.exists) {
      await createAuthAuditLog(
        userId,
        'unknown',
        'unknown',
        'password_reset_complete',
        true,
        {
          note: 'Password reset completed but user not found in Firestore',
        }
      );

      console.warn(`Password reset complete logged for user not in Firestore: ${userId}`);
      return { success: true, logId: 'unknown' };
    }

    const user = userDoc.data() as User;

    // Create immutable audit log
    const logId = await createAuthAuditLog(
      user.userId,
      user.role,
      user.shopId,
      'password_reset_complete',
      true,
      {
        email: user.email,
        completionTime: admin.firestore.Timestamp.now(),
      }
    );

    console.log(`Password reset complete logged: ${userId} (${user.email})`);
    return { success: true, logId };
  } catch (error: any) {
    console.error('Error logging password reset completion:', error);
    return { success: false, error: error.message };
  }
});

/**
 * Actions logAuthEvent accepts, and the entityType each is pinned to.
 * `null` entityType means "auth-only, no entityId/metadata" (original
 * behavior, unchanged). `'setting'` actions additionally require entityId to
 * reference a settingId the caller is actually allowed to manage.
 *
 * SECURITY: this is an authenticated-but-otherwise-self-service callable, so
 * without an allow-list any authenticated user (including Employee) could
 * write an audit_logs entry with an arbitrary action/entityType/entityId and
 * unbounded metadata — log forgery for compliance/forensic purposes, and a
 * storage-bloat vector. See docs/AUDIT_REPORT_VS_DOCUMENTATION.md security
 * review for the finding this fixes.
 */
const AUTH_ONLY_ACTIONS = new Set([
  'LOGIN_SUCCESS',
  'LOGOUT',
  'LOGIN_BLOCKED_STATUS',
  'LOGIN_BLOCKED_NO_ROLE',
  'LOGIN_BLOCKED_NO_SHOP',
  'PASSWORD_RESET',
]);
const SETTING_ACTIONS = new Set([
  'SETTING_CREATED',
  'SETTING_UPDATED',
  'SETTING_DELETED',
]);
const MAX_METADATA_JSON_LENGTH = 2000;

/**
 * Callable: logAuthEvent
 * Only callable by authenticated users. Appends one document to audit_logs.
 * Rejects if unauthenticated, invalid role, shop mismatch, or an
 * unrecognized action (see AUTH_ONLY_ACTIONS / SETTING_ACTIONS above).
 * No update or delete allowed (enforced by Firestore rules).
 */
export const logAuthEvent = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated'
    );
  }

  const userId = context.auth.uid;
  const action = validateRequiredString(data?.action, 'action');
  const shopId = validateRequiredString(data?.shopId, 'shopId');

  const isAuthOnly = AUTH_ONLY_ACTIONS.has(action);
  const isSettingAction = SETTING_ACTIONS.has(action);
  if (!isAuthOnly && !isSettingAction) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      `Unrecognized action: ${action}`
    );
  }

  const userDoc = await db.collection('users').doc(userId).get();
  if (!userDoc.exists) {
    throw new functions.https.HttpsError(
      'not-found',
      'User not found'
    );
  }

  const user = userDoc.data() as User;

  if (!isValidRole(user.role)) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Invalid role'
    );
  }

  if (user.status !== UserStatus.ACTIVE) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'User account is not active'
    );
  }

  const shopMatch = user.role === Role.SuperAdmin || user.shopId === shopId;
  if (!shopMatch) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Shop mismatch'
    );
  }

  let entityType = 'AUTH';
  let entityId: string | undefined;
  let metadata: Record<string, any> | undefined;

  if (isSettingAction) {
    entityType = 'setting';
    entityId = validateRequiredString(data?.entityId, 'entityId');

    // entityId must reference a settingId this caller is actually allowed to
    // manage — a SuperAdmin's system settings, or this caller's own shop.
    // Prevents a caller from claiming an audit entry about another shop's
    // (or a fabricated) setting.
    const expectedPrefix =
      user.role === Role.SuperAdmin ? 'system_' : `shop_${user.shopId}_`;
    if (!entityId.startsWith(expectedPrefix)) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'entityId does not belong to a setting this user may manage'
      );
    }

    if (data?.metadata !== undefined) {
      if (typeof data.metadata !== 'object' || data.metadata === null || Array.isArray(data.metadata)) {
        throw new functions.https.HttpsError('invalid-argument', 'metadata must be an object');
      }
      const serialized = JSON.stringify(data.metadata);
      if (serialized.length > MAX_METADATA_JSON_LENGTH) {
        throw new functions.https.HttpsError(
          'invalid-argument',
          `metadata too large (max ${MAX_METADATA_JSON_LENGTH} chars serialized)`
        );
      }
      metadata = data.metadata;
    }
  }

  const logId = db.collection('audit_logs').doc().id;
  const timestamp = admin.firestore.Timestamp.now();

  await db.collection('audit_logs').doc(logId).set({
    userId: user.userId,
    role: user.role,
    shopId: user.shopId,
    action,
    entityType,
    timestamp,
    ...(entityId !== undefined ? { entityId } : {}),
    ...(metadata !== undefined ? { metadata } : {}),
  });

  return { success: true, logId };
});

/**
 * Callable: bootstrap first user when no one is active.
 * If there are zero users with status Active, sets the caller's status to Active.
 * Use when the only admin is inactive and cannot log in (recovery).
 */
export const bootstrapFirstUser = functions.https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Must be signed in to request activation'
    );
  }

  const uid = context.auth.uid;

  try {
    const userRef = db.collection('users').doc(uid);
    const userSnap = await userRef.get();
    if (!userSnap.exists) {
      return { activated: false, reason: 'user_doc_not_found' };
    }

    const data = userSnap.data()!;
    const status = (data.status ?? 'Inactive').toString().trim();

    if (data.role !== Role.SuperAdmin) {
      return { activated: false, reason: 'not_super_admin' };
    }

    if (status === UserStatus.ACTIVE) {
      return { activated: false, reason: 'already_active' };
    }
    if (status === UserStatus.SUSPENDED) {
      return { activated: false, reason: 'suspended' };
    }

    const activeSnap = await db.collection('users')
      .where('status', '==', 'Active')
      .limit(1)
      .get();

    if (!activeSnap.empty) {
      return { activated: false, reason: 'another_active_exists' };
    }

    await userRef.update({ status: 'Active' });
    console.log(`Bootstrap: activated first user ${uid} (${data.email})`);
    return { activated: true };
  } catch (error: any) {
    console.error('bootstrapFirstUser error:', error);
    throw new functions.https.HttpsError('internal', error.message);
  }
});

/**
 * Firestore trigger on user status change
 * Logs when user account status changes (active/inactive/suspended)
 */
export const onUserStatusChange = functions.firestore
  .document('users/{userId}')
  .onUpdate(async (change, context) => {
    const userId = context.params.userId;
    const before = change.before.data() as User;
    const after = change.after.data() as User;

    // Check if status actually changed
    if (before.status === after.status) {
      return null;
    }

    try {
      // Create immutable audit log for user status change
      const logId = db.collection('audit_logs').doc().id;
      await db.collection('audit_logs').doc(logId).set({
        logId,
        userId: 'system_trigger',
        role: 'system',
        shopId: after.shopId,
        action: 'user_status_change',
        entityType: 'user',
        entityId: userId,
        timestamp: admin.firestore.Timestamp.now(),
        success: true,
        oldStatus: before.status,
        newStatus: after.status,
        userEmail: after.email,
        userName: after.name,
        note: 'User status change detected via trigger. Actual actor should be logged via callable function if available.',
      });

      console.log(`User status change logged: ${userId} (${after.email}) - ${before.status} -> ${after.status}`);
    } catch (error: any) {
      console.error(`Error logging user status change for ${userId}:`, error);
    }

    // BUG FIX: reactivating a user in Firestore (e.g. Admin/Super Admin
    // toggling status back to Active) previously left the Firebase Auth
    // account disabled if the login-lockout system (recordLoginFailure) had
    // ever disabled it — there was no path to clear that flag except a
    // successful sign-in, which is impossible while disabled. Reconcile the
    // Auth-level disable and the lockout doc whenever status becomes Active.
    if (after.status === UserStatus.ACTIVE) {
      try {
        const authUser = await admin.auth().getUser(userId);
        if (authUser.disabled) {
          await admin.auth().updateUser(userId, { disabled: false });
          console.log(`Reactivation: re-enabled Auth account for ${userId}`);
        }
      } catch (authErr: any) {
        console.error(`Failed to re-enable Auth account for ${userId} on reactivation:`, authErr?.message);
      }

      try {
        await db.collection('login_attempts').doc(userId).set(
          {
            userId,
            failureCount: 0,
            lastFailureAt: null,
            locked: false,
            lockedUntil: null,
          },
          { merge: false }
        );
      } catch (lockErr: any) {
        console.error(`Failed to clear login_attempts for ${userId} on reactivation:`, lockErr?.message);
      }
    }

    return null;
  });
