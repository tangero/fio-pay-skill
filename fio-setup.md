# FIO Bank Payment Integration Setup

You are setting up a complete FIO Bank payment integration in the current project. Follow these steps precisely.

## Step 1: Analyze the current project

Read `package.json` (or equivalent) and determine:

1. **Backend framework**: Cloudflare Pages Functions / Next.js / Express / Hono / other
2. **Frontend framework**: React / Vue / Svelte / vanilla
3. **UI library**: shadcn/ui / MUI / Chakra / Ant Design / none
4. **Test framework**: Vitest / Jest / none
5. **Storage**: Cloudflare KV / SQLite / Prisma / Redis / filesystem
6. **Directory structure**: where API routes live, where components live, where tests live

Report your findings to the user before generating code. Ask if they want:
- **Payment verification only** (basic)
- **Payment + donations** (full)

## Step 2: Generate files

Adapt the reference implementation below to the detected stack. Key adaptations:

### Backend adaptation rules

| Stack | API handler signature | Storage calls |
|-------|----------------------|---------------|
| **Cloudflare Pages Functions** | `export const onRequestPost: PagesFunction<Env>` | `env.KV_NAMESPACE.get/put` |
| **Next.js App Router** | `export async function POST(request: Request)` | Use your DB/KV adapter |
| **Next.js Pages Router** | `export default async function handler(req, res)` | Use your DB/KV adapter |
| **Express** | `router.post('/path', async (req, res) => {})` | Use your DB/storage adapter |
| **Hono** | `app.post('/path', async (c) => {})` | Use your DB/storage adapter |

### Frontend adaptation rules

| UI Library | Component style |
|------------|----------------|
| **shadcn/ui** | Use `Card`, `Button`, `cn()` from `@/components/ui/*` |
| **MUI** | Use `Card`, `Button`, `Typography` from `@mui/material` |
| **Plain React** | Use basic HTML elements with inline styles or CSS modules |
| **Vanilla** | Generate plain HTML + JS (no JSX) |

### Storage adaptation rules

For non-KV storage, replace `env.WORKSHOP_DATA.get(key, 'json')` / `env.WORKSHOP_DATA.put(key, JSON.stringify(data))` with the project's storage pattern. The keys to store:
- `payment:{identifier}` — PaymentRecord JSON
- `donation:{eventId}` — DonationRecord JSON
- `fio:last_check` — timestamp string for rate limiting

---

## Reference Implementation

### File 1: Payment Utilities (pure functions, no framework dependencies)

**Target path:** `{api-dir}/fio/payment-utils.ts` (or `_payment-utils.ts` for Cloudflare)

