# Workflow n8n: Facturi Primite - Staging Sync

Construit și testat 2026-08-20/21 (id `zodp1X4nKhWjVReK` în instanța `n8n.onlineleads.ro`, proiect personal `Andrei Ionita <gogu.samsung@gmail.com>`). Spre deosebire de `Gmail Attachment Fetch (on-demand)`, acest workflow **rămâne activ permanent** — nu e un webhook public, ci un trigger programat (schedule), fără suprafață de expunere pe internet. Nu-l dezactiva după folosire.

## Scop

Elimină nevoia ca utilizatorul să încarce manual, în fiecare rulare lunară a skill-ului, facturile de la furnizori. În schimb, pe măsură ce primește o factură prin email, în orice moment al lunii, utilizatorul o redirecționează (forward) — fără nicio editare — către un alias dedicat. Workflow-ul preia automat atașamentul, îl pune într-un folder tampon pe OneDrive, ca fișier neatins (fără nicio analiză de conținut), și marchează emailul ca procesat. Pasul 4.5 al skill-ului verifică acel folder tampon și **Claude** (nu n8n) face verificarea/potrivirea cu plățile la rularea skill-ului — n8n rămâne strict la partea determinist-mecanică (preluare + stocare), fără AI, conform arhitecturii generale a skill-ului.

## Convenția pe care trebuie s-o respecte utilizatorul

Un singur pas: **redirecționează (Forward) emailul cu factura, fără nicio editare, către `gogu.samsung+facturiprimite@gmail.com`** — plus-addressing Gmail nativ, livrează automat în aceeași cutie (`gogu.samsung@gmail.com`), fără cont/alias separat de configurat. Nu e nevoie de subiect special, nu e nevoie de label manual. Câte o factură pe email (dacă un email are mai multe atașamente diferite ca dată/furnizor, fiecare ajunge în tampon ca fișier separat, dar fără metadate distincte — vezi limitări).

## Noduri

1. **Schedule Trigger** (`n8n-nodes-base.scheduleTrigger`, v1.3) — „Daily Check"
   - Rulează zilnic la 08:00 (ora instanței n8n). Ajustabil din nod dacă frecvența nu e potrivită.

2. **Gmail** (`n8n-nodes-base.gmail`, v2.2) — „Search Staged Invoices"
   - `resource: message`, `operation: getAll`, `returnAll: true`, `simple: false`
   - `filters.q: 'to:"gogu.samsung+facturiprimite@gmail.com" in:inbox'`
   - `filters.readStatus: both`
   - `options.downloadAttachments: true`, `options.dataPropertyAttachmentsPrefixName: attachment_`
   - **Nu conține nicio negare de label** — vezi „Istoric" mai jos pentru motiv. Idempotența (nu reprocesa un email deja procesat) se verifică în nodul Code următor, nu aici.

