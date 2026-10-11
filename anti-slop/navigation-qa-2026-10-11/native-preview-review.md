# Anteprima nativa dei tab

Richiesta dell’utente: sostituire l’anteprima stilizzata con una barra nativa non selezionabile.

La schermata usa una TabView con lo stesso elenco, ordine, titoli e simboli dei tab reali. Oggi resta selezionato tramite binding costante; hit testing disattivato senza attenuare i colori. L’accessibilità espone una descrizione unica dell’anteprima non interattiva. Su iOS la size class compatta conserva il layout della barra iPhone anche su iPad; su Mac SwiftUI usa la presentazione nativa della piattaforma.

Verifica: build iOS e Mac isolate riuscite; test UI testCustomizationLight riuscito su iPhone 17 Pro iOS 26.5, con aggiunta, riordino, rimozione, percorsi dalle Impostazioni e ripristino. Schermata customization-native-light.png ispezionata: barra nativa visibile dentro la sezione, icone e testo leggibili, nessuna sovrapposizione. Questa revisione non attesta un nuovo controllo visivo su iPad/Mac o nel tema scuro.

Revisione antislop after: componenti nativi e palette Formi; ENERGY 1, RHYTHM 2, MOTION 1. L’anteprima mostra una scelta concreta dell’utente; il suo ruolo non interattivo è esplicito per l’accessibilità. Non sono state introdotte decorazioni o animazioni aggiuntive. Successivamente l’utente ha autorizzato commit/push insieme all’accesso alle Impostazioni dai tab.
