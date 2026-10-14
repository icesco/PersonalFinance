# Condivisione di un singolo conto

Dal dettaglio del conto si apre **Condivisione del conto**. L'invito usa la stessa gestione privata iCloud già disponibile per i libri, con permesso di modifica. Non è possibile sovrapporre la condivisione dell'intero libro e quella di un conto: bisogna prima interrompere quella esistente. Più conti dello stesso libro possono avere condivisioni e invitati distinti.

Durante l'accettazione, il destinatario sceglie un libro personale nella stessa valuta oppure crea un nuovo libro con il nome desiderato. Si inserisce lo stesso conto, senza copiarlo. Il contenitore di ricezione viene eliminato soltanto se vuoto e riconosciuto come temporaneo; eventuali dati aggiunti dall'utente vengono preservati. Se si sceglie più tardi, l'invito resta disponibile per completare la destinazione. È ancora possibile spostare successivamente il conto dalla sua schermata Condivisione.

## Dati e privacy

Il trasporto esistente mantiene una zona per condivisione e un record radice di tipo `book`. Per il singolo conto, la zona usa il prefisso `FormiConto-` e l'UUID del conto, la radice dichiara `shareKind = conto` e referenzia l'unico `sharedConto`. `SharedBookMembership.localContoID` limita sia l'esportazione del proprietario sia quella del partecipante. La radice non contiene nome, identificatori o piano finanziario del libro privato.

Il conto ha un elenco dedicato di categorie, identificato localmente da `Category.sharedContoID`. Alla condivisione, le categorie già usate dai suoi movimenti e i relativi antenati vengono copiate in questo elenco e i soli movimenti del conto vengono ricollegati alle copie. Categorie personali, movimenti personali e budget preesistenti conservano le loro identità. Si esporta l'intero elenco dedicato, comprese categorie non ancora usate o archiviate. In importazione il perimetro viene rimappato al conto locale del partecipante. Budget, obiettivi e altri conti del libro sono esclusi. I metadati privati del conto (descrizione, identificatore esterno e impronta di riconciliazione) restano locali.

Un trasferimento conserva un solo oggetto locale collegato a entrambi i conti. La proiezione remota contiene soltanto il lato del conto condiviso, l'importo nella valuta di quel conto, le date e l'attribuzione. Nome del conto privato, note, allegati, posizione, valuta e importo del lato privato e ricorrenza privata non vengono esportati.

Una correzione remota di importo, data o persone aggiorna lo stesso trasferimento locale senza scollegare il lato privato. Per i trasferimenti con `destinationAmount`, una correzione del credito lascia invariato l'addebito privato. La cancellazione del movimento elimina il trasferimento locale collegato e il relativo allegato privato. La cancellazione dell'intero conto resta bloccata finché la condivisione è attiva.

L'importazione verifica che il perimetro non venga ampliato, che il lato privato non venga ricollegato dal remoto e che l'attribuzione sia valida; errori applicativi annullano l'intera importazione.

Le zone dei conti e le relative chiavi di appartenenza sono distinte da quelle dei libri. Le versioni precedenti non riconoscono il prefisso dei nuovi inviti e non possono usare i metadati del conto per esportare un libro privato verso la zona condivisa. Entrambi i partecipanti devono aggiornare Formi per usare questa funzionalità.

## Persone e versamenti

Ogni movimento dispone di autore iniziale, ultimo autore di modifica, assegnatario facoltativo e contribuente facoltativo. Gli autori usano l'identità iCloud disponibile localmente; non si inventa un autore per i dati precedenti o quando l'identità è sconosciuta. Il nome mostrato può essere impostato nella condivisione. I partecipanti accettati vengono letti dal CKShare; l'attribuzione è metadato descrittivo e non concede permessi.

Il contribuente è distinto dall'autore: Marco può registrare un versamento di Anna. Nei nuovi trasferimenti inseriti dall'interfaccia viene proposto l'utente corrente, con possibilità di cambiarlo o rimuoverlo. Le ricorrenze registrate ereditano assegnatario e contribuente.

Il riepilogo mensile del conto somma i trasferimenti in ingresso effettivamente registrati fino a oggi, usando l'importo accreditato. Esclude entrate ordinarie, spese, trasferimenti in uscita, movimenti futuri e ricorrenze non registrate. I versamenti senza contribuente compaiono come **Non attribuiti**; non vengono assegnati automaticamente a chi li ha inseriti. Sono versamenti lordi, senza compensare eventuali rimborsi successivi. Non vengono aggiunti al reddito o alle spese.

## Verifica

