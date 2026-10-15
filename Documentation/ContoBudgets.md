# Budget per conto

Un budget può riguardare tutti i conti del libro (`contoID == nil`, comportamento precedente) oppure un conto specifico dello stesso libro. Il campo opzionale è compatibile con i budget preesistenti. Un riferimento a un conto mancante non allarga mai il budget a tutti i conti.

Creazione e modifica verificano libro, conto e categorie: le categorie condivise di un conto non possono finire nei budget di un altro conto. I budget globali mantengono la possibilità di includere categorie di tutto il libro. Lo spostamento di un conto condiviso in un altro libro sposta anche i suoi budget. Il piano automatico del libro continua a gestire solo i propri budget globali.

Totali, transazioni di dettaglio, margine giornaliero, proiezioni, anteprime di nuova spesa e conferme remote applicano lo stesso ambito. Un'anteprima senza conto non attribuisce la spesa ai budget di un conto specifico.

## Previsione mensile

Attivando “Aggiungi budget e spese abituali”, i budget mensili attivi del conto selezionato sostituiscono lo storico di tutte le proprie categorie, incluse le sottocategorie coperte dal budget. I budget globali non vengono assegnati arbitrariamente a un conto. Quelli settimanali, trimestrali e annuali restano utilizzabili nella sezione Budget, senza ripartizioni mensili automatiche.

Per ogni budget: `residuo aggiuntivo = max(0, limite - spese registrate del mese - scadenze del mese già incluse nella previsione)`. Le scadenze sono ancora presenti nel totale degli impegni: la detrazione evita di aggiungerle due volte. Un budget su più categorie produce una sola quota residua, non una quota per categoria. Un superamento del limite non riduce altre scadenze o altri budget.

Le categorie non coperte da budget continuano a usare lo storico, se disponibile. Con storico non utilizzabile si mostrano esplicitamente solo i budget, senza inventare una base storica. Importi o categorie del budget non validi rendono il residuo indisponibile. Se più budget selezionati si sovrappongono, il totale con stima resta indisponibile finché si deselezionano quelli sovrapposti in “Categorie da includere”. Disattivare un budget dalla previsione non reinserisce automaticamente la stima storica delle stesse categorie.

Riserva, copertura, deficit e ripartizione tra persone usano tutti lo stesso residuo selezionato. Le preferenze di selezione restano locali per conto e valuta; limite, categorie e ambito del budget sono sincronizzati.

## Condivisione

L'esportazione di un conto include esclusivamente i budget con quel preciso `contoID`, riferimenti alle sue categorie condivise e allo stesso conto. I budget globali e di conti personali restano esclusi. Importazione e round trip rimappano il riferimento al conto nel namespace locale. Un payload di conto condiviso non può introdurre un budget globale o riferito ad altri conti.

Il protocollo esplicita `scope=book|conto` e il riferimento `conto`. Nei vecchi payload privi di ambito, i nuovi budget restano globali e l'ambito dei budget già esistenti viene preservato. La condivisione tra versioni precedenti che non supportano budget per conto richiede l'aggiornamento dell'app.

## Verifica

`BudgetAccountScopeTests` copre persistenza, ambito globale preesistente, filtro per conto, anteprime, rollback, sostituzione dello storico, detrazione di ricorrenti e occasionali, periodi futuri, storico assente, superamenti, sovrapposizioni, round trip condiviso, spostamento tra libri, eliminazione di un conto senza cancellare i budget delle controparti di trasferimento e rigetto di payload che allargano l'ambito. Test UI dedicati verificano salvataggio del conto nell'editor e sostituzione dello storico nella previsione.
