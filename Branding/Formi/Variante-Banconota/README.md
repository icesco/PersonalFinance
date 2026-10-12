# Formi — formica sulla banconota

MVP di una possibile icona alternativa: una formica vista dall'alto su una banconota senza riferimenti a una valuta. Palette verde petrolio, menta e salvia, coerente con le icone Formi esistenti.

`FormiBanconota.icon` è un documento nativo Icon Composer. Contiene tre SVG trasparenti su canvas 1024 × 1024: formica, incisione e carta. Il fondo è definito nel documento. Il vetro e le ombre sono applicati dal renderer Apple, senza effetti disegnati negli SVG o maschera esterna incorporata.

`Concept-imagegen.png` è il concept raster generato con il tool integrato image_gen; il documento finale usa una ricostruzione vettoriale semplificata. Il prompt integrale è in `imagegen-prompt.txt`.

## Verifica

Esportazioni iOS con ictool incluso in Xcode: Default, Dark, TintedLight, TintedDark, ClearLight e ClearDark. La disponibilità delle esportazioni conferma che il renderer Apple legge il documento; non sostituisce la verifica in Home su dispositivo, né una build che integri questa icona.

Aprire `Confronto.html` per vedere le varianti e valutare la leggibilità a 40–256 px. Aprire `FormiBanconota.icon` in Icon Composer per modificare materiali e livelli.

Il prototipo resta nella cartella Branding e non è integrato nel target dell'app.

Riferimento: https://developer.apple.com/documentation/xcode/creating-your-app-icon-using-icon-composer