```typescript
// Pure utility functions for FIO Bank payment integration
// No framework dependencies — works with any backend

// ============================================================
// Types
// ============================================================

/** FIO Bank API transaction structure (JSON format v1.9) */
export interface FioTransaction {
  column0: { value: string; name: string; id: number } | null;   // Date
  column1: { value: number; name: string; id: number } | null;   // Volume
  column2: { value: string; name: string; id: number } | null;   // Counter account
  column5: { value: string; name: string; id: number } | null;   // Variable symbol
  column10: { value: string; name: string; id: number } | null;  // Counter account name
  column14: { value: string; name: string; id: number } | null;  // Currency
  column16: { value: string; name: string; id: number } | null;  // Message for recipient
  column22: { value: number; name: string; id: number } | null;  // Transaction ID
}

/** FIO API JSON response structure */
export interface FioApiResponse {
  accountStatement: {
    info: {
      accountId: string;
      bankId: string;
      currency: string;
      iban: string;
      bic: string;
      openingBalance: number;
      closingBalance: number;
      dateStart: string;
      dateEnd: string;
      idFrom: number | null;
      idTo: number | null;
      idLastDownload: number | null;
    };
    transactionList: {
      transaction: FioTransaction[];
    } | null;
  };
}

/** Payment record stored in KV/DB */
export interface PaymentRecord {
  status: 'pending' | 'paid';
  evaluationsUsed: number;
  evaluationsLimit: number;
  variableSymbol: string;
  fioTransactionId?: number;
  paidAt?: string;
  amount?: number;
  email: string;
  purchases: Array<{
    fioTransactionId: number;
    paidAt: string;
    amount: number;
    evaluationsAdded: number;
  }>;
}

/** Payment match result */
export interface PaymentMatchResult {
  found: boolean;
  transaction?: {
    id: number;
    date: string;
    amount: number;
    senderName: string | null;
  };
}

/** Donation record stored in KV/DB */
export interface DonationRecord {
  variableSymbol: string;
  eventId: string;
  totalAmount: number;
  donationCount: number;
  donations: Array<{
    fioTransactionId: number;
    amount: number;
    paidAt: string;
  }>;
}

// ============================================================
// Functions
// ============================================================

/** Generates an 8-digit random variable symbol (10000000–99999999) */
export function generateVariableSymbol(): string {
  return String(Math.floor(10000000 + Math.random() * 90000000));
}

/** Validates variable symbol format */
export function isValidVariableSymbol(vs: string): boolean {
  return /^\d{8}$/.test(vs) && parseInt(vs) >= 10000000;
}

/**
 * Finds a matching incoming payment in FIO transactions.
 * Matches by: VS (no leading zeros) + exact amount + CZK + positive volume.
 * Ignores transactions with IDs in excludeTransactionIds (already processed).
 */
export function matchPayment(
  transactions: FioTransaction[],
  expectedVS: string,
  expectedAmount: number,
  excludeTransactionIds: Set<number> = new Set()
): PaymentMatchResult {
  const normalizedExpectedVS = expectedVS.replace(/^0+/, '');

  for (const tx of transactions) {
    const amount = tx.column1?.value;
    const vs = tx.column5?.value?.replace(/^0+/, '') || '';
    const currency = tx.column14?.value;
    const txId = tx.column22?.value;

    if (!amount || amount <= 0) continue;
    if (txId == null) continue;
    if (excludeTransactionIds.has(txId)) continue;

    if (vs === normalizedExpectedVS && amount === expectedAmount && currency === 'CZK') {
      return {
        found: true,
        transaction: {
          id: txId,
          date: tx.column0?.value || new Date().toISOString(),
          amount,
          senderName: tx.column10?.value || null,
        },
      };
    }
  }

  return { found: false };
}

/**
 * Checks whether the user can perform a paid action.
 * Returns result with reason for denial.
 */
export function checkEvaluationAccess(payment: PaymentRecord | null): {
  allowed: boolean;
  reason?: 'payment_required' | 'limit_reached';
  evaluationsUsed?: number;
  evaluationsLimit?: number;
} {
  if (!payment || payment.status !== 'paid') {
    return { allowed: false, reason: 'payment_required' };
  }

  if (payment.evaluationsUsed >= payment.evaluationsLimit) {
    return {
      allowed: false,
      reason: 'limit_reached',
      evaluationsUsed: payment.evaluationsUsed,
      evaluationsLimit: payment.evaluationsLimit,
    };
  }

  return {
    allowed: true,
    evaluationsUsed: payment.evaluationsUsed,
    evaluationsLimit: payment.evaluationsLimit,
  };
}

/** Creates or extends a payment record after successful match */
export function createOrUpdatePaymentRecord(
  existing: PaymentRecord | null,
  matchedTx: NonNullable<PaymentMatchResult['transaction']>,
  email: string,
  variableSymbol: string,
  evaluationsToAdd: number = 30
): PaymentRecord {
  const record: PaymentRecord = existing || {
    status: 'paid',
    evaluationsUsed: 0,
    evaluationsLimit: 0,
    variableSymbol,
    email,
    purchases: [],
  };

  record.status = 'paid';
  record.evaluationsLimit += evaluationsToAdd;
  record.fioTransactionId = matchedTx.id;
  record.paidAt = matchedTx.date;
  record.amount = matchedTx.amount;
  record.purchases.push({
    fioTransactionId: matchedTx.id,
    paidAt: matchedTx.date,
    amount: matchedTx.amount,
    evaluationsAdded: evaluationsToAdd,
  });

  return record;
}

/** Returns date range for FIO API query (last N days) */
export function getFioDateRange(daysBack: number = 7): { dateFrom: string; dateTo: string } {
  const now = new Date();
  const from = new Date(now.getTime() - daysBack * 86400000);
  return {
    dateFrom: from.toISOString().split('T')[0],
    dateTo: now.toISOString().split('T')[0],
  };
}

/** Converts event date to 6-digit variable symbol (YYMMDD) */
export function eventDateToVS(dateString: string): string {
  const d = new Date(dateString);
  const yy = String(d.getFullYear()).slice(-2);
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yy}${mm}${dd}`;
}

/**
 * Finds ALL matching incoming payments (for donations — any amount).
 * Matches by: VS (no leading zeros) + CZK + positive volume.
 */
export function matchDonations(
  transactions: FioTransaction[],
  expectedVS: string,
  excludeTransactionIds: Set<number> = new Set()
): Array<{ id: number; date: string; amount: number; senderName: string | null }> {
  const normalizedExpectedVS = expectedVS.replace(/^0+/, '');
  const matched: Array<{ id: number; date: string; amount: number; senderName: string | null }> = [];

  for (const tx of transactions) {
    const amount = tx.column1?.value;
    const vs = tx.column5?.value?.replace(/^0+/, '') || '';
    const currency = tx.column14?.value;
    const txId = tx.column22?.value;

    if (!amount || amount <= 0) continue;
    if (txId == null) continue;
    if (excludeTransactionIds.has(txId)) continue;

    if (vs === normalizedExpectedVS && currency === 'CZK') {
      matched.push({
        id: txId,
        date: tx.column0?.value || new Date().toISOString(),
        amount,
        senderName: tx.column10?.value || null,
      });
    }
  }

  return matched;
}

/** Generates Czech QR payment string (SPD standard) */
export function generateSPDString(
  iban: string,
  amount: number,
  vs: string,
  message: string = 'Platba'
): string {
  return `SPD*1.0*ACC:${iban}*AM:${amount.toFixed(2)}*CC:CZK*X-VS:${vs}*MSG:${message}`;
}
```

---

### File 2: Verify Payment Endpoint

**Target path:** `{api-dir}/fio/verify-payment.ts`

This is the **Cloudflare Pages Functions** version. Adapt the handler signature, request parsing, and storage calls to the detected stack.

```typescript
// POST /api/fio/verify-payment
// On-demand payment verification via FIO Bank API

import {
  matchPayment,
  createOrUpdatePaymentRecord,
  getFioDateRange,
  FioApiResponse,
  PaymentRecord,
} from './payment-utils';

// ADAPT: Import your auth/session helper
// import { getSession } from '../auth';

