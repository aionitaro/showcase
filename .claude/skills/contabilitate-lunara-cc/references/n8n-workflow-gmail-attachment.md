# Workflow n8n: Gmail Attachment Fetch (on-demand)

Construit și testat 2026-08-20 (id `MsXUPbK89qRsP5qs` în instanța `n8n.onlineleads.ro`, proiect personal `Andrei Ionita <gogu.samsung@gmail.com>`). Dacă acel workflow tot există, refolosește-l — nu recrea de la zero. Dacă a fost șters sau lucrezi pe o instanță n8n diferită, schema de mai jos permite recrearea lui identic.

## Scop

Primește un `messageId` Gmail (și opțional un `attachmentIndex`), descarcă atașamentul respectiv prin nodul Gmail nativ, îl returnează ca răspuns binar HTTP. Există pentru că nu există altă cale (nici prin conectori Cowork, nici prin API Gmail direct fără OAuth propriu) de a scoate conținutul unui atașament dintr-un cont Gmail conectat la n8n.

## Noduri

1. **Webhook** (`n8n-nodes-base.webhook`, v2.1) — „Get Attachment Webhook"
   - `httpMethod: POST`
   - `path: gmail-attachment`
   - `authentication: headerAuth` (necesită header `X-API-KEY`, credențial de tip Header Auth în n8n)
   - `responseMode: responseNode` (răspunsul e construit de nodul următor, nu automat)

2. **Gmail** (`n8n-nodes-base.gmail`, v2.2) — „Fetch Message With Attachment"
   - `resource: message`, `operation: get`
   - `messageId`: expresie `{{ $json.body.messageId }}`
   - `simple: false` (necesar ca să vină și atașamentele, nu doar metadate simplificate)
   - `options.downloadAttachments: true`
   - `options.dataPropertyAttachmentsPrefixName: attachment_` (atașamentele apar ca `attachment_0`, `attachment_1`, ...)
   - Credențial: `gmailOAuth2`, contul Gmail conectat existent

3. **Respond to Webhook** (`n8n-nodes-base.respondToWebhook`, v1.5) — „Return Attachment Binary"
   - `respondWith: binary`
   - `responseDataSource: set`
   - `inputFieldName`: expresie care compune `"attachment_" + attachmentIndex` din body-ul webhook-ului original (referă nodul Webhook explicit, nu `$json`, pentru că la acest punct `$json` vine de la nodul Gmail, nu de la webhook)

## Apel

```bash
curl -s -X POST "https://n8n.onlineleads.ro/webhook/gmail-attachment" \
  -H "X-API-KEY: <valoarea credențialului Header Auth>" \
  -H "Content-Type: application/json" \
  -d '{"messageId": "<id-mesaj-gmail>", "attachmentIndex": 0}' \
  -o output.zip \
  -w "\nHTTP status: %{http_code}\nBytes: %{size_download}\n"
```

`attachmentIndex` e 0-based, în ordinea în care Gmail listează atașamentele mesajului respectiv (de regulă ordinea din care au fost atașate la trimitere).

## Constrângere importantă descoperită la testare

Instanța n8n a utilizatorului stochează datele binare în modul **filesystem-v2** (pe disk, nu inline în JSON-ul de execuție). Asta înseamnă:

- Tool-urile MCP n8n (`execute_workflow` + `get_workflow_execution`) NU pot extrage bytes-ii unui atașament — câmpul `binary.<nume>.data` conține doar marcatorul string `"filesystem-v2"`, nu conținutul real.
- Singura cale de a obține efectiv fișierul e prin răspunsul HTTP al webhook-ului (`Respond to Webhook` cu `respondWith: binary`), care citește corect din filesystem-v2 la runtime.
- Din Cowork (sandbox cloud), acest apel HTTP eșuează la nivel de proxy (403, domeniu nepermis pe lista albă) — motiv pentru care această arhitectură cu webhook + curl e gândită specific pentru Claude Code local/pe infrastructură proprie, unde acest blocaj nu există.

## Test end-to-end reușit (2026-08-20, dintr-o sesiune Claude Code pe web)

La verificarea de mai sus, workflow-ul live din n8n nu corespundea de fapt cu schema documentată mai sus — divergențe descoperite la testare:

- Nodul Webhook nu avea `httpMethod` setat explicit (rămăsese pe default GET, nu POST) și nu avea `authentication: headerAuth` configurat deloc — webhook-ul era complet neautenticat, deschis oricui știa URL-ul.
- Nodul Gmail era pe `operation: getAll` cu un filtru fix `subject:(Salt Business)` și `limit: 1`, ignorând complet `messageId`-ul primit în body — lua mereu cel mai recent email cu acel subiect, nu pe cel cerut.
- `options.downloadAttachments` nu era activat.

Corectat prin `update_workflow` (MCP n8n) ca să corespundă exact schemei din secțiunea „Noduri" de mai sus: `httpMethod: POST`, `authentication: headerAuth` legat de credențialul Header Auth existent, `operation: get` cu `messageId` din body, `downloadAttachments: true`.

După corecție, testat live: căutare Gmail pentru emailul Salt Bank „Iulie 2026" → `messageId` real → apel webhook → `HTTP 200`, 142.300 bytes, arhivă ZIP validă cu 6 fișiere (3 extrase RON/EUR/USD, fiecare PDF+CSV). Workflow-ul a fost dezactivat (`unpublish`) imediat după test.

Important: testul a rulat dintr-o sesiune **Claude Code pe web** (nu Cowork), unde apelurile HTTP către `n8n.onlineleads.ro` au reușit fără blocaj de proxy — inclusiv apelul de `POST` cu payload și descărcare de răspuns binar de ~140 KB. Asta contrazice presupunerea inițială (bazată pe testarea în Cowork) că orice mediu cloud/browser e blocat — pare specific Cowork, nu tuturor sesiunilor non-locale. Totuși, accesul de rețea al sesiunilor cloud poate varia (s-a observat și un 403 tranzitoriu la un test anterior, simplu, către homepage, urmat de succes constant la reîncercări) — nu trata asta ca o garanție permanentă, mai ales pentru automatizări recurente fără supraveghere.

## Securitate

Webhook-ul, odată activ (publicat), e accesibil public pe internet la `https://n8n.onlineleads.ro/webhook/gmail-attachment`, protejat doar de header-ul `X-API-KEY`. Recomandări:

- Nu-l lăsa activ permanent dacă nu ai nevoie de el activ tot timpul — publică-l, folosește-l, dezactivează-l (`unpublish`).
- Nu scrie valoarea `X-API-KEY` în cod sursă, fișiere commit-uite, sau output vizibil — citește-o dintr-o variabilă de mediu locală sau un manager de secrete.
- Dacă acest workflow devine parte dintr-o automatizare complet recurentă (fără intervenție), ia în calcul restricționarea IP-urilor permise (`ipWhitelist` în opțiunile nodului Webhook) la doar mașina care rulează Claude Code.
