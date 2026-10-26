// Active hike progress and useful shortcuts on the Lock Screen and Dynamic Island.
import ActivityKit
import WidgetKit
import SwiftUI

struct ManualHikeAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var trailName: String
    var startedAt: Date
    var expectedReturnAt: Date?
    var checkIns: Int
    var queuedUpdates: Int
    var batteryLevel: Int
    var distanceKm: Double
    var routePointCount: Int
    var safetyPhase: String
    var warningDeadline: Date?

    var needsSafetyAttention: Bool {
      safetyPhase == "warning" || safetyPhase == "escalated"
    }

    var recordingLabel: String {
      if safetyPhase == "warning" { return "Safety alert · open to respond" }
      if safetyPhase == "escalated" { return "SOS alert active" }
      return queuedUpdates > 0 ? "Recording · saved on phone" : "Recording hike"
    }
  }

  var sessionId: String
}

enum HikeLiveActivityAction: String {
  case reportHazard = "report-hazard"
  case active
  case safety
}

func hikeLiveActivityURL(_ action: HikeLiveActivityAction, sessionId: String) -> URL {
  var components = URLComponents()
  components.scheme = "hikercircle"
  components.host = "hike"
  components.path = "/\(action.rawValue)"
  components.queryItems = [
    URLQueryItem(name: "source", value: "ios_live_activity"),
    URLQueryItem(name: "sessionId", value: sessionId),
  ]
  return components.url!
}

struct ManualHikeLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ManualHikeAttributes.self) { context in
      HikeLiveActivityLockScreenView(state: context.state, sessionId: context.attributes.sessionId)
        .activityBackgroundTint(HikeLiveColors.background)
        .activitySystemActionForegroundColor(.white)
        .widgetURL(hikeLiveActivityURL(context.state.needsSafetyAttention ? .safety : .active, sessionId: context.attributes.sessionId))
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          HStack(spacing: 7) {
            Image(systemName: "figure.hiking")
              .font(.title3.weight(.semibold))
              .foregroundStyle(HikeLiveColors.mint)
            VStack(alignment: .leading, spacing: 3) {
              Text("HikerCircle")
                .font(.system(size: 10, weight: .semibold))
                .foregroundStyle(HikeLiveColors.secondary)
              Text(context.state.trailName)
                .font(.caption.weight(.bold))
                .foregroundStyle(.white)
                .lineLimit(1)
            }
          }
        }
        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text(String(format: "%.2f km", context.state.distanceKm))
              .font(.system(size: 20, weight: .bold, design: .rounded))
              .monospacedDigit()
              .foregroundStyle(.white)
            HikeLiveElapsedTime(startedAt: context.state.startedAt, fontSize: 13)
              .frame(width: 88, alignment: .trailing)
              .foregroundStyle(HikeLiveColors.secondary)
          }
        }
        DynamicIslandExpandedRegion(.bottom) {
          VStack(alignment: .leading, spacing: 9) {
            if context.state.needsSafetyAttention {
              Label(context.state.recordingLabel, systemImage: "exclamationmark.shield.fill")
                .font(.caption2.weight(.semibold))
                .foregroundStyle(HikeLiveColors.warning)
            }
            HikeLiveActivityActions(state: context.state, sessionId: context.attributes.sessionId)
          }
          .padding(.top, 4)
        }
      } compactLeading: {
        Image(systemName: context.state.needsSafetyAttention ? "exclamationmark.shield.fill" : "figure.hiking")
          .font(.system(size: 16, weight: .semibold))
          .foregroundStyle(context.state.needsSafetyAttention ? HikeLiveColors.warning : HikeLiveColors.mint)
      } compactTrailing: {
        Text(String(format: "%.1f km", context.state.distanceKm))
          .font(.system(size: 12, weight: .bold, design: .rounded))
          .monospacedDigit()
          .foregroundStyle(.white)
      } minimal: {
        Image(systemName: context.state.needsSafetyAttention ? "exclamationmark.shield.fill" : "figure.hiking")
          .font(.system(size: 15, weight: .semibold))
          .foregroundStyle(context.state.needsSafetyAttention ? HikeLiveColors.warning : HikeLiveColors.mint)
      }
      .widgetURL(hikeLiveActivityURL(context.state.needsSafetyAttention ? .safety : .active, sessionId: context.attributes.sessionId))
      .keylineTint(HikeLiveColors.mint)
    }
  }
}

struct HikeLiveActivityLockScreenView: View {
  let state: ManualHikeAttributes.ContentState
  let sessionId: String