// ADAPT: Define your env/config interface
interface Env {
  WORKSHOP_DATA: KVNamespace;  // ADAPT: your storage
  FIO_API_TOKEN: string;
}

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
};

// ADAPT: Import from config/payment.ts
const EXPECTED_AMOUNT = 100;            // CZK
const EVALUATIONS_PER_PURCHASE = 30;
const FIO_RATE_LIMIT_MS = 35000;        // 35s (30s FIO limit + buffer)

// ADAPT: Change handler signature to match your framework
export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  try {
    // 1. Authentication — ADAPT to your auth system
    // const session = await getSession(request, env.WORKSHOP_DATA);
    // if (!session) return new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401, headers: CORS_HEADERS });

    const body = await request.json() as { identifier?: string; variableSymbol?: string; email?: string };
    const { identifier, variableSymbol, email } = body;

    if (!identifier || !variableSymbol) {
      return new Response(
        JSON.stringify({ error: 'Missing identifier or variableSymbol' }),
        { status: 400, headers: CORS_HEADERS }
      );
    }

    // 2. Check existing payment
    const paymentKey = `payment:${identifier}`;
    // ADAPT: Replace with your storage read
    const existingPayment = await env.WORKSHOP_DATA.get(paymentKey, 'json') as PaymentRecord | null;

    // If paid and limit not exhausted, return info
    if (existingPayment?.status === 'paid' &&
        existingPayment.evaluationsUsed < existingPayment.evaluationsLimit) {
      return new Response(JSON.stringify({
        success: true,
        alreadyPaid: true,
        evaluationsUsed: existingPayment.evaluationsUsed,
        evaluationsLimit: existingPayment.evaluationsLimit,
      }), { headers: CORS_HEADERS });
    }

    // 3. Rate limit: max 1 FIO API call per 35s (global)
    // ADAPT: Replace with your storage read
    const lastCheck = await env.WORKSHOP_DATA.get('fio:last_check');
    const now = Date.now();
    if (lastCheck && now - parseInt(lastCheck) < FIO_RATE_LIMIT_MS) {
      const waitSec = Math.ceil((FIO_RATE_LIMIT_MS - (now - parseInt(lastCheck))) / 1000);
      return new Response(JSON.stringify({
        error: 'rate_limit',
        message: `Payment verification available once per 30s. Try again in ${waitSec}s.`,
      }), { status: 429, headers: CORS_HEADERS });
    }

    // 4. FIO API token check
    if (!env.FIO_API_TOKEN) {
      return new Response(JSON.stringify({
        error: 'Payment gateway not configured.',
      }), { status: 503, headers: CORS_HEADERS });
    }

    // 5. Call FIO API — transactions for last 7 days
    const { dateFrom, dateTo } = getFioDateRange(7);
    const fioUrl = `https://fioapi.fio.cz/v1/rest/periods/${env.FIO_API_TOKEN}/${dateFrom}/${dateTo}/transactions.json`;

    // Write timestamp BEFORE the call (race condition protection)
    // ADAPT: Replace with your storage write
    await env.WORKSHOP_DATA.put('fio:last_check', String(now));

    const fioResponse = await fetch(fioUrl);

    if (fioResponse.status === 409) {
      return new Response(JSON.stringify({
        error: 'rate_limit',
        message: 'Bank API is temporarily overloaded. Try again in 30 seconds.',
      }), { status: 429, headers: CORS_HEADERS });
    }

    if (!fioResponse.ok) {
      console.error('FIO API error:', fioResponse.status, await fioResponse.text());
      return new Response(JSON.stringify({
        error: 'fio_error',
        message: 'Could not verify payment. Please try again later.',
      }), { status: 502, headers: CORS_HEADERS });
    }

    const fioData = await fioResponse.json() as FioApiResponse;

    // 6. Match payment
    const transactions = fioData.accountStatement?.transactionList?.transaction || [];

    const processedIds = new Set(
      (existingPayment?.purchases || []).map(p => p.fioTransactionId)
    );

    const match = matchPayment(transactions, variableSymbol, EXPECTED_AMOUNT, processedIds);

    if (!match.found || !match.transaction) {
      return new Response(JSON.stringify({
        success: false,
        message: 'Payment not received yet. Bank transfers may take up to a few hours. Please try again later.',
      }), { headers: CORS_HEADERS });
    }

    // 7. Payment found — activate/extend package
    const updatedPayment = createOrUpdatePaymentRecord(
      existingPayment,
      match.transaction,
      email || 'unknown',
      variableSymbol,
      EVALUATIONS_PER_PURCHASE
    );

    // ADAPT: Replace with your storage write
    await env.WORKSHOP_DATA.put(paymentKey, JSON.stringify(updatedPayment));

    return new Response(JSON.stringify({
      success: true,
      evaluationsUsed: updatedPayment.evaluationsUsed,
      evaluationsLimit: updatedPayment.evaluationsLimit,
    }), { headers: CORS_HEADERS });

  } catch (error: unknown) {
    console.error('verify-payment error:', error);
    return new Response(JSON.stringify({
      error: 'Internal server error',
    }), { status: 500, headers: CORS_HEADERS });
  }
};

// CORS preflight — ADAPT or remove if your framework handles CORS
export const onRequestOptions: PagesFunction = async () => {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
};
```

---

### File 3: Verify Donation Endpoint (optional)

**Target path:** `{api-dir}/fio/verify-donation.ts`

```typescript
// POST /api/fio/verify-donation
// Verifies voluntary donations via FIO Bank API

