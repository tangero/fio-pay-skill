# Nastavení platební integrace FIO Banky

Nastavuješ kompletní platební integraci FIO Banky v aktuálním projektu. Postupuj přesně podle těchto kroků.

## Krok 1: Analyzuj aktuální projekt

Přečti `package.json` (nebo ekvivalent) a zjisti:

1. **Backend framework**: Cloudflare Pages Functions / Next.js / Express / Hono / jiný
2. **Frontend framework**: React / Vue / Svelte / vanilla
3. **UI knihovna**: shadcn/ui / MUI / Chakra / Ant Design / žádná
4. **Testovací framework**: Vitest / Jest / žádný
5. **Storage**: Cloudflare KV / SQLite / Prisma / Redis / filesystem
6. **Adresářová struktura**: kde žijí API routes, komponenty, testy

Své zjištění nahlás uživateli před generováním kódu. Zeptej se, zda chce:
- **Pouze ověření plateb** (základní)
- **Platby + dary** (kompletní)

## Krok 2: Vygeneruj soubory

Přizpůsob referenční implementaci níže detekovanému stacku. Klíčové adaptace:

### Pravidla adaptace backendu

| Stack | Signatura API handleru | Volání storage |
|-------|----------------------|---------------|
| **Cloudflare Pages Functions** | `export const onRequestPost: PagesFunction<Env>` | `env.KV_NAMESPACE.get/put` |
| **Next.js App Router** | `export async function POST(request: Request)` | Použij DB/KV adaptér projektu |
| **Next.js Pages Router** | `export default async function handler(req, res)` | Použij DB/KV adaptér projektu |
| **Express** | `router.post('/path', async (req, res) => {})` | Použij DB/storage adaptér projektu |
| **Hono** | `app.post('/path', async (c) => {})` | Použij DB/storage adaptér projektu |

### Pravidla adaptace frontendu

| UI knihovna | Styl komponenty |
|------------|----------------|
| **shadcn/ui** | Použij `Card`, `Button`, `cn()` z `@/components/ui/*` |
| **MUI** | Použij `Card`, `Button`, `Typography` z `@mui/material` |
| **Plain React** | Použij základní HTML elementy s inline styly nebo CSS moduly |
| **Vanilla** | Vygeneruj plain HTML + JS (bez JSX) |

### Pravidla adaptace storage

Pro ne-KV storage nahraď `env.WORKSHOP_DATA.get(key, 'json')` / `env.WORKSHOP_DATA.put(key, JSON.stringify(data))` storage vzorem projektu. Klíče k uložení:
- `payment:{identifier}` — PaymentRecord JSON
- `donation:{eventId}` — DonationRecord JSON
- `fio:last_check` — timestamp string pro rate limiting

---

## Referenční implementace

### Soubor 1: Platební utility (čisté funkce bez závislostí na frameworku)

**Cílová cesta:** `{api-dir}/fio/payment-utils.ts` (nebo `_payment-utils.ts` pro Cloudflare)