  var body: some View {
    VStack(alignment: .leading, spacing: 12) {
      HStack(spacing: 10) {
        Image(systemName: state.needsSafetyAttention ? "exclamationmark.shield.fill" : "figure.hiking")
          .font(.system(size: 19, weight: .semibold))
          .foregroundStyle(state.needsSafetyAttention ? HikeLiveColors.warning : HikeLiveColors.mint)
          .frame(width: 34, height: 34)
          .background(HikeLiveColors.mint.opacity(0.1), in: RoundedRectangle(cornerRadius: 11))

        VStack(alignment: .leading, spacing: 3) {
          Text(state.trailName)
            .font(.system(size: 16, weight: .bold))
            .foregroundStyle(.white)
            .lineLimit(1)
          HStack(spacing: 5) {
            Circle()
              .fill(state.needsSafetyAttention ? HikeLiveColors.warning : HikeLiveColors.mint)
              .frame(width: 5, height: 5)
            Text(state.recordingLabel)
              .font(.system(size: 10, weight: .medium))
              .foregroundStyle(state.needsSafetyAttention ? HikeLiveColors.warning : HikeLiveColors.secondary)
              .lineLimit(1)
          }
        }
        Spacer(minLength: 4)
        HStack(spacing: 4) {
          Image(systemName: batterySymbol)
            .font(.system(size: 13, weight: .medium))
          Text("\(state.batteryLevel)%")
            .font(.system(size: 11, weight: .semibold))
            .monospacedDigit()
        }
        .foregroundStyle(state.batteryLevel <= 20 ? HikeLiveColors.warning : HikeLiveColors.secondary)
        .accessibilityLabel("Phone battery \(state.batteryLevel) percent")
      }

      HStack(alignment: .top, spacing: 10) {
        metric(label: "Distance") {
          HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(String(format: "%.2f", state.distanceKm))
              .font(.system(size: 25, weight: .bold, design: .rounded))
              .monospacedDigit()
            Text("km")
              .font(.system(size: 12, weight: .medium))
              .foregroundStyle(HikeLiveColors.secondary)
          }
        }
        metric(label: "Elapsed") {
          HikeLiveElapsedTime(startedAt: state.startedAt, fontSize: 21)
            .frame(height: 30, alignment: .leading)
        }
        metric(label: "Return") {
          Group {
            if let expectedReturnAt = state.expectedReturnAt {
              Text(expectedReturnAt, style: .time)
            } else {
              Text("—")
            }
          }
          .font(.system(size: 21, weight: .semibold, design: .rounded))
          .monospacedDigit()
          .frame(height: 30, alignment: .leading)
        }
      }
      .foregroundStyle(.white)
      .lineLimit(1)
      .minimumScaleFactor(0.75)

      HikeLiveActivityActions(state: state, sessionId: sessionId)
    }
    .padding(.horizontal, 16)
    .padding(.vertical, 11)
  }

  private var batterySymbol: String {
    switch state.batteryLevel {
    case ...10: return "battery.0percent"
    case ...35: return "battery.25percent"
    case ...60: return "battery.50percent"
    case ...85: return "battery.75percent"
    default: return "battery.100percent"
    }
  }

  private func metric<Value: View>(label: String, @ViewBuilder value: () -> Value) -> some View {
    VStack(alignment: .leading, spacing: 2) {
      value()
      Text(label)
        .font(.system(size: 10, weight: .medium))
        .foregroundStyle(HikeLiveColors.secondary)
    }
    .frame(maxWidth: .infinity, alignment: .leading)
  }
}

private struct HikeLiveElapsedTime: View {
  let startedAt: Date
  let fontSize: CGFloat

  var body: some View {
    Text(timerInterval: startedAt...Date.distantFuture, countsDown: false)
      .font(.system(size: fontSize, weight: .semibold, design: .rounded))
      .monospacedDigit()
      .lineLimit(1)
      .minimumScaleFactor(0.75)
  }
}

struct HikeLiveActivityActions: View {
  let state: ManualHikeAttributes.ContentState
  let sessionId: String

  var body: some View {
    HStack(spacing: 8) {
      action(
        "Report hazard", symbol: "exclamationmark.triangle", action: .reportHazard,
        foreground: HikeLiveColors.background, background: HikeLiveColors.mint
      )
      action(
        state.needsSafetyAttention ? "Open safety" : "Open hike",
        symbol: state.needsSafetyAttention ? "exclamationmark.shield" : "arrow.up.right",
        action: state.needsSafetyAttention ? .safety : .active,
        foreground: state.needsSafetyAttention ? HikeLiveColors.warning : .white,
        background: Color.white.opacity(0.09)
      )
    }
  }

  private func action(
    _ title: String, symbol: String, action: HikeLiveActivityAction,
    foreground: Color, background: Color
  ) -> some View {
    Link(destination: hikeLiveActivityURL(action, sessionId: sessionId)) {
      HStack(spacing: 6) {
        Image(systemName: symbol)
          .font(.system(size: 12, weight: .semibold))
        Text(title)
          .font(.system(size: 12, weight: .semibold))
          .lineLimit(1)
          .minimumScaleFactor(0.8)
      }
      .foregroundStyle(foreground)
      .frame(maxWidth: .infinity)
      .frame(minHeight: 34)
      .background(background, in: RoundedRectangle(cornerRadius: 11))
      .contentShape(RoundedRectangle(cornerRadius: 11))
    }
    .buttonStyle(.plain)
  }
}

private enum HikeLiveColors {
  static let background = Color(red: 0.035, green: 0.12, blue: 0.09)
  static let mint = Color(red: 0.64, green: 0.91, blue: 0.69)
  static let secondary = Color.white.opacity(0.64)
  static let warning = Color(red: 1, green: 0.70, blue: 0.38)
}