import {
  matchDonations,
  getFioDateRange,
  FioApiResponse,
  DonationRecord,
} from './payment-utils';

// ADAPT: Define your env/config interface
interface Env {
  WORKSHOP_DATA: KVNamespace;
  FIO_API_TOKEN: string;
}

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
};

const FIO_RATE_LIMIT_MS = 35000;

// ADAPT: Change handler signature
export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  try {
    const body = await request.json() as { eventId?: string; variableSymbol?: string };
    const { eventId, variableSymbol } = body;

    if (!eventId || !variableSymbol) {
      return new Response(
        JSON.stringify({ error: 'Missing eventId or variableSymbol' }),
        { status: 400, headers: CORS_HEADERS }
      );
    }

    // Rate limit
    const lastCheck = await env.WORKSHOP_DATA.get('fio:last_check');
    const now = Date.now();
    if (lastCheck && now - parseInt(lastCheck) < FIO_RATE_LIMIT_MS) {
      const waitSec = Math.ceil((FIO_RATE_LIMIT_MS - (now - parseInt(lastCheck))) / 1000);
      return new Response(JSON.stringify({
        error: 'rate_limit',
        message: `Verification available once per 30s. Try again in ${waitSec}s.`,
      }), { status: 429, headers: CORS_HEADERS });
    }

    if (!env.FIO_API_TOKEN) {
      return new Response(JSON.stringify({
        error: 'Payment gateway not configured.',
      }), { status: 503, headers: CORS_HEADERS });
    }

    // Load existing donation record
    const donationKey = `donation:${eventId}`;
    const existing = await env.WORKSHOP_DATA.get(donationKey, 'json') as DonationRecord | null;

    // Call FIO API — last 14 days
    const { dateFrom, dateTo } = getFioDateRange(14);
    const fioUrl = `https://fioapi.fio.cz/v1/rest/periods/${env.FIO_API_TOKEN}/${dateFrom}/${dateTo}/transactions.json`;

    await env.WORKSHOP_DATA.put('fio:last_check', String(now));

    const fioResponse = await fetch(fioUrl);

    if (fioResponse.status === 409) {
      return new Response(JSON.stringify({
        error: 'rate_limit',
        message: 'Bank API temporarily overloaded. Try again in 30 seconds.',
      }), { status: 429, headers: CORS_HEADERS });
    }

    if (!fioResponse.ok) {
      console.error('FIO API error:', fioResponse.status, await fioResponse.text());
      return new Response(JSON.stringify({
        error: 'fio_error',
        message: 'Could not verify donation. Please try again later.',
      }), { status: 502, headers: CORS_HEADERS });
    }

    const fioData = await fioResponse.json() as FioApiResponse;
    const transactions = fioData.accountStatement?.transactionList?.transaction || [];

    const processedIds = new Set(
      (existing?.donations || []).map(d => d.fioTransactionId)
    );

    const newDonations = matchDonations(transactions, variableSymbol, processedIds);

    // Update record
    const record: DonationRecord = existing || {
      variableSymbol,
      eventId,
      totalAmount: 0,
      donationCount: 0,
      donations: [],
    };

    let newlyFound = false;
    let latestAmount = 0;

    for (const donation of newDonations) {
      record.donations.push({
        fioTransactionId: donation.id,
        amount: donation.amount,
        paidAt: donation.date,
      });
      record.totalAmount += donation.amount;
      record.donationCount += 1;
      latestAmount = donation.amount;
      newlyFound = true;
    }

    if (newlyFound) {
      await env.WORKSHOP_DATA.put(donationKey, JSON.stringify(record));
    }

    return new Response(JSON.stringify({
      found: newlyFound,
      totalAmount: record.totalAmount,
      donationCount: record.donationCount,
      latestAmount: newlyFound ? latestAmount : undefined,
    }), { headers: CORS_HEADERS });

  } catch (error: unknown) {
    console.error('verify-donation error:', error);
    return new Response(JSON.stringify({
      error: 'Internal server error',
    }), { status: 500, headers: CORS_HEADERS });
  }
};

export const onRequestOptions: PagesFunction = async () => {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'POST, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
};
```

---

### File 4: Donations Admin Endpoint (optional)

**Target path:** `{api-dir}/fio/donations.ts`

```typescript
// GET /api/fio/donations?eventId=xxx or ?eventIds=id1,id2,id3
// Admin endpoint to view donation records

import { DonationRecord } from './payment-utils';

// ADAPT: Define your env/config interface
interface Env {
  WORKSHOP_DATA: KVNamespace;
}

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
};

