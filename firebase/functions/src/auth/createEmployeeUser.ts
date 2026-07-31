/**
 * createEmployeeUser Cloud Function
 * Admin or Super Admin: creates Employee (Firebase Auth + Firestore users doc).
 * Caller remains signed in; no client-side Auth switch.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { validateRequiredString } from '../utils/validation';
import { Role } from '../types/canonicalEnums';

const db = admin.firestore();
const auth = admin.auth();

function normalizeRole(role: string): string {
  return (role || '').replace(/\s+/g, '');
}

export const createEmployeeUser = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'Must be authenticated'
    );
  }

  const callerId = context.auth.uid;
  const callerDoc = await db.collection('users').doc(callerId).get();
  if (!callerDoc.exists) {
    throw new functions.https.HttpsError(
      'permission-denied',
      'User not found'
    );
  }

  const caller = callerDoc.data() as {
    role: string;
    status: string;
    shopId: string;
    userId: string;
    name: string;
    email: string;
    phone: string;
  };

  const callerRole = normalizeRole(caller.role);
  if (caller.status !== 'Active') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Account is not active'
    );
  }

  if (callerRole !== 'Admin' && callerRole !== 'SuperAdmin') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only Admin or Super Admin can create Employee users'
    );
  }

  const name = validateRequiredString(data?.name, 'name');
  const email = validateRequiredString(data?.email, 'email').trim().toLowerCase();
  const phone = validateRequiredString(data?.phone, 'phone');
  const password = validateRequiredString(data?.password, 'password');
  if (password.length < 6) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Password must be at least 6 characters'
    );
  }

  let shopId: string;
  if (callerRole === 'Admin') {
    if (!caller.shopId || caller.shopId.trim().length === 0) {
      throw new functions.https.HttpsError(
        'failed-precondition',
        'Admin account has no shop assigned'
      );
    }
    shopId = caller.shopId.trim();
    const requestedShopId =
      typeof data?.shopId === 'string' ? data.shopId.trim() : '';
    if (requestedShopId.length > 0 && requestedShopId !== shopId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Cannot create employees for another shop'
      );
    }
  } else {
    shopId = validateRequiredString(data?.shopId, 'shopId');
  }

  const existing = await db.collection('users').where('email', '==', email).get();
  if (!existing.empty) {
    throw new functions.https.HttpsError(
      'already-exists',
      'An account with this email already exists'
    );
  }

  let newAuthUser: admin.auth.UserRecord;
  try {
    newAuthUser = await auth.createUser({
      email,
      password,
      displayName: name,
    });
  } catch (err: unknown) {
    const code =
      err && typeof err === 'object' && 'code' in err
        ? String((err as { code: string }).code)
        : '';
    if (code === 'auth/email-already-exists') {
      throw new functions.https.HttpsError(
        'already-exists',
        'An account with this email already exists'
      );
    }
    if (code === 'auth/invalid-email') {
      throw new functions.https.HttpsError('invalid-argument', 'Invalid email address');
    }
    if (code === 'auth/weak-password') {
      throw new functions.https.HttpsError(
        'invalid-argument',
        'Password must be at least 6 characters'
      );
    }
    throw new functions.https.HttpsError(
      'internal',
      'Failed to create authentication account'
    );
  }

  const userId = newAuthUser.uid;
  const now = admin.firestore.Timestamp.now();

  try {
    await db.collection('users').doc(userId).set({
      userId,
      name,
      email,
      phone,
      role: data?.role === 'Viewer' ? 'Viewer' : Role.Employee,
      shopId,
      status: 'Active',
      createdAt: now,
    });
  } catch (firestoreErr) {
    try {
      await auth.deleteUser(userId);
    } catch {
      // Best-effort rollback; original error is still thrown below.
    }
    throw new functions.https.HttpsError(
      'internal',
      'Failed to create user profile. Authentication account was rolled back.'
    );
  }

  const logId = db.collection('audit_logs').doc().id;
  await db.collection('audit_logs').doc(logId).set({
    logId,
    userId: callerId,
    role: caller.role,
    shopId: caller.shopId,
    action: 'employee_user_created',
    entityType: 'user',
    entityId: userId,
    timestamp: now,
  });

  return { success: true, userId };
});
