# Audit delle performance di Formi

Verifica del 15 ottobre 2026 su macOS 27.0.1 arm64, Swift 6.4. Il codice contiene già ottimizzazioni utili; i prossimi interventi dovrebbero ridurre il lavoro ripetuto e gli oggetti caricati prima di aumentare le cache.

L'audit comprende lettura dei percorsi principali, benchmark sintetici Release e una lettura della memoria residente dei processi già aperti. Non certifica latenza su iPhone, frame persi, assenza di leak o costo delle sincronizzazioni CloudKit reali. La working copy contiene modifiche concorrenti alla previsione mensile: non sono state modificate da questo audit.

## Cosa funziona già

- `TodaySnapshotReader` e `BalanceSeriesReader` possiedono contesti di lettura separati e restituiscono valori. La Home e lo storico conservano lo snapshot, accorpano gli aggiornamenti e cancellano le richieste superate.
- `Transaction` ha indici singoli su data, tipo, conto sorgente, conto destinazione e categoria. La lista filtra nel database, pagina a 40 righe e usa un ordinamento secondario stabile.
- `LedgerCalculationCoordinator` condivide il lavoro tra lettori, confronta il contenuto effettivo e limita la cache a 32 voci e 50.000 riferimenti a transazioni. La cache persistita compatta lo storico oltre 128 KiB e limita il payload a 512 KiB per conto.
- Le scritture della sola cache non producono notifiche finanziarie locali. Corruzione, modifiche a parità di conteggio, cancellazioni, trasferimenti e maturazione dei movimenti futuri sono coperti da test esistenti.
- Gli allegati persistiti usano external storage. Le anteprime della Capture Inbox hanno una `NSCache` con costo massimo configurato di 24 MiB e 40 elementi. Questo limite non equivale a un limite rigido della RAM complessiva.
- `RecordedSpendingReport` raggruppa per categoria con dizionari: O(N + C log C), senza confrontare ogni transazione con tutte le altre. `RecordedFlowReport` accumula in una passata e risolve le gerarchie per categoria; con gerarchie basse il costo resta vicino a O(N + C log C). Non emergono motivi per memorizzare ogni singola somma.
- `RecurrenceSchedule.next` stima direttamente l'ordinale vicino alla data richiesta. L'espansione dipende dalle occorrenze prodotte nell'orizzonte, senza ripartire dal primo pagamento per ogni consultazione.

## Problemi da affrontare

### 1. La cache dei saldi mantiene un costo significativo anche quando viene riutilizzata

File: `Packages/FinanceCore/Sources/FinanceCore/Services/LedgerCalculationCoordinator.swift`, righe 35–65; `Services/LedgerCache.swift`, righe 150–186.

Ogni richiesta ricostruisce gli endpoint delle transazioni, le raggruppa e le ordina per UUID convertito in stringa nel comparatore. Il riuso in memoria resta O(N + somma(nᵢ log nᵢ)), con confronto finale O(N). Il riuso persistito serializza ogni sorgente, ordina le rappresentazioni e calcola il fingerprint: non evita il caricamento dello storico né il costo di validazione.

Prima: `rows.sorted { $0.id.uuidString < $1.id.uuidString }` a ogni richiesta.

Dopo proposto: confronto canonico senza conversioni ripetute, seguito da riuso per generazione dei dati condiviso tra lettori. Una generazione può evitare il lavoro solo se copre scritture locali, import, cancellazioni, cambi di scope, notifiche remote e maturazione delle date future. Non sostituire l'uguaglianza attuale con solo conteggio o timestamp.

Priorità alta; misurare separatamente cache fredda, riuso in memoria e riuso persistito.

### 2. Il grafico risparmi ricalcola tutta la storia per ogni campione

File: `Models/AccountBalanceSeries.swift`, righe 54–69; `Services/SavingsValuation.swift`, righe 34–77.

