# Verifica del modello locale

## Anteprima durante la dettatura

Le piccole schede usano `VoiceLivePreview`, un parser locale delle trascrizioni parziali, senza chiamare Foundation Models. Sono indicazioni provvisorie e non vengono usate per creare o salvare le transazioni. Il parser riconosce importi con valuta esplicita, numeri italiani semplici, decimali e descrizioni; evita le frasi negative, ipotetiche e i trasferimenti. Le date e i conti restano affidati alla revisione finale.

```sh
swiftc -module-cache-path /private/tmp/formi-live-module-cache -parse-as-library \
  'Personal Finance/Voice/VoiceLivePreview.swift' \
  Tools/VoiceInterpretationQA/LivePreviewChecks.swift \
  -o /private/tmp/formi-voice-live-checks
/private/tmp/formi-voice-live-checks
```

I 22 controlli coprono elenchi, testo incompleto, importi corretti durante la trascrizione, spese ripetute, direzione ereditata o cambiata, valute, negazioni e numeri che non sono importi. Non verificano la trascrizione audio reale.

## Interpretazione finale

Il programma compila direttamente `Personal Finance/Voice/VoiceTransactionInterpreter.swift`: usa lo stesso schema, prompt e mapping dell'app. Non apre Formi e non salva transazioni. Richiede un Mac con Apple Intelligence attiva e il modello disponibile.

Eseguire dalla radice del repository:

```sh
swift build --package-path Packages/FinanceCore --scratch-path /private/tmp/formi-voice-core
swiftc -parse-as-library -target arm64-apple-macos26.0 \
  -I /private/tmp/formi-voice-core/out/Products/Debug \
  -L /private/tmp/formi-voice-core/out/Products/Debug -lFinanceCore \
  'Personal Finance/Voice/VoiceTransactionInterpreter.swift' \
  'Personal Finance/Voice/VoiceTextEvidence.swift' \
  Tools/VoiceInterpretationQA/main.swift Tools/VoiceInterpretationQA/EvidenceChecks.swift \
  Tools/VoiceInterpretationQA/ExtractionChecks.swift \
  -o /private/tmp/formi-voice-model-qa
/private/tmp/formi-voice-model-qa
```

Il percorso dei prodotti può dipendere dalla configurazione SwiftPM/Xcode locale. Il servizio Foundation Models deve essere accessibile al processo: un sandbox di automazione può impedirne l'uso anche se `availability` restituisce `available`.

Diciotto casi verificano importi, direzione, date e conto, per tre ripetizioni. Tre casi controllano anche che la categoria resti vuota in assenza di una causale. Prima delle inferenze vengono eseguiti 21 controlli deterministici sulle evidenze e 4 riproduzioni di risposte strutturate, compresa la riga aggiuntiva osservata nel modello reale. `FORMI_QA_EVIDENCE_ONLY=1` esegue solo questi 25 controlli, senza chiamare il modello.

`FORMI_QA_REPEATS` cambia le ripetizioni; `FORMI_QA_REPORT` cambia il percorso del report JSON (default `/private/tmp/formi-voice-model-report.json`). Il report contiene input, proposte, durata, citazioni originali estratte ed eventuali differenze. Exit code 0 significa tutti i casi superati, 1 differenze o errori, 2 modello indisponibile.

Questa verifica riguarda il testo italiano e il modello del Mac corrente. Non verifica riconoscimento vocale, microfono o comportamento su iPhone. La qualità semantica delle categorie per tutti i commercianti non è coperta dalla suite. Le date vengono risolte dal calendario a partire dalle forme riconosciute nella frase, senza usare una data precisa inventata dal modello. Le forme coperte includono oggi/ieri/domani, date ISO, giorno e mese italiano o inglese, date numeriche con anno completo e giorni fa espressi in cifre. Giorni della settimana e intervalli vaghi richiedono revisione.

## Prima verifica del 10 ottobre 2026

Il report `Results/2026-10-10.json` contiene 30 inferenze reali, con 20 verifiche complete superate. Il tempo mediano è circa 1,8 secondi. Importi, elenchi, movimenti ripetuti, data esplicita e conti sconosciuti hanno superato tutte le ripetizioni. Sono emersi errori sulle negazioni, sull'assenza di data e sulla data relativa ieri. Nel trasferimento la direzione resta correttamente irrisolta, ma il conto scelto varia tra origine e destinazione e fa fallire il confronto rigoroso del conto.

Le categorie e descrizioni mostrano anche supposizioni non sostenute dal testo: ad esempio un generico accredito viene chiamato stipendio. Non considerare quindi questa suite una certificazione di affidabilità. Le proposte devono restare modificabili e richiedere conferma prima del salvataggio.

Un esperimento con ulteriori guide, esempi e campionamento greedy ha peggiorato il risultato: è stato scartato. Il report qui conservato usa l'interprete originale dell'app. I quattro test deterministici `VoiceTransactionTests` di validazione e salvataggio sono passati separatamente.

## Dopo i miglioramenti

`Results/2026-10-10-improved.json` contiene **54 inferenze reali, tutte superate**: 18 casi per 3 ripetizioni. Il tempo mediano è **1,88 secondi**, il massimo **2,95 secondi** in questa esecuzione. Sono passati anche i 25 controlli deterministici e le build macOS e iOS Simulator.

L'interprete verifica le citazioni nelle frasi originali, conserva le negazioni nelle rispettive proposizioni, risolve le date con il calendario e cerca conti citati esplicitamente. Una negazione o un trasferimento resta senza tipo confermabile e senza conto preselezionato. Note e categorie non vengono proposte per una causale inventata o per un generico verbo di pagamento.

I casi aggiunti comprendono due date diverse, negazione seguita da una spesa effettiva, domani, data impossibile, data vaga, decimali in cifre e movimenti senza causale. Prima della correzione finale, una delle 54 risposte separava "Non ho pagato" da "50 euro" in due righe: ora si elimina solo il frammento vuoto già coperto da un movimento nella medesima proposizione. Le riproduzioni verificano che questo non elimini spese ripetute o movimenti incompleti distinti.

Il confronto dei trasferimenti è stato aggiornato: entrambe le forme restano irrisolte e richiedono la scelta manuale del tipo/conto. Nella prima verifica si confrontava anche la scelta, arbitraria, del conto di origine. Il successo della suite riguarda questi casi e questo modello; il salvataggio continua a richiedere la revisione delle proposte.
## Trascrizione locale

Controlli della risoluzione della lingua e della conversione dell’audio del microfono:

```sh
swiftc -parse-as-library -target arm64-apple-macos26.0 \
  -module-cache-path /private/tmp/formi-recorder-module-cache \
  'Personal Finance/Voice/VoiceRecognitionLocale.swift' \
  'Personal Finance/Voice/VoicePCMConverter.swift' \
  Tools/VoiceInterpretationQA/RecorderChecks.swift \
  -o /private/tmp/formi-recorder-checks
/private/tmp/formi-recorder-checks
```

Non registrano il microfono e non scaricano modelli. Il riconoscimento di una frase parlata, il download iniziale e pausa/ripresa vanno verificati su iPhone fisico.
