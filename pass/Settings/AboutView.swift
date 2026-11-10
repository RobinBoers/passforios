//
//  AboutView.swift
//  pass
//

import passKit
import SwiftUI

struct AboutView: View {
    private static let components: [(name: String, url: String)] = [
        ("Pass for iOS", "https://github.com/mssun/passforios"),
        ("GopenPGP", "https://gopenpgp.org"),
        ("KeychainAccess", "https://github.com/kishikawakatsumi/KeychainAccess"),
        ("ObjectiveGit", "https://github.com/libgit2/objective-git"),
        ("ObjectivePGP", "https://github.com/krzyzanowskim/ObjectivePGP"),
        ("OneTimePassword", "https://github.com/mattrubin/OneTimePassword"),
        ("SwiftyUserDefaults", "https://github.com/sunshinejr/SwiftyUserDefaults"),
    ]

    var body: some View {
        Form {
            SwiftUI.Section {
                LabeledContent("Version", value: "\(Bundle.main.releaseVersionNumber ?? "") (\(Bundle.main.buildVersionNumber ?? ""))")
            }

            SwiftUI.Section {
                ForEach(Self.components.indices, id: \.self) { index in
                    let component = Self.components[index]
                    if let url = URL(string: component.url) {
                        Link(component.name, destination: url)
                    }
                }
            } header: {
                Text("Acknowledgements")
            }
        }
        .navigationTitle("About")
        .navigationBarTitleDisplayMode(.inline)
    }
}
