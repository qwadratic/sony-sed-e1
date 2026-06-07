import Foundation
import SEGKit

let app = ExplorerApp()

Task {
    await app.start()
}

RunLoop.current.run()