// ADAPT: Change handler signature
export const onRequestGet: PagesFunction<Env> = async (context) => {
  const { env } = context;
  const url = new URL(context.request.url);

  const eventId = url.searchParams.get('eventId');
  const eventIds = url.searchParams.get('eventIds');

  try {
    if (eventId) {
      const record = await env.WORKSHOP_DATA.get(`donation:${eventId}`, 'json') as DonationRecord | null;
      return new Response(JSON.stringify({
        totalAmount: record?.totalAmount ?? 0,
        donationCount: record?.donationCount ?? 0,
        donations: record?.donations ?? [],
      }), { headers: CORS_HEADERS });
    }

    if (eventIds) {
      const ids = eventIds.split(',').map(id => id.trim()).filter(Boolean);
      const results: Record<string, { totalAmount: number; donationCount: number }> = {};

      await Promise.all(ids.map(async (id) => {
        const record = await env.WORKSHOP_DATA.get(`donation:${id}`, 'json') as DonationRecord | null;
        results[id] = {
          totalAmount: record?.totalAmount ?? 0,
          donationCount: record?.donationCount ?? 0,
        };
      }));

      return new Response(JSON.stringify(results), { headers: CORS_HEADERS });
    }

    return new Response(JSON.stringify({ error: 'Missing eventId or eventIds parameter' }), {
      status: 400,
      headers: CORS_HEADERS,
    });
  } catch (error: unknown) {
    console.error('donations GET error:', error);
    return new Response(JSON.stringify({ error: 'Internal server error' }), {
      status: 500,
      headers: CORS_HEADERS,
    });
  }
};

export const onRequestOptions: PagesFunction = async () => {
  return new Response(null, {
    status: 204,
    headers: {
      'Access-Control-Allow-Origin': '*',
      'Access-Control-Allow-Methods': 'GET, OPTIONS',
      'Access-Control-Allow-Headers': 'Content-Type',
    },
  });
};
```

---

### File 5: Mock Endpoint (for local development)

**Target path:** `{api-dir}/fio/mock.ts`

```typescript
// GET /api/fio/mock?vs=XXXXXXXX&amount=100
// Mock FIO API endpoint for local development
// Simulates FIO API response with an incoming payment

// ADAPT: Define your env/config interface
interface Env {
  WORKSHOP_DATA: KVNamespace;
}

// ADAPT: Change handler signature
export const onRequestGet: PagesFunction<Env> = async (context) => {
  // Block in production — mock is for local dev only
  const url = new URL(context.request.url);
  if (url.hostname !== 'localhost' && !url.hostname.includes('127.0.0.1') && !url.hostname.includes('.local')) {
    return new Response('Not found', { status: 404 });
  }

  const vs = url.searchParams.get('vs') || '00000000';
  const amount = parseFloat(url.searchParams.get('amount') || '100');
  const empty = url.searchParams.get('empty') === 'true';

  const headers = {
    'Content-Type': 'application/json',
    'Access-Control-Allow-Origin': '*',
  };

  // Simulate FIO rate limit (5s cooldown for mock)
  const lastCheck = await context.env.WORKSHOP_DATA.get('fio:mock_last_check');
  const now = Date.now();
  if (lastCheck && now - parseInt(lastCheck) < 5000) {
    return new Response('', { status: 409 });
  }
  await context.env.WORKSHOP_DATA.put('fio:mock_last_check', String(now));

  // Empty response (simulate: payment not received)
  if (empty) {
    return new Response(JSON.stringify({
      accountStatement: {
        info: {
          accountId: '0000000000',
          bankId: '2010',
          currency: 'CZK',
          iban: 'CZ0000000000000000000000',
          bic: 'FIOBCZPPXXX',
          openingBalance: 10000,
          closingBalance: 10000,
          dateStart: new Date(Date.now() - 7 * 86400000).toISOString().split('T')[0] + '+01:00',
          dateEnd: new Date().toISOString().split('T')[0] + '+01:00',
          idFrom: null, idTo: null, idLastDownload: null,
        },
        transactionList: null,
      },
    }), { headers });
  }

  // Response with payment
  const txId = Math.floor(10000000000 + Math.random() * 90000000000);
  const today = new Date().toISOString().split('T')[0];

  return new Response(JSON.stringify({
    accountStatement: {
      info: {
        accountId: '0000000000',
        bankId: '2010',
        currency: 'CZK',
        iban: 'CZ0000000000000000000000',
        bic: 'FIOBCZPPXXX',
        openingBalance: 10000,
        closingBalance: 10000 + amount,
        dateStart: new Date(Date.now() - 7 * 86400000).toISOString().split('T')[0] + '+01:00',
        dateEnd: today + '+01:00',
        idFrom: txId, idTo: txId, idLastDownload: txId,
      },
      transactionList: {
        transaction: [{
          column22: { value: txId, name: 'ID pohybu', id: 22 },
          column0: { value: today + '+01:00', name: 'Datum', id: 0 },
          column1: { value: amount, name: 'Objem', id: 1 },
          column14: { value: 'CZK', name: 'Mena', id: 14 },
          column2: { value: '1234567890', name: 'Protiucet', id: 2 },
          column5: { value: vs, name: 'VS', id: 5 },
          column10: { value: 'Test Sender', name: 'Nazev protiuctu', id: 10 },
          column16: { value: 'Test payment', name: 'Zprava pro prijemce', id: 16 },
        }],
      },
    },
  }), { headers });
};
```

---

### File 6: Payment Configuration

**Target path:** `{src}/config/payment.ts`

```typescript
// Payment configuration — UPDATE THESE VALUES for your project

/** Your FIO Bank IBAN */
export const PAYMENT_IBAN = 'CZ00000000000000000000'; // TODO: Replace with your IBAN

/** Account number for display */
export const PAYMENT_ACCOUNT = '0000000000 / 2010'; // TODO: Replace with your account

/** Payment amount in CZK */
export const PAYMENT_AMOUNT = 100; // TODO: Set your price

/** Number of uses per purchase (for metered access) */
export const EVALUATIONS_PER_PURCHASE = 30;

/** Message in QR payment */
export const PAYMENT_MESSAGE = 'Payment'; // TODO: Customize

