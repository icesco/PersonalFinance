import SwiftUI

struct BudgetingGuidesView: View {
    @Environment(\.dismiss) private var dismiss
    var body: some View {
        NavigationStack {
            List {
                Section("A cosa serve un metodo di budget") {
                    Text("Un metodo ti aiuta a decidere in anticipo come distribuire le entrate tra spese essenziali, desideri e risparmio. Puoi usarlo per dare spazio a un progetto, costruire una riserva o capire dove stai spendendo più di quanto avevi previsto.")
                    DisclosureGroup("Come mi aiuta l'app?") {
                        Text("Parti dalle entrate mensili di riferimento e scegli una distribuzione. Associ le categorie alle necessità o ai desideri; l'app prepara i limiti mensili e l'obiettivo di risparmio, che puoi controllare nell'anteprima prima di applicarli.")
                        Text("Durante il mese, i movimenti registrati alimentano i conteggi. Puoi leggere i limiti nei budget e confrontare l'obiettivo con gli accantonamenti netti dei conti di risparmio che hai selezionato.")
                        Text("Sarai tu a effettuare gli accantonamenti e a registrare i movimenti. Puoi cambiare le percentuali, aggiornare le entrate di riferimento o tornare alla gestione manuale.")
                    }
                    DisclosureGroup("Cosa mi serve per iniziare?") {
                        Text("Per un metodo a percentuali servono un importo mensile di entrate nette come riferimento e le categorie di spesa del libro. Non è necessario avere già uno storico completo per creare il piano; per confrontarlo con il mese servono però i movimenti registrati.")
                        Text("La selezione dei conti di risparmio è facoltativa. Se vuoi misurare gli accantonamenti, scegli i conti di tipo Risparmio e registra anche i trasferimenti e le uscite da quei conti.")
                    }
                }
                Section("Scegliere e adattare il metodo") {
                    DisclosureGroup("Come funziona il 50/30/20?") {
                        Text("Con entrate nette di 2.000 € al mese, il punto di partenza è 1.000 € per le necessità, 600 € per i desideri e 400 € per il risparmio. Le percentuali sono una guida: se le spese essenziali occupano più spazio, passa a un piano personalizzato.")
                        Text("Alcune versioni includono nella quota del 20% anche rimborsi aggiuntivi dei debiti. Qui l'obiettivo indica il denaro da accantonare: i pagamenti dei debiti registrati come spese restano nelle spese del mese.")
                        Link("Approfondisci: Consumer Financial Protection Bureau", destination: URL(string: "https://files.consumerfinance.gov/f/201603_cfpb_rules-to-live-by_my-spending-rule-to-live-by.pdf")!)
                    }
                    DisclosureGroup("Necessità o desiderio?") {
                        Text("Le necessità coprono ciò che ti serve per vivere e lavorare: casa, alimentazione di base, cure e trasporti essenziali. I desideri aggiungono comfort o svago. La stessa categoria può contenere entrambi: per esempio alimentari e ristoranti possono appartenere a gruppi diversi.")
                        Text("Assegna il gruppo alla categoria principale e modifica le sottocategorie quando serve. Non deduciamo questa scelta dal nome delle categorie.")
                    }
                    DisclosureGroup("Le mie entrate cambiano ogni mese") {
                        Text("Usa come riferimento un importo netto prudente e sostenibile. Puoi aiutarti con i mesi già registrati, evitando di trattare bonus occasionali come entrate certe. Il riferimento del piano non sostituisce le entrate effettive del mese.")
                    }
                    DisclosureGroup("Le necessità superano il 50%") {
                        Text("Non significa che il tuo piano sia sbagliato. Adatta le percentuali alle spese essenziali e scegli un obiettivo sostenibile. Puoi rivederlo quando cambiano entrate o impegni, senza dover ricominciare dai budget.")
                    }
                }
                Section("Capire il risparmio") {
                    DisclosureGroup("Margine, obiettivo e accantonamenti") {
                        Text("Il margine del mese è entrate registrate meno spese registrate. Con 2.000 € di entrate e 1.600 € di spese, il margine è 400 €. Un valore negativo rimane visibile: non lo portiamo artificialmente a zero.")
                        Text("L'obiettivo è quanto vorresti accantonare secondo il piano. Gli accantonamenti netti misurano invece i flussi dei conti che hai scelto per il risparmio: entrate meno uscite. Le tre cifre rispondono a domande diverse e non si sommano.")
                    }
                    DisclosureGroup("Come vengono contati i trasferimenti?") {
                        Text("Se trasferisci 300 € dal conto corrente a un conto di risparmio selezionato e poi riporti 80 € sul conto corrente, gli accantonamenti netti sono 220 €. Spostare quei fondi tra due conti di risparmio selezionati non li conta una seconda volta.")
                        Text("Anche entrate ricevute direttamente sul conto di risparmio aumentano gli accantonamenti; spese pagate da quel conto li riducono. I trasferimenti non sono né entrate né spese nel calcolo del margine.")
                    }
                    DisclosureGroup("Non ho un conto dedicato") {
                        Text("Puoi continuare a usare i budget e consultare il margine. Gli accantonamenti sono indicati come non misurati finché non scegli un conto di tipo Risparmio. Una somma rimasta sul conto corrente non viene automaticamente considerata accantonata.")
                    }
                    DisclosureGroup("Perché il saldo è diverso?") {
                        Text("Il saldo comprende anche il denaro che avevi prima del mese. Il calcolo degli accantonamenti considera solo i movimenti registrati dal primo giorno del mese fino a oggi. Saldi iniziali, previsioni e progressi degli obiettivi inseriti manualmente sono esclusi.")
                        Text("Queste cifre descrivono i dati registrati nel libro, non una verifica bancaria. Movimenti mancanti, rimborsi registrati come entrate o trasferimenti non registrati possono influenzare il risultato.")
                    }
                }
                Section("Usare i budget esistenti") {
                    DisclosureGroup("Il piano sostituisce i miei budget?") {
                        Text("Nell'anteprima scegli se conservare i budget manuali sulle stesse categorie oppure disattivarli. I limiti del piano sono mensili; un budget settimanale o dedicato a una categoria può comunque essere utile. Una spesa può rientrare in entrambi, quindi non sommare i valori dei budget.")
                        Text("Se torni alla gestione manuale, vengono disattivati solo i budget generati dal piano. Le transazioni restano disponibili.")
                    }
                }
            }
            .navigationTitle("Budget e risparmio")
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Chiudi") { dismiss() } } }
        }
    }
}
