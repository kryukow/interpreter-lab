import SwiftUI
import UIKit
import SafariServices

@main
struct InterpreterLabApp: App {
    var body: some Scene {
        WindowGroup { LabView().preferredColorScheme(.dark) }
    }
}

struct LabLoginBrowser: UIViewControllerRepresentable {
    let url: URL
    func makeUIViewController(context: Context) -> SFSafariViewController {
        SFSafariViewController(url: url)
    }
    func updateUIViewController(_ controller: SFSafariViewController, context: Context) {}
}