Per ciascuna data del grafico `SavingsValuation.value` rifiltra, riordina e raggruppa i movimenti, ricostruisce i confini temporali e ricalcola gli interessi dall'origine. Con P campioni, N movimenti, R tassi e Y confini annuali, un limite superiore è O(P × ((N + R + Y) log(N + R + Y) + (N + R + Y) × R)). Con R piccolo il costo dominante cresce circa come P × N log N.

Prima: `dates.sorted().map { SavingsValuation.value(..., at: $0) }`.

Dopo proposto: API che produce l'intera serie in una passata cronologica, ordinando movimenti, tassi, cambi d'anno e campioni una volta. Preservare ordine degli accrediti, interessi negativi, cambi di tasso e durata effettiva dell'anno. È un miglioramento algoritmico prima che un problema di caching.

Inoltre `FinanceWidgetBuilder` genera quattro periodi per libro. `WidgetBalanceSnapshot.make` chiama `AccountBalanceSeries.make`, che calcola anche le serie risparmi, ma poi ricostruisce le serie compatte senza `savingsCapital` e `savingsValue`. Questo lavoro viene scartato: rendere opzionale il calcolo degli interessi per questi consumatori.

Priorità alta per conti risparmio con storico lungo.

### 3. Calendario e previsione caricano tutte le transazioni e calcolano nel body

File: `Personal Finance/Views/FinanceCalendarView.swift`, righe 14–42 e 200–202; `Views/MonthlyForecastView.swift`, query e chiamata a `MonthlyForecastCalculator.build` nel body; `Analysis/MonthlyForecastHistory.swift`, righe 27–55.

Le query non filtrate tengono disponibile l'intero archivio, anche di libri estranei alla selezione. Cambiare giorno, filtro o stato della vista può ricostruire gli eventi. Il calendario cerca inoltre la transazione con `first(where:)` per ogni evento visibile: O(E × N) nel caso peggiore.

La previsione esegue il matching delle ricorrenti con una scansione della storia per ogni sorgente: O(R × H) prima dell'ordinamento dei candidati, con limite superiore O(R × H log H). È eseguito sul MainActor. Il fatto che la storia per la stima sia limitata temporalmente non limita il caricamento iniziale della query.

Prima: `@Query var transactions` e `transactions.first(where:)` per evento.

Dopo proposto: lettore con scope e finestra, snapshot dei risultati indicizzato per ID e calcolo su valori fuori dall'interfaccia. Raggruppare i candidati del matching per categoria e importo prima di confrontarli. Conservare le ricorrenti nate prima del mese e le occorrenze materializzate anche se spostate altrove: un semplice filtro sulla data perderebbe eventi validi.

Priorità alta per reattività dell'interfaccia; la latenza della previsione non è stata misurata in questo benchmark.

### 4. I widget moltiplicano scansioni e proiezioni dello stesso archivio

File: `Services/WidgetSnapshotReader.swift`, righe 13–23; `WidgetSnapshot.swift`, righe 65–137; `Models/WidgetBalanceSnapshot.swift`, metodo `make`.

Il lettore carica tutte le transazioni. Per ciascun libro il builder ripassa spese e ricorrenti, valuta i budget e costruisce quattro storici. Ogni storico ricrea snapshot e proiezioni; la proiezione viene costruita sia dalla serie sia dallo snapshot widget. Con L libri, B budget e N transazioni ci sono termini O(L × N) e O(B × N), oltre a ordinamenti, espansione ricorrenze e costo dei risparmi descritto sopra.

Prima: quattro costruzioni indipendenti a partire da tutti i modelli.

Dopo proposto: raggruppamento per conto/libro una volta, un insieme di valori condiviso, un'unica espansione fino all'orizzonte massimo e derivazione dei quattro periodi. Non limitare a 90 giorni le sorgenti necessarie al saldo di apertura. Valutare poi checkpoint di saldo verificati con delta successivi, mantenendo la ricostruibilità.

Priorità alta per CPU e picchi di memoria in import e refresh.

