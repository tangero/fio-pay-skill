# FIO Pay Skill pro Claude Code

[![Verze](https://img.shields.io/github/v/release/tangero/fio-pay-skill?label=verze)](https://github.com/tangero/fio-pay-skill/releases)
[![Licence](https://img.shields.io/github/license/tangero/fio-pay-skill)](LICENSE)

> Integrace plateb z FIO Banky jako znovupoužitelný [Claude Code](https://docs.anthropic.com/en/docs/claude-code) slash command. Jeden příkaz. Jakýkoliv TypeScript/React projekt. Žádné závislosti k ruční instalaci.

Vytvořil [Patrick Zandl](https://github.com/tangero) spolu s [Claude Code](https://claude.com/claude-code) pro komunitu [vibecoding.cz](https://vibecoding.cz).

[English version](README.en.md)

---

### Aktualizace

Pro notifikace o nových verzích klikněte na GitHubu na **Watch** → **Custom** → **Releases** u [tohoto repozitáře](https://github.com/tangero/fio-pay-skill).

Pro aktualizaci stačí znovu spustit instalaci:

```bash
curl -fsSL https://raw.githubusercontent.com/tangero/fio-pay-skill/main/install.sh | bash
```

---

## Co to umí

`/fio-setup` analyzuje váš aktuální projekt a vygeneruje kompletní platební integraci FIO Banky přizpůsobenou vašemu stacku:

- **Ověření platby** — párování příchozích bankovních převodů podle variabilního symbolu + částky
- **QR platby** — český SPD standard, čitelný jakoukoli českou/slovenskou bankovní aplikací
- **Sledování darů** — volitelný modul pro dobrovolné příspěvky
- **Mock endpoint** — lokální vývoj bez volání skutečného bankovního API
- **Unit testy** — 40+ testových případů pro všechny utility funkce

## Proč FIO Banka?

FIO Banka nabízí bezplatné, dobře zdokumentované JSON API pro čtení pohybů na účtu. Na rozdíl od Stripe nebo jiných platebních bran jsou **nulové poplatky** za tuzemské CZK převody. Integrace používá read-only API token — vaše aplikace pouze kontroluje, zda platba dorazila, nikdy nezahajuje transakce.

## Podporované stacky

Skill detekuje strukturu vašeho projektu a přizpůsobí generovaný kód:

| Backend | Frontend | Storage |
|---------|----------|---------|
| Cloudflare Pages Functions | React + shadcn/ui | Cloudflare KV |
| Next.js API Routes | React + libovolná UI lib | SQLite / Prisma |
| Express.js | Plain React | In-memory / Redis |
| Hono | Vanilla HTML/JS | Filesystem |

---

## Instalace

### Varianta A: Jedním příkazem (doporučeno)

```bash
curl -fsSL https://raw.githubusercontent.com/tangero/fio-pay-skill/main/install.sh | bash
```

Stáhne `fio-setup.md` do `~/.claude/commands/` a je hotovo.

### Varianta B: Ruční instalace

```bash
mkdir -p ~/.claude/commands
curl -fsSL https://raw.githubusercontent.com/tangero/fio-pay-skill/main/fio-setup.md \
  -o ~/.claude/commands/fio-setup.md
```

### Varianta C: Git clone

```bash
git clone https://github.com/tangero/fio-pay-skill.git
cd fio-pay-skill
./install.sh
```

### Ověření instalace

Po instalaci by měl soubor existovat na:

```
~/.claude/commands/fio-setup.md
```

Ověřte příkazem:

```bash
ls -la ~/.claude/commands/fio-setup.md
```

---

## Použití

### 1. Otevřete projekt v Claude Code

Přejděte do adresáře jakéhokoliv TypeScript/React projektu a spusťte Claude Code.

### 2. Spusťte slash command

```
/fio-setup
```

### 3. Claude automaticky:

1. **Detekuje váš stack** — přečte `package.json`, najde backend framework, UI knihovnu, testovací framework a storage řešení
2. **Zeptá se na preferenci** — pouze ověření plateb (základní) nebo platby + dary (kompletní)
3. **Vygeneruje utility funkce** — čisté TypeScript funkce pro generování VS, párování plateb, SPD QR řetězce, datumové rozsahy
4. **Vytvoří API endpointy** — přizpůsobené vašemu backendu (Cloudflare Functions / Next.js / Express / Hono)
5. **Přidá QR platební komponentu** — React komponenta s vaší UI knihovnou (shadcn/ui / MUI / plain HTML)
6. **Vytvoří konfigurační soubor** — s placeholder hodnotami pro IBAN, částky, zprávy
7. **Přidá unit testy** — 40+ testových případů připravených ke spuštění
8. **Vypíše checklist** — zbývající manuální kroky (IBAN, token atd.)

### Struktura generovaných souborů

```
{api-dir}/fio/
  payment-utils.ts       — Čisté utility funkce (generování VS, párování, SPD, datumy)
  verify-payment.ts      — Endpoint: ověření konkrétní platby
  verify-donation.ts     — Endpoint: ověření dobrovolných příspěvků (volitelně)
  donations.ts           — Endpoint: admin přehled darů (volitelně)
  mock.ts                — Mock endpoint pro lokální vývoj

{src}/config/payment.ts  — Konfigurace (IBAN, částky, zprávy)
{src}/components/PaymentQRCode.tsx — React QR komponenta
{test-dir}/payment-utils.test.ts   — Unit testy
```

---

## Konfigurace

Po spuštění `/fio-setup` je potřeba vyplnit skutečné hodnoty:

### 1. Platební konfigurace (`config/payment.ts`)

| Hodnota | Popis | Příklad |
|---------|-------|---------|
| `PAYMENT_IBAN` | Váš FIO Bank IBAN | `CZ1720100000002900065431` |
| `PAYMENT_ACCOUNT` | Formát pro zobrazení | `2900065431 / 2010` |
| `PAYMENT_AMOUNT` | Cena v CZK | `100` |
| `PAYMENT_MESSAGE` | Zpráva v QR platbě | `Platba za sluzbu` |

### 2. FIO API Token

Token dává vaší aplikaci read-only přístup k pohybům na účtu.

1. Přihlaste se do [FIO internetbankingu](https://ib.fio.cz)
2. Jděte do **Nastavení** → **API**
3. Klikněte na **Přidat token**
4. Vyberte oprávnění **Pohyby na účtu — pouze čtení**
5. Zkopírujte 64znakový token
6. Přidejte jako environment proměnnou:

| Platforma | Kam přidat |
|-----------|-----------|
| Cloudflare | `.dev.vars` (lokálně), Dashboard → Settings → Variables (produkce) |
| Next.js | `.env.local` |
| Express / Hono | `.env` |

```bash
# .env / .dev.vars / .env.local
FIO_API_TOKEN=vas_64znakovy_token
```

**Důležité:** Token je platný **180 dní**. Nastavte si připomínku v kalendáři na jeho obnovení.

### 3. Instalace QR závislosti

Pokud používáte React QR komponentu:

```bash
npm install qrcode.react
```

---

## Jak to funguje

### Průběh platby

```
1. Vaše aplikace vygeneruje unikátní variabilní symbol (8místné náhodné číslo)
2. Uživatel vidí QR kód (český SPD standard) s platebními údaji
3. Uživatel naskenuje QR v bankovní aplikaci a odešle platbu
4. Uživatel klikne na "Ověřit platbu" ve vaší aplikaci
5. Váš backend zavolá FIO API (pohyby za posledních 7 dní)
6. Páruje podle: VS + přesná částka + měna CZK + kladný objem
7. Pokud nalezeno → aktivuje placenou funkci
```

### Technické detaily

| Parametr | Hodnota |
|----------|---------|
| FIO API rate limit | Max 1 volání za 30 sekund (globální, ne per uživatel) |
| FIO API endpoint | `https://fioapi.fio.cz/v1/rest/periods/{token}/{od}/{do}/transactions.json` |
| Formát variabilního symbolu | 8 číslic, rozsah 10000000–99999999 |
| Pravděpodobnost kolize VS | ~1 z 90 milionů |
| Formát QR | SPD (Short Payment Descriptor) — český standard |
| Párování platby | VS + přesná částka + CZK + příchozí (kladný objem) |
| Párování daru | VS + CZK + příchozí (libovolná částka) |

### Rate limiting

FIO Banka povoluje maximálně 1 API volání za 30 sekund. Generovaný kód vynucuje 35sekundový globální cooldown (30s limit + 5s buffer). Sdílený mezi všemi uživateli — pokud uživatel A ověřuje ve 12:00:00, uživatel B musí počkat do 12:00:35.

### Mock endpoint

Pro lokální vývoj simuluje vygenerovaný `mock.ts` endpoint odpovědi FIO API:

```
GET /api/fio/mock?vs=38472916&amount=100      → Vrátí odpovídající platbu
GET /api/fio/mock?vs=38472916&empty=true       → Vrátí prázdnou odpověď (žádná platba)
```

Mock je automaticky blokován na ne-localhost doménách.

---

## Odinstalace

```bash
rm ~/.claude/commands/fio-setup.md
```

Odstraní pouze Claude Code command. Soubory již vygenerované ve vašich projektech zůstanou nedotčeny.

---

## O projektu

Tento skill vytvořil **[Patrick Zandl](https://github.com/tangero)** spolu s **[Claude Code](https://claude.com/claude-code)** (Anthropic) jako nástroj pro komunitu **[vibecoding.cz](https://vibecoding.cz)**.

Referenční implementace je otestována v produkci na [zitraslavni.cz](https://www.zitraslavni.cz) — platformě pro workshopy tvůrčího psaní, která zpracovává reálné platby a dary přes FIO Banku.

### Co je vibecoding.cz?

[vibecoding.cz](https://vibecoding.cz) je česká komunita a Discord server zaměřený na tvorbu softwaru s AI asistenty pro programování. Pokud vás zajímá vibe coding, vývoj s AI nebo tipy pro Claude Code, přidejte se k nám!

## Licence

MIT — používejte jak chcete.
