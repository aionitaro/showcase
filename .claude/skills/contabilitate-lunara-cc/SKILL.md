---
name: contabilitate-lunara-cc
description: Pregătește pachetul lunar de documente contabile pentru Online Leads SRL — creează structura de foldere pe lună (Primite/Emise/Extrase), descarcă extrasele Salt Bank și facturile FGO prin webhook-uri n8n (self-hosted, n8n.onlineleads.ro), extrage o listă de plăți din extrase, și urcă totul pe OneDrive prin n8n. Variantă pentru Claude Code local — folosește n8n ca „mâini" pentru toate operațiile externe (Gmail, FGO, OneDrive), Claude Code orchestrează și face partea de judecată (parsare, verificare). Folosește acest skill când utilizatorul cere „pregătește documentele pentru contabilitate", „fă pachetul lunar", sau menționează extrase Salt Bank + FGO + OneDrive împreună, în acest repo/proiect local.
---

# Pachet lunar pentru contabilitate — Claude Code + n8n (Online Leads SRL)

## De ce arhitectura asta (și nu una mai directă)

Există și o variantă „pură Cowork" a acestui skill (`contabilitate-lunara`), care s-a lovit de o limitare reală: sandbox-ul cloud în care rulează Cowork are un proxy de ieșire cu listă albă de domenii, care blochează accesul la `n8n.onlineleads.ro`. Din Claude Code, rulat local sau pe o mașină din rețeaua ta, acest blocaj nu există — shell-ul are acces de rețea real, ca orice terminal de pe mașina respectivă.

De asta arhitectura de aici deleagă către n8n tot ce înseamnă „vorbește cu un serviciu extern" (Gmail, FGO, OneDrive) — n8n are deja noduri native testate pentru toate astea, autentificare OAuth gestionată centralizat, și rulează recurent fără sesiune activă dacă vrei să-l automatizezi complet mai târziu. Claude Code rămâne responsabil pentru orchestrare (ce webhook chem, în ce ordine), validare (fișierul are sens? lipsește ceva?), și partea care cere judecată reală (parsarea extraselor, reconcilierea).

Regula de fond: **n8n face pașii determiniști pe API-uri stabile, Claude Code face pașii care cer citire și decizie.**

## Verificare inițială — acces la n8n

Înainte de orice, confirmă că poți atinge instanța n8n din acest mediu:

```bash
curl -s -o /dev/null -w "%{http_code}\n" https://n8n.onlineleads.ro
```

Dacă primești un cod HTTP (orice, chiar 401/404) înseamnă că rețeaua e ok. Dacă comanda eșuează cu eroare de conexiune/DNS, nu continua cu presupunerea că restul pașilor vor merge — verifică rețeaua (VPN/Tailscale către homelab, dacă n8n nu e expus public) înainte de orice altceva.

## Pas 0 — Stabilește luna țintă

Calculează luna calendaristică anterioară lunii curente și formatează-o ca `NN - NumeLună` (ex: `07 - Iulie`). Nume lunilor în română:
`01 - Ianuarie, 02 - Februarie, 03 - Martie, 04 - Aprilie, 05 - Mai, 06 - Iunie, 07 - Iulie, 08 - August, 09 - Septembrie, 10 - Octombrie, 11 - Noiembrie, 12 - Decembrie`

Confirmă cu utilizatorul dacă intenția e alta decât "luna trecută".

## Pas 1 — Creează structura de foldere (local)

```
NN - NumeLună/
├── Primite/
├── Emise/
└── Extrase/
```

Creează-o cu `mkdir -p` în directorul de lucru al proiectului (sau într-o locație pe care utilizatorul o indică). Dacă folderul există deja, nu-l suprascrie — verifică ce lipsește din fiecare subfolder înainte de a continua.

## Pas 2 — Extrase de cont Salt Bank, prin webhook n8n

Workflow-ul de referință construit și testat pentru asta: **`Gmail Attachment Fetch (on-demand)`** (n8n workflow id `MsXUPbK89qRsP5qs`, webhook path `gmail-attachment`). Dacă nu există încă în instanța n8n a utilizatorului, recreează-l — schema completă e în `references/n8n-workflow-gmail-attachment.md`.

