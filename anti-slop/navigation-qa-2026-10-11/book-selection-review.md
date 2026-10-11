# Selezione del libro nelle Impostazioni

Richiesta: libro contabile selezionabile solo dalle Impostazioni. Oggi e Pianifica mostrano il nome senza azione; anche il selettore nel footer della sidebar Mac è diventato un’etichetta. Gli stati che richiedono un libro indirizzano alle Impostazioni. Il selettore resta disponibile nelle Impostazioni iPhone/iPad tramite Libro contabile, separato da Gestisci libri. Il picker nelle Impostazioni Mac conserva singoli libri e Tutti i libri.

Eliminati il vecchio pulsante di Oggi e il relativo namespace/transizione zoom. Nessuna modifica alla selezione automatica iniziale o alle richieste esterne di widget/Shortcuts.

Verifica isolata dalle modifiche parallele: test UI testBookSelectionLivesInSettings passato su iPhone 17 Pro iOS 26.5; Oggi e Pianifica non offrono il selettore; Impostazioni apre il selettore, la scelta del libro torna alle Impostazioni, la chiusura conserva Pianifica. Build iOS e Mac riuscite. Schermate finali book-readonly-home.png e book-selection-settings.png ispezionate. Non si attesta nuova verifica visiva Mac/iPad o tema scuro.

Revisione antislop after: ENERGY 1, RHYTHM 2, MOTION 1; nome del libro come contesto, azione di scelta nelle Impostazioni, controlli nativi, nessuna nuova decorazione o animazione. Commit e push autorizzati per le sole modifiche alla selezione del libro e alle relative verifiche.