// --- Donations (optional) ---

/** Preset donation amounts */
export const DONATION_AMOUNTS = [50, 100, 200] as const;

/** Default donation amount */
export const DONATION_DEFAULT_AMOUNT = 100;

/** Donation payment message */
export const DONATION_MESSAGE = 'Donation';
```

---

### File 7: QR Payment React Component

**Target path:** `{src}/components/PaymentQRCode.tsx`

Requires: `npm install qrcode.react`

```tsx
import React, { useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
// ADAPT: Import your UI components
// shadcn/ui example:
// import { Card, CardContent, CardHeader, CardTitle } from '@/components/ui/card';
// import { Button } from '@/components/ui/button';

import { PAYMENT_IBAN, PAYMENT_ACCOUNT } from '@/config/payment';

interface PaymentQRCodeProps {
  amount: number;
  variableSymbol: string;
  message?: string;
  recipientName?: string;
}

const generateSPAYD = (
  iban: string,
  amount: number,
  variableSymbol: string,
  message?: string,
  recipientName?: string
): string => {
  const parts: string[] = [
    'SPD*1.0',
    `ACC:${iban}`,
    `AM:${amount.toFixed(2)}`,
    'CC:CZK',
  ];
  if (variableSymbol) parts.push(`X-VS:${variableSymbol}`);
  if (message) parts.push(`MSG:${message.slice(0, 60).replace(/[*]/g, '')}`);
  if (recipientName) parts.push(`RN:${recipientName}`);
  return parts.join('*');
};

const PaymentQRCode: React.FC<PaymentQRCodeProps> = ({
  amount,
  variableSymbol,
  message,
  recipientName,
}) => {
  const [copied, setCopied] = useState<string | null>(null);

  const spaydString = generateSPAYD(PAYMENT_IBAN, amount, variableSymbol, message, recipientName);

  const copyToClipboard = async (text: string, field: string) => {
    try {
      await navigator.clipboard.writeText(text);
      setCopied(field);
      setTimeout(() => setCopied(null), 2000);
    } catch (err) {
      console.error('Failed to copy:', err);
    }
  };

  const paymentDetails = [
    { label: 'Account', value: PAYMENT_ACCOUNT, field: 'account' },
    { label: 'Amount', value: `${amount.toLocaleString('cs-CZ')} CZK`, field: 'amount' },
    { label: 'Variable symbol', value: variableSymbol, field: 'vs' },
  ];

  return (
    <div style={{ maxWidth: 400, margin: '0 auto', padding: 24, border: '1px solid #e5e7eb', borderRadius: 12 }}>
      <h3 style={{ textAlign: 'center', marginBottom: 16 }}>Bank Transfer Payment</h3>

      {/* QR code */}
      <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 16 }}>
        <div style={{ padding: 16, background: '#fff', borderRadius: 8, boxShadow: 'inset 0 1px 3px rgba(0,0,0,0.1)' }}>
          <QRCodeSVG value={spaydString} size={200} level="M" includeMargin={true} />
        </div>
      </div>

      <p style={{ textAlign: 'center', color: '#6b7280', fontSize: 14, marginBottom: 16 }}>
        Scan QR code in your banking app
      </p>

      {/* Payment details */}
      <div style={{ borderTop: '1px solid #e5e7eb', paddingTop: 16 }}>
        <p style={{ textAlign: 'center', color: '#374151', fontSize: 14, fontWeight: 500, marginBottom: 12 }}>
          Or enter details manually:
        </p>
        {paymentDetails.map((detail) => (
          <div
            key={detail.field}
            style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center', padding: 8, background: '#f9fafb', borderRadius: 8, marginBottom: 8 }}
          >
            <div>
              <p style={{ fontSize: 12, color: '#9ca3af', margin: 0 }}>{detail.label}</p>
              <p style={{ fontFamily: 'monospace', fontWeight: 600, margin: 0 }}>{detail.value}</p>
            </div>
            <button
              onClick={() => copyToClipboard(detail.field === 'amount' ? amount.toString() : detail.value, detail.field)}
              style={{ padding: '4px 8px', border: '1px solid #e5e7eb', borderRadius: 4, background: 'transparent', cursor: 'pointer' }}
            >
              {copied === detail.field ? '✓' : 'Copy'}
            </button>
          </div>
        ))}
      </div>

      {/* Warning */}
      <div style={{ padding: 12, background: '#fefce8', border: '1px solid #fde68a', borderRadius: 8, marginTop: 16 }}>
        <p style={{ fontSize: 14, color: '#854d0e', margin: 0 }}>
          <strong>Important:</strong> Use the variable symbol shown above for correct payment matching.
        </p>
      </div>
    </div>
  );
};

export default PaymentQRCode;
```

---

### File 8: Unit Tests

**Target path:** `{test-dir}/payment-utils.test.ts`

```typescript
// ADAPT: Import path to match your project structure
import { describe, it, expect } from 'vitest'; // or 'jest'
import {
  generateVariableSymbol,
  isValidVariableSymbol,
  matchPayment,
  matchDonations,
  eventDateToVS,
  checkEvaluationAccess,
  createOrUpdatePaymentRecord,
  getFioDateRange,
  generateSPDString,
  FioTransaction,
  PaymentRecord,
} from '../path/to/payment-utils'; // ADAPT: correct import path