```typescript
// Čisté utility funkce pro platební integraci FIO Banky
// Žádné závislosti na frameworku — funguje s jakýmkoliv backendem

// ============================================================
// Typy
// ============================================================

/** Struktura transakce FIO Bank API (JSON formát v1.9) */
export interface FioTransaction {
  column0: { value: string; name: string; id: number } | null;   // Datum
  column1: { value: number; name: string; id: number } | null;   // Objem
  column2: { value: string; name: string; id: number } | null;   // Protiúčet
  column5: { value: string; name: string; id: number } | null;   // Variabilní symbol
  column10: { value: string; name: string; id: number } | null;  // Název protiúčtu
  column14: { value: string; name: string; id: number } | null;  // Měna
  column16: { value: string; name: string; id: number } | null;  // Zpráva pro příjemce
  column22: { value: number; name: string; id: number } | null;  // ID pohybu
}

/** Struktura JSON odpovědi FIO API */
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

/** Záznam o platbě uložený v KV/DB */
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

/** Výsledek párování platby */
export interface PaymentMatchResult {
  found: boolean;
  transaction?: {
    id: number;
    date: string;
    amount: number;
    senderName: string | null;
  };
}

/** Záznam o daru uložený v KV/DB */
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
// Funkce
// ============================================================

/** Generuje 8místný náhodný variabilní symbol (10000000–99999999) */
export function generateVariableSymbol(): string {
  return String(Math.floor(10000000 + Math.random() * 90000000));
}

/** Validuje formát variabilního symbolu */
export function isValidVariableSymbol(vs: string): boolean {
  return /^\d{8}$/.test(vs) && parseInt(vs) >= 10000000;
}

/**
 * Hledá odpovídající příchozí platbu v seznamu FIO transakcí.
 * Páruje podle: VS (bez leading zeros) + přesná částka + CZK + kladný objem.
 * Ignoruje transakce s ID v excludeTransactionIds (již zpracované).
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
 * Kontroluje, zda uživatel může provést placenou akci.
 * Vrací výsledek s důvodem zamítnutí.
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

/** Vytvoří nebo rozšíří záznam o platbě po úspěšném párování */
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

/** Vrací datumový rozsah pro dotaz na FIO API (posledních N dní) */
export function getFioDateRange(daysBack: number = 7): { dateFrom: string; dateTo: string } {
  const now = new Date();
  const from = new Date(now.getTime() - daysBack * 86400000);
  return {
    dateFrom: from.toISOString().split('T')[0],
    dateTo: now.toISOString().split('T')[0],
  };
}

/** Převede datum akce na 6místný variabilní symbol (YYMMDD) */
export function eventDateToVS(dateString: string): string {
  const d = new Date(dateString);
  const yy = String(d.getFullYear()).slice(-2);
  const mm = String(d.getMonth() + 1).padStart(2, '0');
  const dd = String(d.getDate()).padStart(2, '0');
  return `${yy}${mm}${dd}`;
}

/**
 * Hledá VŠECHNY odpovídající příchozí platby (pro dary — libovolná částka).
 * Páruje podle: VS (bez leading zeros) + CZK + kladný objem.
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

/** Generuje český QR platební řetězec (SPD standard) */
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

### Soubor 2: Endpoint pro ověření platby

**Cílová cesta:** `{api-dir}/fio/verify-payment.ts`

Toto je verze pro **Cloudflare Pages Functions**. Přizpůsob signaturu handleru, parsování requestu a volání storage detekovanému stacku.

```typescript
// POST /api/fio/verify-payment
// On-demand ověření platby přes FIO Bank API

import {
  matchPayment,
  createOrUpdatePaymentRecord,
  getFioDateRange,
  FioApiResponse,
  PaymentRecord,
} from './payment-utils';

// PŘIZPŮSOB: Importuj svůj auth/session helper
// import { getSession } from '../auth';

// PŘIZPŮSOB: Definuj rozhraní prostředí
interface Env {
  WORKSHOP_DATA: KVNamespace;  // PŘIZPŮSOB: tvůj storage
  FIO_API_TOKEN: string;
}

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
};

// PŘIZPŮSOB: Importuj z config/payment.ts
const EXPECTED_AMOUNT = 100;            // CZK
const EVALUATIONS_PER_PURCHASE = 30;
const FIO_RATE_LIMIT_MS = 35000;        // 35s (30s FIO limit + buffer)