1. Găsește `messageId`-ul emailului Salt Bank pentru luna țintă. Dacă ai acces la un MCP Gmail din Claude Code (posibil, dacă utilizatorul are conectorul configurat și acolo), folosește-l pentru căutare — altfel cere utilizatorului să-ți dea ID-ul mesajului sau să-ți confirme verbal că a găsit emailul corect (subiect: „Salt Business: extrasele de cont lunare – {Lună} {An}").
2. Publică (activează) workflow-ul n8n dacă nu e deja activ — necesar ca webhook-ul de producție să răspundă. **Reține să-l dezactivezi la final** (vezi Pas 2.5) — un webhook public permanent e o suprafață de atac inutilă dacă nu ai nevoie de el activ tot timpul.
3. Apelează webhook-ul:

```bash
curl -s -X POST "https://n8n.onlineleads.ro/webhook/gmail-attachment" \
  -H "X-API-KEY: $SALT_BANK_WEBHOOK_KEY" \
  -H "Content-Type: application/json" \
  -d '{"messageId": "<message-id-gasit>", "attachmentIndex": 0}' \
  -o "NN - NumeLună/Extrase_de_cont_NumeLună_An.zip" \
  -w "\nHTTP status: %{http_code}\nBytes: %{size_download}\n"
```

Nu scrie niciodată cheia `X-API-KEY` direct în script sau în output — citește-o dintr-o variabilă de mediu (`$SALT_BANK_WEBHOOK_KEY`) pe care utilizatorul o setează local, sau cere-i-o interactiv fără s-o afișezi înapoi în conversație.

4. Verifică răspunsul: `HTTP status` trebuie să fie 200 și `Bytes` trebuie să corespundă cu o mărime plauzibilă (zeci-sute de KB, nu 0 și nu câțiva bytes — un răspuns de câțiva bytes înseamnă de regulă un mesaj de eroare JSON, nu fișierul).
5. **Arhiva e probabil protejată cu parolă** (Salt Bank o setează implicit la ultimele 6 cifre din CNP-ul titularului). Cere parola utilizatorului interactiv — nu o salva niciodată în fișiere, variabile de mediu persistente, sau istoricul de shell. Dezarhivează local:

```bash
unzip -P "<parola>" "NN - NumeLună/Extrase_de_cont_NumeLună_An.zip" -d "NN - NumeLună/Extrase/"
```

6. Din conținutul dezarhivat, mută/păstrează în `Extrase/` **doar fișierele PDF**. Dacă există și CSV, mută-le într-un subfolder separat (ex: `Extrase/_csv_pentru_analiza/`) — sunt utile pentru Pasul 4, dar nu fac parte din livrabilul final către OneDrive.
7. Șterge arhiva ZIP originală și orice parolă rămasă în variabile shell temporare după ce ai terminat dezarhivarea.

### Pas 2.5 — Dezactivează webhook-ul (dacă l-ai activat la pasul 2)

Dacă workflow-ul nu era deja activ înainte să începi, dezactivează-l acum din n8n (API sau UI). Nu lăsa un webhook public activ „ca să fie mai rapid data viitoare" — costul de a-l reactiva la următoarea rulare lunară e nesemnificativ față de riscul unei suprafețe expuse permanent.

## Pas 3 — Facturi emise din FGO

FGO API e disponibil doar pe planurile GO Premium/Enterprise. Dacă utilizatorul e pe planul GO eFactura (fără API), acest pas rămâne **manual**: cere-i să descarce facturile din interfața web FGO (Facturi emise → filtru lună → descărcare) și să le pună în `NN - NumeLună/Emise/`.

Dacă la un moment dat contul are API activ, acest pas poate deveni un al doilea webhook n8n (HTTP Request → FGO API → listare + descărcare facturi emise în interval de date), simetric cu Pasul 2 — nu bloca restul pachetului în lipsa lui.

**Verificare:** compară numărul de facturi din folder cu ce arată FGO pentru acel filtru de lună.

## Pas 4 — Lista de plăți din extrase

Dacă ai CSV-uri din Pasul 2 (subfolderul `_csv_pentru_analiza/`), folosește-le ca sursă principală — sunt mult mai fiabile de parsat decât PDF (fără ambiguități de layout). Dacă ai doar PDF, extrage tranzacțiile de plată din fiecare.

Pentru fiecare plată, notează: furnizor/beneficiar, sumă, valută. Construiește un tabel (XLSX implicit, sau CSV dacă utilizatorul preferă) și salvează-l ca `NN - NumeLună/Plati NN - NumeLună.xlsx`.

Marchează explicit „verifică manual" orice rând ambiguu (nume trunchiat, format regional neclar de sumă) — nu inventa o valoare când textul sursă e neclar.

**Output dublu, obligatoriu:** fișierul XLSX e doar un pas intermediar, nu livrabilul final al acestui pas — tot conținutul listei de plăți (fiecare rând: dată, furnizor/beneficiar, sumă, valută) trebuie afișat **și direct în chat**, ca tabel, nu doar salvat în fișier. Utilizatorul are nevoie de listă vizibilă imediat ca să poată identifica și strânge facturile primite corespunzătoare, la Pasul 4.5.

## Pas 4.5 — Reconciliere cu facturile primite

Lista de plăți de la Pasul 4 nu e livrabilul final pentru `Primite/` — e punctul de plecare pentru a aduna facturile de la furnizori care corespund plăților identificate.

Utilizatorul poate trimite facturile de la furnizori oricând în cursul lunii, nu doar când rulează acest skill — le redirecționează (forward), **fără nicio editare**, către alias-ul `gogu.samsung+facturiprimite@gmail.com` (plus-addressing Gmail, livrează în aceeași cutie). Nu e nevoie de subiect special, nu e nevoie de label manual — un singur gest, forward și atât. Workflow-ul n8n recurent `Facturi Primite - Staging Sync` (activ permanent, vezi `references/n8n-workflow-facturi-staging.md`) le preia automat zilnic și le pune, neatinse, în folderul tampon OneDrive `Online Leads/Documente Societate/Facturi/_Facturi Primite (netriate)/` — **n8n nu analizează conținutul**, doar mută fișierul; toată verificarea de conținut e treaba ta, aici, la acest pas.

1. **Verifică întâi folderul tampon**, înainte să întrebi utilizatorul de ceva: listează conținutul lui (`folder/getChildren` pe OneDrive, id-ul e în referința de mai sus). Fiecare fișier are numele `AAAA-LL-ZZ_messageId_NumeOriginalAtasament.pdf` — data din nume e **data primirii emailului**, nu data facturii, iar numele original al atașamentului poate fi orice (generic sau informativ) — nu te baza pe numele fișierului pentru identificare.
2. **Deschide efectiv fiecare fișier găsit** (Read pe PDF, sau echivalent) ca să afli data reală a facturii, furnizorul, și suma — informația din numele fișierului nu e suficientă.
3. Pentru fiecare plată din tabelul de la Pasul 4 care ar trebui să aibă o factură de furnizor (exclude transferuri interne și taxe/buget de stat), caută printre facturile citite din tampon una a cărei dată/sumă/furnizor corespund plauzibil (data facturii precede de regulă plata cu până la ~30 de zile).
4. Pentru fiecare potrivire găsită: confirmă-o pe scurt în chat (sumă + furnizor), apoi **mută** fișierul (nu copiază) din folderul tampon în `NN - NumeLună/Primite/`, redenumindu-l curat (`Factura_Furnizor_AAAA-LL-ZZ.pdf`) — folosește operația `file/move` (nu `folder/move`) pe OneDrive, ca folderul tampon să rămână curat, cu doar facturile încă neconfirmate.
5. **Abia pentru plățile rămase neacoperite** după verificarea tamponului, cere utilizatorului să trimită factura corespunzătoare (fie prin forward către alias, pentru viitor, fie upload direct în chat pentru rezolvare imediată).
6. Actualizează fișierul `Plati NN - NumeLună.xlsx` cu o coloană/observație „Factura primita: da/nu" — sau raportează separat, în chat, orice plată încă neacoperită de o factură.
7. Nu bloca restul pachetului dacă utilizatorul nu are toate facturile primite la îndemână — semnalează explicit ce lipsește în verificarea finală, nu presupune că lipsa înseamnă „nu există".

## Pas 5 — Upload pe OneDrive, prin n8n

Folosește nodul OneDrive nativ dintr-un workflow n8n dedicat (configurat cu endpoint OAuth `/consumers/` pentru cont Microsoft personal — vezi `references/arhitectura-automatizare.md` pentru pașii de configurare completi dacă acel workflow nu există încă).

Calea țintă pe OneDrive (verifică mereu ortografia exactă navigând efectiv folderele existente înainte de a crea altele noi — vezi nota de mai jos):
```
Online Leads/Documente Societate/Facturi/<an calendaristic al lunii procesate>/NN - NumeLună/
```

**Atenție la ortografia exactă a folderelor existente.** La prima rulare a acestui skill, calea a fost scrisă greșit („Onlineleads/Documente societate/...", fără spațiu și cu literă mică) și a creat o structură paralelă, separată de arhiva reală de facturi a companiei (`Online Leads/Documente Societate/Facturi/`, cu spațiu și majusculă la Societate, deja existentă din 2018). OneDrive tratează numele de foldere ca fiind distincte dacă diferă chiar și printr-un spațiu sau o literă mare/mică — un „pare aceeași cale" nu e de ajuns. **Înainte să creezi orice folder pe calea de mai sus, navighează efectiv structura existentă** (folder/getChildren pornind de la rădăcină, pas cu pas) ca să confirmi ID-ul real al fiecărui nivel (`Online Leads` → `Documente Societate` → `Facturi` → `<an>`), în loc să presupui ortografia din memorie sau din acest fișier.

Dacă workflow-ul de upload OneDrive nu există încă, creează-l cu un webhook similar celui de la Pasul 2 (primește un path local sau conținut binar, îl scrie pe OneDrive prin nodul nativ, răspunde cu status de succes/eșec) — sau, dacă utilizatorul preferă, apelează-l direct din Claude Code cu tool-urile MCP n8n (`execute_workflow`) dacă acestea sunt disponibile în sesiunea de Claude Code (verifică cu `claude mcp list` sau echivalent dacă serverul n8n e configurat local).

**Nu lăsa acest webhook activ permanent** din același motiv ca la Pasul 2, dacă implementarea folosește un webhook public.

## Verificare finală

Înainte de a raporta pachetul ca gata, confirmă:

- Toate cele 3 subfoldere există și au conținut (dacă unul e gol, spune explicit de ce)
- Numărul de extrase PDF corespunde cu conturile bancare active
- Lista de plăți a fost afișată integral în chat, nu doar salvată în fișier
- Lista de plăți acoperă toate extrasele (nicio bancă/cont omis)
- Reconcilierea din Pasul 4.5: fiecare plată către un furnizor extern are (sau nu) o factură primită asociată — orice plată neacoperită e semnalată explicit, nu ignorată
- Facturile emise acoperă intervalul complet al lunii
- Folderul a ajuns pe OneDrive la calea corectă (`Online Leads/Documente Societate/Facturi/<an>/NN - NumeLună/`, verificată prin navigare efectivă, nu presupusă)
- Niciun webhook n8n folosit în acest proces a rămas activ/public inutil

Raportează un rezumat scurt: câte facturi primite/emise, câte extrase, câte plăți identificate, orice element marcat „verifică manual", și dacă ai lăsat vreun webhook activ (și de ce).

## Diferențe față de varianta Cowork a acestui skill

- Nu mai există limitarea de conector Gmail (Cowork nu poate descărca atașamente) — aici Claude Code poate folosi fie un MCP Gmail local dacă există, fie webhook-ul n8n direct.
- Nu mai există blocajul de proxy/listă albă de domenii — Claude Code local poate face `curl` direct către `n8n.onlineleads.ro`.
- Upload-ul OneDrive rămâne prin n8n în ambele variante (contul OneDrive e personal, nu organizațional, deci conectorul Microsoft 365 din Cowork nu funcționează oricum).
- Automatizarea completă (fără intervenție la fiecare rulare) devine mult mai realistă aici — odată ce workflow-urile n8n sunt stabile, acest skill poate fi invocat dintr-un cron job local care rulează `claude` cu acest skill, fără sesiune interactivă.
