/**
 * Low-Stock Alerting
 *
 * LOCATION: firebase/functions/src/inventory/lowStockAlerts.ts
 *
 * WHY THIS EXISTS:
 * Requirement in Detail §27.3 / §34.2: "Low-stock alerts SHALL trigger
 * automatically when threshold is reached." Previously the app only exposed
 * a live low-stock *count* on the Admin Dashboard and a client-side filter in
 * the Inventory screen — nothing actually "triggered" (there was no event or
 * persisted record produced when a product crossed the threshold).
 *
 * This Firestore trigger fires on every product write (covers both
 * confirmOrder's stock deduction and adjustStock's manual adjustment — both
 * go through Admin SDK, which still invokes triggers) and, when `stock`
 * crosses from above the threshold down to at-or-below it (or down to zero),
 * writes a persisted alert to `low_stock_alerts`. When stock recovers back
 * above the threshold, any open alert for that product is auto-resolved.
 *
 * Threshold is currently the same fixed default used by the dashboard's
 * low-stock count (ReportsService.defaultLowStockThreshold = 10). If this
 * needs to become shop-configurable later, read it from the shop's
 * `settings` document instead of the constant below.
 */

import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

const db = admin.firestore();

const DEFAULT_LOW_STOCK_THRESHOLD = 10;

export const onProductStockChange = functions.firestore
  .document('products/{productId}')
  .onUpdate(async (change, context) => {
    const productId = context.params.productId;
    const before = change.before.data();
    const after = change.after.data();

    const beforeStock = (before?.stock as number | undefined) ?? 0;
    const afterStock = (after?.stock as number | undefined) ?? 0;

    if (beforeStock === afterStock) {
      return null;
    }

    const shopId = after?.shopId as string | undefined;
    const productName = after?.name as string | undefined;
    if (!shopId) {
      return null;
    }

    const threshold = DEFAULT_LOW_STOCK_THRESHOLD;
    const wasLowOrOut = beforeStock <= threshold;
    const isLowOrOut = afterStock <= threshold;

    try {
      if (!wasLowOrOut && isLowOrOut) {
        // Crossed into low-stock (or out-of-stock) territory — raise an alert.
        const alertType = afterStock <= 0 ? 'out_of_stock' : 'low_stock';
        const alertRef = db.collection('low_stock_alerts').doc();
        await alertRef.set({
          alertId: alertRef.id,
          productId,
          shopId,
          productName: productName ?? 'Unknown product',
          stock: afterStock,
          threshold,
          alertType,
          resolved: false,
          createdAt: admin.firestore.Timestamp.now(),
        });
        console.log(`Low-stock alert raised for ${productId} (${productName}): stock=${afterStock}`);
      } else if (wasLowOrOut && !isLowOrOut) {
        // Recovered above threshold — auto-resolve any open alerts for this product.
        const openAlerts = await db
          .collection('low_stock_alerts')
          .where('productId', '==', productId)
          .where('resolved', '==', false)
          .get();

        if (!openAlerts.empty) {
          const batch = db.batch();
          openAlerts.docs.forEach((doc) => {
            batch.update(doc.ref, {
              resolved: true,
              resolvedAt: admin.firestore.Timestamp.now(),
              resolvedStock: afterStock,
            });
          });
          await batch.commit();
          console.log(`Auto-resolved ${openAlerts.size} low-stock alert(s) for ${productId}`);
        }
      }
    } catch (error: any) {
      console.error(`Error processing low-stock alert for ${productId}:`, error);
    }

    return null;
  });
