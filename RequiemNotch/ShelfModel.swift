import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Данные полки

/// Хранит ссылки на файлы (сами файлы не копируются и остаются на месте)
final class ShelfModel: ObservableObject {
    @Published private(set) var items: [URL] = []
    private let storageKey = "shelfItems"

    init() {
        // Восстанавливаем полку после перезапуска, пропуская удалённые/перемещённые файлы
        let paths = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        items = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    func add(_ url: URL) {
        guard !items.contains(url) else { return }
        items.append(url)
        save()
    }

    /// Добавить файлы, которые бросили на остров
    func add(providers: [NSItemProvider]) {
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.3)) { self?.add(url) }
                }
            }
        }
    }

    func remove(_ url: URL) {
        items.removeAll { $0 == url }
        save()
    }

    func clear() {
        items.removeAll()
        save()
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: storageKey)
    }
}

// MARK: - Полка в раскрытом острове

struct ShelfView: View {
    @EnvironmentObject var shelf: ShelfModel
    @EnvironmentObject var model: NotchModel
    /// Файл сейчас над островом (приём файлов — в NotchView)
    private var isTargeted: Bool { model.isDropTargeted }

    var body: some View {
        ZStack {
            // Фон
            RoundedRectangle(cornerRadius: 14)
                .fill(.white.opacity(isTargeted ? 0.16 : 0.08))
            // Пунктирная рамка: видна, когда полка пустая или над ней файл
            RoundedRectangle(cornerRadius: 14)
                .strokeBorder(style: StrokeStyle(lineWidth: 1.5, dash: [5, 4]))
                .foregroundStyle(.white.opacity(isTargeted ? 0.6 : (shelf.items.isEmpty ? 0.25 : 0)))

            if shelf.items.isEmpty {
                VStack(spacing: 6) {
                    Image(systemName: "tray.and.arrow.down")
                        .font(.system(size: 20))
                    Text("Drop files here")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
            } else {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .padding(.horizontal, 10)
                }
            }
        }
        .frame(width: 260, height: 110)
        // Кнопка «очистить полку»
        .overlay(alignment: .topTrailing) {
            if !shelf.items.isEmpty {
                Button {
                    withAnimation { shelf.clear() }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)
                .help("Clear shelf")
                .padding(6)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        // Плавный переход пустая полка ↔ файлы
        .animation(NotchAnimation.content, value: shelf.items)
    }
}

// MARK: - Один файл на полке

struct ShelfItemView: View {
    let url: URL
    @EnvironmentObject var shelf: ShelfModel
    @State private var hovering = false

    var body: some View {
        VStack(spacing: 4) {
            Image(nsImage: NSWorkspace.shared.icon(forFile: url.path))
                .resizable()
                .frame(width: 44, height: 44)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(width: 60)
        }
        .padding(4)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(hovering ? 0.1 : 0))
        )
        .onHover { hovering = $0 }
        // Утащить файл с полки в Finder или любое приложение
        .onDrag { NSItemProvider(object: url as NSURL) }
        // Двойной клик — открыть
        .onTapGesture(count: 2) { NSWorkspace.shared.open(url) }
        // Правый клик
        .contextMenu {
            Button("Open") { NSWorkspace.shared.open(url) }
            Button("Show in Finder") {
                NSWorkspace.shared.activateFileViewerSelecting([url])
            }
            Divider()
            Button("Remove from shelf") {
                withAnimation { shelf.remove(url) }
            }
        }
        .help(url.path)
    }
}
