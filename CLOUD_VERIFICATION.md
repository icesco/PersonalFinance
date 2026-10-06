# Verifica iCloud e libri condivisi

## Prova cloud sintetica, solo su richiesta

`LiveCloudVerificationTests.syntheticOwnerBookRoundTrip` è disattivato per
impostazione predefinita. La compilazione o un risultato `Skipped` non dimostrano
che CloudKit funzioni.

La prova usa un archivio SwiftData in memoria, separato dall’archivio personale,
e il container CloudKit dell’app firmata. Crea un libro, un conto, una spesa e
un’immagine sintetici. Verifica caricamento e rilettura, crea una condivisione
privata senza invitati, aggiorna importo e nome dell’allegato e rilegge il risultato.
Alla fine elimina soltanto la zona con UUID generato dalla stessa esecuzione,
anche in caso di errore. Se la pulizia fallisce, il risultato riporta il nome
della zona sintetica da recuperare.

Prima di eseguirla occorrono autorizzazione esplicita a inviare questi dati di
prova a iCloud, un account iCloud sul Mac e una build firmata con gli entitlement
CloudKit. Questa prova non attiva la sincronizzazione dell’archivio personale.

In Xcode:

1. Selezionare lo schema `Forgia Mac Tests`.
2. In Edit Scheme → Test → Arguments aggiungere temporaneamente
   `FORGIA_VERIFY_LIVE_CLOUD`, conservando `UITEST_MAC_LOCAL` e
   `-CloudSyncEnabled NO`.
3. Eseguire soltanto `LiveCloudVerificationTests` e conservare il risultato
   `.xcresult`, inclusi eventuali errori di pulizia.
4. Rimuovere `FORGIA_VERIFY_LIVE_CLOUD` al termine. Non commettere uno schema
   con questa opzione attiva.

## Verifiche che richiedono due dispositivi/account

Un round trip nello stesso account non prova né la sincronizzazione automatica
SwiftData tra dispositivi né la partecipazione a una condivisione. Per completare
la verifica usare soltanto libri sintetici su installazioni concordate:

- Stesso account, due dispositivi: creazione, modifica e cancellazione di
  movimenti/allegati; riapertura; modifica offline e ricongiungimento.
- Due account diversi: invito esplicito dal proprietario, accettazione, confronto
  di conti, movimenti, budget, ricorrenze e allegati.
- Modifiche da entrambi gli account, aggiornamento automatico a app aperta,
  conflitto sullo stesso campo e scelta esplicita della versione.
- Uscita del partecipante con copia privata conservata, revoca dal proprietario
  e assenza di ulteriori modifiche condivise dopo l’uscita.

Registrare per ogni prova piattaforma/build, azioni, risultato osservato e limiti.
Il superamento dei test con trasporti simulati non sostituisce queste prove.

## Risultato del 6 ottobre 2026

Dopo autorizzazione esplicita dell’utente è stato eseguito sul Mac firmato
`LiveCloudVerificationTests.syntheticOwnerBookRoundTrip`: **1 superato,
0 falliti, 0 saltati**. Verificati creazione della condivisione privata senza
invitati, rilettura dei record e dei dati dell’allegato, aggiornamento di importo
e nome dell’allegato, e cancellazione finale della zona sintetica.

Risultato locale: `/private/tmp/forgia-live-cloud-authorized.xcresult`.
Log: `/private/tmp/forgia-live-cloud-authorized.log`. Lo schema temporaneo con
l’opzione di attivazione è stato rimosso al termine; lo schema condiviso resta
senza questa opzione. L’archivio personale non è stato utilizzato.

Questa prova dimostra il round trip CloudKit del proprietario, non la
sincronizzazione privata SwiftData tra dispositivi o la partecipazione da
un secondo account.
