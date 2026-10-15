# Previsione del mese

Accesso: Calendario e timeline → Previsione del mese. Il selettore comprende solo i conti correnti attivi dei libri attualmente consultati, nella stessa valuta; carte di credito, risparmio, contanti, investimenti, altro e tipo sconosciuto sono esclusi. Il collegamento non appare se non ci sono conti correnti disponibili. Il calcolo usa un solo conto alla volta.

Il selettore del mese parte dal mese corrente e consente solo mesi futuri. La freccia indietro è disabilitata al mese corrente; un'apertura dal calendario su un mese passato viene riportata al presente, anche al ritorno dell'app in primo piano dopo un cambio mese.

## Importi e periodo

- **Ricorrenti residue:** occorrenze del mese ancora irrisolte, comprese quelle scadute. La serie originale non genera doppioni quando un'occorrenza è registrata, anche se cambia la data di pagamento. Le risoluzioni saltate sono escluse.
- **Occasionali programmate:** transazioni non ricorrenti già inserite con data futura. Nel modello corrente la data determina se un movimento è registrato: il passaggio della scadenza non costituisce prova del pagamento bancario.
- **Registrate:** spese con data non successiva all'istante del calcolo. Le occasionali con evidenza di programmazione e le non programmate sono sottoinsiemi separati. Non programmate non significa impreviste.
- **Totale ancora necessario:** per impostazione iniziale, impegni residui + margine di sicurezza scelto. L'opzione esplicita “Aggiungi la stima delle spese abituali” aggiunge le variabili residue; la scelta viene ricordata per conto e valuta. Senza stima, gli impegni noti restano quantificabili anche con storico insufficiente. Il servizio `necessary(includingVariables:)` usa la stessa scelta della schermata.
- **Totale del mese:** registrate + impegni residui, più le variabili residue solo se l'opzione è attiva. La riserva resta separata. Per il passato è il solo consuntivo registrato; le ricorrenze irrisolte sono mostrate a parte.
- Gli intervalli mensili includono l'inizio ed escludono l'inizio del mese successivo, secondo il calendario locale.

Ogni totale apre i movimenti che lo compongono o la base della stima, con accesso al dettaglio della transazione/serie originale.

Nel mese corrente, il primo messaggio riassume la copertura della base scelta e della riserva: “Il saldo basta”, “Coperto con le entrate previste”, “Serve aggiungere denaro” oppure “Copertura da verificare”. Il deficit considera le date, quindi un'entrata successiva non rende coperta una scadenza precedente. Il messaggio non garantisce la copertura di spese non incluse. Le voci analitiche di spese e liquidità sono raccolte in “Dettagli del calcolo”, chiuso all'apertura per ciascun conto.

## Stima delle variabili

La base è costituita dai tre mesi completi precedenti al mese corrente, anche consultando un mese futuro. Sono esclusi trasferimenti, ricorrenti/materializzazioni e occasionali con evidenza di programmazione. Si usano le singole categorie, così una fattura per visite o acqua non riduce la stima del supermercato solo perché condivide la macro categoria.

Ogni categoria richiede almeno tre spese in almeno due mesi. La base mensile è la mediana dei tre totali mensili, includendo i mesi senza spese: un singolo mese eccezionale non viene riproposto automaticamente. Per ciascuna categoria: `residuo = max(0, base abituale - variabili registrate del mese scelto - occasionali programmate della stessa categoria, anche già pagate)`.

Attivando le spese abituali, “Categorie da includere” permette di scegliere le singole categorie con storico sufficiente. La scelta è salvata localmente per conto e valuta e viene mantenuta cambiando mese; inizialmente sono tutte incluse. Escludere una categoria rimuove solo il suo residuo stimato: le scadenze programmate e le spese registrate restano nei totali. Copertura, riserva e ripartizione usano la stessa selezione. Per ogni categoria sono consultabili la media aritmetica dei tre mesi completi (mesi senza spese inclusi), i totali mensili e i movimenti storici; la media è distinta dalla mediana usata nella stima.

I pagamenti importati senza collegamento alla ricorrenza sono esclusi dalla stima quando combaciano per conto, singola categoria, importo e calendario con una serie attiva, con riscontri in almeno due mesi. Si accetta un pagamento per occorrenza, con tolleranza di tre giorni per periodicità mensile o più lunga, un giorno per settimanale/bisettimanale, zero per giornaliera. Questa è una deduzione usata solo dalla stima: non risolve scadenze e non modifica transazioni. Il dettaglio mostra i movimenti esclusi e il motivo.

Le categorie usate anche per entrate/apporti sul conto, o classificate come entrate, sono escluse dalla stima automatica e mostrate come da verificare. Non si deduce il significato finanziario dal nome della categoria. Questo conserva i giroconti esterni importati come spese nel registro e nel saldo, senza presentarli come consumi abituali.

Requisiti complessivi: un movimento registrato all'inizio della finestra o prima, almeno una categoria con tre spese in almeno due mesi e un registro aggiornato negli ultimi 14 giorni. Importi mancanti/non validi impediscono la stima quando influiscono sulla base o sulle detrazioni. La base disponibile rimane consultabile senza presentare una stima inventata. Non si stimano imprevisti futuri né stagionalità; le categorie escluse possono comunque generare spese future.

## Margine di sicurezza

I conti si scelgono direttamente con pulsanti visibili. La riserva è impostata dall'utente come percentuale della base scelta (impegni noti, eventualmente più stima), oppure come importo fisso nella valuta del conto. La scelta parte da zero e viene ricordata localmente per conto e valuta; percentuale e cifra fissa mantengono ciascuna il proprio valore.