// Helper: create a FIO transaction with given params
function makeTx(overrides: {
  id?: number;
  amount?: number;
  vs?: string;
  currency?: string;
  date?: string;
  senderName?: string;
} = {}): FioTransaction {
  return {
    column0: { value: overrides.date ?? '2026-02-06+01:00', name: 'Datum', id: 0 },
    column1: { value: overrides.amount ?? 100, name: 'Objem', id: 1 },
    column2: { value: '1234567890', name: 'Protiucet', id: 2 },
    column5: overrides.vs !== undefined
      ? { value: overrides.vs, name: 'VS', id: 5 }
      : null,
    column10: overrides.senderName
      ? { value: overrides.senderName, name: 'Nazev protiuctu', id: 10 }
      : null,
    column14: { value: overrides.currency ?? 'CZK', name: 'Mena', id: 14 },
    column16: null,
    column22: { value: overrides.id ?? 99999999, name: 'ID pohybu', id: 22 },
  };
}

function makePayment(overrides: Partial<PaymentRecord> = {}): PaymentRecord {
  return {
    status: 'paid',
    evaluationsUsed: 0,
    evaluationsLimit: 30,
    variableSymbol: '38472916',
    email: 'test@example.com',
    purchases: [],
    ...overrides,
  };
}

// ============================================================
// generateVariableSymbol
// ============================================================
describe('generateVariableSymbol', () => {
  it('returns 8-digit string', () => {
    const vs = generateVariableSymbol();
    expect(vs).toMatch(/^\d{8}$/);
  });

  it('returns number >= 10000000', () => {
    for (let i = 0; i < 100; i++) {
      const vs = generateVariableSymbol();
      expect(parseInt(vs)).toBeGreaterThanOrEqual(10000000);
      expect(parseInt(vs)).toBeLessThan(100000000);
    }
  });

  it('generates varying values', () => {
    const values = new Set<string>();
    for (let i = 0; i < 20; i++) values.add(generateVariableSymbol());
    expect(values.size).toBeGreaterThan(1);
  });
});

// ============================================================
// isValidVariableSymbol
// ============================================================
describe('isValidVariableSymbol', () => {
  it('accepts valid 8-digit VS', () => {
    expect(isValidVariableSymbol('38472916')).toBe(true);
    expect(isValidVariableSymbol('10000000')).toBe(true);
    expect(isValidVariableSymbol('99999999')).toBe(true);
  });

  it('rejects too short VS', () => {
    expect(isValidVariableSymbol('1234567')).toBe(false);
    expect(isValidVariableSymbol('')).toBe(false);
  });

  it('rejects too long VS', () => {
    expect(isValidVariableSymbol('123456789')).toBe(false);
  });

  it('rejects non-numeric VS', () => {
    expect(isValidVariableSymbol('1234567a')).toBe(false);
  });

  it('rejects VS under 10000000', () => {
    expect(isValidVariableSymbol('00000001')).toBe(false);
    expect(isValidVariableSymbol('09999999')).toBe(false);
  });
});

// ============================================================
// matchPayment
// ============================================================
describe('matchPayment', () => {
  it('finds matching transaction with exact VS and amount', () => {
    const transactions = [makeTx({ id: 1001, vs: '38472916', amount: 100 })];
    const result = matchPayment(transactions, '38472916', 100);
    expect(result.found).toBe(true);
    expect(result.transaction?.id).toBe(1001);
  });

  it('matches VS without leading zeros', () => {
    const transactions = [makeTx({ id: 1002, vs: '0038472916', amount: 100 })];
    const result = matchPayment(transactions, '38472916', 100);
    expect(result.found).toBe(true);
  });

  it('rejects wrong VS', () => {
    const transactions = [makeTx({ vs: '99999999', amount: 100 })];
    expect(matchPayment(transactions, '38472916', 100).found).toBe(false);
  });

  it('rejects wrong amount', () => {
    const transactions = [makeTx({ vs: '38472916', amount: 50 })];
    expect(matchPayment(transactions, '38472916', 100).found).toBe(false);
  });

  it('rejects wrong currency', () => {
    const transactions = [makeTx({ vs: '38472916', amount: 100, currency: 'EUR' })];
    expect(matchPayment(transactions, '38472916', 100).found).toBe(false);
  });

  it('ignores outgoing payments', () => {
    const transactions = [makeTx({ vs: '38472916', amount: -100 })];
    expect(matchPayment(transactions, '38472916', 100).found).toBe(false);
  });

  it('skips already processed transactions', () => {
    const transactions = [makeTx({ id: 5555, vs: '38472916', amount: 100 })];
    expect(matchPayment(transactions, '38472916', 100, new Set([5555])).found).toBe(false);
  });

  it('returns empty for no transactions', () => {
    expect(matchPayment([], '38472916', 100).found).toBe(false);
  });
});

// ============================================================
// checkEvaluationAccess
// ============================================================
describe('checkEvaluationAccess', () => {
  it('denies if no payment', () => {
    expect(checkEvaluationAccess(null).allowed).toBe(false);
  });

  it('denies if pending', () => {
    expect(checkEvaluationAccess(makePayment({ status: 'pending' })).allowed).toBe(false);
  });

  it('allows if paid with remaining uses', () => {
    expect(checkEvaluationAccess(makePayment({ evaluationsUsed: 5, evaluationsLimit: 30 })).allowed).toBe(true);
  });

  it('denies if limit reached', () => {
    const result = checkEvaluationAccess(makePayment({ evaluationsUsed: 30, evaluationsLimit: 30 }));
    expect(result.allowed).toBe(false);
    expect(result.reason).toBe('limit_reached');
  });
});

