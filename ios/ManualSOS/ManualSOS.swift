import WidgetKit
import SwiftUI

struct ManualSOSEntry: TimelineEntry {
  let date: Date
}

struct ManualSOSProvider: TimelineProvider {
  func placeholder(in context: Context) -> ManualSOSEntry {
    ManualSOSEntry(date: Date())
  }

  func getSnapshot(
    in context: Context,
    completion: @escaping (ManualSOSEntry) -> Void
  ) {
    completion(ManualSOSEntry(date: Date()))
  }

  func getTimeline(
    in context: Context,
    completion: @escaping (Timeline<ManualSOSEntry>) -> Void
  ) {
    completion(Timeline(entries: [ManualSOSEntry(date: Date())], policy: .never))
  }
}

struct ManualSOSEntryView: View {
  private let sosUrl = URL(string: "hikercircle://sos/instant?source=ios_widget")!

  let entry: ManualSOSEntry

  var body: some View {
    Link(destination: sosUrl) {
      VStack(alignment: .leading, spacing: 8) {
        Text("HikerCircle")
          .font(.caption2.bold())
          .foregroundStyle(.white)

        Spacer(minLength: 0)

        VStack(spacing: 3) {
          Text("SOS")
            .font(.system(size: 30, weight: .black, design: .rounded))
            .foregroundStyle(.white)

          Text("Instant")
            .font(.caption2.weight(.semibold))
            .foregroundStyle(.white.opacity(0.82))
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
          LinearGradient(
            colors: [
              Color(red: 0.95, green: 0.08, blue: 0.12),
              Color(red: 0.52, green: 0.05, blue: 0.07)
            ],
            startPoint: .topLeading,
            endPoint: .bottomTrailing
          )
        )
        .clipShape(RoundedRectangle(cornerRadius: 14))
      }
      .padding(12)
    }
    .hikerWidgetBackground {
      LinearGradient(
        colors: [
          Color(red: 0.02, green: 0.22, blue: 0.16),
          Color(red: 0.10, green: 0.42, blue: 0.27),
          Color(red: 0.22, green: 0.70, blue: 0.36)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }
}

struct ManualSOS: Widget {
  let kind = "ManualSOS"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ManualSOSProvider()) { entry in
      ManualSOSEntryView(entry: entry)
    }
    .configurationDisplayName("HikerCircle SOS")
    .description("Tap to trigger Instant SOS.")
    .supportedFamilies([.systemSmall])
  }
}
