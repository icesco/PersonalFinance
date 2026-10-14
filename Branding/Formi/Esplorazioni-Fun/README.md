# Formi — quattro esplorazioni fun

Quattro concept generati con il tool integrato image_gen: banconota gigante, formica che sbuca, banconota origami e ritratto. Palette comune verde petrolio, menta e salvia, con un piccolo accento corallo dove utile.

Aprire Confronto.html per confrontare le versioni chiare e scure e regolare la dimensione da 40 a 240 px.

Ogni cartella contiene un documento nativo FormiFun.icon con fondo separato e un livello PNG trasparente del personaggio e della banconota. Sono concept raster: le parti del disegno sono unite nel PNG, mentre fondo e impostazioni di materiale restano modificabili in Icon Composer. Un’eventuale proposta scelta può essere rifinita e separata in più livelli vettoriali.

Trasparenza verificata nei quattro PNG. Le otto anteprime Default/Dark sono state esportate con Apple ictool 27.1. Luce e ombra native applicate dal renderer. Varianti Tinted/Clear e resa in Home su dispositivo non ancora verificate. Nessuna icona è stata integrata nel target dell’app.

I quattro prompt integrali sono salvati nella cartella principale nei file con suffisso -prompt.txt.

## Uso negli stati vuoti dell’app

Le illustrazioni originali restano tutte conservate, insieme ai prompt e ai documenti Icon Composer. Copie integrali dei PNG trasparenti sono incluse nel catalogo dell’app, senza applicare il materiale dell’icona.

| Illustrazione | Schermata | Asset |
| --- | --- | --- |
| Formica che sbuca | Movimenti senza transazioni nel periodo, conto o categorie selezionati | FormiEmptyPeeking |
| Banconota gigante | Budget senza budget attivi | FormiEmptyCarrying |
| Banconota origami | Flusso con entrate e uscite entrambe a zero | FormiEmptyOrigami |
| Ritratto | Conti del libro vuoti, inclusa l’overlay macOS | FormiEmptyPortrait |

Il componente FormiEmptyIllustration mantiene i colori originali, limita la crescita a 180 pt con Dynamic Type ed esclude l’immagine decorativa da VoiceOver. Testi e azioni restano nelle viste esistenti.

Verifica: build iOS Simulator completata; componente condiviso renderizzato in una galleria SwiftUI macOS chiara/scura (EmptyStates/light.png e dark.png). La galleria controlla il componente e gli asset; non è una cattura delle schermate di produzione su iPhone. Navigazione reale e layout delle singole schermate su dispositivo restano da verificare.

## Loader con la formica

FormiLoadingView usa una sprite sheet derivata da FormiEmptyCarrying: la formica che trasporta la banconota. Sedici pose in una griglia 4 × 4 mostrano le zampe che camminano sul posto, con un ciclo di circa 1,28 secondi. Non sono applicate rotazioni o traslazioni globali del personaggio. Tre puntini accompagnano la camminata; non rappresentano una percentuale.

Due formati: regular per caricamenti di schermata, inline per righe e moduli. L’animazione è attiva solo quando isPlaying è true, la scena è attiva e Riduci movimento è disabilitato; negli altri casi restano illustrazione, testo e puntini fermi. VoiceOver legge una sola etichetta di caricamento e non annuncia ogni fase.

Integrato in Oggi, caricamento iniziale e paginazione dei Movimenti, andamento del saldo, import/export CSV, lettura scontrini e caricamento allegati. Gli avanzamenti determinati e gli indicatori piccoli dentro i controlli mantengono la presentazione esistente.

LoadingStates/preview.gif è una cattura di una galleria SwiftUI macOS del componente reale; il pannello di destra usa isPlaying=false. La sequenza contiene 30 fotogrammi: sedici pose distinte del personaggio nei pannelli animati e pannello in pausa invariato. Non è una registrazione della navigazione su iPhone, né una verifica dell’interruttore di accessibilità sul dispositivo. LoadingStates/preview.png è una cattura statica della stessa galleria.

La revisione con la camminata è anche in LoadingStates/preview-walking.gif. La precedente oscillazione resta archiviata in preview-rocking.gif e FormiLoadingView-rocking.swift.txt. La sprite sheet originale generata con image_gen è in walking-sprite-master.png; il prompt e il riferimento sono documentati in walking-sprite-prompt.txt. Nessuna illustrazione precedente è stata eliminata.
