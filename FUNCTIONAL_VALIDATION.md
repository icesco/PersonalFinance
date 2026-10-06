# Forgia: stato della verifica funzionale

Audit del 6 ottobre 2026 sul codice fino a `7d9f847`.
L’obiettivo di parità funzionale resta aperto: le prove di sistema elencate qui
non sono sostituite dai test unitari o dai collegamenti aperti direttamente.

## Evidenze disponibili

| Requisito | Implementazione e prove controllate | Limite dell’evidenza / prossima prova |
| --- | --- | --- |
| Navigazione conti, budget, scadenze | `MainTabView`, Pianifica, comandi Mac; `testPlanningNavigation` e `testExpenseBudgetPreviewUpdatesBeforeSaving` | Navigazione iPhone verificata in simulatore; Mac verificato nella sessione manuale. Non implica verifica su ogni formato di schermo. |
| Analisi con periodi coerenti | `SpendingOverviewView`, `SpendingAnalysisWindowTests`, `RecordedSpendingReportTests`, `testAnalysisPeriods` | Periodi, confronti a durata coerente, DST e separazione dei trasferimenti coperti; mesi/date italiani osservati su Mac. |
| Ricorrenti e promemoria | `RecurrenceScheduleTests`, `RecurrenceOccurrenceTests`, planner e `RecurrenceReminderTests`; UI per fine serie e apertura da notifica | Notifica locale verificata in simulatore. Consegna e apertura su dispositivo fisico da verificare. |
| Calcolatrice | `AmountCalculatorTests`, `testCalculatorAppliesAmountWithoutSaving` | Calcolo e applicazione alla bozza verificati; la prova UI non salva movimenti reali. |
| Allegati e scontrini | `AttachmentDraftTests`, `AttachmentPersistenceTests`, `ReceiptReaderTests`, `MacReceiptReaderTests` | Immagini e PDF sintetici, inclusa pagina con testo e scansione, verificati su Mac/iOS. Selettore file Mac, lettura e applicazione del totale verificati con PDF sintetico. Scansione da fotocamera, scelta OCR e applicazione dell’importo confermate dall’utente su iPhone. Selettore file iPhone ancora da verificare. |
| Posizione | `PlaceDraftTests`, `testManualPlaceDraftCanBeCancelled`, `SingleLocationRequest` | Nome manuale e persistenza verificati. Rilevamento reale su richiesta e rimozione delle coordinate confermati dall’utente su iPhone. Rifiuto del permesso e accuratezza geografica non ancora verificati. |
| Multivaluta | `CurrencyConversionTests`, `ForeignAmountDraftTests`, `testForeignAmountIsConvertedBeforeSaving`; download BCE manuale su Mac | Conversione, arrotondamento, tasso fissato e provenienza coperti. Download/applicazione/riapertura verificati su Mac con bozza sintetica; nessun movimento salvato. |
| iCloud privato | `CloudConfigurationTests`, `CloudLifecycleTests`, `CloudSyncProgressTests`, migrazione locale | Prove locali e servizi simulati. Sincronizzazione SwiftData tra due dispositivi dello stesso account non ancora dimostrata. |
| Libri condivisi | Suite `SharedBook*`, gestione conflitti, inviti, uscita e aggiornamento automatico | Round trip CloudKit reale del proprietario superato con dati sintetici e pulizia finale. Invito e sincronizzazione tra due account ancora da verificare; procedura in `CLOUD_VERIFICATION.md`. Il test live resta disattivato per impostazione predefinita. |
| Mac nativo | Build firmata e firma verificata; archivio locale aperto; navigazione, finestre e comandi provati; `MacPrivacyWindowTests` | La suite Mac usa dati in memoria. Il suo successo non prova sincronizzazione cloud o Touch ID reale. |
| Widget | `WidgetSnapshotTests`, `WidgetRefreshTests`, `WidgetRoutingTests`, `testWidgetLinksOpenPlanningAndExpense` | Dati, oscuramento e destinazioni coperti dai test. Presenza del widget sulla Home e apertura dell’inserimento spesa tramite + nel formato medio confermate dall’utente su iPhone. Dati popolati e aggiornamento della timeline reale ancora da verificare. |
| Shortcuts / Siri | `FinanceShortcutTests`, `testExpenseShortcutOpensReviewWithoutSaving`; metadati Mac presenti | Invocazione interna coperta. Nel catalogo Mac le azioni non compaiono: `linkd` rifiuta la build locale come `not trusted for binding`. Su iPhone l’utente ha confermato presenza delle azioni, apertura di Pianifica e preparazione della bozza da 12,50 senza salvataggio automatico. Il comando vocale Siri «Apri il riepilogo in Forgia» apre il tab Oggi, come confermato dall’utente. |
| Apple Watch | `WatchDraftTests`, `RemoteExpenseTests`; protocollo, mailbox e flusso offline | Una prova su simulatore non dimostra consegna WatchConnectivity su coppia fisica, conferma di salvataggio e complicazioni installate. |
| Blocco biometrico | `AppLockTests`, `PrivacyWindowTests`, `MacPrivacyWindowTests`, `testLockedLaunchDoesNotExposeFinancialNavigation` | Stato, finestre protette e bozze coperti con autenticatore simulato. Blocco, sblocco Face ID al ritorno dalla Home e conservazione della bozza confermati dall’utente su iPhone. Annullamento dell’autenticazione con app ancora bloccata confermato dall’utente. Touch ID e fallback alle credenziali ancora da provare. |
| Assistenza proattiva verificabile | `SpendingDirectionTests`, `SpendingDirectionInputsTests`, `RecordedSpendingReportTests` | Dati vecchi/incompleti, fondi maturati, impegni futuri, debito e trasferimenti coperti. Le stime rimangono condizionate ai dati registrati. |

