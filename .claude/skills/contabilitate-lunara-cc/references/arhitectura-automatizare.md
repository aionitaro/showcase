# Arhitectura de automatizare — Cowork vs Claude Code vs n8n vs mix

## Constatare din test live (2026-08-20) — Cowork nu poate scoate fișiere binare din Gmail sau din n8n

Testat direct, nu ipotetic. Concluzie: **pasul Gmail → arhivă ZIP disponibilă în Cowork nu poate fi automatizat integral din acest mediu**, din două motive independente, ambele confirmate:

1. **Conectorul Gmail din Cowork nu descarcă atașamente.** `get_thread`/`get_message` întorc doar metadate (nume fișier, tip MIME, ID intern) — niciun tool din acest connector nu întoarce bytes-ii. Verificat explicit în lista de tool-uri disponibile.
2. **n8n ca ocolire nu funcționează din acest mediu, din alt motiv.** Am construit un workflow n8n dedicat (`Gmail Attachment Fetch (on-demand)`, id `MsXUPbK89qRsP5qs`) — Webhook → Gmail `message.get` (`downloadAttachments: true`) → Respond to Webhook (binary). Execuția manuală prin tool-ul MCP `execute_workflow` a reușit (a descărcat corect arhiva, 142 kB). Problema: instanța n8n self-hosted stochează binarele pe disk (`filesystem-v2`), nu inline în JSON-ul de execuție — deci tool-ul `get_workflow_execution` nu poate extrage bytes-ii, indiferent de configurație. Singura cale de a scoate fișierul e prin răspunsul HTTP al webhook-ului, ceea ce necesită publicarea lui (expunere pe internet) și un apel HTTP din sandbox-ul Cowork. Acel apel eșuează la nivel de proxy (403 Forbidden) — sandbox-ul Cowork are o listă albă de domenii permise pentru trafic de ieșire prin Bash, și `n8n.onlineleads.ro` nu e pe ea. Nu e o problemă de configurare n8n sau de autentificare — cererea nici nu ajunge la server.

**Implicație practică:** indiferent cât de bine e construit workflow-ul n8n, Cowork nu poate extrage rezultatul lui binar înapoi în conversație, pentru că sandbox-ul nu poate ieși către domeniul respectiv. Singura rută rămasă e ca fișierul să intre în Cowork ca upload direct de la utilizator (atașat în chat) — nu prin nicio formă de fetch automat din acest mediu.

**Ce ar putea debloca asta în viitor** (netestat, doar ipoteze de investigat separat, nu de presupus ca funcționale):
- Whitelist-area domeniului `n8n.onlineleads.ro` în politica de rețea a sandbox-ului Cowork — ține de Anthropic/infrastructura Cowork, nu de ceva configurabil din sesiune.
- Un serviciu tunel pe un domeniu deja whitelistat (ex: un subdomeniu găzduit pe un provider ale cărui domenii sunt pe lista albă) — mai mult efort, negarantat, tot presupune expunere publică.
- Rularea acestui pas dintr-un mediu care poate atinge n8n.onlineleads.ro (Claude Code local, sau un alt agent cu acces de rețea nerestricționat).

## De aceea există varianta „contabilitate-lunara-cc" pentru Claude Code

Acest fișier de arhitectură e comun ambelor variante ale skill-ului (identic, copiat). Diferența practică:

- **Varianta Cowork** (`contabilitate-lunara`): din cauza blocajului de mai sus, Pasul 2 (extrase Salt Bank) rămâne cu upload manual al arhivei de către utilizator direct în chat — Cowork nu poate face fetch automat din Gmail/n8n.
- **Varianta Claude Code** (`contabilitate-lunara-cc`, acest skill): rulează local sau pe o mașină din rețeaua utilizatorului, deci `curl` către `n8n.onlineleads.ro` funcționează normal, fără proxy care blochează. Pasul 2 poate folosi efectiv workflow-ul `Gmail Attachment Fetch (on-demand)` din `references/n8n-workflow-gmail-attachment.md`, apelat direct prin HTTP — descărcarea devine complet automată, fără intervenție manuală de upload.