### 5. Il riepilogo della lista può annullare parte del beneficio della paginazione

File: `Services/TransactionListQuery.swift`, righe 53–72; `Views/TransactionListView.swift`, righe 666–685.

La prima pagina è limitata, ma ogni reload calcola sincronicamente il riepilogo di tutte le righe del periodo. `propertiesToFetch` riduce le colonne richieste; non elimina la materializzazione di M risultati né il ciclo O(M) sul MainActor. Lo scorrimento successivo accumula inoltre tutte le pagine già visitate. Il solo `fetchLimit` non garantisce memoria costante dell'intera schermata.

Prima: `summary = query.summary(in: modelContext)` prima della pagina.

Dopo proposto: caricare subito la pagina, calcolare il riepilogo con contesto separato e valori Sendable, riutilizzarlo fino alla successiva mutazione pertinente. Se M diventa grande, enumerare a batch per ridurre il picco. Valutare paginazione a cursore per offset elevati solo dopo una misura dedicata.

Priorità media, dipendente dalla dimensione del periodo.

### 6. Dettaglio conto e miniature hanno costi evitabili

File: `Models/Conto.swift`, righe 113–142; `Personal Finance/Views/FinanceContoDetailsView.swift`, righe 8–10; `Views/TransactionAttachments.swift`, metodo `preview`.

`balance` ripercorre le relazioni in entrata e uscita a ogni lettura: O(N). Il dettaglio ordina tutti i movimenti con `allTransactions` per mostrarne cinque: O(N log N), oltre al possibile caricamento delle relazioni.

Prima: `conto.allTransactions.filter(...).prefix(5)`.

Dopo proposto: query limitata e ordinata per i movimenti recenti; snapshot di saldo condiviso per intestazione e componenti collegati, con aggiornamento coerente dopo modifiche.

Le miniature degli allegati creano `UIImage(data:)` o `NSImage(data:)` dai dati originali nella vista. Il limite di 10 MiB del file compresso non limita il costo dei pixel decodificati: una RGBA da 4032 × 3024 richiede circa 46,5 MiB per il solo buffer, prima degli altri costi. È un esempio aritmetico, non un picco osservato.

Prima: immagine originale ridimensionata solo in fase di visualizzazione.

Dopo proposto: thumbnail ImageIO alla risoluzione effettiva di visualizzazione, generata fuori dal MainActor, e riuso della cache di anteprime già presente. Validare con cinque foto grandi e apertura/chiusura ripetuta dell'editor.

Priorità media per dettaglio conto; alta per picchi RAM con foto grandi.

### 7. La sincronizzazione condivisa materializza l'intero store

File: `Sharing/SharedBookImporter.swift`, righe 62–69; `Sharing/SharedBookExporter.swift`, fetch delle transazioni.

L'importer costruisce dizionari di tutti i libri, conti, categorie, transazioni, budget, obiettivi e allegati anche per uno scope piccolo. La complessità di caricamento e indicizzazione è O(N store + record remoti); l'accesso ai dizionari evita ricerche quadratiche, ma non il picco di oggetti. Gli allegati sono external storage: il fetch dei modelli non dimostra che tutti i blob siano già residenti.

Dopo proposto: fetch per identità remota e scope, caricando esplicitamente gli endpoint privati necessari alla verifica dei trasferimenti. Conservare tutte le verifiche di ownership e collisione; evitare di trasformare un'ottimizzazione in una perdita di isolamento dei libri.

Priorità media, da verificare con molte transazioni e import di piccole modifiche.

### 8. La ricerca dei saldi nel grafico è lineare

File: `Models/AccountBalanceSeries.swift`, metodi `balance(at:)` e `savingsAmount(at:)`; `Models/WidgetBalanceSnapshot.swift`, `totalBalances(at:)`.

`last(where:)` ricerca linearmente nella serie ordinata. La selezione interattiva del grafico ripete questa ricerca per conto; la somma su tutte le date del widget ha limite superiore O(D × somma(Pᵢ)), quadratico nel caso di una sola serie con D circa P. Nei widget la compattazione giornaliera e i quattro periodi limitano la dimensione, quindi questa non è automaticamente la prima causa di lentezza.

