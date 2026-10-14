# Previsione del mese

Accesso: Calendario e timeline → Previsione del mese. Il selettore comprende i conti attivi dei libri attualmente consultati, nella stessa valuta; il calcolo usa un solo conto alla volta.

## Importi e periodo

- **Ricorrenti residue:** occorrenze del mese ancora irrisolte, comprese quelle scadute. La serie originale non genera doppioni quando un'occorrenza è registrata, anche se cambia la data di pagamento. Le risoluzioni saltate sono escluse.
- **Occasionali programmate:** transazioni non ricorrenti già inserite con data futura. Nel modello corrente la data determina se un movimento è registrato: il passaggio della scadenza non costituisce prova del pagamento bancario.
- **Registrate:** spese con data non successiva all'istante del calcolo. Le occasionali con evidenza di programmazione e le non programmate sono sottoinsiemi separati. Non programmate non significa impreviste.
- **Totale ancora necessario:** impegni residui + variabili residue stimate + margine di sicurezza scelto. Il valore del servizio `remaining` rimane la base senza riserva. Non disponibile quando manca una stima affidabile o un importo necessario.
- **Totale del mese:** registrate + ancora necessario nel mese corrente/futuro. Per il passato è il solo consuntivo registrato; le ricorrenze irrisolte sono mostrate a parte.
- Gli intervalli mensili includono l'inizio ed escludono l'inizio del mese successivo, secondo il calendario locale.

Ogni totale apre i movimenti che lo compongono o la base della stima, con accesso al dettaglio della transazione/serie originale.

## Stima delle variabili

La base è costituita dai tre mesi completi precedenti al mese corrente, anche consultando un mese futuro. Sono esclusi trasferimenti, ricorrenti/materializzazioni e occasionali con evidenza di programmazione. Raggruppamento per macro categoria; somma divisa per tre, includendo mesi senza spese, arrotondata a due decimali.

Per ciascuna categoria: `residuo = max(0, media - variabili registrate del mese scelto - occasionali programmate del mese scelto, anche già pagate)`. Le programmate di categorie differenti non riducono la stima di questa categoria.

Requisiti: un movimento registrato all'inizio della finestra o prima, almeno cinque spese variabili in almeno due mesi della finestra e un registro aggiornato negli ultimi 14 giorni. Importi mancanti/non validi impediscono la stima quando influiscono sulla base o sulle detrazioni. La base disponibile rimane consultabile senza presentare una stima inventata. Non si stimano imprevisti futuri né stagionalità.

## Margine di sicurezza

I conti si scelgono direttamente con pulsanti visibili. La riserva è impostata dall'utente come percentuale del necessario residuo senza riserva, oppure come importo fisso nella valuta del conto. La scelta parte da zero e viene ricordata localmente per conto e valuta; percentuale e cifra fissa mantengono ciascuna il proprio valore.

La riserva non crea movimenti e non viene aggiunta al totale delle spese del mese. Il totale ancora necessario la include separatamente nel dettaglio. Nei mesi conclusi la riserva non viene applicata.

Con base incompleta, una percentuale non è quantificabile; un importo fisso è mostrabile ma non rende completo il fabbisogno. Input negativi, non numerici e calcoli non rappresentabili non producono un totale inventato. Gli importi sono arrotondati ai decimali della valuta.

Nel mese corrente, la copertura con riserva è `max(0, riserva - saldo minimo alle scadenze, variabili residue + riserva - saldo finale programmato)`. Mantiene quindi la riserva anche prima di un'entrata successiva. Rimangono i limiti relativi alla tempistica giornaliera e alle variabili senza data. Con dati insufficienti o nei mesi passati/futuri la copertura completa con riserva non viene calcolata.

## Saldo e copertura

Il saldo di oggi comprende saldo iniziale e movimenti registrati del conto, inclusi i due versi dei trasferimenti e gli importi di destinazione per cambi valuta. La copertura è disponibile solo per il mese corrente e per corrente/risparmio/contanti, con importi validi e saldo iniziale noto. Carte di credito e investimenti richiedono una verifica separata della liquidità.

Partendo dal saldo attuale, si applicano scadenze, entrate future esplicite e trasferimenti futuri programmati, per giorno. L'importo mancante alle scadenze è il massimo deficit del percorso. Le entrate ricorrenti scadute ancora irrisolte non sono disponibili finché non vengono registrate. Il saldo netto della stessa giornata non garantisce la sequenza intragiornaliera.

Il deficit con stima è il massimo tra deficit delle scadenze e deficit di fine mese dopo le variabili residue. Le variabili non hanno una data stimata: può servire liquidità prima. Non si inventano entrate o apporti. I trasferimenti sono separati da entrate e consumi.

Nei mesi passati/futuri si può consultare il saldo **attuale**, esplicitamente etichettato, ma non viene calcolata una copertura che lo presenti come saldo del mese scelto.

## Provenienza e compatibilità

`Transaction.scheduledOriginDate` è un campo opzionale. La creazione di un movimento futuro conserva la scadenza originale; l'editor la mantiene anche anticipando il pagamento, ripristinandola in caso di errore del salvataggio. Export/import dei libri condivisi trasportano il campo; un payload precedente che lo omette non cancella la provenienza locale. Per le righe precedenti senza il campo, solo `createdAt` anteriore al giorno della scadenza costituisce evidenza di programmazione. Altrimenti la distinzione storica resta priva di evidenza, senza ricostruzioni inventate.

Il campo opzionale è compatibile con i requisiti SwiftData/CloudKit. I test verificano persistenza in memoria e round-trip della condivisione; migrazione di archivi personali e consegna reale CloudKit tra dispositivi non sono provate da questi test.

## Verifiche

`MonthlyForecastTests` copre ambito per conto, deduplicazione, confini mensili, ricorrenze risolte/saltate, pagamento anticipato, trasferimenti con importo di destinazione, entrate successive alle scadenze, periodi passati/futuri, categorie e mesi senza spese, dati mancanti, storico insufficiente/vecchio e provenienza persistente/condivisa.

`MonthlyForecastUITests` usa esclusivamente `MonthlyForecastFixture`, in memoria, per selezione del conto, dettagli dello storico, mesi passati/futuri e leggibilità con tema scuro/testo accessibilità. Il flag della fixture disattiva le animazioni; il comportamento del vero Reduce Motion è ereditato da `financeNumericMotion`.

`MonthlySafetyMarginTests` verifica percentuale, cifra fissa, zero, valuta, input invalidi, base insufficiente e copertura prima delle entrate successive. Il test UI della riserva verifica entrambi i modi, aggiornamento del totale e mantenimento della scelta cambiando conto.
