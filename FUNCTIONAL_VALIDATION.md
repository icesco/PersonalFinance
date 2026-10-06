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
| Allegati e scontrini | `AttachmentDraftTests`, `AttachmentPersistenceTests`, `ReceiptReaderTests`, `MacReceiptReaderTests` | Immagini e PDF sintetici, inclusa pagina con testo e scansione, verificati su Mac/iOS. Selettore file Mac, lettura e applicazione del totale verificati con PDF sintetico. Fotocamera e selettore iPhone ancora da provare sul dispositivo. |
| Posizione | `PlaceDraftTests`, `testManualPlaceDraftCanBeCancelled`, `SingleLocationRequest` | Nome manuale e persistenza verificati. Richiesta reale, rifiuto del permesso e precisione della posizione non ancora provati. |
| Multivaluta | `CurrencyConversionTests`, `ForeignAmountDraftTests`, `testForeignAmountIsConvertedBeforeSaving`; download BCE manuale su Mac | Conversione, arrotondamento, tasso fissato e provenienza coperti. Download/applicazione/riapertura verificati su Mac con bozza sintetica; nessun movimento salvato. |
| iCloud privato | `CloudConfigurationTests`, `CloudLifecycleTests`, `CloudSyncProgressTests`, migrazione locale | Prove locali e servizi simulati. Sincronizzazione SwiftData tra due dispositivi dello stesso account non ancora dimostrata. |
| Libri condivisi | Suite `SharedBook*`, gestione conflitti, inviti, uscita e aggiornamento automatico | CloudKit reale e invito tra due account ancora da eseguire. Procedura in `CLOUD_VERIFICATION.md`. Il test live è disattivato. |
| Mac nativo | Build firmata e firma verificata; archivio locale aperto; navigazione, finestre e comandi provati; `MacPrivacyWindowTests` | La suite Mac usa dati in memoria. Il suo successo non prova sincronizzazione cloud o Touch ID reale. |
| Widget | `WidgetSnapshotTests`, `WidgetRefreshTests`, `WidgetRoutingTests`, `testWidgetLinksOpenPlanningAndExpense` | Dati, oscuramento e destinazioni coperti. Widget installato e aggiornamento della timeline sulla superficie di sistema ancora da verificare. |
| Shortcuts / Siri | `FinanceShortcutTests`, `testExpenseShortcutOpensReviewWithoutSaving` | Invocazione dell’intent dall’app e consegna protetta della bozza coperte. Scoperta/esecuzione da Comandi Rapidi e Siri reale ancora da verificare. |
| Apple Watch | `WatchDraftTests`, `RemoteExpenseTests`; protocollo, mailbox e flusso offline | Una prova su simulatore non dimostra consegna WatchConnectivity su coppia fisica, conferma di salvataggio e complicazioni installate. |
| Blocco biometrico | `AppLockTests`, `PrivacyWindowTests`, `MacPrivacyWindowTests`, `testLockedLaunchDoesNotExposeFinancialNavigation` | Stato, finestre protette e bozze coperti con autenticatore simulato. Face ID/Touch ID, annullamento e fallback reali ancora da provare. |
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

## Passi necessari prima di dichiarare completato l’obiettivo

1. Eseguire la prova CloudKit sintetica autorizzata e completare le prove tra
   dispositivi/account descritte in `CLOUD_VERIFICATION.md`.
2. Provare le superfici reali: widget, Comandi Rapidi/Siri, Watch abbinato,
   autenticazione biometrica e promemoria.
3. Verificare acquisizione scontrino/documento e posizione su richiesta nel
   flusso utente, usando dati di prova concordati.
4. Correggere eventuali errori emersi e conservare evidenza per ciascun percorso.

Nessuna release o condivisione di dati personali è autorizzata da questo audit.