Dopo proposto: ricerca binaria O(log P) per selezioni isolate; fusione cronologica delle serie per ottenere tutti i totali senza ripartire a ogni data. Preservare apertura, confini inclusivi/esclusivi e passaggio tra storico e proiezione. Priorità bassa finché il profilo non la mostra sul percorso critico.

## Memoria e caching

La lettura di `ps` ha rilevato il processo Formi del simulatore con RSS 81.216 KiB, circa 79,3 MiB, e l'estensione widget con 60.224 KiB, circa 58,8 MiB. Sono processi distinti: la somma non misura la memoria del solo processo app. Build installata, scena e quantità dei dati non sono state identificate; il dato è una fotografia, non una baseline confrontabile con un rilascio futuro.

La lettura aggiuntiva con `vmmap -summary` non ha completato ed è stata interrotta terminando soltanto i processi di diagnostica avviati. Non è disponibile una ripartizione affidabile delle allocazioni né una verifica dei leak.

La cache dei saldi conserva copie di valori sorgente, storia e payload; i trasferimenti possono essere rappresentati sotto due conti. I limiti sulle voci e sui riferimenti non sono un budget in byte e non impediscono allocazioni temporanee superiori durante una richiesta grande. `FinanceDataChangeCenter` conserva inoltre mappe degli endpoint fino a 50.000 elementi per container e fino a quattro container. Non c'è evidenza di un leak, ma questa retention va inclusa nelle misure.

Non aumentare ora i limiti delle cache. Introdurre prima riuso dei risultati per scope/revisione e miniature limitate, eliminare i calcoli scartati e misurare byte trattenuti, allocazioni temporanee e rapporto tra hit e miss. Per la cache del ledger valutare un budget in byte e uno svuotamento su pressione memoria, senza affidarsi a cache per la correttezza contabile.

## Benchmark ripetibile

`Packages/FinanceCore/Tests/FinanceCoreTests/PerformanceAuditTests.swift` contiene una prova opt-in senza soglie temporali dipendenti dall'hardware. Genera dati sintetici, verifica i risultati e non apre il database personale né CloudKit. Il test SwiftData usa un database temporaneo su disco.

```sh
FORMI_PERFORMANCE_AUDIT=1 CLANG_MODULE_CACHE_PATH=/private/tmp/formi-audit-clang \
swift test --disable-sandbox --package-path Packages/FinanceCore \
  --scratch-path /private/tmp/formi-performance-build -c release \
  --filter PerformanceAuditTests
```

Il costo del ledger comprende raggruppamento, validazione e preparazione, non le query dell'app. Le tre ripetizioni del riuso servono a stimare una mediana. I valori `processPeakMiB` sono il massimo RSS cumulativo del processo di test: includono runtime, store e allocazioni precedenti e non rappresentano né la RAM della sola cache né la memoria del processo Formi. Le query sono ripetute con contesti nuovi nello stesso store e con cache SQLite/OS potenzialmente calda; la scrittura dei dati sintetici non è cronometrata.

Prima esecuzione completata: benchmark passato, 39,804 secondi incluso il popolamento dello store. Base Git `a6f530d` con modifiche locali concorrenti; non è una misura di una revisione pulita. Per il ledger freddo e persistito è riportato un singolo campione; il riuso in memoria e le query mostrano la mediana di tre campioni.

