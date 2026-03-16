import SwiftUI

struct ContentView: View {
    @StateObject private var viewModel = MenuViewModel()

    private let neoBackground = Color(red: 1.0, green: 0.992, blue: 0.961)
    private let neoAccent = Color(red: 1.0, green: 0.42, blue: 0.42)
    private let neoSecondary = Color(red: 1.0, green: 0.851, blue: 0.239)
    private let neoMuted = Color(red: 0.769, green: 0.710, blue: 0.992)

    var body: some View {
        ZStack {
            neoBackground
                .ignoresSafeArea()

            ScrollView {
                VStack(alignment: .leading, spacing: 18) {
                    headerCard
                    infoCard
                    modeSelector
                    linksCard

                    if viewModel.isLoading {
                        loadingCard
                    }

                    if let errorMessage = viewModel.errorMessage {
                        errorCard(message: errorMessage)
                    }

                    if let menu = viewModel.menu {
                        menuHeaderCard(menu)

                        if viewModel.displayMode == .geral {
                            rawMenuCard(menu)
                        } else {
                            dailyMenuSection(menu)
                        }
                    }
                }
                .padding(16)
                .padding(.bottom, 24)
            }
        }
        .task {
            guard viewModel.menu == nil, !viewModel.isLoading else { return }
            await viewModel.load()
        }
    }