## Risultati e ambito

- FinanceCore: log `forgia-core-full-oct6.log`, 325 test / 57 suite superati
  prima dell’aggiunta della factory per sessioni in memoria; successivo controllo
  mirato `CloudLifecycleTests`: 6 test superati.
- Suite UI iPhone: `forgia-ui-full-oct6.log`, 11 successi e 1 fallimento di
  selezione del libro in Pianifica. Dopo il fix `b838c81`, rerun mirato di
  Pianifica e notifica: entrambi superati (`forgia-planning-scope-ui.log`). Non
  registrare questo insieme come una singola esecuzione completa verde.
- Suite Mac finale: **54 test superati, 0 falliti, 1 saltato**. Il test saltato è
  quello cloud live. Risultato locale:
  `/private/tmp/forgia-mac-signed-dd/Logs/Test/Test-Forgia Mac Tests-2026.10.06_10-39-45-+0200.xcresult`.
- OCR dopo il fix `5db0479`: 3 funzioni test Mac e 3 iOS superate; il test iOS
  parametrizzato copre scansione su pagina separata e sulla stessa pagina.
- Dopo la configurazione multipiattaforma: 9 test mirati iOS di blocco e
  promemoria superati (`forgia-mac-config-ios-regression.log`).

I log e gli `.xcresult` sono artefatti locali temporanei, non allegati permanenti
al repository. Questi conteggi descrivono le esecuzioni osservate, non una
promessa sulle modifiche successive.

### Prova su iPhone fisico

Il 6 ottobre su iPhone 16 Pro Max con iOS 27.0.1 sono passati i test mirati
`ReceiptReaderTests` e `AppLockTests`: **7 funzioni, 8 esecuzioni, 0 errori,
0 saltati**. L’OCR include una prova parametrizzata su PDF misti. Il blocco
usa un autenticatore simulato: non è una prova Face ID. La sessione usa
`UITEST_MAC_LOCAL` e cloud disattivato, con archivio sintetico in memoria.

Risultato locale:
`/private/tmp/forgia-physical-verification-dd/Logs/Test/Test-Forgia Mac Tests-2026.10.06_11-15-58-+0200.xcresult`.
Il profilo widget inizialmente privo di App Group è stato risolto tramite
aggiornamento automatico dei profili Xcode. Nessun entitlement è stato rimosso.
Successivamente l’utente ha confermato la prova manuale sullo stesso iPhone:
scansione di un foglio con importi scritti a mano, comparsa dell’allegato,
riconoscimento di due importi su tre (incluso il totale), proposta di scelta e
applicazione dell’importo selezionato alla bozza. L’utente ha precisato che
l’importo non riconosciuto era scritto male. Questo conferma il percorso
osservato, non l’accuratezza generale dell’OCR sulla scrittura a mano.
L’evidenza è il riscontro dell’utente, non un’osservazione remota dello schermo.
Non è stato richiesto il salvataggio del movimento; l’annullamento della bozza
non è ancora stato confermato.

Nella successiva prova guidata l’utente ha confermato il funzionamento di Face ID:
attivazione di Blocca Forgia in Impostazioni → Privacy, passaggio alla Home e
ritorno nell’app con blocco e successivo sblocco tramite riconoscimento.
L’utente ha inoltre confermato il superamento della prova con una bozza da
12,50: passaggio alla Home, ritorno e sblocco Face ID, importo ancora presente,
quindi annullamento senza salvataggio. Anche queste sono evidenze riportate
dall’utente sul dispositivo fisico. Nella prova successiva l’utente ha
confermato che annullando l’autenticazione l’app resta bloccata. Lo sblocco
subito dopo questo annullamento non è ancora stato confermato. Restano da
verificare fallback alle credenziali del dispositivo e Touch ID su Mac.

### Posizione su iPhone

Il 6 ottobre l’utente ha confermato il funzionamento della prova guidata:
nuova spesa → Luogo → Usa posizione attuale → visualizzazione di coordinate
e precisione stimata → Rimuovi coordinate. La prova richiedeva infine di
annullare la bozza senza salvare. Nessuna coordinata è stata richiesta o
riportata in chat o in questo documento. Il riscontro conferma rilevamento e
rimozione nell’interfaccia; non misura l’accuratezza geografica e non copre
il rifiuto del permesso.

