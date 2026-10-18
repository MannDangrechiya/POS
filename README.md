# 🍎 Go Retail — Commercial Fruit Retail & Wholesale POS System

<p align="center">
  <img src="https://img.shields.io/badge/Flutter-3.9+-02569B?logo=flutter&logoColor=white" alt="Flutter" />
  <img src="https://img.shields.io/badge/Dart-3.0+-0175C2?logo=dart&logoColor=white" alt="Dart" />
  <img src="https://img.shields.io/badge/Firebase-Blaze-FFCA28?logo=firebase&logoColor=black" alt="Firebase" />
  <img src="https://img.shields.io/badge/Version-v2.0.0-success?style=flat" alt="Version" />
  <img src="https://img.shields.io/badge/Tests-56%20Passed-brightgreen" alt="Tests" />
  <img src="https://img.shields.io/badge/Analyzer-0%20Issues-brightgreen" alt="Analyzer" />
  <img src="https://img.shields.io/badge/Platforms-Android%20%7C%20Windows%20%7C%20Web-blue" alt="Platforms" />
</p>

A high-performance, offline-first, commercial **Point-of-Sale (POS)** terminal engineered for fast-paced fruit retail shops, wholesale mandis, and supermarkets.

Unlike standard mobile catalog apps, **Go Retail** operates as a high-speed counter terminal capable of completing transactions in **under 5 seconds**, connecting directly to physical POS peripherals, surviving network outages, managing cash drawer floats, enforcing Indian GST compliance, and calculating wholesale crate volume discounts.

---

## ⚡ Core Real-World POS Capabilities

### 1. 🖥️ High-Speed Checkout & Ergonomics
* **Widescreen 2-Pane Terminal Layout**: Persistent 65% Catalog on the left with a dedicated 35% `LiveCartPane` on the right for continuous, uninterrupted checkout on tablets and desktop monitors.
* **Hardware Barcode Scanner Wedge**: Native `<80ms` keystroke burst listener that captures USB/Bluetooth handheld barcode scanner input directly into the cart without opening the camera or popping up the software keyboard.
* **Multi-Cart Parking (Hold / Recall Bill)**: Park up to 5 concurrent carts with visual badge indicators when customers need to grab extra items or fetch their wallet.
* **Fast Cash Change Calculator**: Quick currency denomination chips (Exact, ₹100, ₹200, ₹500, ₹2000) with automatic change computation and shortage alerts.
* **Dynamic UPI QR Code**: Real-time generation of `upi://pay` QR codes displayed directly on screen for instant scan-and-pay via GPay, PhonePe, and Paytm.

### 2. 🔌 Direct Hardware Peripherals Integration
* **ESC/POS Thermal Printing**: Pure Dart command generator (`58mm` and `80mm` roll support) outputting receipt headers, line items, taxes, discounts, barcode tickets, and automatic paper cuts (`GS V 1`) over raw TCP network sockets (port 9100) or OS print spoolers.
* **RJ11 Cash Drawer Auto-Kick**: Automatic electrical kick pulse (`ESC p 0`) fired upon cash checkout, refund payouts, and float additions, with manager-PIN override for manual no-sale drawer openings.
* **Digital Weighing Scale Stream**: Continuous ASCII stream parser (RS232/USB/TCP) compatible with NCI, Toledo, CAS, and Essae scale protocols. Includes an interactive physics-damped weight simulator with Zero and Tare controls.
* **Customer Facing Display (CFD)**: Secondary monitor/tablet mode mirroring the live cart, running subtotal, and dynamic payment QR code in real-time.
* **Barcode Label Printing**: Direct thermal printing of adhesive barcode labels (Code 128 & QR Code) for pre-packaged fruit punnets and wholesale crates.

### 3. 📋 Cashier Shift Lifecycle & Cash Auditing
* **Opening Cash Float**: Cashiers must declare starting drawer cash before ring-up, eliminating untracked drawer drift.
* **Mid-Shift Petty Cash In / Out**: Record safe drops, float replenishments, and vendor payouts with mandatory manager PIN authorization.
* **Blind Cash Count (Shift Close)**: Cashiers enter physical cash counts without seeing expected system totals. The system automatically computes discrepancy variance (Balanced, Overage, Shortage) and locks the shift.
* **Thermal Z-Reports**: Prints complete end-of-shift thermal audit receipts containing sales totals, tender breakdowns (Cash, UPI, Card, Credit), cash movements, and cashier/manager signature lines.

### 4. 📊 GST Tax Engine & Discounts
* **GST Breakdown (HSN Compliant)**: Automated 5% GST computation splitting amounts into CGST (2.5%) and SGST (2.5%) displayed on cart, receipts, and Z-Reports.
* **Item & Bill Discounts**: Percentage (`%`) and flat rupee (`₹`) discounts with mandatory Manager PIN thresholds for high markdowns.

### 5. 🍎 Wholesale Tier Pricing & Itemized Returns
* **Volume Tier Pricing**: Automatically switches unit prices as customer volumes cross bulk thresholds (e.g. Retail: ₹120/kg; Wholesale 20+ kg crate: ₹85/kg).
* **Itemized Returns & Restocking**: Partial order returns with disposition categorization:
  * **Restock**: Returns resalable fruits back to inventory logs.
  * **Damaged / Spoilage**: Writes off spoiled fruit directly to waste loss tracking.
* **Thermal Refund Vouchers**: Generates customer refund tickets with auto cash drawer kick.

### 6. 📖 Customer Khata / Credit Ledger (Udhar)
* **Dedicated Credit Limits**: Real-time balance and credit limit enforcement preventing customer over-extension.
* **Credit Settlement Flow**: Accept partial or full payments against outstanding debt, adjust cashier drawer balances, and print thermal payment slips.