// ============================================================
// createOrUpdatePaymentRecord
// ============================================================
describe('createOrUpdatePaymentRecord', () => {
  const matchedTx = { id: 1001, date: '2026-02-06', amount: 100, senderName: 'Test' };

  it('creates new record', () => {
    const record = createOrUpdatePaymentRecord(null, matchedTx, 'test@example.com', '38472916');
    expect(record.status).toBe('paid');
    expect(record.evaluationsLimit).toBe(30);
    expect(record.purchases).toHaveLength(1);
  });

  it('extends existing record', () => {
    const existing = makePayment({ evaluationsUsed: 28, evaluationsLimit: 30, purchases: [] });
    const record = createOrUpdatePaymentRecord(existing, matchedTx, 'test@example.com', '38472916');
    expect(record.evaluationsLimit).toBe(60);
  });
});

// ============================================================
// getFioDateRange
// ============================================================
describe('getFioDateRange', () => {
  it('returns YYYY-MM-DD format', () => {
    const { dateFrom, dateTo } = getFioDateRange();
    expect(dateFrom).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(dateTo).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('dateTo is today', () => {
    const { dateTo } = getFioDateRange();
    expect(dateTo).toBe(new Date().toISOString().split('T')[0]);
  });
});

// ============================================================
// generateSPDString
// ============================================================
describe('generateSPDString', () => {
  it('generates valid SPD string', () => {
    const spd = generateSPDString('CZ1720100000002900065431', 100, '38472916');
    expect(spd).toBe('SPD*1.0*ACC:CZ1720100000002900065431*AM:100.00*CC:CZK*X-VS:38472916*MSG:Platba');
  });

  it('accepts custom message', () => {
    const spd = generateSPDString('CZ1720100000002900065431', 100, '12345678', 'Test');
    expect(spd).toContain('MSG:Test');
  });
});

// ============================================================
// eventDateToVS
// ============================================================
describe('eventDateToVS', () => {
  it('converts date to YYMMDD', () => {
    expect(eventDateToVS('2026-02-15')).toBe('260215');
  });

  it('pads single-digit month and day', () => {
    expect(eventDateToVS('2026-01-05')).toBe('260105');
  });

  it('returns 6-digit string', () => {
    expect(eventDateToVS('2026-06-20')).toHaveLength(6);
  });
});

// ============================================================
// matchDonations
// ============================================================
describe('matchDonations', () => {
  it('finds donations with matching VS', () => {
    const txs = [makeTx({ vs: '260215', amount: 100, id: 1 })];
    expect(matchDonations(txs, '260215')).toHaveLength(1);
  });

  it('finds multiple donations', () => {
    const txs = [
      makeTx({ vs: '260215', amount: 50, id: 1 }),
      makeTx({ vs: '260215', amount: 200, id: 2 }),
      makeTx({ vs: '999999', amount: 100, id: 3 }),
    ];
    expect(matchDonations(txs, '260215')).toHaveLength(2);
  });

  it('matches any amount', () => {
    const txs = [makeTx({ vs: '260215', amount: 500, id: 1 })];
    expect(matchDonations(txs, '260215')[0].amount).toBe(500);
  });

  it('excludes processed transactions', () => {
    const txs = [
      makeTx({ vs: '260215', amount: 100, id: 1 }),
      makeTx({ vs: '260215', amount: 200, id: 2 }),
    ];
    expect(matchDonations(txs, '260215', new Set([1]))).toHaveLength(1);
  });
});
```

---

## Step 3: Install dependency

If the project uses React and the QR component is generated, install:

```bash
npm install qrcode.react
```

## Step 4: Environment variables

Add `FIO_API_TOKEN` to the project's env config:

- **Cloudflare:** `.dev.vars` for local, Cloudflare Dashboard for production
- **Next.js:** `.env.local`
- **Express:** `.env`
- **Other:** `.env`

Also add to `.env.example` (or equivalent):

```
FIO_API_TOKEN=your_64_char_fio_api_token_here
```

## Step 5: Final checklist

After generating all files, print this checklist for the user:

```
✅ FIO Bank payment integration generated!

Remaining manual steps:
□ Update IBAN in config/payment.ts
□ Update account number in config/payment.ts
□ Set payment amount in config/payment.ts
□ Add FIO_API_TOKEN to environment variables
□ Run tests: npm test (or npx vitest run)
□ Test locally with mock endpoint
□ Set reminder to rotate FIO API token (180 days)

FIO API Token:
1. Log into https://ib.fio.cz
2. Settings → API → Create new token (read-only)
3. Copy the 64-character token
4. Add as FIO_API_TOKEN env variable
```

## Important technical details

- **FIO API rate limit:** Max 1 call per 30 seconds, enforced globally (not per user)
- **FIO API URL:** `https://fioapi.fio.cz/v1/rest/periods/{token}/{dateFrom}/{dateTo}/transactions.json`
- **Token validity:** 180 days, read-only recommended
- **VS collision probability:** ~1:90M for 8-digit random
- **SPD format:** Czech QR payment standard, supported by all Czech/Slovak banks
- **Payment matching:** VS (normalized, no leading zeros) + exact amount + CZK + positive volume
- **Donation matching:** VS + CZK + positive volume (any amount)
