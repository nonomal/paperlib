//
//  EntitiesInteractor.swift
//  PaperLib
//
//  Created by GeoffreyChen on 26/11/2021.
//

import Alamofire
import Combine
import Foundation
import RealmSwift
import SwiftUI

protocol EntitiesInteractor {
    func load(entities: LoadableSubject<Results<PaperEntity>>, search: String?, flag: Bool, tags: [String], folders: [String], sort: String)
    func load<T: PaperCategorizer>(categorizers: LoadableSubject<Results<T>>, cancelBagKey: String)

    func add(from fileURLs: [URL])

    func delete(ids: Set<ObjectId>)
    func delete<T: PaperCategorizer>(categorizerName: String, categorizerType: T.Type)

    func update(entities: [PaperEntityDraft])
    func match(entities: [PaperEntityDraft])
    func routineMatch()

    func openLib()
    func migrateLocaltoSync()
    func export(entities: [PaperEntity], format: String)

    func handleChromePluginUrl(_ url: URL)
    func getJoinedUrl(_ url: String) -> URL?
    func setRoutineTimer()
}

class RealEntitiesInteractor: EntitiesInteractor {
    let dbRepository: DBRepository
    let fileRepository: FileRepository
    let webRepository: WebRepository
    let appState: Store<AppState>

    let cancelBags: CancelBags = .init(["apiVersion", "timer", "entities", "entitiesByIds", "update", "add", "match", "delete", "edit", "folders-edit", "delete-tag", "delete-folder", "open-lib", "plugin", "categorizers"])

    var routineTimer: Publishers.Autoconnect<Timer.TimerPublisher> = Timer.publish(every: 86400, on: .main, in: .common).autoconnect()

    init(appState: Store<AppState>, dbRepository: DBRepository, fileRepository: FileRepository, webRepository: WebRepository) {
        self.appState = appState
        self.dbRepository = dbRepository
        self.fileRepository = fileRepository
        self.webRepository = webRepository

        self.setRoutineTimer()

        self.webRepository.apiVersion()
            .sink(receiveCompletion: {_ in}, receiveValue: {_ in})
            .store(in: cancelBags["apiVersion"])
    }

    // MARK: - Select

    func load(entities: LoadableSubject<Results<PaperEntity>>, search: String?, flag: Bool, tags: [String], folders: [String], sort: String) {
        self.cancelBags.cancel(for: "entities")

        entities.wrappedValue.setIsLoading(cancelBag: self.cancelBags["entities"])

        Task {
            await self.dbRepository.entities(search: search, publication: nil, flag: flag, tags: tags, folders: folders, sort: sort)
                .sinkToLoadable {
                    entities.wrappedValue.setIsLoading(cancelBag: CancelBag())
                    print("[Reloaded] entities")
                    entities.wrappedValue = $0
                }
                .store(in: self.cancelBags["entities"])
        }
    }

    func load<T: PaperCategorizer>(categorizers: LoadableSubject<Results<T>>, cancelBagKey: String) {
        Task {
            self.cancelBags.cancel(for: cancelBagKey)
            categorizers.wrappedValue.setIsLoading(cancelBag: self.cancelBags[cancelBagKey])

            await self.dbRepository.categorizers(categorizerType: T.self)
                .sinkToLoadable {
                    categorizers.wrappedValue.setIsLoading(cancelBag: self.cancelBags[cancelBagKey])
                    categorizers.wrappedValue = $0
                }
                .store(in: self.cancelBags[cancelBagKey])
        }
    }

    // MARK: - Add