La riserva non crea movimenti e non viene aggiunta al totale delle spese del mese. Il totale ancora necessario la include separatamente nel dettaglio. Nei mesi conclusi la riserva non viene applicata.

Con base incompleta, una percentuale non è quantificabile; un importo fisso è mostrabile ma non rende completo il fabbisogno. Input negativi, non numerici e calcoli non rappresentabili non producono un totale inventato. Gli importi sono arrotondati ai decimali della valuta.

Nel mese corrente, la copertura con riserva è `max(0, riserva - saldo minimo alle scadenze, variabili incluse + riserva - saldo finale programmato)`. Le variabili incluse valgono zero quando l'opzione è disattivata. Mantiene quindi la riserva anche prima di un'entrata successiva. Rimangono i limiti relativi alla tempistica giornaliera e alle variabili senza data. Con dati insufficienti per la base scelta o nei mesi passati/futuri la copertura completa con riserva non viene calcolata.

## Saldo e copertura

Il saldo di oggi comprende saldo iniziale e movimenti registrati del conto, inclusi i due versi dei trasferimenti e gli importi di destinazione per cambi valuta. La copertura è disponibile solo per il mese corrente e per conti correnti attivi, con importi validi e saldo iniziale noto.

Partendo dal saldo attuale, si applicano scadenze, entrate future esplicite e trasferimenti futuri programmati, per giorno. L'importo mancante alle scadenze è il massimo deficit del percorso. Le entrate ricorrenti scadute ancora irrisolte non sono disponibili finché non vengono registrate. Il saldo netto della stessa giornata non garantisce la sequenza intragiornaliera.

Il deficit con stima è il massimo tra deficit delle scadenze e deficit di fine mese dopo le variabili residue. Le variabili non hanno una data stimata: può servire liquidità prima. Non si inventano entrate o apporti. I trasferimenti sono separati da entrate e consumi.

Nei mesi passati/futuri si può consultare il saldo **attuale**, esplicitamente etichettato, ma non viene calcolata una copertura che lo presenti come saldo del mese scelto.

## Ripartizione dei versamenti

Nel mese corrente “Dividi quanto manca” ripartisce tra due persone il fabbisogno aggiuntivo della stessa copertura del riepilogo: considera saldo, scadenze, entrate e trasferimenti previsti, variabili solo se incluse e riserva scelta. Non ripartisce il totale delle spese già coperte. Con dati insufficienti non mostra quote inventate; con fabbisogno zero indica che non servono altri versamenti.

Si parte da metà ciascuno oppure si imposta una percentuale della prima persona tra 0 e 100. La seconda completa il 100%; il primo importo è arrotondato ai decimali della valuta e il secondo è la differenza rispetto al totale arrotondato, così non si perdono o aggiungono centesimi.

Quando la condivisione identifica esattamente due partecipanti si usano i loro nomi e si abilita inizialmente la ripartizione. La condivisione specifica del conto ha precedenza su quella del libro. In assenza di una coppia identificata, l'utente può attivare la ripartizione e indicare i due nomi. Le preferenze sono locali, distinte per conto e valuta; le percentuali dei partecipanti identificati sono legate ai loro ID in ordine stabile. Non si modificano transazioni, contributi già registrati o metadati di condivisione.

## Provenienza e compatibilità

`Transaction.scheduledOriginDate` è un campo opzionale. La creazione di un movimento futuro conserva la scadenza originale; l'editor la mantiene anche anticipando il pagamento, ripristinandola in caso di errore del salvataggio. Export/import dei libri condivisi trasportano il campo; un payload precedente che lo omette non cancella la provenienza locale. Per le righe precedenti senza il campo, solo `createdAt` anteriore al giorno della scadenza costituisce evidenza di programmazione. Altrimenti la distinzione storica resta priva di evidenza, senza ricostruzioni inventate.

Il campo opzionale è compatibile con i requisiti SwiftData/CloudKit. I test verificano persistenza in memoria e round-trip della condivisione; migrazione di archivi personali e consegna reale CloudKit tra dispositivi non sono provate da questi test.

## Verifiche

`MonthlyForecastTests` copre ambito per conto, deduplicazione, confini mensili, ricorrenze risolte/saltate, pagamento anticipato, trasferimenti con importo di destinazione, entrate successive alle scadenze, periodi passati/futuri, categorie e mesi senza spese, dati mancanti, storico insufficiente/vecchio e provenienza persistente/condivisa.

`MonthlyForecastUITests` usa esclusivamente `MonthlyForecastFixture`, in memoria, per selezione del conto, dettagli dello storico, navigazione dal mese corrente ai futuri con blocco dei mesi passati e leggibilità con tema scuro/testo accessibilità. Il flag della fixture disattiva le animazioni; il comportamento del vero Reduce Motion è ereditato da `financeNumericMotion`.

`MonthlySafetyMarginTests` verifica percentuale, cifra fissa, zero, valuta, input invalidi, base insufficiente e copertura prima delle entrate successive. Il test UI della riserva verifica entrambi i modi, aggiornamento del totale e mantenimento della scelta cambiando conto.

## Budget per conto

I budget mensili attivi del conto possono sostituire lo storico delle proprie categorie, selezionando “Aggiungi budget e spese abituali”. Il residuo aggiunto detrae sia le spese già registrate sia le scadenze già comprese negli impegni. Dettagli su ambito, sovrapposizioni, periodi supportati e condivisione: [Budget per conto](ContoBudgets.md).