// PŘIZPŮSOB: Změň signaturu handleru podle svého frameworku
export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  try {
    // 1. Autentizace — PŘIZPŮSOB svému auth systému
    // const session = await getSession(request, env.WORKSHOP_DATA);
    // if (!session) return new Response(JSON.stringify({ error: 'Neautorizováno' }), { status: 401, headers: CORS_HEADERS });

    const body = await request.json() as { identifier?: string; variableSymbol?: string; email?: string };
    const { identifier, variableSymbol, email } = body;

    if (!identifier || !variableSymbol) {
      return new Response(
        JSON.stringify({ error: 'Chybí identifier nebo variableSymbol' }),
        { status: 400, headers: CORS_HEADERS }
      );
    }

    // 2. Kontrola existující platby
    const paymentKey = `payment:${identifier}`;
    // PŘIZPŮSOB: Nahraď svým čtením ze storage
    const existingPayment = await env.WORKSHOP_DATA.get(paymentKey, 'json') as PaymentRecord | null;

    // Pokud je zaplaceno a limit nevyčerpán, vrať info
    if (existingPayment?.status === 'paid' &&
        existingPayment.evaluationsUsed < existingPayment.evaluationsLimit) {
      return new Response(JSON.stringify({
        success: true,
        alreadyPaid: true,
        evaluationsUsed: existingPayment.evaluationsUsed,
        evaluationsLimit: existingPayment.evaluationsLimit,
      }), { headers: CORS_HEADERS });
    }

    // 3. Rate limit: max 1 FIO API volání za 35s (globální)
    // PŘIZPŮSOB: Nahraď svým čtením ze storage
    const lastCheck = await env.WORKSHOP_DATA.get('fio:last_check');
    const now = Date.now();
    if (lastCheck && now - parseInt(lastCheck) < FIO_RATE_LIMIT_MS) {
      const waitSec = Math.ceil((FIO_RATE_LIMIT_MS - (now - parseInt(lastCheck))) / 1000);
      return new Response(JSON.stringify({
        error: 'rate_limit',
        message: `Ověření je možné jednou za 30 sekund. Zkuste to za ${waitSec}s.`,
      }), { status: 429, headers: CORS_HEADERS });
    }

    // 4. Kontrola FIO API tokenu
    if (!env.FIO_API_TOKEN) {
      return new Response(JSON.stringify({
        error: 'Platební brána není nakonfigurována.',
      }), { status: 503, headers: CORS_HEADERS });
    }

    // 5. Volání FIO API — transakce za posledních 7 dní
    const { dateFrom, dateTo } = getFioDateRange(7);
    const fioUrl = `https://fioapi.fio.cz/v1/rest/periods/${env.FIO_API_TOKEN}/${dateFrom}/${dateTo}/transactions.json`;

    // Zapsat timestamp PŘED voláním (ochrana proti race condition)
    // PŘIZPŮSOB: Nahraď svým zápisem do storage
    await env.WORKSHOP_DATA.put('fio:last_check', String(now));

    const fioResponse = await fetch(fioUrl);

    if (fioResponse.status === 409) {
      return new Response(JSON.stringify({
        error: 'rate_limit',
        message: 'Bankovní API je dočasně přetížené. Zkuste to za 30 sekund.',
      }), { status: 429, headers: CORS_HEADERS });
    }

    if (!fioResponse.ok) {
      console.error('FIO API chyba:', fioResponse.status, await fioResponse.text());
      return new Response(JSON.stringify({
        error: 'fio_error',
        message: 'Nepodařilo se ověřit platbu. Zkuste to později.',
      }), { status: 502, headers: CORS_HEADERS });
    }

    const fioData = await fioResponse.json() as FioApiResponse;

    // 6. Párování platby
    const transactions = fioData.accountStatement?.transactionList?.transaction || [];

    const processedIds = new Set(
      (existingPayment?.purchases || []).map(p => p.fioTransactionId)
    );

    const match = matchPayment(transactions, variableSymbol, EXPECTED_AMOUNT, processedIds);

    if (!match.found || !match.transaction) {
      return new Response(JSON.stringify({
        success: false,
        message: 'Platba zatím nebyla přijata. Mezibankovní převody mohou trvat až několik hodin. Zkuste to prosím později.',
      }), { headers: CORS_HEADERS });
    }

    // 7. Platba nalezena — aktivovat/rozšířit balíček
    const updatedPayment = createOrUpdatePaymentRecord(
      existingPayment,
      match.transaction,
      email || 'unknown',
      variableSymbol,
      EVALUATIONS_PER_PURCHASE
    );

    // PŘIZPŮSOB: Nahraď svým zápisem do storage
    await env.WORKSHOP_DATA.put(paymentKey, JSON.stringify(updatedPayment));

    return new Response(JSON.stringify({
      success: true,
      evaluationsUsed: updatedPayment.evaluationsUsed,
      evaluationsLimit: updatedPayment.evaluationsLimit,
    }), { headers: CORS_HEADERS });

  } catch (error: unknown) {
    console.error('verify-payment chyba:', error);
    return new Response(JSON.stringify({
      error: 'Interní chyba serveru',
    }), { status: 500, headers: CORS_HEADERS });
  }
};