3. **Code** (`n8n-nodes-base.code`, v2, `runOnceForAllItems`) — „Fan Out Attachments"
   - Sare peste orice email al cărui `labelIds` conține deja `Label_50` (label-ul „Facturi Netriate - Procesat") — verificare pe datele mesajului complet, nu pe rezultatul căutării.
   - Pentru fiecare atașament rămas (`attachment_0`, `attachment_1`, ...), produce un item: `{ fileName: "AAAA-LL-ZZ_messageId_NumeOriginalFisier.pdf", sourceMessageId }`, cu binarul mutat pe cheia `data`. Data din nume e **data primirii emailului** (`internalDate`), nu data facturii — n8n nu citește conținutul PDF-ului.
   - `messageId`-ul brut e inclus în nume special ca protecție împotriva coliziunilor (vezi „Istoric").

4. **Microsoft OneDrive** (`n8n-nodes-base.microsoftOneDrive`, v1.1) — „Upload To Staging"
   - `resource: file`, `operation: upload`, `binaryData: true`, `binaryPropertyName: data`
   - `fileName`: expresie `{{ $json.fileName }}`
   - `parentId`: `187AE3AD232D393E!s7922b83f1a7246bab348e877b259e308` (folderul `_Facturi Primite (netriate)`, sub `Online Leads/Documente Societate/Facturi/`)

5. **Gmail** (`n8n-nodes-base.gmail`, v2.2) — „Mark Email Processed"
   - `resource: message`, `operation: addLabels`, `messageId`: expresie `{{ $json.sourceMessageId }}`, `labelIds: ["Label_50"]`
   - Conectat în paralel cu „Upload To Staging", din același nod Code (fan-out) — rulează o dată per atașament, deci pentru un email cu mai multe atașamente aplică labelul de mai multe ori (inofensiv, Gmail API e idempotent la asta).

Conexiuni: `Daily Check → Search Staged Invoices → Fan Out Attachments → [Upload To Staging, Mark Email Processed]` (ramificație, nu secvență — ambele pornesc din nodul Code).

## Istoric — patru probleme reale găsite prin testare live, în ordine

Fiecare din cele de mai jos a fost descoperită rulând workflow-ul cu date reale, nu prin citirea documentației Gmail. Regulă generală rezultată: **nu presupune comportamentul căutării/filtrării Gmail — testează cu o execuție reală înainte să lași activ un workflow recurent.**

1. **`subject:"[FACTURA]"` — text search larg, nu match literal.** Gmail ignoră parantezele pătrate ca zgomot și caută simplu cuvântul „factura" — a prins notificări Orange Yoxo, DIGI etc. Combinat cu `returnAll: true` + descărcare completă, o execuție a durat **4 minute 19 secunde** pe o cutie cu ~106.000 mesaje.

2. **`label:"Facturi Netriate"` — funcțional, dar cu pas manual în plus.** Filtru exact, testat la 0,57s. Utilizatorul a cerut eliminarea etichetării manuale.

3. **`to:"...@gmail.com"` singur — prindea copii nelegate ale aceluiași forward.** La un test real cu o factură reală (`facturaADS0031.pdf`, de la ADS Contab Expert), căutarea a găsit **3 mesaje** pentru un singur forward: copia reală din Inbox, o copie doar-Sent, și un **draft** rămas din compunerea emailului (toate au `to:` alias-ul în antet, inclusiv draftul). Toate trei au fost procesate și marcate, riscând suprascrierea silențioasă a unei facturi cu alta dacă ar fi avut nume de fișier identic. Fix: adăugat `in:inbox` în query, care exclude atât draft-urile cât și copiile doar-Sent.

4. **`-label:"..."` (negare de label, testată atât cu numele complet cât și cu ID-ul brut `Label_50`) — nu excludea mesaje deja etichetate.** După fix-ul #3, un mesaj deja marcat „Procesat" (confirmat prin `labelIds` pe obiectul complet al mesajului) a fost totuși reprocesat, de trei ori la rând, la interval de secunde — deci nu era lag de propagare a indexului. Fix definitiv: eliminată orice negare de label din `filters.q`; verificarea „deja procesat" mutată în codul JS al nodului „Fan Out Attachments", folosind `item.json.labelIds` (mereu corect, vine din obiectul complet al mesajului, nu din indexul de căutare).

## Labels Gmail existente (context istoric)

- **„Facturi Netriate - Procesat"** (id `Label_50`) — singurul folosit activ, aplicat automat de workflow. Verificarea lui se face în cod (vezi #4 mai sus), nu prin query Gmail.
- **„Facturi Netriate"** (id `Label_51`) — rămas din iterația #2, neutilizat de workflow-ul curent, sigur de ignorat.

## Ce NU face acest workflow (intenționat)

La un moment dat s-a explorat adăugarea unui pas de analiză AI (Google Gemini, resource `document.analyze`, credențial „Gemini PAID API account") care să citească fiecare PDF și să extragă dată/furnizor/sumă direct în n8n. Decizie: **nu s-a implementat** — verificarea de conținut (dată, furnizor, sumă, potrivire cu o plată) rămâne exclusiv treaba lui Claude la Pas 4.5, pentru că oricum face acea verificare la rularea skill-ului; dublarea ei în n8n ar fi adăugat cost și complexitate fără beneficiu. Dacă vreodată se reconsideră (ex: volum mare de facturi, nevoie de reconciliere fără sesiune Claude activă), nodurile relevante sunt `n8n-nodes-base.extractFromFile` (operation: pdf) pentru text, sau `@n8n/n8n-nodes-langchain.googleGemini` (resource: document, operation: analyze) pentru analiză directă a PDF-ului (inclusiv scanate) — dar rețin: `document.analyze` nu are opțiune nativă de output JSON structurat, ar trebui parsat manual din răspunsul text.

## Limitări cunoscute

- Dacă upload-ul pe OneDrive eșuează pentru un atașament, emailul e totuși marcat „Procesat" (labelul se aplică necondiționat, din paralel, nu doar la succes) — verifică `execution list` din n8n dacă un fișier lipsește din staging deși utilizatorul confirmă că l-a trimis corect.
- Numele fișierului din tampon (`AAAA-LL-ZZ_messageId_NumeOriginal.pdf`) nu conține data reală a facturii, nici furnizorul curățat — doar data primirii emailului și numele original al atașamentului (care poate fi orice, ex. `facturaADS0031.pdf`, sau generic ca `invoice.pdf`). Pasul 4.5 din skill trebuie să **deschidă efectiv fiecare fișier** (nu doar să citească numele) ca să determine data/furnizorul/suma reale, pentru potrivire cu lista de plăți.
- Dacă utilizatorul trimite două facturi diferite în același email (atașamente multiple), ambele ajung în tampon ca fișiere separate (nume unice, datorită `messageId`-ului în nume), dar Claude trebuie să le deschidă individual la Pas 4.5 ca să le distingă — nu există nicio metadată automată care să le diferențieze în afara conținutului PDF-ului însuși.