| Operazione | Dimensione | Tempo |
| --- | ---: | ---: |
| Ledger freddo | 1.000 movimenti | 16,7 ms |
| Ledger riusato in memoria | 1.000 movimenti | 3,6 ms |
| Ledger persistito validato | 1.000 movimenti | 9,1 ms |
| Ledger freddo | 10.000 movimenti | 149,0 ms |
| Ledger riusato in memoria | 10.000 movimenti | 33,3 ms |
| Ledger persistito validato | 10.000 movimenti | 45,0 ms |
| Ledger freddo | 50.000 movimenti | 843,3 ms |
| Ledger riusato in memoria | 50.000 movimenti | 204,2 ms |
| Ledger persistito validato | 50.000 movimenti | 256,7 ms |
| Valutazione risparmi a 365 date | 100 movimenti | 57,4 ms |
| Valutazione risparmi a 365 date | 1.000 movimenti | 589,0 ms |
| Prima pagina di 40 righe | store da 10.000 righe | 2,7 ms |
| Riepilogo del periodo, 8.785 risultati | store da 10.000 righe | 258,9 ms |

La pagina è circa 98 volte più veloce del riepilogo in questa configurazione. È il riepilogo sincrono a rendere il percorso iniziale poco scalabile, anche se la lista è paginata. Il ledger riusato evita molto lavoro, ma 204 ms a 50.000 righe mostrano che l'hit non è trascurabile. Questa misura non implica un blocco del thread UI: il coordinatore è un actor separato.

Il massimo RSS cumulativo del processo di test sale da circa 51 MiB nella fase da 1.000 righe a 72 MiB nella fase da 10.000 e 159,5 MiB nella fase da 50.000. Rimane lo stesso massimo nelle fasi successive: non è possibile attribuire 159,5 MiB alle query o al grafico risparmi. La cache persistita occupa rispettivamente 80.617, 35.412 e 175.875 byte, con 1.000, 418 e 2.084 punti: il secondo caso è più piccolo perché viene compattato per giorno.

Log integrale locale: `/private/tmp/formi-performance-baseline.log`. La compilazione iniziale nella sandbox si è fermata alla generazione dSYM; l'esecuzione con i permessi necessari ha compilato e superato il benchmark. Restano warning preesistenti, inclusi quelli di concorrenza dei test CloudKit.

Verifica aggiuntiva sul binario Release già compilato: 42 test in 7 suite superati per cache, coordinatore, lettore Home, valutazione risparmi e query della lista. Log: `/private/tmp/formi-performance-regressions.log`. Non è stata eseguita l'intera suite dell'app né una sessione UI sul dispositivo.

## Verifica runtime ancora necessaria

Eseguire in Release su iPhone una sequenza ripetibile con dataset sintetici piccoli e grandi: avvio Home, cambio libro, apertura Analisi, calendario e cambio mese, grafico risparmi annuale, editor con cinque foto, import e modifica/cancellazione di una transazione. Confrontare prima e dopo con lo stesso dataset e dispositivo.

Registrare Time Profiler/SwiftUI, footprint fisico e picco, allocazioni dopo ripetuti cicli di apertura/chiusura, fault/fetch delle relazioni, durata dei refresh e quantità di righe materializzate. Aggiungere signpost per fetch, mapping, ledger, proiezioni, stima e pubblicazione widget. Separare primo avvio, cache calda e invalidazione locale/remota. Il benchmark sintetico non sostituisce questa misura.

Ordine consigliato: eliminare valutazioni risparmi scartate dai widget; serie interessi in una passata; ridurre il costo del riuso ledger; snapshot di calendario/previsione e riepilogo lista fuori dal MainActor; miniature limitate; quindi query di sync e aggregati incrementali, guidati dai profili.

## Ottimizzazioni applicate

La serie interessi usa ora `SavingsValuation.values`: ordina sorgenti e date una volta e riutilizza gli stati ai confini reali di movimenti, tassi e anni. Ogni campione intermedio calcola l'interesse a partire dall'ultimo confine, senza dividerne l'accumulo in base alle date del grafico. Questo conserva le operazioni Decimal della funzione `value`, mantenuta come riferimento indipendente. I confronti esatti includono tre fusi orari, anno bisestile, movimenti e tassi nello stesso istante, interessi positivi/negativi, date non ordinate e duplicate e variazione della densità dei campioni.