Ambele variante păstrează n8n ca „mâini" pentru operațiile pe servicii externe (Gmail, FGO când va avea API, OneDrive) — diferă doar cine poate efectiv atinge acele endpoint-uri n8n din mediul lui de execuție.

## Ce diferă de fapt

Cele trei opțiuni nu se exclud — fac lucruri diferite bine, și fluxul descris (Gmail → FGO → parsare → OneDrive) are pași cu naturi diferite:

- **Pași determiniști pe API-uri stabile**: Gmail search+download, apel FGO API, upload OneDrive. Input/output previzibile, nu necesită judecată.
- **Pași care necesită judecată**: parsarea extraselor (nume de furnizor ambigue, format regional de sumă), verificarea finală (lipsește ceva? pare greșit ceva?).

Regula generală: **motoarele de workflow (n8n) sunt mai bune la primul tip, un agent LLM (Claude) e mai bun la al doilea.**

## Opțiunea A — n8n pur

Avantaje: rulează recurent fără sesiune activă, cost previzibil (per execuție, nu per token de conversație), noduri gata făcute pentru Gmail, HTTP Request (pentru FGO API) și Microsoft OneDrive/SharePoint.

Dezavantaje: parsarea extraselor de cont (Pasul 4) e fragilă în n8n dacă formatul PDF-ului variază — ai nevoie fie de reguli regex rigide (se rup la orice schimbare de format Salt Bank), fie de un nod AI în workflow (posibil, dar atunci pierzi simplitatea "totul e determinist").

Recomandat dacă: formatul extraselor Salt Bank e stabil de multă vreme și ești dispus să menții reguli de parsare.

## Opțiunea B — Claude Cowork/Code pur, la cerere

Avantaje: un singur loc unde ceri "fă pachetul pentru luna trecută" și primești rezultatul, cu verificare de bun-simț la fiecare pas (dacă un extras lipsește, Claude întreabă în loc să trimită un pachet gol). Ușor de ajustat din mers dacă un furnizor apare cu nume diferite în extrase.

Dezavantaje: necesită o sesiune activă (manuală sau programată) — nu "doar rulează la fundal" fără nimeni să inițieze. Cost per rulare mai mare decât un workflow n8n echivalent, pentru că fiecare pas trece prin raționament LLM.

Recomandat dacă: vrei control și verificare la fiecare pachet lunar, sau formatul documentelor variază suficient încât regulile fixe din n8n s-ar rupe des.

## Opțiunea C — Mix (recomandat pentru acest caz)

Împarte pe natura pasului, nu pe tot fluxul:

1. **n8n** pentru partea 100% determinstă și recurentă: trigger lunar (ex: în ziua 1 a lunii) → caută email Salt Bank → dezarhivează → salvează PDF-urile în Extrase → apelează FGO API pentru facturile emise ale lunii anterioare → salvează în Emise → creează structura de foldere dacă nu există.
2. **Claude (acest skill)** pentru partea care cere judecată: citește extrasele deja descărcate de n8n, extrage lista de plăți cu atenție la ambiguități, face verificarea finală de sanitate (lipsuri, numerotare), și doar după ce pachetul e validat, declanșează sau confirmă upload-ul pe OneDrive.
3. Punctul de legătură: n8n poate să notifice (email/Slack/Telegram) "pachetul pentru NN - Lună e pregătit local, rulează verificarea" — iar utilizatorul sau un trigger programat pornește o sesiune Claude care preia de acolo.

Avantaje: partea ieftină și stabilă rulează singură fără cost de conversație; partea care beneficiază de judecată umană-simulată rămâne la Claude. Riscul de eroare silențioasă (pachet trimis incomplet la contabilitate) scade, pentru că verificarea finală rămâne la un agent care poate spune "stai, lipsește ceva" în loc doar să execute pași.

Dezavantaje: mai multe piese de întreținut (un workflow n8n + un skill Claude), și necesită ca cele două să fie sincronizate dacă structura de foldere se schimbă vreodată.

## Ce lipsește azi ca mix-ul C să funcționeze end-to-end

