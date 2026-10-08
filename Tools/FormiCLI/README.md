# Formi CLI

La CLI `formi` viene compilata e inclusa nella versione macOS dell'app a
`Formi.app/Contents/MacOS/formi` (il nome del file `.app` può variare).
In Formi, apri **Impostazioni → Integrazioni → CLI per AI** e premi **Installa CLI…**.
La finestra di macOS permette di scegliere la cartella in cui installare il comando,
ad esempio in `~/.local/bin` o in una cartella scrivibile già nel tuo PATH.
Viene creato un piccolo launcher shell che esegue la CLI Swift inclusa nell'app:
non serve installare Swift. Il launcher usa la versione aggiornata della CLI
quando aggiorni Formi nella stessa posizione; se sposti l'app, reinstallalo.
Il launcher apre i file JSON indicati e li passa alla CLI tramite stdin, conservando
le opzioni e i percorsi con spazi. Il binario incluso nell’app usa una sandbox
autonoma: per invocarlo direttamente con un import, usa `import - < movimenti.json`.
Un launcher già installato da Formi viene aggiornato; un file `formi` diverso
non viene sovrascritto. L'annullamento della finestra non scrive alcun file. Nessuna installazione avviene
all'avvio, durante gli aggiornamenti o quando abiliti l'accesso ai dati.

Dopo l'installazione, abilita l'accesso e copia le istruzioni per il tuo assistente.
Se la cartella scelta non è nel PATH, usa **Copia comando PATH**.
Il comando `export PATH=…` vale per la sessione corrente; per renderlo permanente
aggiungilo al file di configurazione della tua shell. Formi non modifica il PATH
o i file della shell. Puoi anche usare la CLI inclusa nell'app tramite il percorso
completo, senza installare il launcher.

## Aggiornamenti e copie Debug/Release

Il comando installato è `formi` nelle build Release e `formi-debug` nelle build Debug:
possono stare nella stessa cartella senza sostituirsi. Ogni launcher richiama
il percorso della copia dell'app che lo ha installato e verifica la configurazione.
Se aggiorni l'app nella stessa posizione, la nuova CLI viene usata alla successiva
invocazione, senza reinstallare il launcher. Non vengono eseguite installazioni
automatiche. Se sposti l'app, premi di nuovo **Installa CLI…** nella copia desiderata.
Se una build di un altro tipo sostituisce l'app nello stesso percorso, il launcher
rifiuta il comando prima di inviare movimenti. L'app verifica a sua volta percorso
e configurazione di destinazione prima di leggere o scrivere i dati.

`formi info` (o `formi-debug info`) mostra configurazione, percorso dell'app,
versione e build dell'app, versione della CLI e del protocollo. Questi nomi separano
le copie a cui inviare i comandi; non creano database separati: il progetto usa ancora
gli stessi bundle identifier e App Group per Debug e Release.

## Istruzioni per AI

`formi ai-help` (anche `formi --help --ai`) descrive il flusso completo:
verifica della copia dell'app, selezione di UUID reali, anteprima, autorizzazione
prima di `--yes`, gestione dei duplicati, retry dopo timeout e limiti supportati.
`formi --help` elenca i comandi e `formi schema` descrive i dati JSON.
Le istruzioni guidano l'assistente; le validazioni dell'app impongono importi,
selezioni, idempotenza e scrittura atomica. `--yes` esprime l'autorizzazione del
chiamante: la CLI non può verificare che l'assistente abbia ottenuto una conferma umana.
Negli esempi seguenti sostituisci `formi` con `formi-debug` per una build Debug.

## Comandi

```sh
formi --help
formi schema
formi accounts
formi categories --book UUID_DEL_LIBRO

# Una spesa: anteprima, senza scrittura.
formi add --account UUID_DEL_CONTO --category UUID_DELLA_CATEGORIA \
  --amount 25.50 --currency EUR --date 2026-10-08 \
  --description 'Supermercato' --request-id UUID_STABILE

# Salvataggio: ripeti gli stessi parametri aggiungendo --yes.
formi add --account UUID_DEL_CONTO --category UUID_DELLA_CATEGORIA \
  --amount 25.50 --currency EUR --date 2026-10-08 \
  --description 'Supermercato' --request-id UUID_STABILE --yes

# Più movimenti, oppure un singolo oggetto JSON.
formi preview movimenti.json
formi import movimenti.json --yes
formi import - --yes < movimenti.json
```

