import SwiftUI
import Observation
import YuguangCore

@MainActor @Observable
final class ForumModel {
    enum Sort: String, CaseIterable { case latest = "最新发布", replies = "回复最多 · 已加载" }
    var board: ForumBoard?
    var topics: [ForumTopic] = []
    private(set) var favoriteTeams: Set<String>
    private(set) var onlyFavoriteNews: Bool
    var filteringNews: Bool { board?.path == "/502" && onlyFavoriteNews }
    var needsFavoriteTeams: Bool { filteringNews && favoriteTeams.isEmpty }
    var unavailableNews = 0
    var processedNews = 0
    private var pendingNews: [ForumTopic] = []
    private var seenNewsIDs: Set<String> = []
    func configureFavorites(_ teams: Set<String>, onlyNews: Bool) {
        guard teams != favoriteTeams || onlyNews != onlyFavoriteNews else { return }
        favoriteTeams = teams; onlyFavoriteNews = onlyNews
        if board?.path == "/502" { refresh() }
    }
    var showCompactImages = false
    var sort = Sort.latest
    var loading = false
    var error: String?
    var current = 0
    var total = 1
    var scrollID: String?
    var selected: ForumTopic?
    var detail: ForumDetail?
    var detailLoading = false
    var detailError: String?
    private(set) var readIDs = Set(UserDefaults.standard.stringArray(forKey: "forumReadIDs") ?? [])
    @ObservationIgnored private let service: any ForumService
    @ObservationIgnored private var listNearEnd = false
    @ObservationIgnored private var boundaryTask: Task<Void, Never>?
    /// Geometry and request completion both recheck the boundary. A short debounce lets
    /// SwiftUI lay out appended rows before deciding whether another batch is needed.
    func updateListBoundary(nearEnd: Bool) {
        listNearEnd = nearEnd
        recheckListBoundary()
    }
    private func recheckListBoundary() {
        boundaryTask?.cancel()
        guard listNearEnd, selected == nil, !loading, error == nil, hasMore, !needsFavoriteTeams else { return }
        let ticket = generation
        boundaryTask = Task { [weak self] in
            do { try await Task.sleep(for: .milliseconds(80)) } catch { return }
            guard let self, !Task.isCancelled, ticket == generation,
                  listNearEnd, selected == nil, !loading, error == nil, hasMore, !needsFavoriteTeams else { return }
            loadMore()
        }
    }
    @ObservationIgnored private var listTask: Task<Void, Never>?
    @ObservationIgnored private var detailTask: Task<Void, Never>?
    @ObservationIgnored private var generation = 0
    @ObservationIgnored private var detailGeneration = 0
    private var recentReads = UserDefaults.standard.stringArray(forKey: "forumReadIDs") ?? []
    init(service: any ForumService = HupuForum(), favoriteTeams: Set<String>? = nil, onlyFavoriteNews: Bool? = nil) {
        self.service = service
        self.favoriteTeams = favoriteTeams ?? Set(UserDefaults.standard.stringArray(forKey: "favoriteTeams") ?? [])
        self.onlyFavoriteNews = onlyFavoriteNews ?? (UserDefaults.standard.object(forKey: "onlyFavoriteNews") as? Bool ?? true)
    }
    var ordered: [ForumTopic] {
        sort == .latest ? topics : topics.sorted { $0.replies != $1.replies ? $0.replies > $1.replies : ($0.createdAt != $1.createdAt ? $0.createdAt > $1.createdAt : $0.id > $1.id) }
    }
    var hasMore: Bool { (current < total || !pendingNews.isEmpty) && max(topics.count, processedNews) < 1000 }
    func choose(_ board: ForumBoard) {
        if self.board == board { return }
        self.board = board; refresh()
    }
    func changeSort(_ value: Sort) { sort = value; scrollID = nil }
    func refresh() {
        boundaryTask?.cancel(); listNearEnd = false
        listTask?.cancel(); generation += 1
        back(); pendingNews = []; seenNewsIDs = []; processedNews = 0; unavailableNews = 0; topics = []; current = 0; total = 1; scrollID = nil; loading = false; error = nil
        loadMore()
    }
    func loadMore() {
        guard let board, !loading, hasMore, !needsFavoriteTeams else { return }
        loading = true; error = nil
        let ticket = generation, next = current + 1
        let filter = filteringNews, teams = favoriteTeams
        listTask = Task { [weak self] in
            guard let self else { return }
            defer {
                if ticket == generation { loading = false; recheckListBoundary() }
            }
            do {
                let batch: [ForumTopic]
                if filter {
                    if pendingNews.isEmpty {
                        let result = try await service.topics(board: board, page: next)
                        guard !Task.isCancelled, ticket == generation else { return }
                        guard result.current == next else { throw ForumError.changedPage }
                        pendingNews = result.topics.filter { seenNewsIDs.insert($0.id).inserted }
                        current = result.current; total = result.total
                    }
                    let candidates = Array(pendingNews.prefix(12))
                    let filtered = try await service.filterNews(candidates, teams: teams)
                    guard !Task.isCancelled, ticket == generation else { return }
                    pendingNews.removeFirst(candidates.count); processedNews += candidates.count
                    batch = filtered.topics; unavailableNews += filtered.unavailable
                } else {
                    let result = try await service.topics(board: board, page: next)
                    guard !Task.isCancelled, ticket == generation else { return }
                    guard result.current == next else { throw ForumError.changedPage }
                    batch = result.topics; current = result.current; total = result.total
                }
                topics = HupuForum.unique(topics + batch)
            } catch {
                guard !Task.isCancelled, ticket == generation else { return }
                self.error = error.localizedDescription
            }
        }
    }
    func open(_ topic: ForumTopic) {
        boundaryTask?.cancel(); selected = topic; detail = nil; fetchDetail(page: 1)
    }
    func fetchDetail(page: Int) {
        guard let topic = selected else { return }
        detailTask?.cancel(); detailGeneration += 1
        let ticket = detailGeneration
        detailLoading = true; detailError = nil
        detailTask = Task { [weak self] in
            guard let self else { return }
            defer { if ticket == detailGeneration { detailLoading = false } }
            do {
                let result = try await service.detail(id: topic.id, page: page)
                guard !Task.isCancelled, ticket == detailGeneration else { return }
                guard result.current == page || (page == 1 && result.total == 0) else { throw ForumError.changedPage }
                if page > 1, let existing = detail {
                    detail = ForumDetail(title: existing.title, html: existing.html, author: existing.author,
                                         comments: existing.comments + result.comments, current: result.current, total: result.total)
                } else { detail = result }
                recentReads.removeAll { $0 == topic.id }; recentReads.append(topic.id)
                recentReads = Array(recentReads.suffix(2000)); readIDs = Set(recentReads)
                UserDefaults.standard.set(recentReads, forKey: "forumReadIDs")
            } catch {
                guard !Task.isCancelled, ticket == detailGeneration else { return }
                detailError = error.localizedDescription
            }
        }
    }
    func back() {
        detailTask?.cancel(); detailGeneration += 1
        selected = nil; detail = nil; detailLoading = false; detailError = nil
        recheckListBoundary()
    }
    func stop() {
        listNearEnd = false; boundaryTask?.cancel(); listTask?.cancel(); detailTask?.cancel()
    }
}
