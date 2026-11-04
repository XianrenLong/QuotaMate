import Cocoa
import SwiftUI

/// The menu bar panel. Dart sends every string and number already localized,
/// so this file only lays them out and reports clicks back.
struct TrayPanelData {
  struct Window { var label = "", value = "", reset = "", color = "blue", forecast: String?, forecastTone = "success"; var remaining = 0 }
  struct Metric { var label = "", value = "" }
  struct Provider: Identifiable { var id: String, label: String }
  var provider = "gpt"
  var providers = [Provider(id: "gpt", label: "GPT"), Provider(id: "claude", label: "Claude")]
  var account = "", status = "", empty = "", todayTitle = "", hoursStart = "", hoursLabel = "", hoursEnd = ""
  var busy = false
  var windows: [Window] = []
  var metrics: [Metric] = []
  var hours: [Double] = []
  var open = "Open QuotaMate", settings = "Settings", quit = "Quit", refresh = "Refresh"

  init() {}
  init(_ j: [String: Any]) {
    func s(_ m: [String: Any], _ k: String) -> String { m[k] as? String ?? "" }
    provider = s(j, "provider")
    providers = (j["providers"] as? [[String: Any]] ?? []).map { Provider(id: s($0, "id"), label: s($0, "label")) }
    account = s(j, "account"); status = s(j, "status"); empty = s(j, "empty")
    todayTitle = s(j, "todayTitle"); hoursStart = s(j, "hoursStart"); hoursLabel = s(j, "hoursLabel"); hoursEnd = s(j, "hoursEnd")
    busy = j["busy"] as? Bool ?? false
    windows = (j["windows"] as? [[String: Any]] ?? []).map {
      Window(label: s($0, "label"), value: s($0, "value"), reset: s($0, "reset"), color: s($0, "color"),
             forecast: $0["forecast"] as? String, forecastTone: s($0, "forecastTone"), remaining: $0["remaining"] as? Int ?? 0)
    }
    metrics = (j["metrics"] as? [[String: Any]] ?? []).map { Metric(label: s($0, "label"), value: s($0, "value")) }
    hours = (j["hours"] as? [Any] ?? []).compactMap { ($0 as? NSNumber)?.doubleValue }
    let actions = j["actions"] as? [String: Any] ?? [:]
    open = s(actions, "open"); settings = s(actions, "settings"); quit = s(actions, "quit"); refresh = s(actions, "refresh")
  }
}

final class TrayPanelModel: ObservableObject {
  @Published var data = TrayPanelData()
  var onProvider: (String) -> Void = { _ in }
  var onRefresh: () -> Void = {}
  var onOpen: () -> Void = {}
  var onSettings: () -> Void = {}
}

/// The app's own palette, light and dark, matching lib/ui/palette.dart.
private enum Tone {
  static func dynamic(_ light: UInt32, _ dark: UInt32) -> Color {
    Color(nsColor: NSColor(name: nil) { appearance in
      let hex = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua ? dark : light
      return NSColor(srgbRed: CGFloat(hex >> 16 & 0xFF) / 255, green: CGFloat(hex >> 8 & 0xFF) / 255, blue: CGFloat(hex & 0xFF) / 255, alpha: 1)
    })
  }
  static let blue = dynamic(0x3483FF, 0x6BA7FF)
  static let green = dynamic(0x35B54A, 0x6ACF83)
  static let amber = dynamic(0xDC962F, 0xF0B45E)
  static let amberText = dynamic(0x91600A, 0xF4CF80)
  static let amberFill = dynamic(0xFFF4DF, 0x3E3325)
  static let greenText = dynamic(0x24833A, 0x91DFA4)
  static let track = dynamic(0xE5E4EE, 0x383D4F)
  static let tile = dynamic(0xEFEEF4, 0x1D1F2B)
  static let line = dynamic(0xE9E8F0, 0x3A3E50)
  static let ink = dynamic(0x171A29, 0xF0F1F8)
  static let muted = dynamic(0x7C8099, 0xABB0C4)
}