Esempio di lotto (sostituisci gli UUID con quelli restituiti dai comandi di lettura):

```json
[
  {
    "requestID": "5D7B0B90-4D21-4D90-9E5D-C99B55FDC001",
    "accountID": "00000000-0000-0000-0000-000000000001",
    "categoryID": "00000000-0000-0000-0000-000000000002",
    "type": "expense",
    "amount": "25.50",
    "currency": "EUR",
    "date": "2026-10-08",
    "description": "Supermercato"
  },
  {
    "requestID": "5D7B0B90-4D21-4D90-9E5D-C99B55FDC002",
    "accountID": "00000000-0000-0000-0000-000000000001",
    "type": "income",
    "amount": "100.00",
    "currency": "EUR",
    "date": "2026-10-08",
    "description": "Rimborso"
  }
]
```

Tutte le risposte operative sono JSON; `--json` è accettato ma facoltativo.
Un errore restituisce `ok: false` ed exit code 1. Il successo restituisce
`ok: true`; `result.saved` distingue un'anteprima da un salvataggio.
`accounts` restituisce anche il fuso orario usato per le date e `writable`.
Gli importi sono stringhe decimali positive con punto, nella valuta del libro,
senza conversione implicita. Categoria e descrizione sono facoltative.
`add` usa la data odierna e `expense` se non specificati; per una singola entrata
usa `--type income`. Il formato JSON richiede una data e un tipo espliciti.

## Categorie: creazione e modifica

`categories --book UUID --include-archived` elenca anche categorie archiviate,
con `parentID` (omesso per le principali), `name`, `type`, `color`, `icon`, `active`
e `updatedAt`. `revisions` contiene il token della gerarchia per ciascun libro.
La gerarchia segue i due livelli dell'app: principali e sottocategorie.

```sh
# Anteprima creazione: UUID_STABILE è nuovo, generato una sola volta.
formi category-create --book UUID_LIBRO --name 'Sport' \
  --parent UUID_PRINCIPALE --color '#2F7A72' --icon figure.run \
  --request-id UUID_STABILE

# Ripeti gli stessi argomenti con il token result.revision dell'anteprima.
formi category-create --book UUID_LIBRO --name 'Sport' \
  --parent UUID_PRINCIPALE --color '#2F7A72' --icon figure.run \
  --request-id UUID_STABILE --revision TOKEN_ANTEPRIMA --yes

# Sposta e rinomina una sottocategoria; anche qui il primo comando è anteprima.
formi category-update --book UUID_LIBRO --category UUID_CATEGORIA \
  --parent UUID_NUOVA_PRINCIPALE --name 'Attività sportive' \
  --request-id UUID_NUOVA_OPERAZIONE

# Promuovi a principale, modifica tipo o archivia/riattiva.
formi category-update --book UUID_LIBRO --category UUID_CATEGORIA \
  --parent none --type both --active true --request-id UUID_NUOVA_OPERAZIONE
```

I campi omessi in modifica restano invariati. Il nome deve avere 1–200 caratteri,
il colore è `#RRGGBB`, l'icona un SF Symbol disponibile sul Mac, il tipo
`expense|income|both`, lo stato `--active true|false`. Gli identificatori, le date
tecniche e il libro di appartenenza sono gestiti dall'app e non sono modificabili.
`--parent none` rende principale; `--parent UUID` crea/sposta sotto una principale
dello stesso libro. Per rendere una principale sottocategoria, sposta prima tutti
i suoi figli, anche archiviati. Nomi uguali fra fratelli sono rifiutati anche se
archiviati, per evitare selezioni ambigue.

