import Charts
import CoreData
import SwiftUI

/// Library reading stats: chapters per week, time read, and the titles and artists read most.
/// Streaks, the heatmap and lifetime totals stay in Insights, linked from here.
struct MCReadingStatsView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var store = MCCollectionStore.shared
    @State private var sessions: [MCReadingStatSession]?

    var body: some View {
        NavigationStack {
            List {
                if let sessions {
                    let stats = MCReadingStats(sessions: sessions, store: store)
                    Section {
                        HStack(spacing: 12) {
                            tile("\(stats.chaptersThisWeek)", stats.chaptersThisWeek == 1 ? "chapter this week" : "chapters this week")
                            tile(stats.durationThisWeek, "read this week")
                        }
                        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
                    }
                    Section("Chapters per week") {
                        Chart(stats.weeks) { week in
                            BarMark(x: .value("Week", week.start, unit: .weekOfYear), y: .value("Chapters", week.chapters))
                                .foregroundStyle(Color.accentColor)
                                .accessibilityLabel(week.start.formatted(.dateTime.month(.abbreviated).day()))
                                .accessibilityValue("\(week.chapters) chapters")
                        }
                        .chartXAxis { AxisMarks(values: .stride(by: .weekOfYear, count: 3)) { _ in AxisValueLabel(format: .dateTime.month(.abbreviated).day()) } }
                        .frame(height: 160)
                        .padding(.vertical, 6)
                    }
                    Section("Most read titles") {
                        if stats.topTitles.isEmpty { Text("Read a library title to see it here.").foregroundStyle(.secondary) }
                        ForEach(stats.topTitles) { item in
                            HStack(spacing: 12) {
                                if let id = item.entryID, let entry = store.library.entry(id) {
                                    MCEntryCover(entry: entry).frame(width: 32, height: 48).clipShape(RoundedRectangle(cornerRadius: 4))
                                    Text(store.library.title(entry)).lineLimit(2)
                                }
                                Spacer()
                                Text("\(item.chapters) ch").font(.subheadline.monospacedDigit()).foregroundStyle(.secondary)
                            }
                        }
                    }
                    if !stats.topArtists.isEmpty {
                        Section("Most read artists") {
                            ForEach(stats.topArtists) { item in
                                LabeledContent(item.id, value: "\(item.chapters) ch")
                            }
                        }
                    }
                } else {
                    ProgressView().frame(maxWidth: .infinity)
                }
                Section {
                    NavigationLink("Streaks, heatmap and totals") { InsightsView() }
                }
            }
            .navigationTitle("Reading stats")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() } } }
            .task { sessions = await MCReadingStatSession.load() }
        }
        .midokuAccent()
    }

    private func tile(_ value: String, _ label: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(value).font(.title2.bold().monospacedDigit())
            Text(label).font(.caption).foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}

struct MCReadingStatSession: Sendable {
    let start: Date
    let end: Date
    let sourceKey: String
    let mangaKey: String
    let chapterKey: String

    static func load() async -> [MCReadingStatSession] {
        await CoreDataManager.shared.container.performBackgroundTask { context in
            let request = NSFetchRequest<NSDictionary>(entityName: "ReadingSession")
            request.resultType = .dictionaryResultType
            request.propertiesToFetch = ["startDate", "endDate", "history.sourceId", "history.mangaId", "history.chapterId"]
            return ((try? context.fetch(request)) ?? []).compactMap { values in
                guard let start = values["startDate"] as? Date, let end = values["endDate"] as? Date,
                      let source = values["history.sourceId"] as? String, let manga = values["history.mangaId"] as? String,
                      let chapter = values["history.chapterId"] as? String else { return nil }
                return MCReadingStatSession(start: start, end: end, sourceKey: source, mangaKey: manga, chapterKey: chapter)
            }
        }
    }
}

struct MCReadingStats {
    struct Week: Identifiable {
        let start: Date
        let chapters: Int
        var id: Date { start }
    }

    let chaptersThisWeek: Int
    let durationThisWeek: String
    let weeks: [Week]
    struct Count: Identifiable {
        let id: String
        let entryID: UUID?
        let chapters: Int
    }

    let topTitles: [Count]
    let topArtists: [Count]

    @MainActor init(sessions: [MCReadingStatSession], store: MCCollectionStore, now: Date = .now) {
        let calendar = Calendar.current
        let thisWeek = calendar.dateInterval(of: .weekOfYear, for: now)?.start ?? now
        // A chapter counts once per week, however many sessions it took.
        var chaptersByWeek: [Date: Set<String>] = [:]
        var seconds: TimeInterval = 0
        for session in sessions {
            guard let week = calendar.dateInterval(of: .weekOfYear, for: session.end)?.start else { continue }
            chaptersByWeek[week, default: []].insert("\(session.sourceKey)|\(session.mangaKey)|\(session.chapterKey)")
            if week == thisWeek { seconds += max(0, min(session.end.timeIntervalSince(session.start), 6 * 3600)) }
        }
        chaptersThisWeek = chaptersByWeek[thisWeek]?.count ?? 0
        durationThisWeek = Duration.seconds(Int(seconds)).formatted(.units(allowed: [.hours, .minutes], width: .narrow))
        weeks = (0..<12).reversed().compactMap { offset in
            calendar.date(byAdding: .weekOfYear, value: -offset, to: thisWeek).map { Week(start: $0, chapters: chaptersByWeek[$0]?.count ?? 0) }
        }

        // Count distinct chapters per library title; nested and merged sources count for their top title.
        var rootByListing: [UUID: UUID] = [:]
        for entry in store.library.entries {
            let root = store.library.ancestorIDs(of: entry.id).last ?? entry.id
            for link in entry.links where rootByListing[link.listingID] == nil || link.listingID == entry.primaryListingID {
                rootByListing[link.listingID] = root
            }
        }
        var chaptersByTitle: [UUID: Set<String>] = [:]
        for session in sessions {
            guard let connection = store.connection(sourceKey: session.sourceKey),
                  let listing = store.library.listing(identity: .init(connectionID: connection.id, externalID: session.mangaKey)),
                  let root = rootByListing[listing.id] else { continue }
            chaptersByTitle[root, default: []].insert("\(session.sourceKey)|\(session.mangaKey)|\(session.chapterKey)")
        }
        let titles = chaptersByTitle.map { Count(id: $0.key.uuidString, entryID: $0.key, chapters: $0.value.count) }
            .sorted { $0.chapters == $1.chapters ? $0.id < $1.id : $0.chapters > $1.chapters }
        topTitles = Array(titles.prefix(5))
        var artists: [String: Int] = [:]
        for title in titles {
            guard let id = title.entryID, let entry = store.library.entry(id) else { continue }
            for artist in Set(store.searchProfile(entry).artists) { artists[artist, default: 0] += title.chapters }
        }
        topArtists = Array(artists.map { Count(id: $0.key, entryID: nil, chapters: $0.value) }
            .sorted { $0.chapters == $1.chapters ? $0.id < $1.id : $0.chapters > $1.chapters }.prefix(5))
    }
}