// CORS preflight — PŘIZPŮSOB nebo odstraň pokud tvůj framework řeší CORS
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

### Soubor 3: Endpoint pro ověření darů (volitelný)

**Cílová cesta:** `{api-dir}/fio/verify-donation.ts`

```typescript
// POST /api/fio/verify-donation
// Ověření dobrovolných příspěvků přes FIO Bank API

import {
  matchDonations,
  getFioDateRange,
  FioApiResponse,
  DonationRecord,
} from './payment-utils';

// PŘIZPŮSOB: Definuj rozhraní prostředí
interface Env {
  WORKSHOP_DATA: KVNamespace;
  FIO_API_TOKEN: string;
}

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
};

const FIO_RATE_LIMIT_MS = 35000;

// PŘIZPŮSOB: Změň signaturu handleru
export const onRequestPost: PagesFunction<Env> = async (context) => {
  const { request, env } = context;

  try {
    const body = await request.json() as { eventId?: string; variableSymbol?: string };
    const { eventId, variableSymbol } = body;

    if (!eventId || !variableSymbol) {
      return new Response(
        JSON.stringify({ error: 'Chybí eventId nebo variableSymbol' }),
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
        message: `Ověření je možné jednou za 30 sekund. Zkuste to za ${waitSec}s.`,
      }), { status: 429, headers: CORS_HEADERS });
    }

    if (!env.FIO_API_TOKEN) {
      return new Response(JSON.stringify({
        error: 'Platební brána není nakonfigurována.',
      }), { status: 503, headers: CORS_HEADERS });
    }

    // Načtení existujícího záznamu o darech
    const donationKey = `donation:${eventId}`;
    const existing = await env.WORKSHOP_DATA.get(donationKey, 'json') as DonationRecord | null;

    // Volání FIO API — posledních 14 dní
    const { dateFrom, dateTo } = getFioDateRange(14);
    const fioUrl = `https://fioapi.fio.cz/v1/rest/periods/${env.FIO_API_TOKEN}/${dateFrom}/${dateTo}/transactions.json`;

    await env.WORKSHOP_DATA.put('fio:last_check', String(now));

    const fioResponse = await fetch(fioUrl);

    if (fioResponse.status === 409) {
      return new Response(JSON.stringify({
        error: 'rate_limit',
        message: 'Bankovní API je dočasně přetížené. Zkuste to za 30 sekund.',
      }), { status: 429, headers: CORS_HEADERS });
    }

    if (!fioResponse.ok) {
      console.error('FIO API chyba:', fioResponse.status, await fioResponse.text());
      return new Response(JSON.stringify({
        error: 'fio_error',
        message: 'Nepodařilo se ověřit příspěvek. Zkuste to později.',
      }), { status: 502, headers: CORS_HEADERS });
    }

    const fioData = await fioResponse.json() as FioApiResponse;
    const transactions = fioData.accountStatement?.transactionList?.transaction || [];

    const processedIds = new Set(
      (existing?.donations || []).map(d => d.fioTransactionId)
    );

    const newDonations = matchDonations(transactions, variableSymbol, processedIds);

    // Aktualizace záznamu
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
    console.error('verify-donation chyba:', error);
    return new Response(JSON.stringify({
      error: 'Interní chyba serveru',
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

### Soubor 4: Admin endpoint pro dary (volitelný)

**Cílová cesta:** `{api-dir}/fio/donations.ts`

```typescript
// GET /api/fio/donations?eventId=xxx nebo ?eventIds=id1,id2,id3
// Admin endpoint pro zobrazení záznamů o darech

import { DonationRecord } from './payment-utils';

// PŘIZPŮSOB: Definuj rozhraní prostředí
interface Env {
  WORKSHOP_DATA: KVNamespace;
}

const CORS_HEADERS = {
  'Content-Type': 'application/json',
  'Access-Control-Allow-Origin': '*',
};

// PŘIZPŮSOB: Změň signaturu handleru
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

    return new Response(JSON.stringify({ error: 'Chybí eventId nebo eventIds parametr' }), {
      status: 400,
      headers: CORS_HEADERS,
    });
  } catch (error: unknown) {
    console.error('donations GET chyba:', error);
    return new Response(JSON.stringify({ error: 'Interní chyba serveru' }), {
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

### Soubor 5: Mock endpoint (pro lokální vývoj)

**Cílová cesta:** `{api-dir}/fio/mock.ts`

```typescript
// GET /api/fio/mock?vs=XXXXXXXX&amount=100
// Mock FIO API endpoint pro lokální vývoj
// Simuluje odpověď FIO API s příchozí platbou

// PŘIZPŮSOB: Definuj rozhraní prostředí
interface Env {
  WORKSHOP_DATA: KVNamespace;
}

// PŘIZPŮSOB: Změň signaturu handleru
export const onRequestGet: PagesFunction<Env> = async (context) => {
  // Blokovat na produkci — mock je jen pro lokální vývoj
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

  // Simulace FIO rate limitu (5s cooldown pro mock)
  const lastCheck = await context.env.WORKSHOP_DATA.get('fio:mock_last_check');
  const now = Date.now();
  if (lastCheck && now - parseInt(lastCheck) < 5000) {
    return new Response('', { status: 409 });
  }
  await context.env.WORKSHOP_DATA.put('fio:mock_last_check', String(now));

  // Prázdná odpověď (simulace: platba nedorazila)
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

  // Odpověď s platbou
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
          column14: { value: 'CZK', name: 'Měna', id: 14 },
          column2: { value: '1234567890', name: 'Protiúčet', id: 2 },
          column5: { value: vs, name: 'VS', id: 5 },
          column10: { value: 'Testovací plátce', name: 'Název protiúčtu', id: 10 },
          column16: { value: 'Testovací platba', name: 'Zpráva pro příjemce', id: 16 },
        }],
      },
    },
  }), { headers });
};
```

---

### Soubor 6: Konfigurace plateb

**Cílová cesta:** `{src}/config/payment.ts`

```typescript
// Konfigurace plateb — AKTUALIZUJ TYTO HODNOTY pro svůj projekt