I widget preparano snapshot e proiezioni una volta per i quattro periodi e per i libri. Ogni periodo mantiene il proprio confine finale esclusivo; l'orizzonte massimo considera anche una settimana che attraversa la fine dell'anno. Le serie degli interessi, scartate dal formato del widget, non vengono più calcolate. I test confrontano il risultato condiviso con i periodi costruiti singolarmente.

Il coordinatore ledger ordina i byte degli UUID invece di convertirli in stringhe nel comparatore. Restano invariati uguaglianza completa delle sorgenti, fingerprint persistiti, invalidazione e limiti della cache. Il test verifica anche payload identici e riuso con ordine di input diverso.

Il riepilogo della lista passa a un reader actor con contesto proprio. La prima pagina può essere visualizzata mentre il totale viene calcolato, mostrando un caricamento esplicito. Query e revisione impediscono alle risposte superate di sostituire i nuovi totali. Con modifiche non salvate nel contesto UI viene conservato il calcolo originale sullo stesso contesto, senza salvare o escludere tali dati. La paginazione procede indipendentemente dal caricamento del riepilogo.

Le miniature degli allegati riutilizzano il renderer ImageIO in background e la cache esistente: l'immagine originale viene mantenuta per documento e OCR, mentre la vista decodifica soltanto l'anteprima ridotta. Il test usa una foto sintetica da 4032 × 3024 e verifica una preview da 256 × 192 e dati originali invariati.

Il calendario limita la query ai conti selezionati e indicizza le transazioni per ID per il dettaglio del giorno. Il matching della previsione raggruppa la storia per categoria prima di confrontare i candidati delle ricorrenti, mantenendo ordine e regole di abbinamento.

Gli snapshot completi di calendario/previsione e le query di sincronizzazione sono affrontati nel secondo intervento descritto sotto. Il saldo nel dettaglio conto resta un candidato da misurare prima di introdurre un altro snapshot; la ricerca dei punti nei grafici è ottimizzata nel secondo intervento. Non sono stati aggiunti indici, migrazioni, cache incrementali persistenti o aumenti dei budget di memoria senza nuove misure.

## Risultati dopo le ottimizzazioni

Verifica su copia temporanea coerente in `/private/tmp/formi-optimization-snapshot`, necessaria perché il lavoro concorrente sulla previsione aveva aggiornato i test durante la compilazione del modulo. Gli undici file sorgente ottimizzati sono stati confrontati con quelli della working copy. La build iOS della working copy è riuscita; suite e controlli nel simulatore usano la copia coerente.

| Operazione | Prima | Dopo | Confronto |
| --- | ---: | ---: | --- |
| Interessi a 365 date, 1.000 movimenti | 647,7 ms | 4,9 ms | Riferimento e nuova API nella stessa esecuzione, circa 132 volte più veloce |
| Interessi a 365 date, 100 movimenti | 82,2 ms | 1,2 ms | Riferimento e nuova API nella stessa esecuzione |
| Riuso ledger, 10.000 movimenti | 33,3 ms | 11,3 ms | Mediane di tre campioni, prima dall'audit iniziale |
| Riuso ledger, 50.000 movimenti | 204,2 ms | 100,7 ms | Mediane di tre campioni, circa metà tempo |

Il benchmark isolato è passato in 30,702 secondi. Il riferimento della serie interessi è la funzione originale ancora presente; la nuova API produce i valori di tutte le date. Per il ledger le misure provengono da esecuzioni distinte sulla stessa macchina con altre attività in corso: le percentuali non sono una garanzia di latenza su dispositivo.

Ledger freddo a 50.000 movimenti: 835,8 ms; riuso persistito: 298,7 ms. Questi percorsi non beneficiano della sola sostituzione del comparatore nel coordinatore. Il riepilogo da 8.785 righe rimane O(M), mediana 257,9 ms, mentre la pagina ha mediana 2,1 ms. Il beneficio della modifica alla lista è spostare il riepilogo dal MainActor e liberare il contesto di lettura dopo il risultato, non trasformare l'aggregazione in O(1).

