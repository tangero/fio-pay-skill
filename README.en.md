# FIO Pay Skill for Claude Code

> Czech bank payment integration (FIO Bank API) as a reusable [Claude Code](https://docs.anthropic.com/en/docs/claude-code) slash command. One command. Any TypeScript/React project. Zero dependencies to install manually.

Created by [Patrick Zandl](https://github.com/tangero) with [Claude Code](https://claude.com/claude-code) for the [vibecoding.cz](https://vibecoding.cz) community.

[Cesky / Czech version](README.md)

---

## What it does

`/fio-setup` analyzes your current project and generates a complete FIO Bank payment integration tailored to your stack:

- **Payment verification** — match incoming bank transfers by variable symbol + amount
- **QR code payments** — Czech SPD standard, scannable by any Czech/Slovak banking app
- **Donation tracking** — optional module for voluntary contributions
- **Mock endpoint** — local development without hitting the real bank API
- **Unit tests** — 40+ test cases for all utility functions

## Why FIO Bank?

FIO Bank offers a free, well-documented JSON API for reading account transactions. Unlike Stripe or other payment gateways, there are **zero fees** for domestic CZK transfers. The integration uses a read-only API token — your app only checks if a payment arrived, it never initiates transactions.

## Supported stacks

The skill detects your project structure and adapts generated code accordingly:

| Backend | Frontend | Storage |
|---------|----------|---------|
| Cloudflare Pages Functions | React + shadcn/ui | Cloudflare KV |
| Next.js API Routes | React + any UI lib | SQLite / Prisma |
| Express.js | Plain React | In-memory / Redis |
| Hono | Vanilla HTML/JS | Filesystem |

---

## Installation

### Option A: One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/tangero/fio-pay-skill/main/install.sh | bash
```

This downloads `fio-setup.md` into `~/.claude/commands/` and you're done.

### Option B: Manual install

```bash
mkdir -p ~/.claude/commands
curl -fsSL https://raw.githubusercontent.com/tangero/fio-pay-skill/main/fio-setup.md \
  -o ~/.claude/commands/fio-setup.md
```

### Option C: Git clone

```bash
git clone https://github.com/tangero/fio-pay-skill.git
cd fio-pay-skill
./install.sh
```

### Verify installation

After install, the file should exist at:

```
~/.claude/commands/fio-setup.md
```

You can verify with:

```bash
ls -la ~/.claude/commands/fio-setup.md
```

---

## Usage

### 1. Open your project in Claude Code

Navigate to any TypeScript/React project directory and start Claude Code.

### 2. Run the slash command

```
/fio-setup
```

### 3. Claude will automatically:

1. **Detect your stack** — reads `package.json`, finds your backend framework, UI library, test framework, and storage solution
2. **Ask your preference** — payment verification only (basic) or payment + donations (full)
3. **Generate utility functions** — pure TypeScript functions for VS generation, payment matching, SPD QR strings, date ranges
4. **Create API endpoints** — adapted to your backend (Cloudflare Functions / Next.js / Express / Hono)
5. **Add QR payment component** — React component using your UI library (shadcn/ui / MUI / plain HTML)
6. **Create config file** — with placeholder values for your IBAN, amounts, messages
7. **Add unit tests** — 40+ test cases ready to run
8. **Print a checklist** — remaining manual steps (IBAN, token, etc.)

### Generated file structure

```
{api-dir}/fio/
  payment-utils.ts       — Pure utility functions (VS generation, matching, SPD, dates)
  verify-payment.ts      — Endpoint: verify a specific payment
  verify-donation.ts     — Endpoint: verify voluntary donations (optional)
  donations.ts           — Endpoint: admin donation overview (optional)
  mock.ts                — Mock endpoint for local dev

{src}/config/payment.ts  — Configuration (IBAN, amounts, messages)
{src}/components/PaymentQRCode.tsx — React QR component
{test-dir}/payment-utils.test.ts   — Unit tests
```

---

## Configuration

After running `/fio-setup`, you need to fill in your actual values:

### 1. Payment config (`config/payment.ts`)

| Value | Description | Example |
|-------|-------------|---------|
| `PAYMENT_IBAN` | Your FIO Bank IBAN | `CZ1720100000002900065431` |
| `PAYMENT_ACCOUNT` | Display format | `2900065431 / 2010` |
| `PAYMENT_AMOUNT` | Price in CZK | `100` |
| `PAYMENT_MESSAGE` | QR payment message | `Platba za sluzbu` |

### 2. FIO API Token

The token gives your app read-only access to account transactions.

1. Log into [FIO internetbanking](https://ib.fio.cz)
2. Go to **Settings** (Nastaveni) → **API**
3. Click **Create new token** (Pridat token)
4. Select **read-only** permissions (Pohyby na uctu — pouze cteni)
5. Copy the 64-character token
6. Add as environment variable:

| Platform | Where to add |
|----------|-------------|
| Cloudflare | `.dev.vars` (local), Dashboard → Settings → Variables (production) |
| Next.js | `.env.local` |
| Express / Hono | `.env` |

```bash
# .env / .dev.vars / .env.local
FIO_API_TOKEN=your_64_character_token_here
```

**Important:** The token is valid for **180 days**. Set a calendar reminder to rotate it.

### 3. Install QR dependency

If you're using the React QR component:

```bash
npm install qrcode.react
```

---

## How it works

### Payment flow

```
1. Your app generates a unique variable symbol (8-digit random number)
2. User sees a QR code (Czech SPD standard) with payment details
3. User scans QR in their banking app and sends the payment
4. User clicks "Verify payment" in your app
5. Your backend calls FIO API (last 7 days of transactions)
6. Matches by: VS + exact amount + CZK currency + positive volume
7. If found → activates the paid feature
```

### Technical details

| Parameter | Value |
|-----------|-------|
| FIO API rate limit | Max 1 call per 30 seconds (global, not per user) |
| FIO API endpoint | `https://fioapi.fio.cz/v1/rest/periods/{token}/{from}/{to}/transactions.json` |
| Variable symbol format | 8 digits, range 10000000–99999999 |
| VS collision probability | ~1 in 90 million |
| QR format | SPD (Short Payment Descriptor) — Czech standard |
| Payment matching | VS + exact amount + CZK + incoming (positive volume) |
| Donation matching | VS + CZK + incoming (any amount) |

### Rate limiting

FIO Bank allows maximum 1 API call per 30 seconds. The generated code enforces a 35-second global cooldown (30s limit + 5s buffer). This is shared across all users — if user A checks at 12:00:00, user B must wait until 12:00:35.

### Mock endpoint

For local development, the generated `mock.ts` endpoint simulates FIO API responses:

```
GET /api/fio/mock?vs=38472916&amount=100      → Returns matching payment
GET /api/fio/mock?vs=38472916&empty=true       → Returns empty (no payment)
```

The mock is automatically blocked on non-localhost domains.

---

## Uninstall

```bash
rm ~/.claude/commands/fio-setup.md
```

This only removes the Claude Code command. Any files already generated in your projects remain untouched.

---

## About

This skill was created by **[Patrick Zandl](https://github.com/tangero)** together with **[Claude Code](https://claude.com/claude-code)** (Anthropic) as a tool for the **[vibecoding.cz](https://vibecoding.cz)** community.

The reference implementation is battle-tested in production at [zitraslavni.cz](https://www.zitraslavni.cz) — a creative writing workshop platform handling real payments and donations via FIO Bank.

### What is vibecoding.cz?

[vibecoding.cz](https://vibecoding.cz) is a Czech community and Discord server focused on building software with AI coding assistants. If you're interested in vibe coding, AI-assisted development, or Claude Code tips and tricks, come join us!

## License

MIT — use it however you want.
