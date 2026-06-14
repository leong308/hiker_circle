//
//  ManualHikeLiveActivity.swift
//  Runner
//
//  Created by Leong Zi Qi on 13/06/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ManualHikeAttributes: ActivityAttributes {
  public struct ContentState: Codable, Hashable {
    var trailName: String
    var startedAt: Date
    var expectedReturnAt: Date?
    var checkIns: Int
    var manualPins: Int
    var queuedUpdates: Int
    var batteryLevel: Int
    var distanceKm: Double
    var routePointCount: Int
  }

  var sessionId: String
}

struct ManualHikeLiveActivity: Widget {
  var body: some WidgetConfiguration {
    ActivityConfiguration(for: ManualHikeAttributes.self) { context in
      HikeLiveActivityLockScreenView(context: context)
        .activityBackgroundTint(HikeLiveColors.deepGreen)
        .activitySystemActionForegroundColor(.white)
    } dynamicIsland: { context in
      DynamicIsland {
        DynamicIslandExpandedRegion(.leading) {
          VStack(alignment: .leading, spacing: 2) {
            Text("HikerCircle")
              .font(.caption2.bold())
              .foregroundStyle(.white.opacity(0.75))

            Text(context.state.trailName)
              .font(.caption.bold())
              .foregroundStyle(.white)
              .lineLimit(1)
          }
        }

        DynamicIslandExpandedRegion(.trailing) {
          VStack(alignment: .trailing, spacing: 2) {
            Text("Distance")
              .font(.caption2)
              .foregroundStyle(.white.opacity(0.75))

            Text(String(format: "%.2f km", context.state.distanceKm))
              .font(.title3.bold())
              .foregroundStyle(.white)
          }
        }

        DynamicIslandExpandedRegion(.bottom) {
          HStack(spacing: 8) {
            liveLink(
              title: "View Details",
              url: deepLink("active", sessionId: context.attributes.sessionId),
              background: Color.white.opacity(0.18)
            )

            liveLink(
              title: "Check In",
              url: deepLink("check-in", sessionId: context.attributes.sessionId),
              background: HikeLiveColors.green
            )
          }
        }
      } compactLeading: {
        Text("HC")
          .font(.caption2.bold())
          .foregroundStyle(HikeLiveColors.green)
      } compactTrailing: {
        Text("\(context.state.checkIns)")
          .font(.caption.bold())
          .foregroundStyle(.white)
      } minimal: {
        Text("H")
          .font(.caption2.bold())
          .foregroundStyle(HikeLiveColors.green)
      }
    }
  }
}

private struct HikeLiveActivityLockScreenView: View {
  let context: ActivityViewContext<ManualHikeAttributes>

  var body: some View {
    VStack(alignment: .leading, spacing: 8) {
      HStack {
        VStack(alignment: .leading, spacing: 3) {
          Text(context.state.trailName)
            .font(.headline.bold())
            .foregroundStyle(.white)
            .lineLimit(1)

          Text(statusLine)
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.72))
            .lineLimit(1)
        }

        Spacer()

        VStack(alignment: .trailing, spacing: 3) {
          Text("Elapsed")
            .font(.caption2)
            .foregroundStyle(.white.opacity(0.75))

          Text(timerInterval: context.state.startedAt...Date.distantFuture, countsDown: false)
            .font(.caption.bold())
            .foregroundStyle(.white)
            .monospacedDigit()
        }
      }

      HStack(spacing: 8) {
        metricTile(label: "Distance", value: String(format: "%.2f km", context.state.distanceKm))
        metricTile(label: "Check-ins", value: "\(context.state.checkIns)")
        metricTile(label: "Pins", value: "\(context.state.manualPins)")
        metricTile(label: "Battery", value: "\(context.state.batteryLevel)%")
      }

      HStack(spacing: 8) {
        liveLink(
          title: "View",
          url: deepLink("active", sessionId: context.attributes.sessionId),
          background: Color.white.opacity(0.18)
        )

        liveLink(
          title: "Check In",
          url: deepLink("check-in", sessionId: context.attributes.sessionId),
          background: HikeLiveColors.green
        )
      }
    }
    .padding(12)
  }

  private var statusLine: String {
    "GPS \(context.state.routePointCount) | Queue \(context.state.queuedUpdates) | ETA \(etaText(context.state.expectedReturnAt))"
  }

  private func metricTile(label: String, value: String) -> some View {
    VStack(spacing: 2) {
      Text(value)
        .font(.caption.bold())
        .foregroundStyle(.white)

      Text(label)
        .font(.caption2)
        .foregroundStyle(.white.opacity(0.72))
    }
    .frame(maxWidth: .infinity)
    .padding(.vertical, 7)
    .background(Color.black.opacity(0.22))
    .clipShape(RoundedRectangle(cornerRadius: 10))
  }

  private func etaText(_ date: Date?) -> String {
    guard let date else {
      return "--"
    }

    return date.formatted(date: .omitted, time: .shortened)
  }
}

private func liveLink(
  title: String,
  url: URL,
  background: Color
) -> some View {
  Link(destination: url) {
    Text(title)
      .font(.caption.bold())
      .foregroundStyle(.white)
      .frame(maxWidth: .infinity)
      .padding(.vertical, 7)
      .background(background)
      .clipShape(Capsule())
  }
}

private func deepLink(_ path: String, sessionId: String) -> URL {
  URL(string: "hikercircle://hike/\(path)?source=ios_live_activity&sessionId=\(sessionId)")!
}

private enum HikeLiveColors {
  static let green = Color(red: 0.247, green: 0.561, blue: 0.369) // #3F8F5E
  static let brightGreen = Color(red: 0.204, green: 0.659, blue: 0.325) // #34A853
  static let deepGreen = Color(red: 0.031, green: 0.220, blue: 0.157)
}
