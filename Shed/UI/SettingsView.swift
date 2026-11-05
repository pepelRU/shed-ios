import SwiftUI

struct SettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @EnvironmentObject private var preferences: SchedulePreferences
    @EnvironmentObject private var repository: ScheduleRepository
    @EnvironmentObject private var dnevnikAuth: DnevnikAuth
    @EnvironmentObject private var updateChecker: UpdateChecker

    @State private var showLogin = false

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 12) {
                header

                section(icon: "person.2.fill", title: "Подгруппа") {
                    HStack(spacing: 8) {
                        ForEach([1, 2], id: \.self) { value in
                            ChoicePill(
                                title: "\(value)",
                                selected: preferences.subgroup == value
                            ) {
                                guard preferences.subgroup != value else { return }
                                Haptics.selection()
                                preferences.subgroup = value
                            }
                        }
                    }
                }

                divider
                section(icon: "sun.max.fill", title: "Оформление") {
                    HStack(spacing: 6) {
                        ForEach(ThemeMode.allCases, id: \.self) { mode in
                            ChoicePill(
                                title: mode.title,
                                selected: preferences.themeMode == mode
                            ) {
                                guard preferences.themeMode != mode else { return }
                                Haptics.selection()
                                preferences.themeMode = mode
                            }
                        }
                    }
                }

                divider
                section(icon: "calendar", title: "Проверять изменения") {
                    VStack(spacing: 8) {
                        ForEach(ScheduleRefreshPeriod.allCases, id: \.self) { period in
                            ChoicePill(
                                title: period.title,
                                selected: preferences.refreshPeriod == period,
                                fillWidth: true
                            ) {
                                guard preferences.refreshPeriod != period else { return }
                                Haptics.selection()
                                preferences.refreshPeriod = period
                            }
                        }
                    }
                }

                divider
                dnevnikRow
                divider
                updateRow
                divider
                diagnostics
                divider

                Text("Shed · версия \(version)")
                    .font(.caption)
                    .foregroundStyle(ShedColors.muted)
                    .frame(maxWidth: .infinity)
                    .padding(.top, 4)
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 28)
        }
        .background(ShedColors.background.ignoresSafeArea())
        .fullScreenCover(isPresented: $showLogin) {
            DnevnikLoginView { success in
                showLogin = false
                if success {
                    Task { await repository.refresh() }
                }
            }
            .environmentObject(dnevnikAuth)
        }
    }

    private var header: some View {
        HStack(spacing: 10) {
            Text("Настройки")
                .font(.title2.weight(.bold))
                .foregroundStyle(ShedColors.text)
            Spacer()
            Link(destination: URL(string: "https://t.me/tyukenov")!) {
                Image(systemName: "paperplane.fill")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(ShedColors.primary)
                    .frame(width: 40, height: 40)
                    .background(ShedColors.primary.opacity(0.12), in: Circle())
            }
            Button {
                Haptics.tick()
                dismiss()
            } label: {
                Image(systemName: "xmark")
                    .font(.system(size: 15, weight: .bold))
                    .foregroundStyle(ShedColors.text)
                    .frame(width: 40, height: 40)
                    .background(ShedColors.surfaceVariant, in: Circle())
            }
            .buttonStyle(.plain)
        }
        .padding(.top, 6)
        .padding(.bottom, 4)
    }

    private var dnevnikRow: some View {
        HStack(spacing: 12) {
            iconBadge("graduationcap.fill")
            VStack(alignment: .leading, spacing: 2) {
                Text("Дневник.ру")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ShedColors.text)
                Text(dnevnikAuth.isSignedIn
                    ? dnevnikAuth.state.message
                    : "Вход через Госуслуги. Пароль Shed не читает и не сохраняет.")
                    .font(.caption)
                    .foregroundStyle(ShedColors.muted)
                    .lineLimit(2)
            }
            Spacer()
            if dnevnikAuth.isSignedIn {
                Button("Выйти") {
                    Haptics.tick()
                    dnevnikAuth.signOut()
                    Task { await repository.refresh() }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ShedColors.error)
                .buttonStyle(.plain)
            } else {
                Button("Войти") {
                    Haptics.tick()
                    showLogin = true
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ShedColors.primary)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var updateRow: some View {
        HStack(spacing: 12) {
            iconBadge("arrow.triangle.2.circlepath")
            VStack(alignment: .leading, spacing: 2) {
                Text("Обновления")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(ShedColors.text)
                Text(updateStatusText)
                    .font(.caption)
                    .foregroundStyle(ShedColors.muted)
                    .lineLimit(2)
            }
            Spacer()
            switch updateChecker.state {
            case .checking:
                ProgressView()
            case .available(let info):
                Link("Скачать", destination: URL(string: info.url) ?? URL(string: "https://github.com")!)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(ShedColors.primary)
            case .upToDate, .idle, .error:
                Button("Проверить") {
                    Haptics.tick()
                    Task { await updateChecker.check(force: true) }
                }
                .font(.caption.weight(.semibold))
                .foregroundStyle(ShedColors.primary)
                .buttonStyle(.plain)
            }
        }
        .padding(.vertical, 6)
    }

    private var diagnostics: some View {
        VStack(alignment: .leading, spacing: 7) {
            HStack(spacing: 10) {
                iconBadge("waveform.path.ecg")
                Text("Диагностика")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ShedColors.text)
            }
            Text(diagnosticsText)
                .font(.caption)
                .foregroundStyle(ShedColors.muted)
            if let error = repository.snapshot.errorMessage, !error.isEmpty {
                Text(error)
                    .font(.caption)
                    .foregroundStyle(ShedColors.error)
            }
            Button {
                Haptics.tick()
                Task { await repository.refresh() }
            } label: {
                HStack(spacing: 7) {
                    if repository.snapshot.isRefreshing {
                        ProgressView()
                            .controlSize(.small)
                    }
                    Text(repository.snapshot.isRefreshing ? "Обновляю…" : "Обновить сейчас")
                        .font(.caption.weight(.semibold))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 9)
                .background(ShedColors.surfaceVariant, in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                .foregroundStyle(ShedColors.primary)
            }
            .buttonStyle(.plain)
            .disabled(repository.snapshot.isRefreshing)
        }
        .padding(.vertical, 4)
    }

    private var diagnosticsText: String {
        let checked = repository.snapshot.changesCheckedAt
            .map { DateFormatters.updated.string(from: $0) } ?? "ещё не проверялось"
        let source = repository.snapshot.fromCache ? "кэш" : "сеть"
        return "Проверено: \(checked) · дней: \(repository.snapshot.days.count) · источник: \(source)"
    }

    private var updateStatusText: String {
        switch updateChecker.state {
        case .idle: return "Проверка при входе в приложение"
        case .checking: return "Проверяю новую версию"
        case .upToDate: return "Установлена последняя версия"
        case .available(let info): return "Доступна версия \(info.version)"
        case .error(let message): return message
        }
    }

    private var version: String {
        let short = Bundle.main.object(forInfoDictionaryKey: "CFBundleShortVersionString") as? String ?? "1.0"
        let build = Bundle.main.object(forInfoDictionaryKey: "CFBundleVersion") as? String ?? "1"
        return "\(short) (\(build))"
    }

    private var divider: some View {
        Rectangle()
            .fill(ShedColors.outline.opacity(0.65))
            .frame(height: 1)
    }

    private func section<Content: View>(
        icon: String,
        title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 11) {
            HStack(spacing: 10) {
                iconBadge(icon)
                Text(title)
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(ShedColors.text)
            }
            content()
        }
        .padding(.vertical, 4)
    }

    private func iconBadge(_ name: String) -> some View {
        Image(systemName: name)
            .font(.system(size: 15, weight: .semibold))
            .foregroundStyle(ShedColors.primary)
            .frame(width: 34, height: 34)
            .background(ShedColors.primary.opacity(0.10), in: RoundedRectangle(cornerRadius: 11, style: .continuous))
    }
}

struct ChoicePill: View {
    let title: String
    let selected: Bool
    var fillWidth: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold))
                .lineLimit(1)
                .minimumScaleFactor(0.8)
                .frame(maxWidth: fillWidth ? .infinity : nil)
                .padding(.horizontal, 8)
                .padding(.vertical, 10)
                .background(
                    selected ? ShedColors.primary : ShedColors.surfaceVariant,
                    in: RoundedRectangle(cornerRadius: 11, style: .continuous)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 11, style: .continuous)
                        .stroke(selected ? ShedColors.primary : ShedColors.outline, lineWidth: 1)
                )
                .foregroundStyle(selected ? ShedColors.onPrimary : ShedColors.muted)
        }
        .buttonStyle(.plain)
        .frame(maxWidth: fillWidth ? .infinity : nil)
    }
}
