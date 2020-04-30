import Foundation
import ArgumentParser

struct FullCommand: ParsableCommand {
    enum CodingKeys: String, CodingKey {
        case pre = "pre"
    }

    private let git: GitShell
    private let changelogCommits: ChangelogCommits

    static var configuration: CommandConfiguration {
        return .init(
            commandName: "full",
            abstract: "All Unreleased and Released Changes",
            discussion: "Returns all of the unreleased and released in changelog"
        )
    }

    @Flag(name: .shortAndLong, help: "Include pre-releases in the output")
    var pre: Bool
    
    init() {
        self.git = try! GitShell(bash: Bash())
        self.changelogCommits = try! ChangelogCommits(commits: self.git.commits())
    }
    
    init(from decoder: Decoder) throws {
        self.git = try! GitShell(bash: Bash())
        self.changelogCommits = try! ChangelogCommits(commits: self.git.commits())

        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.pre = try container.decode(Bool.self, forKey: .pre)
    }
    
    func run() throws {
        var categorizedEntries: [OldChangelog.Category: [OldChangelog.Entry]] = [:]
        var versionShas: [(String, String, String)] = []
        var releaseID: String?
        var releaseDate: Date?
        var releaseSha: String?
        var lastSha: String?

        print("""
        # Changelog

        All notable changes to this project will be documented in this file.

        The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/).

        Generated by [Git Changelog](https://github.com/uptech/git-cl), an open source project brought to you by [UpTech Works, LLC](https://upte.ch). A consultancy that partners with companies to help **build**, **launch**, and **refine** their products.

        """)

        for changelogCommit: ChangelogCommit in self.changelogCommits {
            // if it is release
            if let release = changelogCommit.release(self.pre) {
                // track release shas for generating link references at the end
                if let releaseID = releaseID, let _ = releaseDate, let releaseSha = releaseSha {
                    versionShas.append((releaseID, releaseSha, changelogCommit.commit.sha))
                } else { // handle Unreleased
                    versionShas.append(("Unreleased", "HEAD", changelogCommit.commit.sha))
                }

                // print the previous release or unreleased
                if let releaseID = releaseID, let releaseDate = releaseDate, let _ = releaseSha {
                    print(markdownRelease(releaseID: releaseID, date: releaseDate, categorizedEntries: categorizedEntries, withLinkRef: true))
                } else {
                    print(markdownUnreleased(categorizedEntries, withLinkRef: true))
                }

                // reset the categorizedEntries and associated tracking state
                releaseID = release
                releaseDate = changelogCommit.commit.date
                releaseSha = changelogCommit.commit.sha
                categorizedEntries = [:]
            }

            if !changelogCommit.changelogEntries.isEmpty {
                for entry in changelogCommit.changelogEntries {
                    categorizedEntries.upsertAppend(value: entry.message, for: entry.typeString)
                }
            }
            lastSha = changelogCommit.commit.sha
        }

        // track release shas for generating link references at the end
        if let releaseID = releaseID, let _ = releaseDate, let releaseSha = releaseSha {
            versionShas.append((releaseID, releaseSha, lastSha!))
        } else { // handle Unreleased
            versionShas.append(("Unreleased", "HEAD", lastSha!))
        }

        // print the previous release or unreleased
        if let releaseID = releaseID, let releaseDate = releaseDate {
            print(markdownRelease(releaseID: releaseID, date: releaseDate, categorizedEntries: categorizedEntries, withLinkRef: true))
        } else {
            print(markdownUnreleased(categorizedEntries, withLinkRef: true))
        }

        // print the link references
        let compareBaseURL = self.repositoryURL()!
        versionShas.forEach { versionShaInfo in
            print("[\(versionShaInfo.0)]: \(compareBaseURL.absoluteString)/compare/\(versionShaInfo.2.prefix(7))...\(versionShaInfo.1.prefix(7))")
        }
    }

    private func repositoryURL() -> URL? {
        let urlString = try! self.git.findRespoitoryOriginURL()!.absoluteString
        return URL(string: urlString.replacingOccurrences(of: ":", with: "/").replacingOccurrences(of: "git@", with: "https://"))
    }
}