### 7. ⚡ Offline Resilience & Auto-Sync
* **Local Offline Queue**: When Wi-Fi/cellular connection drops, transactions persist locally in `SharedPreferences`, cash drawers kick, and thermal receipts print immediately marked `[OFFLINE QUEUED]`.
* **Background Sync Heartbeat**: Every 30 seconds, pending offline orders are safely and idempotently synced to Firebase Cloud Functions once internet connectivity restores.

### 8. 📈 Wholesale Margin & Profitability Analytics
* **COGS Tracking**: Tracks wholesale cost price (`costPrice`) on all products.
* **Real-Time KPI Dashboard**: Gross Margin %, Net Spoilage Loss, Total Khata Receivables, Multi-Register volume breakdown, and Product Margin Leaderboard.

---

## 🏛️ System Architecture

```text
               ┌────────────────────────────────────────────────────────┐
               │              Flutter Client Application                │
               │   (GetX State Management, Responsive 2-Pane Layout)    │
               └───────────────────────────┬────────────────────────────┘
                                           │
         ┌─────────────────────────────────┼────────────────────────────────┐
         │                                 │                                │
         ▼                                 ▼                                ▼
┌─────────────────┐             ┌─────────────────────┐           ┌───────────────────┐
│ Hardware Driver │             │    Offline Engine   │           │   Backend Cloud   │
│   Peripherals   │             │  (Local Order Queue)│           │  Firebase / GCP   │
├─────────────────┤             ├─────────────────────┤           ├───────────────────┤
│ ESC/POS Printer │             │ Local Storage Cache │           │ Cloud Functions   │
│ RJ11 Cash Drawer│             │ Heartbeat Auto-Sync │           │ Cloud Firestore   │
│ RS232 Scale     │             │ Idempotent Replay   │           │ Firebase Storage  │
│ Secondary CFD   │             │ Offline Receipts    │           │ Cloud Auth (RBAC) │
└─────────────────┘             └─────────────────────┘           └───────────────────┘
```

---

## 🔐 Role-Based Access Control (RBAC)

| Capability / Action | Super Admin | Admin | Cashier / Employee | Viewer |
| :--- | :---: | :---: | :---: | :---: |
| **POS Checkout & Billing** | ✅ | ✅ | ✅ | ❌ |
| **Open / Close Shift (Float & Z-Report)** | ✅ | ✅ | ✅ | ❌ |
| **Petty Cash In / Out (Safe Drops)** | ✅ | ✅ | PIN Required | ❌ |
| **High Discounts (>15% or >₹200)** | ✅ | ✅ | PIN Required | ❌ |
| **Itemized Returns & Refunds** | ✅ | ✅ | PIN Required | ❌ |
| **Customer Khata Credit Billing** | ✅ | ✅ | ✅ | ❌ |
| **Customer Credit Settlement** | ✅ | ✅ | ✅ | ❌ |
| **Product & Wholesale Tier Management** | ✅ | ✅ | ❌ | ❌ |
| **Wholesale Margin Analytics** | ✅ | ✅ | ❌ | ✅ |
| **Hardware Settings & Calibration** | ✅ | ✅ | ❌ | ❌ |

---

## 🛠️ Tech Stack

* **Frontend**: Flutter 3.9+ / Dart 3.0+
* **State Management**: GetX (Reactive Controllers & Services)
* **Printing Engine**: Pure Dart ESC/POS Protocol Generator (Zero external C++ dependencies)
* **Backend Runtime**: Google Cloud Functions (Node.js 20 / TypeScript)
* **Database**: Cloud Firestore (Multi-Tenant with Shop-Isolated Security Rules & Composite Indexes)
* **Storage**: Firebase Cloud Storage (Product images & PDF receipts)
* **Authentication**: Firebase Authentication with custom claims & audit logging

---

## 🚀 Getting Started

### Prerequisites
- [Flutter SDK](https://docs.flutter.dev/get-started/install) (3.9.2 or higher)
- [Node.js](https://nodejs.org/) (v20+) & [Firebase CLI](https://firebase.google.com/docs/cli)
- Android Studio / VS Code with Flutter extension

### 1. Clone & Install Dependencies
```bash
git clone https://github.com/MannDangrechiya/POS.git
cd POS
flutter pub get
```

### 2. Configure Firebase Backend
```bash
cd firebase
npm install
npm run build

# Deploy Security Rules, Indexes, Storage, and Cloud Functions
firebase deploy
```

### 3. Run the POS Terminal
```bash
# Run on connected Android POS tablet or phone
flutter run -d android

# Run on Windows desktop POS terminal
flutter run -d windows
```

### 4. Build Production Binaries
```bash
# Build Android Production Release APK
flutter build apk --release

# Build Android App Bundle (Google Play Store)
flutter build appbundle --release

# Build Windows Desktop Production Executable
flutter build windows --release
```

---

## 🧪 Automated Testing & Verification

The project includes unit and integration tests covering the entire POS transaction lifecycle:

```bash
flutter test
```

### Test Coverage Highlights:
* `test/cart_hold_test.dart`: Multi-cart park and recall state isolation.
* `test/hardware_peripherals_test.dart`: Raw ESC/POS command generation, barcode 128 / QR commands, scale stream parser, drawer pulse.
* `test/shift_and_tax_test.dart`: Cash drawer balancing, blind count variance, GST 5% breakdown, thermal Z-Report ticket structure.
* `test/wholesale_and_returns_test.dart`: Dynamic wholesale tiered pricing, partial return disposition (restock vs damage write-off), Khata credit ledger, and offline queue serialization.
* `test/phase5_production_test.dart`: Multi-register terminal persistence, barcode label generator, wholesale COGS and margin formulas.

---

## 📄 License
This repository is private and proprietary. Developed for commercial retail and wholesale operations.
