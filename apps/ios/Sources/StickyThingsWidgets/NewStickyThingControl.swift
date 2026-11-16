import SwiftUI
import WidgetKit

/// The Action Button and Control Center entry point. iOS 18 lets people assign this control
/// directly to the Action Button, or add it to Control Center and the Lock Screen.
@main
struct NewStickyThingControl: ControlWidget {
    var body: some ControlWidgetConfiguration {
        StaticControlConfiguration(kind: "app.stickythings.control.new") {
            ControlWidgetButton(action: OpenStickyThingIntent()) {
                Label("New Sticky Thing", systemImage: "note.text")
            }
        }
        .displayName("New Sticky Thing")
        .description("Open Sticky Things and start a note.")
    }
}
