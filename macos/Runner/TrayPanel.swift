import Cocoa
import SwiftUI

/// The menu bar panel. Dart sends every string and number already localized,
/// so this file only lays them out and reports clicks back.
struct TrayPanelData {
  struct Window {
    var label = "", unit = "剩余", value = "", reset = "", color = "blue"
    var forecast: String?, shortForecast: String?, forecastTone = "success"
    var remaining = 0
  }
  struct Metric { var label = "", value = "" }
  struct Provider: Identifiable { var id: String, label: String }
  var provider = "gpt"
  var providers = [Provider(id: "gpt", label: "GPT"), Provider(id: "claude", label: "Claude")]
  var account = "", status = "", empty = "", todayTitle = "", hoursStart = "", hoursLabel = "", hoursEnd = ""
  var online = true, busy = false
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
    online = j["online"] as? Bool ?? !account.isEmpty
    busy = j["busy"] as? Bool ?? false
    windows = (j["windows"] as? [[String: Any]] ?? []).map {
      let unitText = s($0, "unit")
      return Window(
        label: s($0, "label"),
        unit: unitText.isEmpty ? "剩余" : unitText,
        value: s($0, "value"),
        reset: s($0, "reset"),
        color: s($0, "color"),
        forecast: $0["forecast"] as? String,
        shortForecast: $0["shortForecast"] as? String,
        forecastTone: s($0, "forecastTone"),
        remaining: $0["remaining"] as? Int ?? 0
      )
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
  static let surface = dynamic(0xFBFAFD, 0x252836)
  static let blue = dynamic(0x2F7CF6, 0x6BA7FF)
  static let blueCard = dynamic(0xE8F1FF, 0x1E2B42)
  static let blueBorder = dynamic(0xC9DCFC, 0x2F4569)
  static let blueTrack = dynamic(0xC3D9FA, 0x2C4063)
  static let green = dynamic(0x32B24D, 0x6ACF83)
  static let greenCard = dynamic(0xE6F6EC, 0x1C3026)
  static let greenBorder = dynamic(0xC0E6CD, 0x2B4B3B)
  static let greenTrack = dynamic(0xBAE1C7, 0x294638)
  static let greenPill = dynamic(0xD2F0DC, 0x233D30)
  static let greenPillBorder = dynamic(0xA8DFBA, 0x315944)
  static let greenText = dynamic(0x1E7A34, 0x91DFA4)
  static let amberText = dynamic(0x915F09, 0xF4CF80)
  static let amberFill = dynamic(0xFFF3D6, 0x3E3325)
  static let amberBorder = dynamic(0xF0D49B, 0x574630)
  static let tile = dynamic(0xF1F0F6, 0x1D1F2B)
  static let pillBg = dynamic(0xE6E5EE, 0x1D1F2B)
  static let line = dynamic(0xE4E3EC, 0x3A3E50)
  static let ink = dynamic(0x171A29, 0xF0F1F8)
  static let muted = dynamic(0x6E738A, 0xABB0C4)
}

struct TrayPanelView: View {
  @ObservedObject var model: TrayPanelModel
  private var d: TrayPanelData { model.data }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      header.padding(.horizontal, 16).padding(.top, 14).padding(.bottom, 12)
      Rectangle().fill(Tone.line).frame(height: 1)
      VStack(alignment: .leading, spacing: 14) {
        if d.windows.isEmpty {
          Text(d.empty).font(.system(size: 12)).foregroundColor(Tone.muted)
            .frame(maxWidth: .infinity, alignment: .leading).padding(12)
            .background(
              ZStack {
                RoundedRectangle(cornerRadius: 10).fill(Tone.tile)
                RoundedRectangle(cornerRadius: 10).stroke(Tone.line, lineWidth: 1)
              }.padding(0.5)
            )
        } else {
          HStack(alignment: .top, spacing: 10) {
            ForEach(Array(d.windows.enumerated()), id: \.offset) { _, w in
              windowCard(w)
            }
          }
        }
        today
      }
      .padding(.horizontal, 16)
      .padding(.vertical, 14)
      Rectangle().fill(Tone.line).frame(height: 1)
      footer.padding(.horizontal, 16).padding(.vertical, 11)
    }
    .frame(width: 356)
    .background(Tone.surface)
    .foregroundColor(Tone.ink)
  }

  private var subtitleText: String {
    if d.account.isEmpty { return d.status }
    if d.status.isEmpty || d.status == "已同步" || d.status == "Synced" { return d.account }
    return "\(d.account) · \(d.status)"
  }

  private var header: some View {
    HStack(alignment: .center, spacing: 10) {
      Image(systemName: "hourglass")
        .font(.system(size: 24, weight: .semibold))
        .foregroundColor(Tone.blue)
        .frame(width: 28, height: 32)
      VStack(alignment: .leading, spacing: 4) {
        HStack(spacing: 6) {
          Text("QuotaMate").font(.system(size: 16, weight: .bold))
          Spacer()
          HStack(spacing: 0) {
            ForEach(d.providers) { p in
              Button { model.onProvider(p.id) } label: {
                Text(p.label).font(.system(size: 11, weight: p.id == d.provider ? .semibold : .medium))
                  .padding(.horizontal, 10).padding(.vertical, 3.5)
                  .foregroundColor(p.id == d.provider ? .white : Tone.muted)
                  .background(Capsule().fill(p.id == d.provider ? Tone.blue : Color.clear))
                  .contentShape(Capsule())
              }.buttonStyle(.plain)
            }
          }.padding(2).background(Capsule().fill(Tone.pillBg))
          Button { model.onRefresh() } label: {
            Image(systemName: "arrow.clockwise").font(.system(size: 11.5, weight: .semibold))
              .foregroundColor(Tone.muted).rotationEffect(.degrees(d.busy ? 180 : 0))
              .frame(width: 24, height: 24)
              .background(
                ZStack {
                  RoundedRectangle(cornerRadius: 6).fill(Tone.surface)
                  RoundedRectangle(cornerRadius: 6).stroke(Tone.line, lineWidth: 1)
                }.padding(0.5)
              )
              .contentShape(Rectangle())
          }.buttonStyle(.plain).help(d.refresh).disabled(d.busy)
        }
        HStack(spacing: 6) {
          Circle()
            .fill(d.online ? Tone.green : Tone.muted)
            .frame(width: 6.5, height: 6.5)
          Text(subtitleText)
            .font(.system(size: 11))
            .foregroundColor(Tone.muted)
            .lineLimit(1)
            .truncationMode(.tail)
        }
      }
    }
  }

  private func windowCard(_ w: TrayPanelData.Window) -> some View {
    let isGreen = w.color == "green"
    let accent = isGreen ? Tone.green : Tone.blue
    let cardBg = isGreen ? Tone.greenCard : Tone.blueCard
    let cardBorder = isGreen ? Tone.greenBorder : Tone.blueBorder
    let ringTrack = isGreen ? Tone.greenTrack : Tone.blueTrack
    let progress = CGFloat(min(100, max(0, w.remaining))) / 100.0
    let badgeText = w.shortForecast ?? w.forecast
    return VStack(spacing: 8) {
      Text(w.label)
        .font(.system(size: 13, weight: .semibold))
        .foregroundColor(Tone.ink)
        .lineLimit(1)
      ZStack {
        Circle()
          .stroke(ringTrack, lineWidth: 7.5)
        Circle()
          .trim(from: 0, to: progress)
          .stroke(accent, style: StrokeStyle(lineWidth: 7.5, lineCap: .round))
          .rotationEffect(.degrees(-90))
        VStack(spacing: 1) {
          Text("\(w.remaining)%")
            .font(.system(size: 20, weight: .bold))
            .foregroundColor(Tone.ink)
          Text(w.unit)
            .font(.system(size: 11, weight: .medium))
            .foregroundColor(Tone.ink.opacity(0.75))
        }
      }
      .frame(width: 86, height: 86)
      .padding(.vertical, 2)
      Text(w.reset)
        .font(.system(size: 11.5, weight: .medium))
        .foregroundColor(Tone.ink.opacity(0.85))
        .lineLimit(1)
        .minimumScaleFactor(0.85)
      if let forecast = badgeText, !forecast.isEmpty {
        let warning = w.forecastTone == "warning"
        HStack(spacing: 4) {
          Image(systemName: warning ? "chart.line.uptrend.xyaxis" : "checkmark.circle.fill")
            .font(.system(size: 10, weight: .semibold))
          Text(forecast)
            .font(.system(size: 10.5, weight: .medium))
            .lineLimit(1)
            .minimumScaleFactor(0.8)
        }
        .foregroundColor(warning ? Tone.amberText : Tone.greenText)
        .padding(.horizontal, 8)
        .padding(.vertical, 4.5)
        .frame(maxWidth: .infinity)
        .background(
          ZStack {
            RoundedRectangle(cornerRadius: 11).fill(warning ? Tone.amberFill : Tone.greenPill)
            RoundedRectangle(cornerRadius: 11).stroke(warning ? Tone.amberBorder : Tone.greenPillBorder, lineWidth: 1)
          }.padding(0.5)
        )
      }
    }
    .padding(.horizontal, 10)
    .padding(.vertical, 12)
    .frame(maxWidth: .infinity)
    .background(
      ZStack {
        RoundedRectangle(cornerRadius: 12).fill(cardBg)
        RoundedRectangle(cornerRadius: 12).stroke(cardBorder, lineWidth: 1)
      }.padding(0.5)
    )
  }

  private var today: some View {
    VStack(alignment: .leading, spacing: 8) {
      Text(d.todayTitle)
        .font(.system(size: 12.5, weight: .semibold))
        .foregroundColor(Tone.ink)
      VStack(spacing: 11) {
        HStack(spacing: 0) {
          ForEach(Array(d.metrics.enumerated()), id: \.offset) { i, m in
            if i > 0 {
              Rectangle().fill(Tone.line).frame(width: 1, height: 30)
            }
            VStack(spacing: 3) {
              Text(m.label)
                .font(.system(size: 11))
                .foregroundColor(Tone.muted)
                .lineLimit(1)
              Text(m.value)
                .font(.system(size: 16, weight: .bold))
                .foregroundColor(Tone.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
            }
            .frame(maxWidth: .infinity)
          }
        }
        Rectangle().fill(Tone.line).frame(height: 1)
        VStack(spacing: 6) {
          HStack(alignment: .bottom, spacing: 5) {
            ForEach(Array(d.hours.enumerated()), id: \.offset) { i, v in
              RoundedRectangle(cornerRadius: 3.5)
                .fill(Tone.blue.opacity(i == d.hours.count - 1 ? 0.42 : 0.92))
                .frame(height: max(4, 38 * CGFloat(v)))
                .frame(maxWidth: .infinity)
            }
          }
          .frame(height: 38, alignment: .bottom)
          .padding(.top, 2)
          HStack {
            Text(d.hoursStart)
            Spacer()
            Text(d.hoursLabel)
            Spacer()
            Text(d.hoursEnd)
          }
          .font(.system(size: 10.5))
          .foregroundColor(Tone.muted)
        }
      }
      .padding(12)
      .background(
        ZStack {
          RoundedRectangle(cornerRadius: 12).fill(Tone.tile)
          RoundedRectangle(cornerRadius: 12).stroke(Tone.line, lineWidth: 1)
        }.padding(0.5)
      )
    }
  }

  private var footer: some View {
    HStack {
      Button { model.onOpen() } label: {
        Label(d.open, systemImage: "macwindow")
          .font(.system(size: 12, weight: .medium))
          .padding(.horizontal, 11)
          .padding(.vertical, 5.5)
          .background(
            ZStack {
              RoundedRectangle(cornerRadius: 7).fill(Tone.surface)
              RoundedRectangle(cornerRadius: 7).stroke(Tone.line, lineWidth: 1)
            }.padding(0.5)
          )
          .contentShape(Rectangle())
      }.buttonStyle(.plain)
      Spacer()
      Button(d.settings) { model.onSettings() }.buttonStyle(.plain).foregroundColor(Tone.muted)
      Button(d.quit) { NSApp.terminate(nil) }.buttonStyle(.plain).foregroundColor(Tone.muted).padding(.leading, 12)
    }.font(.system(size: 12))
  }
}
