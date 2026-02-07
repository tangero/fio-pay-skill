# FIO Pay Skill for Claude Code

Czech bank payment integration (FIO Bank API) as a reusable Claude Code slash command.

One command. Any TypeScript/React project. Zero dependencies to install manually.

## What it does

`/fio-setup` analyzes your current project and generates a complete FIO Bank payment integration tailored to your stack:

- **Payment verification** — match incoming bank transfers by variable symbol + amount
- **QR code payments** — Czech SPD standard, scannable by any banking app
- **Donation tracking** — optional module for voluntary contributions
- **Mock endpoint** — local development without real bank API
- **Unit tests** — 40+ test cases for all utility functions

## Supported stacks

| Backend | Frontend | Storage |
|---------|----------|---------|
| Cloudflare Pages Functions | React + shadcn/ui | Cloudflare KV |
| Next.js API Routes | React + any UI lib | SQLite / Prisma |
| Express.js | Plain React | In-memory / Redis |
| Hono | Vanilla HTML/JS | Filesystem |

## Install

### One-liner (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/davidzemancz/fio-pay-skill/main/install.sh | bash
```

### Manual install

```bash
mkdir -p ~/.claude/commands
curl -fsSL https://raw.githubusercontent.com/davidzemancz/fio-pay-skill/main/fio-setup.md \
  -o ~/.claude/commands/fio-setup.md
```

### Git clone

```bash
git clone https://github.com/davidzemancz/fio-pay-skill.git
cd fio-pay-skill
./install.sh
```

## Usage

In any project directory, run in Claude Code:

```
/fio-setup
```

Claude will:
1. Detect your project stack (package.json, framework, UI library)
2. Generate payment utility functions
3. Create API endpoints matching your backend
4. Add a QR payment component for your frontend
5. Create a config file with placeholders
6. Add unit tests
7. Print a checklist of remaining manual steps

## Generated files

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

## Configuration

After running `/fio-setup`, update these values:

1. **IBAN** — your FIO Bank IBAN in `config/payment.ts`
2. **Account number** — display format (e.g. `2900065431 / 2010`)
3. **Amount** — expected payment amount in CZK
4. **FIO_API_TOKEN** — add to `.env` / `.dev.vars` (get from internetbanking.fio.cz)

## FIO API Token

1. Log into [FIO internetbanking](https://ib.fio.cz)
2. Go to Settings → API → Create new token
3. Select **read-only** permissions
4. Copy the 64-character token
5. Add as `FIO_API_TOKEN` environment variable

**Important:** Token is valid for 180 days. Set a reminder to rotate it.

## How payment matching works

```
User gets variable symbol (8-digit random) →
User pays via QR code or manual transfer →
Your app calls FIO API (last 7 days of transactions) →
Matches by: VS + exact amount + CZK currency + positive volume →
Activates the paid feature
```

Rate limit: FIO allows max 1 API call per 30 seconds (enforced globally).

## Uninstall

```bash
rm ~/.claude/commands/fio-setup.md
```

## License

MIT
