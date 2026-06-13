//
//  ManualSOSLiveActivity.swift
//  ManualSOS
//
//  Created by Leong Zi Qi on 13/06/2026.
//

import ActivityKit
import WidgetKit
import SwiftUI

struct ManualSOSAttributes: ActivityAttributes {
    public struct ContentState: Codable, Hashable {
        // Dynamic stateful properties about your activity go here!
        var emoji: String
    }

    // Fixed non-changing properties about your activity go here!
    var name: String
}

struct ManualSOSLiveActivity: Widget {
    var body: some WidgetConfiguration {
        ActivityConfiguration(for: ManualSOSAttributes.self) { context in
            // Lock screen/banner UI goes here
            VStack {
                Text("Hello \(context.state.emoji)")
            }
            .activityBackgroundTint(Color.cyan)
            .activitySystemActionForegroundColor(Color.black)

        } dynamicIsland: { context in
            DynamicIsland {
                // Expanded UI goes here.  Compose the expanded UI through
                // various regions, like leading/trailing/center/bottom
                DynamicIslandExpandedRegion(.leading) {
                    Text("Leading")
                }
                DynamicIslandExpandedRegion(.trailing) {
                    Text("Trailing")
                }
                DynamicIslandExpandedRegion(.bottom) {
                    Text("Bottom \(context.state.emoji)")
                    // more content
                }
            } compactLeading: {
                Text("L")
            } compactTrailing: {
                Text("T \(context.state.emoji)")
            } minimal: {
                Text(context.state.emoji)
            }
            .widgetURL(URL(string: "http://www.apple.com"))
            .keylineTint(Color.red)
        }
    }
}

extension ManualSOSAttributes {
    fileprivate static var preview: ManualSOSAttributes {
        ManualSOSAttributes(name: "World")
    }
}

extension ManualSOSAttributes.ContentState {
    fileprivate static var smiley: ManualSOSAttributes.ContentState {
        ManualSOSAttributes.ContentState(emoji: "😀")
     }
     
     fileprivate static var starEyes: ManualSOSAttributes.ContentState {
         ManualSOSAttributes.ContentState(emoji: "🤩")
     }
}

#Preview("Notification", as: .content, using: ManualSOSAttributes.preview) {
   ManualSOSLiveActivity()
} contentStates: {
    ManualSOSAttributes.ContentState.smiley
    ManualSOSAttributes.ContentState.starEyes
}
