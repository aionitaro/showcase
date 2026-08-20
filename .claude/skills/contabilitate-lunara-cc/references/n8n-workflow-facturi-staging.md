# Workflow n8n: Facturi Primite - Staging Sync

Construit și testat 2026-08-20 (id `zodp1X4nKhWjVReK` în instanța `n8n.onlineleads.ro`, proiect personal `Andrei Ionita <gogu.samsung@gmail.com>`). Spre deosebire de `Gmail Attachment Fetch (on-demand)`, acest workflow **rămâne activ permanent** — nu e un webhook public, ci un trigger programat (schedule), fără suprafață de expunere pe internet. Nu-l dezactiva după folosire.

## Scop

Elimină nevoia ca utilizatorul să încarce manual, în fiecare rulare lunară a skill-ului, facturile de la furnizori. În schimb, pe măsură ce primește o factură prin email, în orice moment al lunii, utilizatorul o redirecționează (forward) cu o convenție fixă de subiect + un label Gmail. Workflow-ul o preia automat, o pune într-un folder tampon pe OneDrive, și marchează emailul ca procesat. Pasul 4.5 al skill-ului verifică acel folder tampon înainte să ceară orice utilizatorului.

## Convenția pe care trebuie s-o respecte utilizatorul la forward

1. Redirecționează (Forward) emailul cu factura către propria adresă (sau doar editează subiectul emailului redirecționat, dacă clientul de mail permite).
2. Rescrie subiectul exact în formatul: `[FACTURA] AAAA-LL-ZZ Nume scurt furnizor` — ex: `[FACTURA] 2026-07-20 ADS Contab Expert`. Data e cea de pe factură (data emiterii), nu data trimiterii emailului.
3. Aplică label-ul Gmail **„Facturi Netriate"** (id `Label_51`) pe emailul redirecționat.

Fără label, emailul nu e văzut de căutare, indiferent de subiect — vezi avertismentul de mai jos despre motivul pentru care nu ne bazăm doar pe text din subiect.

## Noduri

1. **Schedule Trigger** (`n8n-nodes-base.scheduleTrigger`, v1.3) — „Daily Check"
   - Rulează zilnic la 08:00 (ora instanței n8n). Ajustabil din nod dacă frecvența nu e potrivită.

2. **Gmail** (`n8n-nodes-base.gmail`, v2.2) — „Search Staged Invoices"
   - `resource: message`, `operation: getAll`, `returnAll: true`, `simple: false`
   - `filters.q: 'label:"Facturi Netriate" -label:"Facturi Netriate - Procesat"'`
   - `filters.readStatus: both`
   - `options.downloadAttachments: true`, `options.dataPropertyAttachmentsPrefixName: attachment_`

3. **Code** (`n8n-nodes-base.code`, v2, `runOnceForAllItems`) — „Parse Subject And Fan Out Attachments"
   - Validează că subiectul începe literal cu `[FACTURA] ` urmat de o dată `AAAA-LL-ZZ` validă — orice email care nu respectă exact formatul e ignorat silențios (rămâne needlabelat, deci reapare la următoarea rulare, până când utilizatorul corectează subiectul).
   - Pentru fiecare atașament găsit (`attachment_0`, `attachment_1`, ...), produce un item de output: `{ fileName: "AAAA-LL-ZZ_Nume-Curatat.pdf", sourceMessageId, sourceSubject }` cu binarul mutat pe cheia `data`.
   - Dacă un email are mai multe atașamente, fiecare primește un sufix `_1`, `_2` etc. în numele fișierului.

4. **Microsoft OneDrive** (`n8n-nodes-base.microsoftOneDrive`, v1.1) — „Upload To Staging"
   - `resource: file`, `operation: upload`, `binaryData: true`, `binaryPropertyName: data`
   - `fileName`: expresie `{{ $json.fileName }}`
   - `parentId`: `187AE3AD232D393E!s7922b83f1a7246bab348e877b259e308` (folderul `_Facturi Primite (netriate)`, sub `Online Leads/Documente Societate/Facturi/`)

5. **Gmail** (`n8n-nodes-base.gmail`, v2.2) — „Mark Email Processed"
   - `resource: message`, `operation: addLabels`, `messageId`: expresie `{{ $json.sourceMessageId }}`, `labelIds: ["Label_50"]` (label-ul „Facturi Netriate - Procesat")
   - Conectat în paralel cu „Upload To Staging", din același nod Code (fan-out) — rulează o dată per atașament, deci pentru un email cu mai multe atașamente aplică labelul de mai multe ori (inofensiv, Gmail API e idempotent la asta).

Conexiuni: `Daily Check → Search Staged Invoices → Parse Subject And Fan Out Attachments → [Upload To Staging, Mark Email Processed]` (ramificație, nu secvență — ambele pornesc din nodul Code).

## Avertisment critic — de ce filtrarea e pe label, nu pe text din subiect

Prima versiune a acestui workflow folosea `filters.q: 'subject:"[FACTURA]"'`, presupunând că Gmail va căuta literal șirul `[FACTURA]`. Testare reală a arătat că Gmail **ignoră parantezele pătrate ca zgomot** și tratează asta ca o căutare de text simplu după cuvântul „factura" — a returnat emailuri complet nelegate (notificări Orange Yoxo, DIGI etc.), pentru că orice email cu „factura" undeva în subiect s-a potrivit.

Codul din nodul „Parse..." ar fi respins oricum aceste emailuri (verifică `subject.startsWith('[FACTURA]')` strict), deci rezultatul final ar fi fost tot corect — dar cu `returnAll: true` + `simple: false` + `downloadAttachments: true`, workflow-ul încerca să descarce conținutul complet al **fiecărui** email nelegat găsit. Testat live: o execuție cu acest bug a durat **4 minute 19 secunde** pe o cutie poștală cu ~106.000 mesaje, pentru o căutare care ar fi trebuit să dureze sub o secundă. Rulat zilnic, ar fi fost extrem de costisitor și lent, posibil chiar ar fi lovit limite de rate Gmail API.

Soluția: `label:"Facturi Netriate"` în Gmail search **este** un filtru exact (index de bază de date, nu căutare de text), spre deosebire de `subject:`. Testat după fix: **0,57 secunde**. Concluzie generală, valabilă pentru orice workflow n8n viitor care filtrează Gmail: **preferă `label:` sau `-label:` peste `subject:`/text liber ori de câte ori ai o alternativă bazată pe etichetă**, mai ales combinat cu `returnAll: true` pe o cutie poștală mare.

## Labels Gmail folosite

- **„Facturi Netriate"** (id `Label_51`) — aplicat manual de utilizator pe emailul redirecționat, semnalează „ia asta în considerare".
- **„Facturi Netriate - Procesat"** (id `Label_50`) — aplicat automat de workflow după upload reușit, previne reprocesarea.

## Limitări cunoscute

- Dacă upload-ul pe OneDrive eșuează pentru un atașament, emailul e totuși marcat „Procesat" (labelul se aplică necondiționat, din paralel, nu doar la succes) — verifică `execution list` din n8n dacă un fișier lipsește din staging deși utilizatorul confirmă că l-a trimis corect.
- Emailuri cu subiect care nu respectă exact formatul (dată invalidă, lipsă spațiu) sunt ignorate silențios, fără notificare — rămân cu label-ul „Facturi Netriate" la nesfârșit până utilizatorul corectează subiectul și le lasă să fie reprocesate la următoarea rulare zilnică.