### Download BCE nel flusso Mac

Il 6 ottobre, nella build firmata avviata con `UITEST_MAC_LOCAL` e
`-CloudSyncEnabled NO`: Nuova spesa → Importo in valuta estera → 100 USD →
Scarica tasso BCE. L’interfaccia ha mostrato `89,25 EUR`, tasso
`0.8925383791503034630489111031774366`, data `2026-10-05`. Dopo Usa importo,
la bozza mostrava `89,25`; riaprendo la conversione, importo originale, tasso e
provenienza erano conservati. Conversione e bozza annullate, sessione chiusa
con codice 0. È evidenza del percorso osservato, non una quotazione garantita
per altre date.

### Importazione PDF nel flusso Mac

Il 6 ottobre, sessione firmata in memoria: Nuova spesa → Da file → selettore
macOS → `forgia-scontrino-sintetico.pdf` (solo testo sintetico) → Leggi scontrino.
Il foglio iniziale risultava troppo basso e il comando incorporato nella lista
non era attivabile tramite il controllo assistito. Con `Form` raggruppato e
misure minime Mac, il comando è esposto come pulsante: Usa 25,90 ha chiuso il
lettore e impostato `25,9` nel campo importo, mantenendo il PDF nella bozza.
Bozza annullata e sessione chiusa con codice 0; nessun movimento persistente
creato. La build Mac è riuscita; l’acquisizione da fotocamera resta fuori da
questa prova.

### Widget sulla Home di iPhone

Il 6 ottobre l’utente ha confermato la presenza di Riepilogo Forgia sulla Home,
con le scritte «Apri Forgia» e «Aggiorna nell’app». Nel formato medio compare
anche il pulsante + in alto: premendolo, Forgia si apre e presenta
l’inserimento di una spesa, come confermato dall’utente.

La sessione di prova `UITEST_MAC_LOCAL` non pubblica snapshot del widget.
Questa prova verifica presenza, visualizzazione riportata e collegamento alla
spesa; non dimostra dati popolati, aggiornamento della timeline, oscuramento
sulla superficie reale o passaggio Face ID durante questa specifica apertura.
Non è stato richiesto di salvare la spesa.

### Comandi Rapidi su iPhone

Il 6 ottobre l’utente ha confermato che le azioni di Forgia compaiono nel
catalogo di Comandi Rapidi sull’iPhone. Ha poi eseguito Apri budget e scadenze,
confermando l’apertura della schermata Pianifica, e Prepara una spesa con
importo 12,50, confermando la preparazione della bozza senza salvataggio
automatico nella prova guidata. Ha inoltre confermato che pronunciando a Siri
«Apri il riepilogo in Forgia» l’app si apre sul tab Oggi. Questi risultati sono
riscontri dell’utente sul dispositivo fisico: coprono i percorsi osservati
tramite Comandi Rapidi e Siri, ma non la risoluzione del blocco di
indicizzazione su Mac né tutte le azioni tramite voce.

### Catalogo Comandi Rapidi Mac

Il 6 ottobre sono state cercate Forgia e l’azione Prepara una spesa nell’editor
reale di Comandi Rapidi. Le ricerche non restituiscono le azioni dell’app, mentre
la ricerca di azioni generiche restituisce risultati. La build contiene i tre
intent discoverable in `Metadata.appintents/extract.actionsdata`.

È stata registrata la build in Launch Services e provata una copia separata
in `~/Applications/Forgia Verification.app`, poi rimossa. `linkd` riporta prima
`Could not create application record` (`-10814`) per la build temporanea, poi
`Bundle cc.fbianco.finance.Personal-Finance is not trusted for binding, skipping`
per la copia installata. Log locale: `/private/tmp/forgia-intents-indexing.log`.
Questo identifica un blocco di indicizzazione della build provata, non prova che
una distribuzione approvata risolva automaticamente il problema. Non sono state
modificate protezioni di macOS. Resta un comando vuoto denominato
`Forgia — verifica sintetica` nella libreria Comandi Rapidi, creato per la prova;
non contiene azioni e non è stato eseguito.

## Passi necessari prima di dichiarare completato l’obiettivo

1. Completare le prove tra dispositivi/account descritte in
   `CLOUD_VERIFICATION.md`; il round trip sintetico del proprietario è superato.
2. Provare le superfici reali: widget, Comandi Rapidi/Siri, Watch abbinato,
   autenticazione biometrica e promemoria.
3. Verificare acquisizione scontrino/documento e posizione su richiesta nel
   flusso utente, usando dati di prova concordati.
4. Correggere eventuali errori emersi e conservare evidenza per ciascun percorso.

La prova cloud con soli dati sintetici è stata autorizzata esplicitamente il
6 ottobre. Nessuna release o trasmissione di dati personali è autorizzata da
questo audit.
