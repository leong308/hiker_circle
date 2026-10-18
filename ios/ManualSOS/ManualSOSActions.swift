// ManualSOSActions provides instant, medical, and duress SOS deep links.
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
    VStack(alignment: .leading, spacing: 6) {
      Text("SOS with HikerCircle")
        .font(.caption.bold())
        .foregroundStyle(.white)

      HStack(spacing: 8) {
        actionTile(
          symbol: "SOS",
          title: "Instant",
          url: "hikercircle://sos/instant?source=ios_widget"
        )

        actionTile(
          symbol: "+",
          title: "Medical",
          url: "hikercircle://sos/medical?source=ios_widget"
        )

        actionTile(
          symbol: "!",
          title: "Duress",
          url: "hikercircle://sos/duress?source=ios_widget"
        )
      }
    }
    .padding(4)
    .hikerWidgetBackground {
      LinearGradient(
        colors: [
          Color(red: 0.03, green: 0.22, blue: 0.16),
          Color(red: 0.25, green: 0.56, blue: 0.37),
          Color(red: 0.20, green: 0.66, blue: 0.33)
        ],
        startPoint: .topLeading,
        endPoint: .bottomTrailing
      )
    }
  }

  private func actionTile(
    symbol: String,
    title: String,
    url: String
  ) -> some View {
    Link(destination: URL(string: url)!) {
      VStack(spacing: 6) {
        Text(symbol)
          .font(.system(size: 28, weight: .black))
          .foregroundStyle(.white)

        Text(title)
          .font(.caption2.bold())
          .foregroundStyle(.white.opacity(0.86))
      }
      .frame(maxWidth: .infinity, maxHeight: .infinity)
      .background(Color.black.opacity(0.42))
      .clipShape(RoundedRectangle(cornerRadius: 12))
    }
  }
}
