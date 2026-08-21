# Workflow n8n: OneDrive File Ops (on-demand)

Construit și testat 2026-08-21 (id `VTttaO5c5Z0hPeqN` în instanța `n8n.onlineleads.ro`, proiect personal `Andrei Ionita <gogu.samsung@gmail.com>`). La fel ca `Gmail Attachment Fetch (on-demand)`: webhook public, autentificat prin header, **publicat doar cât e nevoie, dezactivat imediat după** — nu-l lăsa activ permanent.

## Scop

Punct unic, reutilizabil, pentru toate operațiile OneDrive de care skill-ul are nevoie (Pas 1.5, Pas 4.5, potențial Pas 5): listare folder, descărcare fișier, upload/suprascriere, mutare, redenumire. Apelabil prin `curl` cu o cheie `X-API-KEY` — funcționează identic indiferent dacă sesiunea Claude Code curentă are sau nu acces direct la tool-urile MCP n8n (spre deosebire de a construi workflow-uri temporare ad-hoc de fiecare dată, care presupun acel acces).

## Noduri

1. **Webhook** (`n8n-nodes-base.webhook`, v2.1) — „OneDrive Ops Webhook"
   - `httpMethod: POST`, `path: onedrive-ops`, `authentication: headerAuth` (același credențial „Header Auth account" ca la `Gmail Attachment Fetch`, deci aceeași valoare `X-API-KEY`)
   - `responseMode: responseNode`
   - `options.binaryData: true` — necesar ca să accepte upload-uri multipart/form-data (metadate + fișier binar în aceeași cerere); cererile JSON simple (fără fișier) funcționează normal în paralel, parsarea depinde de `Content-Type`-ul cererii primite, nu de acest setting.

2. **Switch** (`n8n-nodes-base.switch`, v3.4, mode `rules`) — „Route Operation"
   - Rutează pe `{{ $json.body.operation }}`, 5 ramuri: `getChildren`, `download`, `upload`, `move`, `rename`. Fără fallback — o cerere cu `operation` necunoscut e ignorată silențios (nicio ramură nu se potrivește, execuția se termină fără răspuns vizibil pentru client — limitare cunoscută, acceptabilă cât timp doar Claude apelează acest webhook, cu valori fixe).

3. Câte un nod **Microsoft OneDrive** (v1.1) per ramură:
   - **Get Children**: `resource: folder`, `operation: getChildren`, `folderId: {{ $json.body.folderId }}`
   - **Download File**: `resource: file`, `operation: download`, `fileId: {{ $json.body.itemId }}`, `binaryPropertyName: data`
   - **Upload File**: `resource: file`, `operation: upload`, `parentId: {{ $json.body.parentId }}`, `fileName: {{ $json.body.fileName }}`, `binaryData: true`, `binaryPropertyName: file` — **atenție la valoarea asta**, vezi avertismentul de mai jos
   - **Move File**: `resource: file`, `operation: move`, `fileId: {{ $json.body.itemId }}`, `destinationFolderId: {{ $json.body.destinationFolderId }}`
   - **Rename File**: `resource: file`, `operation: rename`, `itemId: {{ $json.body.itemId }}`, `newName: {{ $json.body.newName }}`

4. **Respond to Webhook** — două noduri, nu unul:
   - „Respond JSON" (`respondWith: allIncomingItems`, `options.responseKey: items`) — primește din Get Children / Upload / Move / Rename (patru ramuri converg aici)
   - „Respond Binary" (`respondWith: binary`, `responseDataSource: set`, `inputFieldName: data`) — primește doar din Download

## Apeluri (`curl`), testate live pe fiecare operație

**getChildren** — răspuns JSON, array sub cheia `items` (chiar și pentru un singur rezultat):
```bash
curl -s -X POST "https://n8n.onlineleads.ro/webhook/onedrive-ops" \
  -H "X-API-KEY: $ONEDRIVE_OPS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"operation": "getChildren", "folderId": "<id-folder>"}'
```

**download** — răspuns binar direct:
```bash
curl -s -X POST "https://n8n.onlineleads.ro/webhook/onedrive-ops" \
  -H "X-API-KEY: $ONEDRIVE_OPS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"operation": "download", "itemId": "<id-fisier>"}' \
  -o fisier_local.pdf
```

**upload** — `multipart/form-data`, nu JSON. Câmpul cu fișierul **trebuie numit exact `file`**:
```bash
curl -s -X POST "https://n8n.onlineleads.ro/webhook/onedrive-ops" \
  -H "X-API-KEY: $ONEDRIVE_OPS_KEY" \
  -F "operation=upload" \
  -F "parentId=<id-folder-destinatie>" \
  -F "fileName=NumeFisier.xlsx" \
  -F "file=@local/fisier.xlsx"
```
Comportament confirmat: dacă `parentId`+`fileName` coincid cu un fișier deja existent, upload-ul **suprascrie** conținutul (comportament implicit Microsoft Graph la coliziune de nume) — util pentru ciclul „descarcă → editează → reîncarcă" pe `Plati.xlsx`, fără să creeze o versiune paralelă.

**move**:
```bash
curl -s -X POST "https://n8n.onlineleads.ro/webhook/onedrive-ops" \
  -H "X-API-KEY: $ONEDRIVE_OPS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"operation": "move", "itemId": "<id-fisier>", "destinationFolderId": "<id-folder-destinatie>"}'
```

**rename**:
```bash
curl -s -X POST "https://n8n.onlineleads.ro/webhook/onedrive-ops" \
  -H "X-API-KEY: $ONEDRIVE_OPS_KEY" \
  -H "Content-Type: application/json" \
  -d '{"operation": "rename", "itemId": "<id-fisier>", "newName": "NumeNou.pdf"}'
```

Nu există operație `delete` — intenționat, ca să nu existe risc de ștergere accidentală printr-un apel greșit. Dacă apare vreodată nevoie reală de ștergere (ex. curățare fișiere de test), fă-o printr-un workflow n8n temporar, de unică folosință, arhivat imediat după — nu adăuga `delete` la acest webhook permanent.

## Avertismente critice — două bug-uri reale găsite prin testare live

1. **`respondWith: firstIncomingItem` (valoarea implicită) trunchiază la un singur rezultat.** Pentru `getChildren`, care poate întoarce mai multe fișiere/foldere, asta e greșit — trebuie `allIncomingItems`. Chiar și așa, fără `options.responseKey` setat explicit, testarea a arătat tot un singur item întors (nu un array) — abia cu `responseKey: "items"` (array-ul apărând sub `$.items` în JSON-ul răspunsului) s-au întors corect toate elementele. **Nu presupune că `allIncomingItems` fără `responseKey` produce un array valid — testează.**

2. **Numele câmpului binar la upload multipart NU e cel setat în `binaryPropertyName` cu un prefix+index (cum sugerează descrierea din UI „va fi prefixul, cu un număr de la 0 atașat").** Testare reală: cu un singur fișier trimis ca `-F "file=@..."`, câmpul binar rezultat în n8n a fost `file` (exact numele câmpului din formular), nu `data0`. Eroarea inițială a fost silențioasă la nivel de HTTP (200, corp gol) — vizibilă doar verificând `search_workflow_executions`/`get_workflow_execution`, care a arătat `NodeOperationError: The item has no binary field 'data0'`. **Regulă rezultată: `binaryPropertyName` pe nodul OneDrive Upload trebuie să fie identic cu numele câmpului folosit în `-F` la curl — verifică execuția reală, nu presupune convenția din docstring.**

## Concluzie generală (valabilă pentru orice webhook viitor din acest skill)

Un răspuns HTTP 200 nu înseamnă că operația a reușit așa cum te aștepți — verifică fie conținutul răspunsului (dacă workflow-ul e configurat corect să-l reflecte), fie direct execuția din n8n (`search_workflow_executions` + `get_workflow_execution`), înainte să declari un workflow nou ca „funcțional" și să-l documentezi ca atare.