Il massimo RSS cumulativo del benchmark è circa 160 MiB, sostanzialmente lo stesso dell'audit iniziale. Non viene dichiarata una riduzione della RAM complessiva dell'app: il test delle miniature dimostra il limite dei pixel decodificati, mentre footprint e picchi dell'app su iPhone richiedono ancora Instruments.

Validazione completata: 656 test FinanceCore in 108 suite; benchmark Release separato; due test allegati nel simulatore, inclusa la riduzione di una foto grande senza modifica dei dati originali; due UI test per calendario e navigazione grafico/lista con riepilogo asincrono. I confronti Decimal sono esatti, senza tolleranza numerica. Per la paginazione il totale appena disponibile torna a determinare la fine dell'elenco, evitando una pagina aggiuntiva quando il numero di righe è un multiplo di 40.

Log: `/private/tmp/formi-optimization-snapshot-tests.log`, `/private/tmp/formi-optimization-benchmark.log`, `/private/tmp/formi-optimization-ui-tests.log`. Risultati del simulatore: `/private/tmp/formi-optimization-verification.xcresult`.

L'ultima rifinitura della paginazione è stata ricompilata e il test UI grafico/lista è stato ripetuto con successo. Log: `/private/tmp/formi-optimization-pagination-tests.log`; risultati: `/private/tmp/formi-optimization-pagination-verification.xcresult`. Confronto finale: tutti gli undici file sorgente ottimizzati coincidono con la copia verificata.


## Snapshot e sincronizzazione: secondo intervento

Calendario e previsione usano reader actor con ModelContext proprio e restituiscono esclusivamente valori Sendable. La UI conserva l'ultimo snapshot della selezione corrente; cambio conto/mese, cancellazione e revisione impediscono la pubblicazione di risposte superate. I refresh locali sono limitati ai conti interessati, con aggiornamenti anche dopo sync, cambio giorno/fuso, riattivazione e scadenza degli eventi. Un controllo periodico attivo recupera eventuali notifiche mancanti. Gli errori offrono un nuovo tentativo. Le modifiche non salvate vengono lette dal contesto UI, senza forzare salvataggi.

Il calendario prepara eventi e raggruppamenti per le quattro combinazioni calendario/timeline e tutte le operazioni/sole spese una volta per snapshot. Cambio giorno, filtro e scorrimento riutilizzano questi valori. La query conserva anche le occorrenze materializzate fuori mese necessarie a sopprimere duplicati. I modelli per navigazione e stile vengono caricati solo per gli eventi visualizzati; la timeline indicizza per UUID invece di cercare ogni transazione per ogni riga.

La previsione legge lo storico del solo conto selezionato, con categorie prefetched, risoluzioni delle sue ricorrenti e budget attivi del conto. Lo storico completo del conto resta necessario per saldo, provenienza, stime e freschezza: non viene troncato arbitrariamente. I calcolatori esistenti possono eseguire sull'actor proprietario del contesto, senza cambiare le operazioni numeriche. La cache è in memoria e limitata allo snapshot corrente, senza nuovi dati persistenti.

Export e import condivisi interrogano conti e identità coinvolti e i dipendenti necessari a verificare le cancellazioni, inclusi quelli fuori libro. Restano i fallback per collegamenti legacy senza UUID denormalizzati e le verifiche dei trasferimenti privati. La rilevazione dei duplicati globali è conservata tramite proiezione delle sole identità a batch di 512: resta O(N) e non è una query limitata al solo libro. I dizionari completi sono invece circoscritti. La verifica delle tombstone usa insiemi indicizzati invece di ripetere scansioni dei record per ogni figlio.

