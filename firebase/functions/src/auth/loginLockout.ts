/**
 * Login Failure Lockout System
 *
 * LOCATION: firebase/functions/src/auth/loginLockout.ts
 *
 * RESPONSIBILITIES:
 * - Track failed login attempts per user in `login_attempts/{userId}`
 * - After MAX_FAILURES (5) consecutive failures within LOCKOUT_WINDOW_MS (15 min):
 *     1. Disable the Firebase Auth account (Admin SDK) — hard block, not just advisory
 *     2. Set `lockedUntil` timestamp so client can display a countdown
 * - On successful login: reset failure counter and re-enable the Auth account
 * - Write an audit_log entry for every lockout event
 *
 * DESIGN DECISIONS:
 * - `recordLoginFailure` requires NO auth (user just failed to authenticate)
 * - `resetLoginFailure`  requires auth (only callable after a real Firebase Auth success)
 * - Firestore transaction guarantees atomic read-increment-write; no race conditions
 * - Admin SDK `updateUser({ disabled: true })` is the authoritative block — Firestore
 *   rules alone cannot stop Firebase Auth token issuance
 * - Lockout document is in a separate `login_attempts` collection so it does not
 *   pollute the `users` document and is fully server-controlled
 *
 * DOCUMENT SCHEMA — login_attempts/{userId}:
 * {
 *   userId: string,
 *   failureCount: number,          // resets to 0 on success
 *   lastFailureAt: Timestamp,
 *   lockedUntil: Timestamp | null, // null when not locked
 *   locked: boolean,
 * }
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { User } from '../types';

const db = admin.firestore();

const MAX_FAILURES     = 5;
const LOCKOUT_MS       = 15 * 60 * 1000; // 15 minutes in milliseconds

// ---------------------------------------------------------------------------
// Helper: write a lockout-related entry to audit_logs
// ---------------------------------------------------------------------------
async function writeLockoutAuditLog(
  userId: string,
  action: string,
  extras: Record<string, any> = {}
): Promise<void> {
  const logRef = db.collection('audit_logs').doc();
  await logRef.set({
    logId: logRef.id,
    userId,
    role: 'system',
    shopId: 'system',
    action,
    entityType: 'authentication',
    entityId: userId,
    timestamp: admin.firestore.Timestamp.now(),
    success: false,
    ...extras,
  });
}

// ---------------------------------------------------------------------------
// Callable: recordLoginFailure
// No auth required — called by client after Firebase Auth rejects sign-in.
// Accepts { email } so we can look up the userId.
// ---------------------------------------------------------------------------
export const recordLoginFailure = functions.https.onCall(async (data) => {
  const email: string | undefined = data?.email;

  if (!email || typeof email !== 'string' || email.trim() === '') {
    // Nothing to track without an identifier — silently succeed so the
    // client's error handling is not blocked.
    return { success: false, reason: 'no_email_provided' };
  }

  const cleanEmail = email.trim().toLowerCase();

  // ── 1. Resolve userId from Firestore ──────────────────────────────────────
  const usersSnap = await db
    .collection('users')
    .where('email', '==', cleanEmail)
    .limit(1)
    .get();

  if (usersSnap.empty) {
    // Unknown email — do not leak whether the account exists. Log and return.
    console.log(`recordLoginFailure: unknown email ${cleanEmail}`);
    return { success: true, locked: false };
  }

  const user = usersSnap.docs[0].data() as User;
  const userId = user.userId;

  const attemptRef = db.collection('login_attempts').doc(userId);
  const now        = admin.firestore.Timestamp.now();
  const nowMs      = now.toMillis();

  // ── 2. Atomically increment failure counter ────────────────────────────────
  let newCount = 0;
  let locked   = false;
  let lockedUntil: admin.firestore.Timestamp | null = null;

  await db.runTransaction(async (tx) => {
    const snap = await tx.get(attemptRef);
    const existing = snap.exists ? snap.data()! : null;

    // If a previous lockout has expired, treat it as a fresh slate
    const previouslyLocked: boolean = existing?.locked === true;
    const previousLockedUntil: admin.firestore.Timestamp | null =
      existing?.lockedUntil ?? null;
    const lockExpired =
      previouslyLocked &&
      previousLockedUntil !== null &&
      previousLockedUntil.toMillis() <= nowMs;

    const baseCount = lockExpired ? 0 : (existing?.failureCount ?? 0);
    newCount = baseCount + 1;

    if (newCount >= MAX_FAILURES) {
      locked       = true;
      lockedUntil  = admin.firestore.Timestamp.fromMillis(nowMs + LOCKOUT_MS);
    }

    tx.set(
      attemptRef,
      {
        userId,
        failureCount: newCount,
        lastFailureAt: now,
        locked,
        lockedUntil: lockedUntil,
      },
      { merge: false }
    );
  });

  // ── 3. If threshold reached, disable the Firebase Auth account ────────────
  if (locked) {
    try {
      await admin.auth().updateUser(userId, { disabled: true });
      console.log(`Login lockout: disabled Auth account for ${userId} after ${newCount} failures`);
    } catch (authErr: any) {
      // Log but don't fail — Firestore lockout document is the fallback
      console.error(`Failed to disable Auth account for ${userId}:`, authErr?.message);
    }

    // Audit log for lockout event
    await writeLockoutAuditLog(userId, 'login_lockout', {
      failureCount: newCount,
      lockedUntil,
      email: user.email,
      shopId: user.shopId,
      note: `Account locked after ${MAX_FAILURES} consecutive failed login attempts`,
    });
  } else {
    // Audit log for each individual failure (non-locking)
    await writeLockoutAuditLog(userId, 'login_failure_counted', {
      failureCount: newCount,
      email: user.email,
      shopId: user.shopId,
    });
  }

  // Cast to the known non-null type so TypeScript can resolve .toMillis()
  const lockedUntilTs = lockedUntil as admin.firestore.Timestamp | null;

  return {
    success: true,
    locked,
    failureCount: newCount,
    lockedUntil: lockedUntilTs ? lockedUntilTs.toMillis() : null,
    remainingAttempts: locked ? 0 : MAX_FAILURES - newCount,
  };
});

// ---------------------------------------------------------------------------
// Callable: checkLoginLockout
// No auth required — called by client BEFORE attempting Firebase Auth sign-in.
//
// BUG THIS FIXES: `resetLoginFailure` requires a successful sign-in to run,
// but a locked account is disabled at the Firebase Auth level (Admin SDK), so
// a disabled user can NEVER sign in successfully — resetLoginFailure could
// never be reached and the account would stay disabled forever after the
// 15-minute window. This callable performs the time-based auto-unlock
// (no identity check needed since it only acts once `lockedUntil` has
// already elapsed) so the client can check-before-attempting, and so the
// account becomes sign-in-able again once the lockout window passes.
// ---------------------------------------------------------------------------
export const checkLoginLockout = functions.https.onCall(async (data) => {
  const email: string | undefined = data?.email;

  if (!email || typeof email !== 'string' || email.trim() === '') {
    return { locked: false };
  }

  const cleanEmail = email.trim().toLowerCase();

  const usersSnap = await db
    .collection('users')
    .where('email', '==', cleanEmail)
    .limit(1)
    .get();

  if (usersSnap.empty) {
    // Unknown email — do not leak whether the account exists.
    return { locked: false };
  }

  const user = usersSnap.docs[0].data() as User;
  const userId = user.userId;

  const attemptRef = db.collection('login_attempts').doc(userId);
  const snap = await attemptRef.get();
  if (!snap.exists) {
    return { locked: false };
  }

  const existing = snap.data()!;
  if (existing.locked !== true) {
    return { locked: false };
  }

  const lockedUntil: admin.firestore.Timestamp | null = existing.lockedUntil ?? null;
  const nowMs = Date.now();

  if (lockedUntil !== null && lockedUntil.toMillis() > nowMs) {
    // Still within the lockout window.
    return { locked: true, lockedUntil: lockedUntil.toMillis() };
  }

  // Lockout window has elapsed — clear the lockout counter regardless (it's
  // brute-force bookkeeping only), but only re-enable the Firebase Auth
  // account if the user is still Active in Firestore.
  //
  // SECURITY FIX: this function is unauthenticated by design (it must run
  // before the caller can sign in), so it MUST NOT blindly re-enable an
  // account — an Admin/Super Admin may have Suspended or (soft-)Deleted this
  // user (deleteEmployee.ts explicitly disables their Auth account) any time
  // after the lockout was set. Re-enabling unconditionally would let that
  // account sign in again once the 15-minute window passes, silently undoing
  // the admin's action. Only the login-lockout's own disable may be cleared
  // here, never a status-driven disable.
  await attemptRef.set(
    {
      userId,
      failureCount: 0,
      lastFailureAt: null,
      locked: false,
      lockedUntil: null,
    },
    { merge: false }
  );

  if (user.status !== 'Active') {
    return { locked: false };
  }

  try {
    const authUser = await admin.auth().getUser(userId);
    if (authUser.disabled) {
      await admin.auth().updateUser(userId, { disabled: false });
      console.log(`Login lockout: auto re-enabled Auth account for ${userId} after lockout window elapsed`);

      await writeLockoutAuditLog(userId, 'login_lockout_expired', {
        email: user.email,
        shopId: user.shopId,
        success: true,
        note: 'Lockout window elapsed; account auto re-enabled on next login attempt',
      });
    }
  } catch (authErr: any) {
    console.error(`Failed to auto re-enable Auth account for ${userId}:`, authErr?.message);
  }

  return { locked: false };
});

// ---------------------------------------------------------------------------
// Callable: resetLoginFailure
// Requires auth — called by client after a SUCCESSFUL Firebase Auth sign-in.
// Resets the counter and re-enables the Auth account.
// ---------------------------------------------------------------------------
export const resetLoginFailure = functions.https.onCall(async (_data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError(
      'unauthenticated',
      'User must be authenticated to reset login failure count'
    );
  }

  const userId = context.auth.uid;
  const attemptRef = db.collection('login_attempts').doc(userId);

  // ── 1. Clear the lockout document atomically ───────────────────────────────
  await db.runTransaction(async (tx) => {
    const snap = await tx.get(attemptRef);
    if (!snap.exists) return; // Nothing to reset

    tx.set(
      attemptRef,
      {
        userId,
        failureCount: 0,
        lastFailureAt: null,
        locked: false,
        lockedUntil: null,
      },
      { merge: false }
    );
  });

  // ── 2. Re-enable the Firebase Auth account if it was disabled ─────────────
  try {
    const authUser = await admin.auth().getUser(userId);
    if (authUser.disabled) {
      await admin.auth().updateUser(userId, { disabled: false });
      console.log(`Login lockout: re-enabled Auth account for ${userId} after successful login`);

      // Audit log for unlock event
      const logRef = db.collection('audit_logs').doc();
      await logRef.set({
        logId: logRef.id,
        userId,
        role: 'system',
        shopId: 'system',
        action: 'login_lockout_cleared',
        entityType: 'authentication',
        entityId: userId,
        timestamp: admin.firestore.Timestamp.now(),
        success: true,
        note: 'Account re-enabled after successful authentication',
      });
    }
  } catch (authErr: any) {
    console.error(`Failed to re-enable Auth account for ${userId}:`, authErr?.message);
  }

  return { success: true, reset: true };
});
