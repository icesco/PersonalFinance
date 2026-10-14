# Formi: illustrazioni delle funzionalità

Quattro illustrazioni trasparenti, generate con lo strumento imagegen integrato a partire da FormiEmptyCarrying. I prompt esatti sono in `prompts.json`; la prima variante del saldo è conservata come esplorazione.

- **Budget:** Formi distribuisce una banconota in una busta a scomparti; stato senza budget.
- **Libro condiviso:** due formiche custodiscono lo stesso libro; introduzione alla condivisione del libro.
- **Conto condiviso:** due formiche trasportano un portafoglio; introduzione alla condivisione del conto.
- **Saldo:** Formi osserva una curva con salite e discese; stato senza saldi nel periodo.

I PNG originali restano qui e le copie usate dall’app sono negli imageset omonimi. `FormiFeatureIllustration` mantiene i colori della mascotte e aggiunge un fondo menta locale in modalità scura per il contrasto.

`FormiFeatureIcon` disegna sette oggetti semplificati in SwiftUI Canvas: budget, libri, conti, libri condivisi, conti condivisi, saldo e categorie. I colori seguono il tema corrente. Usati nelle impostazioni iOS e macOS, nelle righe dei libri, negli accessi rapidi ai budget e ai conti, nelle azioni di condivisione e nelle intestazioni del saldo. I budget conservano l’icona della categoria quando presente.

`preview-light.png` e `preview-dark.png` sono render dei componenti SwiftUI, con simboli a 22, 30 e 42 pt. Sono tavole di verifica visiva, non screenshot dell’app in esecuzione.
