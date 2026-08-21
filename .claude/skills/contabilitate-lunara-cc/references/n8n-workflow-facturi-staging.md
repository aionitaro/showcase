# Workflow n8n: Facturi Primite - Staging Sync

Construit și testat 2026-08-20 (id `zodp1X4nKhWjVReK` în instanța `n8n.onlineleads.ro`, proiect personal `Andrei Ionita <gogu.samsung@gmail.com>`). Spre deosebire de `Gmail Attachment Fetch (on-demand)`, acest workflow **rămâne activ permanent** — nu e un webhook public, ci un trigger programat (schedule), fără suprafață de expunere pe internet. Nu-l dezactiva după folosire.

## Scop

Elimină nevoia ca utilizatorul să încarce manual, în fiecare rulare lunară a skill-ului, facturile de la furnizori. În schimb, pe măsură ce primește o factură prin email, în orice moment al lunii, utilizatorul o redirecționează (forward) cu o convenție fixă de subiect + un label Gmail. Workflow-ul o preia automat, o pune într-un folder tampon pe OneDrive, și marchează emailul ca procesat. Pasul 4.5 al skill-ului verifică acel folder tampon înainte să ceară orice utilizatorului.

## Convenția pe care trebuie s-o respecte utilizatorul la forward

1. Redirecționează (Forward) sau trimite direct emailul cu factura către **`gogu.samsung+facturiprimite@gmail.com`** — plus-addressing Gmail nativ, livrează automat în aceeași cutie (`gogu.samsung@gmail.com`), fără cont sau alias separat de configurat pe partea Gmail.
2. Rescrie subiectul exact în formatul: `[FACTURA] AAAA-LL-ZZ Nume scurt furnizor` — ex: `[FACTURA] 2026-07-20 ADS Contab Expert`. Data e cea de pe factură (data emiterii), nu data trimiterii emailului.

Nu mai e nevoie de niciun label manual din partea utilizatorului — vezi istoricul de mai jos pentru evoluția filtrării.

## Noduri

1. **Schedule Trigger** (`n8n-nodes-base.scheduleTrigger`, v1.3) — „Daily Check"
   - Rulează zilnic la 08:00 (ora instanței n8n). Ajustabil din nod dacă frecvența nu e potrivită.

2. **Gmail** (`n8n-nodes-base.gmail`, v2.2) — „Search Staged Invoices"
   - `resource: message`, `operation: getAll`, `returnAll: true`, `simple: false`
   - `filters.q: 'to:"gogu.samsung+facturiprimite@gmail.com" -label:"Facturi Netriate - Procesat"'`
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

## Istoric — evoluția filtrării Gmail (de ce nu ne bazăm pe text din subiect)

Trei iterații, fiecare corectând o problemă reală descoperită prin testare live, nu presupunere:

1. **`subject:"[FACTURA]"` (respins).** Presupunerea inițială a fost că Gmail caută literal șirul `[FACTURA]`. Testare reală a arătat că Gmail **ignoră parantezele pătrate ca zgomot** și tratează asta ca o căutare de text simplu după cuvântul „factura" — a returnat emailuri complet nelegate (notificări Orange Yoxo, DIGI etc.), pentru că orice email cu „factura" undeva în subiect s-a potrivit. Codul din nodul „Parse..." ar fi respins oricum aceste emailuri la pasul de validare a subiectului, deci rezultatul final ar fi fost tot corect — dar cu `returnAll: true` + `simple: false` + `downloadAttachments: true`, workflow-ul încerca să descarce conținutul complet al **fiecărui** email nelegat găsit. Testat live: o execuție cu acest bug a durat **4 minute 19 secunde** pe o cutie poștală cu ~106.000 mesaje, pentru o căutare care ar fi trebuit să dureze sub o secundă.

2. **`label:"Facturi Netriate"` (funcțional, dar cu un pas manual în plus).** Utilizatorul aplica manual acest label pe emailul redirecționat. Filtru exact (index de bază de date, nu căutare de text) — testat la **0,57 secunde**. Funcționa corect, dar utilizatorul a semnalat că etichetarea manuală, pe lângă rescrierea subiectului, era un pas în plus inutil.

3. **`to:"gogu.samsung+facturiprimite@gmail.com"` (varianta curentă).** Plus-addressing Gmail — orice email trimis la `cont+orice-text@gmail.com` ajunge automat în `cont@gmail.com`, fără alias de configurat. Elimină pasul de etichetare: utilizatorul doar trimite/redirecționează către acest alias. Testat: **~1 secundă**, la fel de precis ca filtrarea pe label — `to:` cu adresă completă între ghilimele nu suferă de problema de tokenizare de la `subject:`.

Concluzie generală, valabilă pentru orice workflow n8n viitor care filtrează Gmail: **preferă `label:`, `to:` sau `from:` cu adresă completă peste `subject:`/text liber ori de câte ori ai o alternativă structurată**, mai ales combinat cu `returnAll: true` pe o cutie poștală mare — și verifică empiric (execuție reală, nu doar validare de sintaxă) înainte să lași un workflow recurent activ.

## Labels Gmail folosite

- **„Facturi Netriate - Procesat"** (id `Label_50`) — aplicat automat de workflow după upload reușit, previne reprocesarea. Singurul label încă relevant — nu necesită nicio acțiune din partea utilizatorului.
- **„Facturi Netriate"** (id `Label_51`) — rămas din iterația anterioară (#2 de mai sus), neutilizat de workflow-ul curent. Nu e nevoie să fie șters, dar nu mai are niciun rol activ.

## Limitări cunoscute

- Dacă upload-ul pe OneDrive eșuează pentru un atașament, emailul e totuși marcat „Procesat" (labelul se aplică necondiționat, din paralel, nu doar la succes) — verifică `execution list` din n8n dacă un fișier lipsește din staging deși utilizatorul confirmă că l-a trimis corect.
- Emailuri trimise la alias cu subiect care nu respectă exact formatul (dată invalidă, lipsă spațiu) sunt ignorate silențios, fără notificare, și **nu primesc labelul „Procesat"** — rămân eligibile la căutare și sunt reverificate (dar tot ignorate) la fiecare rulare zilnică, până când utilizatorul corectează subiectul (necesar: redirecționează din nou cu subiect corect) sau șterge/arhivează emailul respectiv.