/** IBAN tvého FIO účtu */
export const PAYMENT_IBAN = 'CZ00000000000000000000'; // TODO: Nahraď svým IBAN

/** Číslo účtu pro zobrazení */
export const PAYMENT_ACCOUNT = '0000000000 / 2010'; // TODO: Nahraď svým číslem účtu

/** Částka platby v CZK */
export const PAYMENT_AMOUNT = 100; // TODO: Nastav svou cenu

/** Počet použití na jeden nákup (pro měřený přístup) */
export const EVALUATIONS_PER_PURCHASE = 30;

/** Zpráva v QR platbě */
export const PAYMENT_MESSAGE = 'Platba'; // TODO: Přizpůsob

// --- Dobrovolné příspěvky (volitelné) ---

/** Předvolby částek pro příspěvek */
export const DONATION_AMOUNTS = [50, 100, 200] as const;

/** Výchozí částka příspěvku */
export const DONATION_DEFAULT_AMOUNT = 100;

/** Zpráva pro příjemce v QR platbě (příspěvek) */
export const DONATION_MESSAGE = 'Dobrovolný příspěvek';
```

---

### Soubor 7: QR platební React komponenta

**Cílová cesta:** `{src}/components/PaymentQRCode.tsx`

Vyžaduje: `npm install qrcode.react`

```tsx
import React, { useState } from 'react';
import { QRCodeSVG } from 'qrcode.react';
// PŘIZPŮSOB: Importuj své UI komponenty
// příklad shadcn/ui:
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
      console.error('Kopírování selhalo:', err);
    }
  };

  const paymentDetails = [
    { label: 'Číslo účtu', value: PAYMENT_ACCOUNT, field: 'account' },
    { label: 'Částka', value: `${amount.toLocaleString('cs-CZ')} Kč`, field: 'amount' },
    { label: 'Variabilní symbol', value: variableSymbol, field: 'vs' },
  ];

  return (
    <div style={{ maxWidth: 400, margin: '0 auto', padding: 24, border: '1px solid #e5e7eb', borderRadius: 12 }}>
      <h3 style={{ textAlign: 'center', marginBottom: 16 }}>Platba bankovním převodem</h3>

      {/* QR kód */}
      <div style={{ display: 'flex', justifyContent: 'center', marginBottom: 16 }}>
        <div style={{ padding: 16, background: '#fff', borderRadius: 8, boxShadow: 'inset 0 1px 3px rgba(0,0,0,0.1)' }}>
          <QRCodeSVG value={spaydString} size={200} level="M" includeMargin={true} />
        </div>
      </div>

      <p style={{ textAlign: 'center', color: '#6b7280', fontSize: 14, marginBottom: 16 }}>
        Naskenujte QR kód v mobilní aplikaci vaší banky
      </p>

      {/* Platební údaje */}
      <div style={{ borderTop: '1px solid #e5e7eb', paddingTop: 16 }}>
        <p style={{ textAlign: 'center', color: '#374151', fontSize: 14, fontWeight: 500, marginBottom: 12 }}>
          Nebo zadejte údaje ručně:
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
              {copied === detail.field ? '✓' : 'Kopírovat'}
            </button>
          </div>
        ))}
      </div>

      {/* Upozornění */}
      <div style={{ padding: 12, background: '#fefce8', border: '1px solid #fde68a', borderRadius: 8, marginTop: 16 }}>
        <p style={{ fontSize: 14, color: '#854d0e', margin: 0 }}>
          <strong>Důležité:</strong> Pro správné přiřazení platby použijte uvedený variabilní symbol.
        </p>
      </div>
    </div>
  );
};