    func add(from fileURLs: [URL]) {
        self.cancelBags.cancel(for: "add")

        var publisherList: [AnyPublisher<PaperEntityDraft, Error>] = .init()

        fileURLs.forEach { url in
            self.appState[\.receiveSignals.processingCount] += 1
            let publisher = Just<Void>
                .withErrorType(Error.self)
                .flatMap { _ in
                    self.fileRepository.read(from: url)
                }
                .flatMap { entity -> AnyPublisher<PaperEntityDraft, Error> in
                    return self.webRepository.fetch(for: entity!, enable: true).eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()

            publisherList.append(publisher)
        }

        let c = publisherList.count

        Publishers.MergeMany(publisherList)
            .collect()
            .flatMap({ entities in
                self.fileRepository.move(for: entities)
            })
            .sink(receiveCompletion: { _ in }, receiveValue: {entities in

                let filteredEntities = entities.filter({ $0 != nil }).map({ $0! })
                Task {
                    await self.dbRepository.update(from: filteredEntities)
                        .flatMap { successes -> AnyPublisher<[Bool], Error> in
                            return self.fileRepository.remove(for: filteredEntities.filter({ !successes[filteredEntities.firstIndex(of: $0)!] }))
                        }
                        .sink(receiveCompletion: { _ in }, receiveValue: {_ in
                            self.appState[\.receiveSignals.processingCount] -= c
                        })
                        .store(in: CancelBag())
                }

            })
            .store(in: self.cancelBags["add"])
    }

    // MARK: - Delete

    func delete(ids: Set<ObjectId>) {
        self.cancelBags.cancel(for: "delete")

        Task {
            await self.dbRepository.delete(ids: Array(ids))
                .flatMap { filePaths in
                    self.fileRepository.remove(for: filePaths)
                }
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                .store(in: self.cancelBags["delete"])
        }
    }

    func delete<T: PaperCategorizer>(categorizerName: String, categorizerType: T.Type) {
        self.cancelBags.cancel(for: "delete-categorizer")

        Task {
            await self.dbRepository.delete(categorizerName: categorizerName, categorizerType: categorizerType)
                .sink(receiveCompletion: { _ in }, receiveValue: { _ in })
                .store(in: self.cancelBags["delete-categorizer"])
        }
    }

    // MARK: - Update

    func update(entities: [PaperEntityDraft]) {
        self.cancelBags.cancel(for: "update")

        Just<[PaperEntityDraft]>
            .withErrorType(entities, Error.self)
            .flatMap { entities in
                self.fileRepository.move(for: entities)
            }
            .sink(receiveCompletion: { _ in }, receiveValue: {entities in
                let filteredEntities = entities.filter({ $0 != nil }).map({ $0! })
                Task {
                    await self.dbRepository.update(from: filteredEntities)
                        .sink(receiveCompletion: {_ in}, receiveValue: {_ in})
                        .store(in: CancelBag())
                }
            })
            .store(in: self.cancelBags["update"])

    }

    func match(entities: [PaperEntityDraft]) {
        self.cancelBags.cancel(for: "match")

        var publisherList: [AnyPublisher<PaperEntityDraft, Error>] = .init()

        entities.forEach { entity in
            self.appState[\.receiveSignals.processingCount] += 1
            let publisher = Just<Void>
                .withErrorType(Error.self)
                .flatMap { _ -> AnyPublisher<PaperEntityDraft, Error> in
                    return self.webRepository.fetch(for: entity, enable: true).eraseToAnyPublisher()
                }
                .eraseToAnyPublisher()

            publisherList.append(publisher)
        }

        let c = publisherList.count

        Publishers.MergeMany(publisherList)
            .collect()
            .flatMap { entities in
                self.fileRepository.move(for: entities)
            }
            .sink(receiveCompletion: { _ in }, receiveValue: { entities in
                let filteredEntities = entities.filter({ $0 != nil }).map({ $0! })
                Task {
                    await self.dbRepository.update(from: filteredEntities)
                        .sink(receiveCompletion: {_ in}, receiveValue: {_ in})
                        .store(in: CancelBag())

                    self.appState[\.receiveSignals.processingCount] -= c
                }

            })
            .store(in: self.cancelBags["match"])
    }

    func routineMatch() {
        Task {
            print("[Routine] rematch")
            self.appState[\.setting.lastRematchTime] = Int(Date().timeIntervalSince1970)
            UserDefaults.standard.set(Int(Date().timeIntervalSince1970), forKey: "lastRematchTime")

            await self.dbRepository.entities(search: nil, publication: "arXiv", flag: false, tags: [], folders: [], sort: "title")
                .sink(receiveCompletion: {_ in}, receiveValue: { entities in
                    let drafts = entities.map({entity in return PaperEntityDraft(from: entity)})
                    self.match(entities: Array(drafts))
                })
                .store(in: CancelBag())
        }
    }

    // MARK: - Misc
    func export(entities: [PaperEntity], format: String) {
        if format == "bibtex" {
            _exportBibtex(entities: entities)
        } else if format == "plain" {
            _exportPlain(entities: entities)
        }
    }

    func _replacePublication(_ publication: String) -> String {
        if self.appState[\.setting.exportReplacement] == nil || !self.appState[\.setting.enableExportReplacement] {
            return publication
        }
        let exportReplacement = try? JSONDecoder().decode([String: String].self, from: self.appState[\.setting.exportReplacement]!)
        if exportReplacement == nil {
            return publication
        }
        if let replace = exportReplacement![publication] {
            return replace
        } else {
            return publication
        }
    }

    func _exportBibtex(entities: [PaperEntity]) {
        var allTexBib = ""

        entities.forEach { entity in
            var citeKey = ""
            citeKey += entity.authors.split(separator: " ")[0] + "_"
            citeKey += entity.pubTime + "_"
            citeKey += formatString(String(entity.title[..<String.Index(utf16Offset: 3, in: entity.title)]), removeNewline: true, removeWhite: true, removeSymbol: true)!
            var texbib = ""
            if entity.pubType == 1 {
                texbib = """
                @inproceedings{\(citeKey),
                    year = \(entity.pubTime),
                    title = {\(entity.title)},
                    author = {\(entity.authors.replacingOccurrences(of: ", ", with: " and "))},
                    booktitle = {\(_replacePublication(entity.publication))},
                }
                """
            } else {
                texbib = """
                @article{\(citeKey),
                    year = \(entity.pubTime),
                    title = {\(entity.title)},
                    author = {\(entity.authors.replacingOccurrences(of: ", ", with: " and "))},
                    journal = {\(_replacePublication(entity.publication))},
                }
                """
            }
            allTexBib += texbib + "\n\n"
        }
        let pasteBoard = NSPasteboard.general
        pasteBoard.clearContents()
        pasteBoard.writeObjects([allTexBib as NSString])
    }

    func _exportPlain(entities: [PaperEntity]) {
        var allPlain = ""

        entities.forEach { entity in
            let text = "\(entity.authors). \"\(entity.title)\" In \(entity.publication), \(entity.pubTime). \n\n"
            allPlain += text
        }
        let pasteBoard = NSPasteboard.general
        pasteBoard.clearContents()
        pasteBoard.writeObjects([allPlain as NSString])
    }

    func openLib() {
        Task {
            await self.dbRepository.logoutCloud()
            _ = await self.dbRepository.getConfig()
            DispatchQueue.main.sync {
                self.appState[\.receiveSignals.appLibMoved] = Date()
            }
        }
    }

    func migrateLocaltoSync() {
        self.dbRepository.migrateLocaltoCloud()
    }

    func handleChromePluginUrl(_ url: URL) {
        self.cancelBags.cancel(for: "plugin")
        self.appState[\.receiveSignals.processingCount] += 1

        do {
            var urlStr = url.absoluteString
            urlStr = formatString(urlStr, removeStr: "paperlib://")!
            let urlComponents = urlStr.components(separatedBy: "?")
            let operation = urlComponents.first

            if operation == "download" {
                if url.absoluteString.contains("arxiv.org") {
                    let pattern = "(\\d{4}.\\d{4,5}|[a-z\\-] (\\.[A-Z]{2})?\\/\\d{7})(v\\d )?"
                    var downloadLink = urlComponents[1].components(separatedBy: "=")[1]

                    let regex = try NSRegularExpression(pattern: pattern)
                    let results = regex.matches(in: downloadLink, range: NSRange(downloadLink.startIndex..., in: downloadLink))
                    let arxivID = results.map {
                        String(downloadLink[Range($0.range, in: downloadLink)!])
                    }.first

                    if let arxivID = arxivID {
                        downloadLink = "https://arxiv.org/pdf/\(arxivID).pdf"

                        print(downloadLink)

                        if let downloadUrl = URL(string: downloadLink) {
                            self.fileRepository.download(url: downloadUrl)
                            .sink(receiveCompletion: {_ in}, receiveValue: {
                                self.appState[\.receiveSignals.processingCount] -= 1
                                if let downloadedUrl = $0 {
                                    self.add(from: [downloadedUrl])
                                }
                            })
                            .store(in: self.cancelBags["plugin"])
                        }
                    } else {
                        self.appState[\.receiveSignals.processingCount] -= 1
                    }
                }
            }
        } catch let err {
            self.appState[\.receiveSignals.processingCount] -= 1
            print(err)
        }
    }

    func getJoinedUrl(_ url: String) -> URL? {
        if var joinedURL = URL(string: self.appState[\.setting.appLibFolder]) {
            joinedURL.appendPathComponent(url)
            return joinedURL
        } else {
            return nil
        }
    }

    func setRoutineTimer() {

        if self.appState[\.setting.lastRematchTime] == 0 {
            UserDefaults.standard.set(Int(Date().timeIntervalSince1970), forKey: "lastRematchTime")
            self.appState[\.setting.lastRematchTime] = Int(Date().timeIntervalSince1970)
        }

        if (Int(Date().timeIntervalSince1970) - self.appState[\.setting.lastRematchTime]) > (86400 * self.appState[\.setting.rematchInterval]) {
            self.routineMatch()
        }
        self.routineTimer.upstream.connect().cancel()
        self.cancelBags.cancel(for: "timer")
        self.routineTimer = Timer.publish(every: Double(86400 * self.appState[\.setting.rematchInterval]), on: .main, in: .common).autoconnect()
        self.routineTimer
            .sink(receiveValue: { [weak self] _ in
                if self?.appState[\.setting.allowRoutineMatch] ?? false {
                    self?.routineMatch()
                }
            })
            .store(in: self.cancelBags["timer"])
    }

}

struct StubEntitiesInteractor: EntitiesInteractor {

    func load(entities _: LoadableSubject<Results<PaperEntity>>, search _: String?, flag _: Bool, tags _: [String], folders _: [String], sort _: String) {}
    func load<T: PaperCategorizer>(categorizers: LoadableSubject<Results<T>>, cancelBagKey: String) {}

    func add(from _: [URL]) {}

    func delete(ids _: Set<ObjectId>) {}
    func delete<T>(categorizerName: String, categorizerType: T.Type) where T: PaperCategorizer {}

    func update(entities: [PaperEntityDraft]) {}
    func match(entities _: [PaperEntityDraft]) {}
    func routineMatch() {}

    func getJoinedUrl(_ url: String) -> URL? {
        return URL(string: "")
    }
    func openLib() {}
    func migrateLocaltoSync() {}
    func export(entities _: [PaperEntity], format _: String) {}
    func handleChromePluginUrl(_ url: URL) {}
    func setRoutineTimer() {}

}