Validazione FinanceCore Release su copia coerente `/private/tmp/formi-planning-snapshot`: 668 test in 111 suite superati. I nuovi confronti verificano l'uguaglianza esatta degli snapshot rispetto ai calcolatori originali per mesi passati/presenti/futuri, tutte le presentazioni calendario, ricorrenze spostate/saltate/materializzate, modifiche e cancellazioni, budget, categorie escluse e modifiche non salvate. I test sync verificano equivalenza dell'export, UUID duplicati estranei al libro e protezione di ricorrenze/budget privati durante cancellazioni. Log: `/private/tmp/formi-planning-all-tests.log`.

Benchmark sintetico Release, singola esecuzione sul Mac sotto carico, 2.501 transazioni di cui 501 nel conto selezionato e note da 2 KiB:

| Percorso | Riferimento | Nuovo | Limite del confronto |
| --- | ---: | ---: | --- |
| Calendario, 20 ricostruzioni vs snapshot + 20 letture | 1.521,9 ms | 57,9 ms | Circa 26 volte per questa sequenza; il nuovo include il fetch iniziale |
| Previsione | 359,7 ms | 478,4 ms | Riferimento con righe già caricate; nuovo include fetch e calcolo. Non misura un'accelerazione del calcolo |
| Indice globale transazioni vs identità + modelli selezionati | 1.299,8 ms | 1.108,4 ms | Una misura sintetica, non un ciclo CloudKit completo |

Nel percorso sync i modelli completi selezionati scendono da 2.501 a 501 (-80%); la scansione delle identità rimane globale. Il picco RSS cumulativo del processo sale nelle fasi successive da circa 94,5 a 116 MiB e non dimostra una riduzione di memoria dell'app. Il test conserva più contesti per confrontare vecchio e nuovo percorso. Non sono stati misurati footprint, leak o fluidità su iPhone. Log: `/private/tmp/formi-planning-benchmark.log`; benchmark opt-in `PerformanceAuditTests.planningAndSharingQueries` con `FORMI_PERFORMANCE_AUDIT=1`.


La selezione dei punti nelle serie ordinate usa ora un upper bound binario O(log P), conservando l'ultimo punto a timestamp uguale, il fallback iniziale e la scelta tra storico e proiezione. I totali widget percorrono cronologicamente le serie: O(D log D + somma(Pᵢ) + S × D), dove S è il numero di conti e D le date richieste. L'ordine di somma dei conti a ogni data rimane quello originale, preservando le operazioni Decimal. `BalanceSeriesLookupTests` confronta i valori esatti con il precedente riferimento lineare, includendo date duplicate, serie vuote, campioni prima/dopo i confini e proiezioni assenti.


Verifica UI della versione finale compilata: superati i cinque casi per selezione conto/dettagli/mesi, budget del conto, tema scuro con testo grande, ripartizione con riserva e categorie della stima. La sessione è stata interrotta durante l'avvio dell'automazione del sesto caso; non c'è un esito finale per i casi rimanenti. I due casi calendario/timeline e il cambio rapido conto/mese erano passati nelle esecuzioni precedenti. Non viene dichiarata superata l'intera suite UI. Log dell'ultima esecuzione: `/private/tmp/formi-planning-ui-complete.log`.

La correzione degli identificatori mantiene quelli dei singoli controlli senza applicarne uno al contenitore dello snapshot. Nei test gli interruttori vicini al bordo vengono portati in vista e azionati sul controllo, verificandone lo stato. Il primo confronto dei totali widget includeva erroneamente gli UUID casuali dei punti creati da due esecuzioni indipendenti: date e importi risultavano uguali. Il test ora confronta esattamente questi due campi.


Verifica finale FinanceCore Release: **672 test in 112 suite superati**, inclusi i confronti esatti della ricerca binaria e dei totali cronologici e la protezione del budget esterno collegato al conto cancellato. Log: `/private/tmp/formi-planning-core-verified.log`. I 17 file sorgente/test direttamente coinvolti sono stati confrontati con la copia verificata; nessuna differenza. `git diff --check` superato. Il confronto con la working copy riguarda questi file, non tutte le modifiche concorrenti del progetto.
