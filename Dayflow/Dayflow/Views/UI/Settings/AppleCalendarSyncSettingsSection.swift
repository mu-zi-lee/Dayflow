import SwiftUI

struct AppleCalendarSyncSettingsSection: View {
  @ObservedObject private var sync = AppleCalendarSync.shared

  var body: some View {
    SettingsSection(title: "Apple Calendar", subtitle: "") {
      VStack(alignment: .leading, spacing: 14) {
        if !sync.hasAccess {
          SettingsPrimaryButton(
            title: "Connect Apple Calendar",
            systemImage: "calendar.badge.plus",
            isLoading: sync.isAuthorizing,
            isDisabled: sync.isAuthorizing,
            action: sync.requestAccess
          )
        } else {
          if let name = sync.calendarName {
            Label(name, systemImage: "calendar")
              .font(.custom("Figtree", size: 13))
              .foregroundStyle(SettingsStyle.text)
          } else {
            Picker("Account", selection: $sync.selectedAccountID) {
              ForEach(sync.accounts) { account in
                Text(account.name).tag(account.id)
              }
            }
            .frame(maxWidth: 320)
          }
        }
        if sync.hasAccess || sync.isEnabled {
          Toggle("Sync activities automatically", isOn: Binding(
            get: { sync.isEnabled }, set: sync.setEnabled
          ))
          .toggleStyle(.switch)
          .font(.custom("Figtree", size: 13))
          .disabled(!sync.isEnabled && sync.calendarName == nil && sync.accounts.isEmpty)
        }
        if let date = sync.lastSyncAt {
          Text("Last synced \(date.formatted(date: .abbreviated, time: .shortened))")
            .font(.custom("Figtree", size: 12))
            .foregroundStyle(SettingsStyle.statusGood)
        }
        if sync.isEnabled && sync.hasAccess {
          SettingsSecondaryButton(
            title: "Sync all history",
            systemImage: "arrow.triangle.2.circlepath",
            action: sync.syncAllHistory
          )
        }
        if let error = sync.errorMessage {
          Text(error)
            .font(.custom("Figtree", size: 12))
            .foregroundStyle(SettingsStyle.destructive)
            .fixedSize(horizontal: false, vertical: true)
        }
      }
      .onAppear { sync.start() }
    }
  }
}
