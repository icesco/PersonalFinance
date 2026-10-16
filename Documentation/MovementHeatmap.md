# Mappa dei movimenti

Accesso da Analisi, sotto l'andamento del saldo. La cella contiene un'anteprima reale del calendario del mese, nella modalità Uscite. La schermata completa permette di scegliere un singolo conto o tutti quelli inclusi nell'ambito di Analisi, cambiare mese e misura, selezionare un giorno e aprire il dettaglio originale di un movimento.

## Regole dei dati

- Il mese usa intervalli di calendario con fine esclusiva e rispetta il fuso orario, anche al cambio dell'ora.
- Sono inclusi solo i movimenti registrati con data non successiva all'istante di lettura. Non si generano occorrenze virtuali delle ricorrenze.
- Le uscite appartengono al conto di origine, le entrate al conto di destinazione. La sola presenza nell'altro estremo non le include.
- Il netto è entrate meno uscite, non il saldo disponibile. Importi negativi già presenti nel registro conservano il loro significato, ad esempio un rimborso riduce le uscite.
- I trasferimenti sono elencati una sola volta nella vista aggregata e nei singoli conti coinvolti, ma non contribuiscono ai totali. Un trasferimento entrante da un'altra valuta usa l'importo di destinazione, se registrato.
- Le valute dei libri restano separate. I conti richiesti ma non disponibili non ampliano mai l'ambito. I conti archiviati restano consultabili se inclusi nell'ambito iniziale.
- I vecchi movimenti senza identificativi denormalizzati usano le relazioni come fallback.
- Un importo mancante o non numerico rende non disponibile il relativo totale; non viene sostituito con uno zero finanziario.
- Le bande sono fisse nella valuta mostrata: fino a 25, fino a 100, fino a 500, oltre 500. Il cambio conto non altera la scala.

## Interfaccia e aggiornamento

Le card, i titoli, il caricamento e i colori provengono dai componenti di Formi. Entrate e flussi positivi usano il colore del margine; uscite e flussi negativi quello delle spese. Il significato è accompagnato da importi, etichette e simboli per distinguere giorni vuoti, netto zero e soli trasferimenti.

La selezione della misura sopravvive ai cambi di mese e conto. I pulsanti mese hanno un'area di 48 punti; i giorni sono alti almeno 52 punti. L'anteprima è un unico accesso, senza pulsanti del giorno annidati nel link.

Il reader crea un contesto separato e restituisce DTO senza modelli SwiftData. Le letture sono limitate al mese; vengono ricaricate dopo modifiche locali, eventi di sincronizzazione, ritorno in primo piano, cambio giorno/fuso e controllo periodico. Le risposte obsolete sono scartate. In presenza di modifiche non salvate viene usato il contesto del chiamante senza salvare o scartare quelle modifiche.

## Verifiche

- `MovementHeatmapTests`: ambito e verso dei flussi, trasferimenti e duplicati, giorni vuoti/compensati, esclusione del futuro e delle occorrenze virtuali, DST, rimborsi, importi non validi, fallback legacy, valute, conti archiviati e lettura delle modifiche non salvate.
- `MovementHeatmapUITests`: anteprima caricata, tre modalità, scelta conto e vista aggregata, conservazione della misura, giorni e mesi vuoti, trasferimenti, apertura del movimento e ritorno, aspetto chiaro e scuro.

Nessuna modifica allo schema persistente o al widget.

## Esito del 16 ottobre 2026

- FinanceCore: 713 test passati in 116 suite nel checkout corrente, inclusi i quattro nuovi test di dominio.
- Simulatore iPhone 18 Pro: entrambi i test UI della heatmap passati, zero errori; anteprima, modalità, scope, navigazione e stati vuoti verificati in chiaro e scuro.
- Compilazione macOS con Xcode 27.1: `BUILD SUCCEEDED`.
- `git diff --check`: passato.

### Delivery Gate antislop

- PASS Hard Gate: interfaccia eseguita su simulatore, controlli percorsi nei test UI, nessun contenuto inventato nel prodotto; fixture e catture esplicitamente illustrative. Nessun cambiamento ai dati reali per la verifica.
- PASS Purpose Gate: calendario reale come anteprima, icona calendario per l'accesso, colori semantici e superfici dei componenti già presenti nell'app. Nessun asset o trattamento grafico aggiuntivo.
- PASS Liveliness: intensità 2 / ritmo 2 / movimento 1; calendario come punto focale, importo del mese e dettaglio su livelli distinti, nessuna animazione continua. Le animazioni di ingresso restano quelle condivise dall'app.
- PASS Craftsmanship: quattro catture UI esaminate (anteprima e dettaglio, chiaro e scuro), testo leggibile e nessun taglio osservato; legenda e segni affiancano i colori. Il mese ha pulsanti da 48 punti e i giorni un'altezza minima di 52 punti.

La prova UI riguarda il simulatore iPhone; non equivale a una verifica su dispositivo fisico o di sincronizzazione CloudKit live.
