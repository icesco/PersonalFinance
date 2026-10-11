# Verifica visiva sidebar — 11 ottobre 2026

## Mac

App nativa compilata da una copia delle sole modifiche nell’indice Git. Fixture DEBUG in memoria, senza CloudKit o dati utente. Sidebar a 190 punti, con gruppi Panoramica e Gestisci, tutte le otto destinazioni e accessi a impostazioni/personalizzazione. Verificata in chiaro e scuro: etichette leggibili, nessuna sovrapposizione. La voce Personalizza tab iPhone va su due righe alla larghezza minima ed è leggibile.

Provata la selezione delle destinazioni Oggi, Analisi, Movimenti, Cerca, Pianifica, Calendario, Budget e Conti. Aggiunta Analisi alla barra compatta dalla personalizzazione: la sidebar mantiene tutte le sezioni dopo la chiusura.

La prima ispezione ha individuato una sheet di personalizzazione troppo bassa e una spiegazione troncata dai footer nativi Mac. Correzioni: minimo 560 × 640 punti per il contenuto Mac; spiegazioni come righe multilinea su Mac. Ricompilazione isolata riuscita e schermata finale ispezionata, con testo completo.

Artefatti: mac-sidebar-light.png, mac-sidebar-dark.png, mac-customization-dark.png. Il tema scuro finale documenta anche la correzione dei testi.

## iPad

Ispezionata la sidebar in verticale su iPad Pro 11 M5, simulatore iOS 27 dedicato. Tutte le destinazioni, impostazioni e personalizzazione sono visibili e leggibili, senza tagli o sovrapposizioni. Artefatto valido: ipad-sidebar-light.png.

L’ambiente CoreSimulator ha bloccato l’avvio del primo dispositivo iOS 26.5 durante la migrazione; il secondo dispositivo iOS 27 ha avviato Formi ma ha presentato timeout e mancata risposta all’iniezione degli input. Per questo non si attestano interazioni complete, personalizzazione o tema scuro su iPad. Il controllo visivo della sidebar chiara è riuscito.

## Pubblicazione

Build Mac e iOS delle sole modifiche nell’indice Git. Conservati fuori dal commit: modifiche al progetto e agli scheme, ripristino finestre Mac, lavoro parallelo su MoneyFlow e relativi test. Test logici e UI iPhone descritti nel follow-up 002.
