//
//  ManualSOSActions.swift
//  Runner
//
//  Created by Leong Zi Qi on 13/06/2026.
//

import WidgetKit
import SwiftUI

struct ManualSOSActions: Widget {
  let kind = "ManualSOSActions"

  var body: some WidgetConfiguration {
    StaticConfiguration(kind: kind, provider: ManualSOSProvider()) { entry in
      ManualSOSActionsView(entry: entry)
    }
    .configurationDisplayName("HikerCircle SOS Actions")
    .description("Instant SOS, Medical Help, and Duress SOS.")
    .supportedFamilies([.systemMedium])
  }
}

struct ManualSOSActionsView: View {
  let entry: ManualSOSEntry

  var body: some View {
    VStack(alignment: .leading, spacing: 11) {
      Text("SOS with HikerCircle")
        .font(.caption.bold())
        .foregroundStyle(.white)

      HStack(spacing: 8) {
        actionTile(
          symbol: "SOS",
          title: "Instant",
          url: "hikercircle://sos/instant?source=ios_widget",
          colors: [
            Color(red: 0.95, green: 0.08, blue: 0.12),
            Color(red: 0.52, green: 0.05, blue: 0.07)
          ]
        )

        actionTile(
          symbol: "+",
          title: "Medical",
          url: "hikercircle://sos/medical?source=ios_widget",
          colors: [
            Color(red: 0.08, green: 0.36, blue: 0.25),
            Color(red: 0.03, green: 0.20, blue: 0.15)
          ]
        )

        actionTile(
          symbol: "!",
          title: "Duress",
          url: "hikercircle://sos/duress?source=ios_widget",
          colors: [
            Color(red: 0.08, green: 0.36, blue: 0.25),
            Color(red: 0.03, green: 0.20, blue: 0.15)
          ]
        )
      }
    }
    .padding(12)
    .hikerWidgetBackground {
      LinearGradient(
        colors: [
          Color(red: 0.03, green: 0.22, blue: 0.16),
          Color(red: 0.10, green: 0.42, blue: 0.27),
          Color(red: 0.22, green: 0.70, blue: 0.36)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }

  private func actionTile(
    symbol: String,
    title: String,
    url: String,
    colors: [Color]
  ) -> some View {
    Link(destination: URL(string: url)!) {
      VStack(spacing: 6) {
        Text(symbol)
          .font(.system(size: 28, weight: .black, design: .rounded))
          .foregroundStyle(.white)

        Text(title)
          .font(.caption2.bold())
          .foregroundStyle(.white.opacity(0.86))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(
        LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
      )
      .clipShape(RoundedRectangle(cornerRadius: 14))
    }
  }
}
