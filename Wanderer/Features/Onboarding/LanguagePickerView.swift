import SwiftUI

struct LanguagePickerView: View {
    @AppStorage("wanderer.selectedLanguage") private var storedLanguage = ""
    @State private var selectedID = LanguageOption.deviceDefault.id
    @State private var hasLoaded = false

    private var selected: LanguageOption {
        LanguageOption.named(selectedID)
    }

    var body: some View {
        ZStack {
            background

            VStack(spacing: 0) {
                header
                languageList
                footer
            }
        }
        .onAppear {
            guard !hasLoaded else { return }
            hasLoaded = true
            selectedID = storedLanguage.isEmpty ? LanguageOption.deviceDefault.id : storedLanguage
        }
    }

    private var background: some View {
        WandererTheme.platinum
            .ignoresSafeArea()
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: LiggaSpace.m) {
            WandererMark(size: 40)
                .padding(.top, LiggaSpace.s)

            VStack(alignment: .leading, spacing: LiggaSpace.xs) {
                Text("Choose your language")
                    .font(.ligga(.largeTitle, weight: .bold))
                    .foregroundStyle(WandererTheme.ink)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityAddTraits(.isHeader)

                Text("We picked one from your device settings. You can change it any time.")
                    .font(.ligga(.subheadline))
                    .foregroundStyle(WandererTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, WandererTheme.gutter)
        .padding(.bottom, LiggaSpace.m)
    }

    private var languageList: some View {
        ScrollView(showsIndicators: false) {
            LazyVStack(spacing: LiggaSpace.xs) {
                ForEach(LanguageOption.all) { language in
                    languageRow(language)
                }
            }
            .padding(.horizontal, WandererTheme.gutter)
            .padding(.vertical, LiggaSpace.xxs)
            .padding(.bottom, LiggaSpace.m)
        }
        .sensoryFeedback(.selection, trigger: selectedID)
    }

    private func languageRow(_ language: LanguageOption) -> some View {
        let isSelected = language.id == selectedID

        return Button {
            withAnimation(.easeOut(duration: 0.18)) {
                selectedID = language.id
            }
        } label: {
            HStack(spacing: LiggaSpace.s) {
                Text(language.nativeName)
                    .font(.ligga(.body, weight: isSelected ? .semibold : .regular))
                    .foregroundStyle(isSelected ? WandererTheme.coralDeep : WandererTheme.ink)

                Spacer(minLength: 8)

                if language.id != "en" || isSelected {
                    Text(language.englishName)
                        .font(.ligga(.caption))
                        .foregroundStyle(WandererTheme.muted)
                        .lineLimit(1)
                }

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.ligga(.title3, weight: .semibold))
                    .foregroundStyle(isSelected ? WandererTheme.coral : WandererTheme.dust)
                    .accessibilityHidden(true)
            }
            .padding(.horizontal, LiggaSpace.m)
            .padding(.vertical, LiggaSpace.xs)
            .frame(minHeight: 56)
            .background(
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isSelected ? 1 : 0.72))
                    .overlay(
                        RoundedRectangle(cornerRadius: 12, style: .continuous)
                            .stroke(isSelected ? WandererTheme.coral : .clear, lineWidth: 2)
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(language.nativeName), \(language.englishName)")
        .accessibilityAddTraits(isSelected ? [.isSelected, .isButton] : .isButton)
    }

    private var footer: some View {
        VStack(spacing: LiggaSpace.xs) {
            PrimaryButton(title: "Continue", action: {
                storedLanguage = selected.id
            })
            .accessibilityIdentifier("language-continue")

            Text("You can change this later in Profile.")
                .font(.ligga(.footnote))
                .foregroundStyle(WandererTheme.muted)
        }
        .padding(.horizontal, WandererTheme.gutter)
        .padding(.top, LiggaSpace.s)
        .padding(.bottom, LiggaSpace.xs)
        .background(
            LinearGradient(
                colors: [WandererTheme.sand.opacity(0), WandererTheme.sand],
                startPoint: .top,
                endPoint: .bottom
            )
            .ignoresSafeArea()
        )
    }
}

#Preview {
    LanguagePickerView()
}