export default PaymentQRCode;
```

---

### Soubor 8: Unit testy

**Cílová cesta:** `{test-dir}/payment-utils.test.ts`

```typescript
// PŘIZPŮSOB: Importní cestu podle struktury projektu
import { describe, it, expect } from 'vitest'; // nebo 'jest'
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
} from '../path/to/payment-utils'; // PŘIZPŮSOB: správná importní cesta

// Helper: vytvoří FIO transakci s danými parametry
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
    column2: { value: '1234567890', name: 'Protiúčet', id: 2 },
    column5: overrides.vs !== undefined
      ? { value: overrides.vs, name: 'VS', id: 5 }
      : null,
    column10: overrides.senderName
      ? { value: overrides.senderName, name: 'Název protiúčtu', id: 10 }
      : null,
    column14: { value: overrides.currency ?? 'CZK', name: 'Měna', id: 14 },
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
  it('vrací 8místný řetězec číslic', () => {
    const vs = generateVariableSymbol();
    expect(vs).toMatch(/^\d{8}$/);
  });

  it('vrací číslo >= 10000000', () => {
    for (let i = 0; i < 100; i++) {
      const vs = generateVariableSymbol();
      expect(parseInt(vs)).toBeGreaterThanOrEqual(10000000);
      expect(parseInt(vs)).toBeLessThan(100000000);
    }
  });

  it('generuje různé hodnoty', () => {
    const values = new Set<string>();
    for (let i = 0; i < 20; i++) values.add(generateVariableSymbol());
    expect(values.size).toBeGreaterThan(1);
  });
});

// ============================================================
// isValidVariableSymbol
// ============================================================
describe('isValidVariableSymbol', () => {
  it('akceptuje platný 8místný VS', () => {
    expect(isValidVariableSymbol('38472916')).toBe(true);
    expect(isValidVariableSymbol('10000000')).toBe(true);
    expect(isValidVariableSymbol('99999999')).toBe(true);
  });

  it('zamítá příliš krátký VS', () => {
    expect(isValidVariableSymbol('1234567')).toBe(false);
    expect(isValidVariableSymbol('')).toBe(false);
  });

  it('zamítá příliš dlouhý VS', () => {
    expect(isValidVariableSymbol('123456789')).toBe(false);
  });

  it('zamítá nečíselný VS', () => {
    expect(isValidVariableSymbol('1234567a')).toBe(false);
  });

  it('zamítá VS pod 10000000', () => {
    expect(isValidVariableSymbol('00000001')).toBe(false);
    expect(isValidVariableSymbol('09999999')).toBe(false);
  });
});