struct TrayPanelView: View {
  @ObservedObject var model: TrayPanelModel
  private var d: TrayPanelData { model.data }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header
      Text(d.account.isEmpty ? d.status : "\(d.account)\n\(d.status)")
        .font(.system(size: 11)).foregroundColor(Tone.muted).lineSpacing(2)
        .fixedSize(horizontal: false, vertical: true).padding(.top, 8).padding(.bottom, 12)
      if d.windows.isEmpty {
        Text(d.empty).font(.system(size: 12)).foregroundColor(Tone.muted)
          .frame(maxWidth: .infinity, alignment: .leading).padding(10)
          .background(RoundedRectangle(cornerRadius: 7).fill(Tone.tile)).padding(.bottom, 12)
      }
      ForEach(Array(d.windows.enumerated()), id: \.offset) { _, w in windowRow(w).padding(.bottom, 12) }
      Divider().overlay(Tone.line).padding(.bottom, 10)
      today
      footer.padding(.top, 12)
    }
    .padding(16)
    .frame(width: 340)
    .foregroundColor(Tone.ink)
  }

  private var header: some View {
    HStack(spacing: 6) {
      Image(systemName: "hourglass").foregroundColor(Tone.blue)
      Text("QuotaMate").font(.system(size: 14, weight: .semibold))
      Spacer()
      HStack(spacing: 0) {
        ForEach(d.providers) { p in
          Button { model.onProvider(p.id) } label: {
            Text(p.label).font(.system(size: 11, weight: p.id == d.provider ? .semibold : .regular))
              .padding(.horizontal, 10).padding(.vertical, 3)
              .foregroundColor(p.id == d.provider ? .white : Tone.muted)
              .background(Capsule().fill(p.id == d.provider ? Tone.blue : Color.clear))
              .contentShape(Capsule())
          }.buttonStyle(.plain)
        }
      }.padding(2).background(Capsule().fill(Tone.tile))
      Button { model.onRefresh() } label: {
        Image(systemName: "arrow.clockwise").font(.system(size: 12, weight: .medium))
          .foregroundColor(Tone.muted).rotationEffect(.degrees(d.busy ? 180 : 0))
          .frame(width: 22, height: 22).contentShape(Rectangle())
      }.buttonStyle(.plain).help(d.refresh).disabled(d.busy)
    }
  }

  private func windowRow(_ w: TrayPanelData.Window) -> some View {
    let color = w.color == "green" ? Tone.green : Tone.blue
    return VStack(alignment: .leading, spacing: 5) {
      HStack {
        Text(w.label).font(.system(size: 12))
        Spacer()
        Text(w.value).font(.system(size: 12, weight: .semibold))
      }
      GeometryReader { g in
        ZStack(alignment: .leading) {
          Capsule().fill(Tone.track)
          Capsule().fill(color).frame(width: max(4, g.size.width * CGFloat(min(100, max(0, w.remaining))) / 100))
        }
      }.frame(height: 7)
      Text(w.reset).font(.system(size: 11)).foregroundColor(Tone.muted)
      if let forecast = w.forecast {
        let warning = w.forecastTone == "warning"
        HStack(spacing: 5) {
          Image(systemName: warning ? "chart.line.downtrend.xyaxis" : "checkmark.circle").font(.system(size: 10, weight: .semibold))
          Text(forecast).font(.system(size: 11)).fixedSize(horizontal: false, vertical: true)
        }
        .foregroundColor(warning ? Tone.amberText : Tone.greenText)
        .padding(.horizontal, 8).padding(.vertical, 5)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(RoundedRectangle(cornerRadius: 6).fill(warning ? Tone.amberFill : Tone.tile))
      }
    }
  }

  private var today: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(d.todayTitle).font(.system(size: 11)).foregroundColor(Tone.muted)
      HStack(spacing: 8) {
        ForEach(Array(d.metrics.enumerated()), id: \.offset) { _, m in
          VStack(alignment: .leading, spacing: 2) {
            Text(m.label).font(.system(size: 10)).foregroundColor(Tone.muted).lineLimit(1)
            Text(m.value).font(.system(size: 14, weight: .semibold)).lineLimit(1).minimumScaleFactor(0.7)
          }
          .frame(maxWidth: .infinity, alignment: .leading).padding(8)
          .background(RoundedRectangle(cornerRadius: 7).fill(Tone.tile))
        }
      }
      HStack(alignment: .bottom, spacing: 3) {
        ForEach(Array(d.hours.enumerated()), id: \.offset) { i, v in
          RoundedRectangle(cornerRadius: 2)
            .fill(Tone.blue.opacity(i == d.hours.count - 1 ? 0.45 : 0.85))
            .frame(height: max(2, 30 * CGFloat(v)))
            .frame(maxWidth: .infinity)
        }
      }.frame(height: 30, alignment: .bottom).padding(.top, 2)
      HStack {
        Text(d.hoursStart); Spacer(); Text(d.hoursLabel); Spacer(); Text(d.hoursEnd)
      }.font(.system(size: 10)).foregroundColor(Tone.muted)
    }
  }

  private var footer: some View {
    HStack {
      Button { model.onOpen() } label: {
        Label(d.open, systemImage: "macwindow").font(.system(size: 12))
          .padding(.horizontal, 10).padding(.vertical, 5)
          .background(RoundedRectangle(cornerRadius: 6).stroke(Tone.line))
          .contentShape(Rectangle())
      }.buttonStyle(.plain)
      Spacer()
      Button(d.settings) { model.onSettings() }.buttonStyle(.plain).foregroundColor(Tone.muted)
      Button(d.quit) { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundColor(Tone.muted).padding(.leading, 10)
    }.font(.system(size: 12))
  }
}
