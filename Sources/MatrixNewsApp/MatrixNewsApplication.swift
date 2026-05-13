import SwiftUI

#if SWIFT_PACKAGE
import MatrixNewsCore
#endif

@main
struct MatrixNewsApplication: App {
    @StateObject private var model = NewsViewModel()

    var body: some Scene {
        WindowGroup {
            MatrixNewsRootView()
                .environmentObject(model)
                .matrixMacWindowChrome()
                .task {
                    await model.load()
                }
        }
    }
}
