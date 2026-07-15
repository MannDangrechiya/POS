/**
 * Product Deletion Cloud Function
 *
 * LOCATION: firebase/functions/src/products/deleteProduct.ts
 *
 * WHY THIS EXISTS:
 * Firestore rules deny `delete` on the `products` collection unconditionally
 * (`allow delete: if false`) and, until now, no Cloud Function existed to
 * delete a product any other way — meaning no role, including Super Admin,
 * had any way to delete a product at all. Requirement in Detail §26.2 / §5.1
 * grant Super Admin a Write/delete capability on products that Admin does
 * not have.
 *
 * WHY SOFT DELETE, NOT A HARD DELETE:
 * §26.3 requires "Deleted products remain visible in historical orders."
 * order_items only stores `productId` + `priceSnapshot` (no product-name
 * snapshot — see confirmOrder.ts) and the Admin order-detail screen resolves
 * item names by looking the product back up live via `productId`. A hard
 * delete would make that lookup fail and historical orders would lose their
 * product names. Soft-deleting (status: 'Deleted') keeps the document
 * resolvable for that lookup while removing it from sale/listing everywhere
 * else (POS Home and the admin product list already filter to Active/Inactive
 * only, so 'Deleted' is excluded from both automatically).
 *
 * Mirrors the SuperAdmin-only delete pattern used in expenseAudit.ts.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';
import { validateSuperAdmin } from '../utils/roleValidation';
import { validateRequiredString } from '../utils/validation';
import { createAuditLog } from '../utils/auditLogger';

const db = admin.firestore();

interface DeleteProductRequest {
  productId: string;
  shopId: string;
}

export const deleteProduct = functions.https.onCall(async (data, context) => {
  if (!context.auth) {
    throw new functions.https.HttpsError('unauthenticated', 'User must be authenticated');
  }

  const userId = context.auth.uid;
  const req = data as DeleteProductRequest;
  const productId = validateRequiredString(req?.productId, 'productId');
  const shopId = validateRequiredString(req?.shopId, 'shopId');

  try {
    // Only Super Admin may delete products (Admin can only disable — see
    // product_list_screen.dart's existing Active/Inactive toggle).
    const user = await validateSuperAdmin(userId);

    const productRef = db.collection('products').doc(productId);
    const productSnap = await productRef.get();
    if (!productSnap.exists) {
      throw new functions.https.HttpsError('not-found', 'Product not found');
    }

    const product = productSnap.data()!;
    if (product.shopId !== shopId) {
      throw new functions.https.HttpsError(
        'permission-denied',
        'Product does not belong to this shop'
      );
    }
    if (product.status === 'Deleted') {
      throw new functions.https.HttpsError('failed-precondition', 'Product already deleted');
    }

    await productRef.update({ status: 'Deleted' });

    await createAuditLog(user, 'product_delete', 'product', productId, {
      name: product.name,
      shopId,
      previousStatus: product.status,
    });

    return { success: true, productId };
  } catch (err: any) {
    if (err instanceof functions.https.HttpsError) throw err;
    if (err instanceof Error && err.message.includes('Access denied')) {
      throw new functions.https.HttpsError('permission-denied', err.message);
    }
    throw new functions.https.HttpsError('internal', err?.message ?? 'Failed to delete product');
  }
});