    private var headerCard: some View {
        neoCard(background: neoAccent) {
            VStack(alignment: .leading, spacing: 10) {
                Text("RUUF")
                    .font(.system(size: 40, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .textCase(.uppercase)
                    .tracking(2)

                Text("Cardápio universitário da UFPI")
                    .font(.system(size: 20, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)

                Text("Teresina • Picos • Floriano • Bom Jesus")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 6)
                    .background(neoSecondary)
                    .overlay(
                        Rectangle().stroke(.black, lineWidth: 3)
                    )
            }
        }
        .rotationEffect(.degrees(-1.2))
    }

    private var infoCard: some View {
        neoCard(background: .white) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Atualização UFPI")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .textCase(.uppercase)
                Text("O site costuma atualizar o cardápio na segunda entre 10:00 e 12:00.")
                    .font(.system(size: 15, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                Button {
                    Task { await viewModel.load() }
                } label: {
                    labelButton(title: "Atualizar agora", background: neoSecondary)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var modeSelector: some View {
        HStack(spacing: 8) {
            ForEach(MenuDisplayMode.allCases) { mode in
                Button {
                    viewModel.displayMode = mode
                } label: {
                    Text(mode.rawValue.uppercased())
                        .font(.system(size: 13, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .background(
                            neoBlockBackground(
                                color: viewModel.displayMode == mode ? neoMuted : .white,
                                borderWidth: 3,
                                shadowOffset: 4
                            )
                        )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private var linksCard: some View {
        neoCard(background: .white) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Links detectados")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .textCase(.uppercase)

                ForEach(Campus.allCases) { campus in
                    HStack {
                        Text(campus.rawValue)
                            .font(.system(size: 15, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                        Spacer()
                        if let url = viewModel.campusLinks[campus] {
                            Link("PDF", destination: url)
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 10)
                                .padding(.vertical, 4)
                                .background(neoSecondary)
                                .overlay(Rectangle().stroke(.black, lineWidth: 2))
                        } else {
                            Text("-")
                                .font(.system(size: 14, weight: .bold, design: .rounded))
                                .foregroundStyle(.black)
                        }
                    }
                }
            }
        }
    }

    private var loadingCard: some View {
        neoCard(background: neoMuted) {
            HStack(spacing: 12) {
                ProgressView()
                    .tint(.black)
                Text("Carregando dados da UFPI e processando PDF...")
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
            }
        }
    }

    private func errorCard(message: String) -> some View {
        neoCard(background: neoAccent) {
            VStack(alignment: .leading, spacing: 10) {
                Text("Erro")
                    .font(.system(size: 16, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .textCase(.uppercase)
                Text(message)
                    .font(.system(size: 14, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
                Button {
                    Task { await viewModel.load() }
                } label: {
                    labelButton(title: "Tentar de novo", background: .white)
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func menuHeaderCard(_ menu: WeeklyMenu) -> some View {
        neoCard(background: neoSecondary) {
            VStack(alignment: .leading, spacing: 8) {
                Text("Teresina • \(menu.periodLabel)")
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                Link(destination: menu.sourceURL) {
                    Text("Abrir PDF original")
                        .font(.system(size: 14, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 6)
                        .background(.white)
                        .overlay(Rectangle().stroke(.black, lineWidth: 3))
                }
            }
        }
    }

    private func rawMenuCard(_ menu: WeeklyMenu) -> some View {
        VStack(alignment: .leading, spacing: 12) {
            neoCard(background: .white) {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Cardápio geral estruturado")
                        .font(.system(size: 16, weight: .black, design: .rounded))
                        .foregroundStyle(.black)
                        .textCase(.uppercase)

                    Text("Resumo semanal organizado por dia, turno e categoria.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
            }

            ForEach(menu.dailyMenus) { daily in
                weeklyDaySummaryCard(daily)
            }
        }
    }

    private func weeklyDaySummaryCard(_ daily: DailyMenu) -> some View {
        neoCard(background: daily.day == .sabado ? neoMuted : .white) {
            VStack(alignment: .leading, spacing: 10) {
                Text(daily.day.title.uppercased())
                    .font(.system(size: 17, weight: .black, design: .rounded))
                    .foregroundStyle(.black)

                Rectangle()
                    .fill(.black)
                    .frame(height: 2)

                weeklyMealSummarySection(title: "Almoço", meal: daily.lunch)

                if let dinner = daily.dinner {
                    weeklyMealSummarySection(title: "Jantar", meal: dinner)
                } else {
                    Text("Jantar: não disponível neste dia.")
                        .font(.system(size: 13, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                }
            }
        }
    }

    private func weeklyMealSummarySection(title: String, meal: MealMenu) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 14, weight: .black, design: .rounded))
                .foregroundStyle(.black)

            let available = MenuCategory.ordered.filter { !meal.items(for: $0).isEmpty }

            if available.isEmpty {
                Text("Sem itens estruturados para este turno.")
                    .font(.system(size: 13, weight: .bold, design: .rounded))
                    .foregroundStyle(.black)
            } else {
                ForEach(available) { category in
                    VStack(alignment: .leading, spacing: 3) {
                        Text(category.rawValue)
                            .font(.system(size: 12, weight: .black, design: .rounded))
                            .foregroundStyle(.black)
                            .textCase(.uppercase)

                        Text(meal.items(for: category).joined(separator: " • "))
                            .font(.system(size: 13, weight: .bold, design: .rounded))
                            .foregroundStyle(.black)
                    }
                    .padding(8)
                    .background(.white.opacity(0.7))
                    .overlay(Rectangle().stroke(.black, lineWidth: 2))
                }
            }
        }
    }

    private func dailyMenuSection(_ menu: WeeklyMenu) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 10) {
                    ForEach(menu.dailyMenus) { daily in
                        let selected = daily.day == viewModel.selectedDay
                        Button {
                            viewModel.selectedDay = daily.day
                        } label: {
                            Text(daily.day.title.uppercased())
                                .font(.system(size: 13, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 12)
                                .padding(.vertical, 8)
                                .background(
                                    neoBlockBackground(
                                        color: selected ? neoAccent : .white,
                                        borderWidth: 3,
                                        shadowOffset: 4
                                    )
                                )
                        }
                        .buttonStyle(.plain)
                    }
                }
                .padding(.vertical, 2)
            }

            if let daily = viewModel.menuForSelectedDay() {
                mealCard(title: "Almoço", meal: daily.lunch, background: .white)

                if let dinner = daily.dinner {
                    mealCard(title: "Jantar", meal: dinner, background: neoMuted)
                }

                Button {
                    Task { await viewModel.toggleReminder(for: daily.day) }
                } label: {
                    labelButton(
                        title: viewModel.remindersEnabled[daily.day] == true ? "Remover lembrete" : "Ativar lembrete semanal (10:30)",
                        background: viewModel.remindersEnabled[daily.day] == true ? .white : neoSecondary
                    )
                }
                .buttonStyle(.plain)
            }
        }
    }

    private func mealCard(title: String, meal: MealMenu, background: Color) -> some View {
        neoCard(background: background) {
            VStack(alignment: .leading, spacing: 10) {
                Text(title)
                    .font(.system(size: 18, weight: .black, design: .rounded))
                    .foregroundStyle(.black)
                    .textCase(.uppercase)

                let available = MenuCategory.ordered.filter { !meal.items(for: $0).isEmpty }

                if available.isEmpty {
                    Text("Sem itens estruturados para este turno.")
                        .font(.system(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(.black)
                } else {
                    ForEach(available) { category in
                        VStack(alignment: .leading, spacing: 4) {
                            Text(category.rawValue.uppercased())
                                .font(.system(size: 12, weight: .black, design: .rounded))
                                .foregroundStyle(.black)
                                .padding(.horizontal, 8)
                                .padding(.vertical, 4)
                                .background(neoSecondary)
                                .overlay(Rectangle().stroke(.black, lineWidth: 2))

                            ForEach(meal.items(for: category), id: \.self) { item in
                                Text("• \(item)")
                                    .font(.system(size: 14, weight: .bold, design: .rounded))
                                    .foregroundStyle(.black)
                            }
                        }
                    }
                }
            }
        }
    }

    private func labelButton(title: String, background: Color) -> some View {
        Text(title.uppercased())
            .font(.system(size: 12, weight: .black, design: .rounded))
            .foregroundStyle(.black)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(
                neoBlockBackground(
                    color: background,
                    borderWidth: 3,
                    shadowOffset: 4
                )
            )
    }

    private func neoCard<Content: View>(
        background: Color,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .padding(14)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(
                neoBlockBackground(
                    color: background,
                    borderWidth: 4,
                    shadowOffset: 8
                )
            )
    }

    private func neoBlockBackground(color: Color, borderWidth: CGFloat, shadowOffset: CGFloat) -> some View {
        Rectangle()
            .fill(color)
            .overlay(Rectangle().stroke(.black, lineWidth: borderWidth))
            .shadow(color: .black, radius: 0, x: shadowOffset, y: shadowOffset)
    }
}

#Preview {
    ContentView()
}
