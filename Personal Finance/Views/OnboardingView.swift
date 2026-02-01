//
//  OnboardingView.swift
//  Personal Finance
//
//  Created by Claude on 01/02/26.
//

import SwiftUI

struct OnboardingView: View {
    @Environment(AppStateManager.self) private var appState
    @State private var currentPage = 0

    private let pages: [OnboardingPage] = [
        OnboardingPage(
            icon: "dollarsign.circle.fill",
            title: "Benvenuto in Personal Finance",
            description: "Gestisci le tue finanze personali in modo semplice e intuitivo. Traccia entrate, spese e monitora i tuoi budget.",
            iconColor: .blue
        ),
        OnboardingPage(
            icon: "creditcard.fill",
            title: "Gestisci Più Conti",
            description: "Crea e gestisci conti correnti, risparmi, carte di credito e investimenti. Visualizza il saldo totale in tempo reale.",
            iconColor: .green
        ),
        OnboardingPage(
            icon: "chart.bar.fill",
            title: "Monitora i Budget",
            description: "Imposta budget per categoria e tieni sotto controllo le tue spese. Ricevi avvisi quando ti avvicini ai limiti.",
            iconColor: .orange
        ),
        OnboardingPage(
            icon: "arrow.left.arrow.right.circle.fill",
            title: "Trasferimenti e Ricorrenze",
            description: "Trasferisci denaro tra conti e configura transazioni ricorrenti per gestire entrate e spese periodiche.",
            iconColor: .purple
        ),
        OnboardingPage(
            icon: "checkmark.circle.fill",
            title: "Inizia Ora",
            description: "Hai già un account predefinito pronto all'uso. Puoi iniziare subito ad aggiungere transazioni e personalizzare le categorie.",
            iconColor: .blue
        )
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Page Content
            TabView(selection: $currentPage) {
                ForEach(pages.indices, id: \.self) { index in
                    OnboardingPageView(page: pages[index])
                        .tag(index)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: .always))
            .indexViewStyle(.page(backgroundDisplayMode: .always))

            // Bottom Button
            VStack(spacing: 16) {
                if currentPage < pages.count - 1 {
                    HStack {
                        Button("Salta") {
                            completeOnboarding()
                        }
                        .foregroundColor(.secondary)

                        Spacer()

                        Button("Avanti") {
                            withAnimation {
                                currentPage += 1
                            }
                        }
                        .buttonStyle(.borderedProminent)
                    }
                    .padding(.horizontal)
                } else {
                    Button(action: completeOnboarding) {
                        Text("Inizia")
                            .font(.headline)
                            .frame(maxWidth: .infinity)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                    .padding(.horizontal)
                }
            }
            .padding(.vertical)
        }
        .interactiveDismissDisabled()
    }

    private func completeOnboarding() {
        withAnimation {
            appState.completeOnboarding()
        }
    }
}

struct OnboardingPage {
    let icon: String
    let title: String
    let description: String
    let iconColor: Color
}

struct OnboardingPageView: View {
    let page: OnboardingPage

    var body: some View {
        VStack(spacing: 30) {
            Spacer()

            // Icon
            Image(systemName: page.icon)
                .font(.system(size: 80))
                .foregroundStyle(page.iconColor.gradient)
                .padding(.bottom, 20)

            // Title
            Text(page.title)
                .font(.largeTitle)
                .fontWeight(.bold)
                .multilineTextAlignment(.center)
                .padding(.horizontal)

            // Description
            Text(page.description)
                .font(.body)
                .foregroundColor(.secondary)
                .multilineTextAlignment(.center)
                .padding(.horizontal, 40)
                .fixedSize(horizontal: false, vertical: true)

            Spacer()
            Spacer()
        }
    }
}

#Preview {
    OnboardingView()
        .environment(AppStateManager())
}
