# Budget: transazioni del periodo

Direzione: proseguire il linguaggio attuale di Formi, con superfici salvia e albicocca, importi leggibili e controlli nativi. ENERGY 2 / RHYTHM 2 / MOTION 1. Il totale resta il punto focale; le spese vengono subito dopo, prima delle metriche secondarie.

## Verifica della modifica

- Elenco ottenuto dalle stesse regole del totale: categoria e sottocategorie, appartenenza al libro, periodo con fine esclusiva, sole uscite e deduplicazione.
- Le spese future già registrate sono incluse e identificate. Le ricorrenze non registrate non vengono generate.
- Ordinamento per data o importo, apertura nel dettaglio esistente della transazione, ritorno al budget e stato vuoto.
- Query SwiftData limitata alle uscite del periodo; righe in LazyVStack. Totale e proiezione nel dettaglio derivano dalla stessa query.
- Righe compatte come nei Movimenti: icona da 34 pt, descrizione in subheadline e seconda riga con data e conto. Area minima di 48 pt; menu con altezza minima di 44 pt. Intestazione adattabile con ViewThatFits e importo sotto ai dettagli alle dimensioni di accessibilità.
- Nessun nuovo asset di marca, animazione personalizzata o dipendenza.

## Gate della porzione modificata

Hard Gate: testi concreti; nessun link senza destinazione o controllo fittizio. Stato vuoto esplicito. Nessun caricamento asincrono introdotto. Le schermate iPhone in chiaro e scuro sono state ispezionate senza tagli o sovrapposizioni nell'elenco. I dati delle schermate sono una fixture di test in memoria, disponibile solo in DEBUG con argomento UITEST_BUDGET_DETAIL.

Purpose Gate: il gradiente già presente distingue lo stato del budget. Le superfici separano riepilogo e movimenti. Le icone riprendono le categorie reali; la freccia indica la navigazione. Nessuna decorazione aggiuntiva.

Liveliness: totale come punto focale, ritmi diversi per riepilogo e righe, accento del tema limitato ai controlli. Solo le transizioni native di navigazione e del menu.

Craftsmanship: le spese spiegano il totale; l'ordinamento per importo serve a individuare le uscite maggiori. Tutte le nuove azioni hanno un comportamento concreto. Riutilizzati dettaglio transazione, palette e componenti del prodotto.

## Evidenze e limiti

- FinanceCore: 3 test RecordedBudgetSpendingTests passati, inclusa la corrispondenza fra elenco e totale.
- Compilazione iOS Simulator e macOS completata.
- Percorsi UI chiaro e scuro passati su iPhone 17 Pro, iOS 26.5: budget, totale 130 EUR, ordinamento, dettaglio, ritorno, chiusura e budget vuoto. Risultati in /private/tmp/formi-budget-detail-qa-pass.xcresult (chiaro) e /private/tmp/formi-budget-detail-qa-dark.xcresult (scuro).
- Schermate: budget-light.png, budget-dark.png, budget-empty-light.png.
- iPad, dispositivo fisico, tastiera macOS e dimensioni di accessibilità non verificati visivamente in questa sessione.

Le prime esecuzioni hanno rilevato selettori del test troppo ampi, corretti con identificatori dei pulsanti specifici. La modifica UI non richiede cambi di schema o dati persistenti.

## Celle compatte

Aggiornate su richiesta prendendo a riferimento compactRow di TransactionCell. Compilazione e percorso UI chiaro nuovamente passati: /private/tmp/formi-budget-compact-qa.xcresult, 1 test passato. La categoria rimane disponibile nel dettaglio; la riga mostra descrizione, data, conto, importo e indicazione Futura quando necessaria. Font di accessibilità senza troncamento imposto e importo disposto sotto ai dettagli.
