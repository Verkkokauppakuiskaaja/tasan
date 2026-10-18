# Tasan! AI (Cloudflare Worker)

Tasan!-sovelluksen oma Claude-palvelu kuvasta tapahtumaksi -toimintoon. Pohjana on CalendropAI:n Worker, mutta palvelulla on oma nimi, oma sovellusavain ja oma Anthropic-avain, joten kulut ja käyttörajat eivät sekoitu CalendropAI:hin.

Puhelin lukee kuvan tekstin itse (Apple Vision) ja lähettää vain tekstin. Palvelu kysyy Claudelta tapahtumat ja palauttaa jokaiselle lisäksi:

- `areaKind`: perheen osa-alue (`clothing`, `school`, `hobbies`, `parties`, `holidays` tai `other`)
- `preparation`: mitä pitää tehdä tai ottaa mukaan etukäteen, jos lähde kertoo sen

Vastaus on muuten sama kuin CalendropAI:ssä (`events[]` ja `event`).

## Käyttöönotto

```
cd Worker
npm install
npx wrangler login
npx wrangler deploy
npx wrangler secret put CLAUDE_API_KEY   # Anthropic Console > API Keys, oma avain Tasanille
npx wrangler secret put APP_KEY          # sama arvo kuin TASAN_AI_KEY Config/Tasan.xcconfigissa
```

APP_KEY:n arvo tällä hetkellä: `9f21e0b73bf138fa8b5a1e12daba6e88a4fce637cbe497a4`

Deploy antaa osoitteen `https://tasan-ai.<aliverkkotunnus>.workers.dev`. Jos se ei ole `tasan-ai.jussi-9cc.workers.dev`, vaihda `TASAN_AI_HOST` tiedostossa `Config/Tasan.xcconfig`.

Tarkistus: `curl https://tasan-ai.jussi-9cc.workers.dev/health`

## Malli

`wrangler.jsonc`:ssä `CLAUDE_MODEL = claude-haiku-5-5`, sama kuin CalendropAI:ssä: nopea ja edullinen tähän poimintaan. Mallin voi vaihtaa (esim. `claude-sonnet-5-5`) muuttamalla arvoa ja ajamalla `npx wrangler deploy`.

## Kehitys

```
npm test          # testit ilman verkkoa, Claude korvattu valevastauksella
npx wrangler dev  # paikallinen palvelin, tarvitsee .dev.vars-tiedoston (CLAUDE_API_KEY, APP_KEY)
```