// ============================================================
// matchPayment
// ============================================================
describe('matchPayment', () => {
  it('najde odpovídající transakci s přesným VS a částkou', () => {
    const transactions = [makeTx({ id: 1001, vs: '38472916', amount: 100 })];
    const result = matchPayment(transactions, '38472916', 100);
    expect(result.found).toBe(true);
    expect(result.transaction?.id).toBe(1001);
  });

  it('páruje VS bez leading zeros', () => {
    const transactions = [makeTx({ id: 1002, vs: '0038472916', amount: 100 })];
    const result = matchPayment(transactions, '38472916', 100);
    expect(result.found).toBe(true);
  });

  it('zamítá chybný VS', () => {
    const transactions = [makeTx({ vs: '99999999', amount: 100 })];
    expect(matchPayment(transactions, '38472916', 100).found).toBe(false);
  });

  it('zamítá chybnou částku', () => {
    const transactions = [makeTx({ vs: '38472916', amount: 50 })];
    expect(matchPayment(transactions, '38472916', 100).found).toBe(false);
  });

  it('zamítá jinou měnu', () => {
    const transactions = [makeTx({ vs: '38472916', amount: 100, currency: 'EUR' })];
    expect(matchPayment(transactions, '38472916', 100).found).toBe(false);
  });

  it('ignoruje odchozí platby', () => {
    const transactions = [makeTx({ vs: '38472916', amount: -100 })];
    expect(matchPayment(transactions, '38472916', 100).found).toBe(false);
  });

  it('přeskočí již zpracované transakce', () => {
    const transactions = [makeTx({ id: 5555, vs: '38472916', amount: 100 })];
    expect(matchPayment(transactions, '38472916', 100, new Set([5555])).found).toBe(false);
  });

  it('vrátí prázdný výsledek bez transakcí', () => {
    expect(matchPayment([], '38472916', 100).found).toBe(false);
  });
});