- **Cheie API FGO**: trebuie generată din panoul FGO (Integrări → API) și stocată ca credențial (în n8n ca și credential, sau accesibilă sesiunii Claude).
- **OneDrive — nu prin conectorul Claude Microsoft 365.** Contul OneDrive al proiectului este un cont Microsoft **personal**, nu organizațional. Conectorul Microsoft 365 din directorul de conectori Claude e construit pentru autentificare Entra ID de tip organizațional (work/school account) și respinge conturile personale — deci acea rută e închisă pentru acest caz, indiferent de cât de mult ai vrea upload-ul automat direct din Claude. Soluția e nodul OneDrive nativ din n8n (vezi secțiunea dedicată mai jos).
- **Workflow n8n existent**: există deja un workflow parțial pentru automatizarea extraselor Salt Bank (Gmail → ZIP → PDF → OneDrive) — de extins cu partea FGO API în loc de reconstruit de la zero.

## OneDrive personal prin n8n — configurare

Nodul `Microsoft OneDrive` din n8n folosește OAuth2 prin Microsoft Entra ID. Implicit, endpoint-ul `/common/` acceptă teoretic ambele tipuri de cont (personal și organizațional), dar în practică generează erori de autentificare inconsecvente pentru conturi strict personale — motiv pentru care comunitatea n8n recomandă forțarea explicită a endpoint-ului pentru consumatori.

**Pași de configurare** (presupunând că App Registration din Azure există deja — vezi nota de mai jos dacă nu):

1. În n8n, la credențialele folosite de nodul OneDrive (tip `Microsoft OAuth2 API` sau credențialul dedicat OneDrive), editează manual câmpurile de endpoint:
   - **Authorization URL**: `https://login.microsoftonline.com/consumers/oauth2/v2.0/authorize`
   - **Access Token URL**: `https://login.microsoftonline.com/consumers/oauth2/v2.0/token`
   - **Scope**: include cel puțin `Files.ReadWrite offline_access` (offline_access e necesar ca token-ul de refresh să funcționeze fără reautentificare manuală repetată)
2. Client ID / Client Secret rămân cele din App Registration-ul Azure existent — nu e nevoie de o aplicație nouă doar pentru schimbarea endpoint-ului, atâta timp cât aplicația permite deja conturi personale (**Supported account types** = "Personal Microsoft accounts" sau "Accounts in any organizational directory and personal Microsoft accounts", verificabil în Azure Portal → App registrations → aplicația respectivă → Authentication).
3. Reconectează credențialul (butonul de "Connect"/"Sign in") — va cere autentificare cu contul Microsoft personal; token-ul de refresh rezultat ar trebui să dureze fără reautentificare manuală atâta timp cât workflow-ul rulează periodic (Microsoft expiră refresh token-urile neutilizate după ~90 de zile de inactivitate, deci o rulare lunară e sub acest prag).
4. Testează cu o operație simplă (ex: listare foldere în rădăcina OneDrive) înainte de a lega nodul de restul workflow-ului.

**Dacă App Registration-ul existent nu permite conturi personale** (verifici la pasul 2 de mai sus): în Azure Portal, pe aceeași aplicație, la **Authentication**, schimbă "Supported account types" ca să includă conturile personale — nu necesită o aplicație nouă, doar o modificare de configurare pe cea existentă.

**Alternativă dacă nodul nativ tot dă probleme:** un nod `HTTP Request` care apelează direct Microsoft Graph API (`https://graph.microsoft.com/v1.0/me/drive/root:/path/to/file:/content`) cu același token OAuth — mai multă muncă de configurare inițială, dar elimină orice comportament specific nodului OneDrive care ar putea să nu respecte corect endpoint-ul `/consumers/`.

## Recomandare practică de secvențiere

Nu construi tot mix-ul deodată. Ordinea cu cel mai bun raport efort/beneficiu:

1. Rulează manual acest skill 1-2 luni ca să validezi că pașii și formatul de output (structura de foldere, lista de plăți) sunt exact ce vrea contabilitatea — corectează skill-ul pe parcurs.
2. Odată stabil, mută partea Gmail+FGO+foldere în n8n (extinzând workflow-ul existent), păstrând Claude doar pentru parsarea extraselor și verificarea finală.
3. Abia la final, dacă tot procesul s-a dovedit stabil pe 3+ luni, ia în calcul eliminarea completă a intervenției umane.