Le sottocategorie ereditano il tipo del genitore. Modificare il tipo di una
principale aggiorna anche i figli; movimenti incompatibili, inclusi quelli
programmati, impediscono l'operazione. L'archiviazione di una principale archivia
anche i figli. La riattivazione della principale lascia i figli archiviati:
riattivali singolarmente dopo aver riattivato il genitore. Non c'è eliminazione
definitiva. Identificatori e collegamenti a movimenti e budget vengono conservati;
spostare un figlio cambia naturalmente i raggruppamenti per categoria principale.

`result.changes` mostra tutti i valori `before`/`after`, inclusi i figli coinvolti.
Il comando senza `--yes` non scrive né categorie né ricevute. Per salvare, ripeti
gli stessi argomenti con `--revision` restituita dall'anteprima e `--yes`.
Se la gerarchia è cambiata, la CLI rifiuta il salvataggio: rigenera l'anteprima e
verifica di nuovo gli effetti. Ogni modifica viene salvata in una sola operazione.

Conserva `--request-id`, campi e `--revision` invariati sui retry. Le ricevute
persistenti impediscono duplicati e la riapplicazione di modifiche già eseguite,
anche se poi l'utente cambia o elimina la categoria. `alreadyRecorded: true`
segnala la precedente esecuzione e `changes` è vuoto: rileggi `categories` per
lo stato attuale. Un requestID già usato con dati diversi viene rifiutato. Per
una nuova operazione genera un nuovo UUID. Vale anche il blocco dei libri condivisi.

## Integrità dei dati

- `add` e `import` mostrano un'anteprima finché non viene passato `--yes`.
- Un lotto contiene da 1 a 500 movimenti e viene salvato in un'unica operazione:
  un errore su una riga impedisce il salvataggio di tutto il lotto.
- Conserva `requestID` e tutti i dati invariati nei tentativi successivi. Un
  timeout non prova che il salvataggio non sia avvenuto. Le ricevute persistenti
  impediscono di ricreare un movimento già inserito, anche se poi viene eliminato.
- `add` genera un requestID se omesso e lo restituisce nell'anteprima. Per
  automazioni e tentativi successivi, passalo esplicitamente fin dal primo comando.
- Stesso conto, giorno, tipo, importo e descrizione vengono segnalati come possibile
  duplicato, anche all'interno del lotto. `--allow-duplicates --yes` permette
  inserimenti identici intenzionali con requestID diversi.
- Sono supportate spese ed entrate nei libri personali. Trasferimenti, ricorrenze,
  allegati e scritture nei libri condivisi non sono inclusi in questa versione.

## Collegamento locale

Apri la copia corretta di Formi prima di usare i comandi sui dati. La CLI non avvia
l'app, non la porta in primo piano e non crea finestre. Se l'app è chiusa, restituisce
subito un errore. `info`, `schema`, `ai-help` e `--help` funzionano anche ad app chiusa.
La CLI segnala la richiesta con una notifica distribuita indirizzata al percorso e
alla configurazione dell'app. La notifica contiene soltanto l'UUID casuale, senza
`userInfo`, per rispettare la sandbox macOS.
La richiesta e la risposta passano su una pasteboard macOS dedicata a un UUID
casuale, distinta dagli appunti dell'utente; viene rilasciata alla fine del comando.
Non viene aperta una porta di rete e la CLI non apre il database SwiftData. Un unico
ricevitore resta attivo anche dopo la chiusura delle finestre. Le chiamate vengono
elaborate in sequenza sul main actor dell'app con il container attualmente in uso;
oltre 32 richieste in corso restituisce `app_busy` senza accumulare altre operazioni.
Come altre interfacce di automazione locale, una volta abilitata la CLI può essere
usata dai processi dell'utente: concedi l'accesso soltanto agli assistenti scelti.
Il blocco privacy e la disattivazione della CLI vengono verificati anche dopo
l'attesa dell'avvio dell'app. La sincronizzazione iCloud resta gestita da Formi;
il successo del comando attesta il salvataggio locale, non la consegna cloud.

La build Mac include un eseguibile per le architetture richieste da Xcode,
firmato con l'identità dell'app quando la firma è abilitata. La distribuzione
App Store e la notarizzazione richiedono una verifica separata sul prodotto firmato.