// ============================================================
// checkEvaluationAccess
// ============================================================
describe('checkEvaluationAccess', () => {
  it('zamítne bez platby', () => {
    expect(checkEvaluationAccess(null).allowed).toBe(false);
  });

  it('zamítne s pending platbou', () => {
    expect(checkEvaluationAccess(makePayment({ status: 'pending' })).allowed).toBe(false);
  });

  it('povolí se zbývajícími použitími', () => {
    expect(checkEvaluationAccess(makePayment({ evaluationsUsed: 5, evaluationsLimit: 30 })).allowed).toBe(true);
  });

  it('zamítne po vyčerpání limitu', () => {
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

  it('vytvoří nový záznam', () => {
    const record = createOrUpdatePaymentRecord(null, matchedTx, 'test@example.com', '38472916');
    expect(record.status).toBe('paid');
    expect(record.evaluationsLimit).toBe(30);
    expect(record.purchases).toHaveLength(1);
  });

  it('rozšíří existující záznam', () => {
    const existing = makePayment({ evaluationsUsed: 28, evaluationsLimit: 30, purchases: [] });
    const record = createOrUpdatePaymentRecord(existing, matchedTx, 'test@example.com', '38472916');
    expect(record.evaluationsLimit).toBe(60);
  });
});

// ============================================================
// getFioDateRange
// ============================================================
describe('getFioDateRange', () => {
  it('vrací formát YYYY-MM-DD', () => {
    const { dateFrom, dateTo } = getFioDateRange();
    expect(dateFrom).toMatch(/^\d{4}-\d{2}-\d{2}$/);
    expect(dateTo).toMatch(/^\d{4}-\d{2}-\d{2}$/);
  });

  it('dateTo je dnešek', () => {
    const { dateTo } = getFioDateRange();
    expect(dateTo).toBe(new Date().toISOString().split('T')[0]);
  });
});

// ============================================================
// generateSPDString
// ============================================================
describe('generateSPDString', () => {
  it('generuje validní SPD řetězec', () => {
    const spd = generateSPDString('CZ1720100000002900065431', 100, '38472916');
    expect(spd).toBe('SPD*1.0*ACC:CZ1720100000002900065431*AM:100.00*CC:CZK*X-VS:38472916*MSG:Platba');
  });

  it('akceptuje vlastní zprávu', () => {
    const spd = generateSPDString('CZ1720100000002900065431', 100, '12345678', 'Test');
    expect(spd).toContain('MSG:Test');
  });
});

// ============================================================
// eventDateToVS
// ============================================================
describe('eventDateToVS', () => {
  it('převede datum na YYMMDD', () => {
    expect(eventDateToVS('2026-02-15')).toBe('260215');
  });

  it('doplní nulami jednocíselný měsíc a den', () => {
    expect(eventDateToVS('2026-01-05')).toBe('260105');
  });

  it('vrátí 6místný řetězec', () => {
    expect(eventDateToVS('2026-06-20')).toHaveLength(6);
  });
});

// ============================================================
// matchDonations
// ============================================================
describe('matchDonations', () => {
  it('najde dary s odpovídajícím VS', () => {
    const txs = [makeTx({ vs: '260215', amount: 100, id: 1 })];
    expect(matchDonations(txs, '260215')).toHaveLength(1);
  });

  it('najde více darů', () => {
    const txs = [
      makeTx({ vs: '260215', amount: 50, id: 1 }),
      makeTx({ vs: '260215', amount: 200, id: 2 }),
      makeTx({ vs: '999999', amount: 100, id: 3 }),
    ];
    expect(matchDonations(txs, '260215')).toHaveLength(2);
  });

  it('páruje libovolnou částku', () => {
    const txs = [makeTx({ vs: '260215', amount: 500, id: 1 })];
    expect(matchDonations(txs, '260215')[0].amount).toBe(500);
  });

  it('vylučuje zpracované transakce', () => {
    const txs = [
      makeTx({ vs: '260215', amount: 100, id: 1 }),
      makeTx({ vs: '260215', amount: 200, id: 2 }),
    ];
    expect(matchDonations(txs, '260215', new Set([1]))).toHaveLength(1);
  });
});
```

---

## Krok 3: Instalace závislosti

Pokud projekt používá React a QR komponenta byla vygenerována, nainstaluj:

```bash
npm install qrcode.react
```

## Krok 4: Environment proměnné

Přidej `FIO_API_TOKEN` do konfigurace prostředí projektu:

- **Cloudflare:** `.dev.vars` lokálně, Cloudflare Dashboard pro produkci
- **Next.js:** `.env.local`
- **Express:** `.env`
- **Ostatní:** `.env`

Přidej také do `.env.example` (nebo ekvivalentu):

```
FIO_API_TOKEN=vas_64znakovy_fio_api_token
```

## Krok 5: Závěrečný checklist

Po vygenerování všech souborů vypiš uživateli tento checklist:

```
✅ Platební integrace FIO Banky vygenerována!

Zbývající manuální kroky:
□ Aktualizovat IBAN v config/payment.ts
□ Aktualizovat číslo účtu v config/payment.ts
□ Nastavit částku platby v config/payment.ts
□ Přidat FIO_API_TOKEN do environment proměnných
□ Spustit testy: npm test (nebo npx vitest run)
□ Otestovat lokálně s mock endpointem
□ Nastavit připomínku na rotaci FIO API tokenu (180 dní)

FIO API Token:
1. Přihlásit se na https://ib.fio.cz
2. Nastavení → API → Přidat token (pouze čtení)
3. Zkopírovat 64znakový token
4. Přidat jako FIO_API_TOKEN env proměnnou
```

## Důležité technické detaily

- **FIO API rate limit:** Max 1 volání za 30 sekund, vynuceno globálně (ne per uživatel)
- **FIO API URL:** `https://fioapi.fio.cz/v1/rest/periods/{token}/{datumOd}/{datumDo}/transactions.json`
- **Platnost tokenu:** 180 dní, doporučeno read-only
- **Pravděpodobnost kolize VS:** ~1:90M pro 8místné náhodné číslo
- **SPD formát:** Český QR platební standard, podporovaný všemi českými/slovenskými bankami
- **Párování platby:** VS (normalizovaný, bez leading zeros) + přesná částka + CZK + kladný objem
- **Párování daru:** VS + CZK + kladný objem (libovolná částka)
