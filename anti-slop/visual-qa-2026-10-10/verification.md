# Verifica visuale Formi — 10 ottobre 2026

Simulatore: Forgia Logo Flow QA, iOS 26.5, UDID 934679FE-D5EE-41E1-B50C-DA7BFE788C44.

Build Debug riuscita. Avvio con UITEST_MAC_LOCAL + UITEST_ANTISLOP: storage, demo e onboarding in memoria, senza CloudKit.

Verificate in chiaro e scuro le schermate reali CSVImportView, AccountFilterStepView (colonna e conto), CSVExportView (alert), OnboardingView (alert) e TodayView (banner dopo caricamento riuscito).

Interazioni: CSV di prova letto dal parser; scelta colonna Conto, scelta Banca; export Chiudi + Riprova recupera 46 transazioni; demo Chiudi lascia attivi i pulsanti; Home Riprova rimuove il banner e conserva il riepilogo.

Le injection sono compilate solo in DEBUG; la fixture si apre soltanto con il flag esplicito. Nessuna modifica ai dati reali. Errori indotti per verificare UI, non prova di guasti reali CloudKit. NSSavePanel Mac non incluso in questa verifica. Correzioni 5–8 ancora fuori ambito.