`SharedContoTests` copre esclusione dei dati privati, andata/ritorno degli snapshot senza duplicazioni, correzioni/cancellazioni collegate, importi accreditati distinti dall'addebito, inserimento nel libro personale, attribuzione separata dall'autore, rinnovo delle identità dopo abbandono e rientro, categorie, rollback e tentativi di ampliare il perimetro.

Il fixture DEBUG `UITEST_SHARED_CONTO` mostra Casa con i versamenti di Marco e Anna senza inviare inviti o sincronizzare un conto reale. Le verifiche locali non costituiscono una prova di invito e sincronizzazione tra due account iCloud fisici. Non è stata effettuata una distribuzione TestFlight o una pubblicazione dello schema CloudKit Production.

L'avviso di condivisione delle categorie è visibile nella schermata Condivisione e nei moduli di inserimento/modifica. Dal conto e dai moduli si apre Gestisci categorie condivise. La selezione filtra il perimetro del conto; cambiare conto azzera una selezione non compatibile. Voce, acquisizione guidata e salvataggi remoti validano lo stesso vincolo. Alla cessazione della condivisione, l'elenco conservato diventa privato.

Da **Gestisci categorie condivise → Copia categorie personali** è possibile selezionare categorie attive di libri personali, raggruppate per libro. La copia di una sottocategoria include la principale. Le copie mantengono nome, colore, icona e tipo ma ricevono identità proprie nel conto di destinazione; le originali non vengono spostate né modificate. Ripetere la copia riutilizza le identità esistenti senza duplicare o sovrascrivere modifiche indipendenti. Le categorie appartenenti a libri interamente condivisi non sono proposte come categorie personali.

Nella gestione principale delle categorie il selettore **Personali / Condivise** separa i due elenchi. Le categorie condivise sono raggruppate per conto, contrassegnato con `person.2`, con accesso alla gestione e ai movimenti della categoria. Nella condivisione del singolo conto i budget rimangono locali a ogni partecipante e non vengono esportati o importati. La condivisione di un libro intero continua a includere i budget del libro.

Categorie personali e condivise usano la stessa lista gerarchica e gli stessi editor di nome, icona, colore, tipo e categoria principale. Ogni categoria principale offre «Aggiungi a…» per creare sottocategorie nel medesimo elenco condiviso. Con più conti condivisi, un selettore sceglie l’elenco da gestire; i possibili genitori restano limitati a quell’elenco.

L’elenco principale usa un’intestazione compatta con conteggi e, per le categorie condivise, il nome del conto. Il pulsante «Gestisci» nella barra apre una schermata separata con creazione, modifica, archiviazione, aggiunta di sottocategorie e copia delle categorie personali. Le righe di navigazione usano il solo chevron nativo.

Il selettore Personali/Condivise appare solo se il libro contiene categorie condivise attive (per conti condivisi attivi, oppure perché il libro è interamente condiviso). Se la selezione precedente era Condivise e nel nuovo libro non ci sono categorie condivise, viene mostrato comunque l’elenco personale. La prima categoria di un conto condiviso vuoto resta creabile dalla gestione del conto.

Tenendo premuto «Gestisci», «Nuova categoria» apre direttamente l’aggiunta nel perimetro visualizzato: libro personale o conto condiviso selezionato. Con più conti condivisi, il menu nella barra superiore permette di scegliere un elenco alla volta; categorie omonime di conti diversi restano indipendenti. Aggiunta e modifica condividono lo stesso componente grafico e gli stessi modali di icone e colori.

Il menu dei conti condivisi è integrato nella riga nome/conteggi della safe area, senza duplicare il nome del conto. Con al massimo cinque categorie attive, il conto condiviso offre «Categorie per iniziare»: il banner apre un modale in cui scegliere le categorie e sottocategorie da aggiungere nel solo elenco di quel conto, mantenendo invariate le categorie esistenti. I suggerimenti hanno chiavi stabili che sopravvivono alla rimappatura locale dei conti; quelli archiviati non tornano e ripetere l’azione non duplica le categorie.

Se il libro ha conti condivisi ma ancora nessuna categoria condivisa, la lista personale offre un banner di avvio per ciascuno di quei conti. In questo modo il selettore Personali/Condivise rimane nascosto finché l’elenco condiviso è vuoto, ma la generazione delle prime categorie è comunque raggiungibile.

Il modale delle categorie suggerite parte senza selezioni. Una sottocategoria selezionata include la propria principale solo se manca; selezionare una principale seleziona tutte le sottocategorie disponibili, che possono poi essere deselezionate singolarmente. La selezione della principale funziona anche quando è già presente, agendo soltanto sulle sottocategorie mancanti. «Aggiungi» conferma solo gli elementi scelti, «Annulla» non salva nulla. La selezione vale sia per l’elenco personale sia per quello del conto condiviso e non riorganizza o ricolora categorie esistenti.
