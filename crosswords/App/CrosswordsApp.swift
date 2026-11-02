import Combine
import SwiftUI

@main
struct CrosswordsApp: App {
    @State private var app: AppModel = {
        let app = AppModel()
        app.handleReminderTaps()
        #if DEBUG
        DebugLaunch.prepare(app)
        #endif
        return app
    }()
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(app)
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active: app.didBecomeActive()
            case .background: app.didEnterBackground()
            default: break
            }
        }
    }
}

struct RootView: View {
    @Environment(AppModel.self) private var app

    var body: some View {
        @Bindable var app = app
        HomeView()
            .fullScreenCover(item: $app.activeGame) { launch in
                GameView(controller: launch.controller)
            }
            .onReceive(NotificationCenter.default.publisher(for: .NSCalendarDayChanged).receive(on: RunLoop.main)) { _ in
                app.didBecomeActive()
            }
            .onAppear { app.menuDidAppear() }
            #if DEBUG
            .task { DebugLaunch.apply(to: app) }
            #endif
    }
}
