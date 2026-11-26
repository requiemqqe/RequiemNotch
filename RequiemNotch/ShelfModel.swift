import SwiftUI
import AppKit
import Combine
import UniformTypeIdentifiers

// MARK: - Данные полки

/// Хранит ссылки на файлы (сами файлы не копируются и остаются на месте)
final class ShelfModel: ObservableObject {
    @Published private(set) var items: [URL] = []
    /// Сейчас тащат файл С полки — остров не должен принимать его обратно
    @Published private(set) var isDraggingOut = false

    private let storageKey = "shelfItems"
    private var dragWatcher: Timer?

    init() {
        // Восстанавливаем полку после перезапуска, пропуская удалённые/перемещённые файлы
        let paths = UserDefaults.standard.stringArray(forKey: storageKey) ?? []
        items = paths
            .map { URL(fileURLWithPath: $0) }
            .filter { FileManager.default.fileExists(atPath: $0.path) }
    }

    /// Один и тот же файл может прийти в разном виде (ссылка-идентификатор, симлинк,
    /// лишний «/» в конце) — приводим к единому пути, чтобы не было дубликатов
    private static func normalized(_ url: URL) -> URL {
        let path = (url as NSURL).filePathURL ?? url
        return path.standardizedFileURL.resolvingSymlinksInPath()
    }

    func add(_ url: URL) {
        let file = Self.normalized(url)
        guard FileManager.default.fileExists(atPath: file.path),
              !items.contains(where: { $0.path == file.path }) else { return }
        items.append(file)
        save()
    }

    /// Добавить файлы, которые бросили на остров
    func add(providers: [NSItemProvider]) {
        // Файл тащат с нашей же полки — это не новый файл
        guard !isDraggingOut else { return }
        for provider in providers {
            _ = provider.loadObject(ofClass: URL.self) { [weak self] url, _ in
                guard let url else { return }
                DispatchQueue.main.async {
                    withAnimation(.spring(response: 0.35, dampingFraction: 0.8)) { self?.add(url) }
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

    /// Убрать файлы, которые удалили или переместили, пока приложение работало
    func pruneMissing() {
        let existing = items.filter { FileManager.default.fileExists(atPath: $0.path) }
        guard existing.count != items.count else { return }
        withAnimation(NotchAnimation.content) { items = existing }
        save()
    }

    /// Начали тащить файл с полки: до отпускания кнопки мыши остров его не принимает
    func beginDragOut() {
        isDraggingOut = true
        dragWatcher?.invalidate()
        dragWatcher = Timer.scheduledTimer(withTimeInterval: 0.15, repeats: true) { [weak self] timer in
            guard NSEvent.pressedMouseButtons & 1 == 0 else { return }
            timer.invalidate()
            self?.isDraggingOut = false
        }
    }

    private func save() {
        UserDefaults.standard.set(items.map(\.path), forKey: storageKey)
    }
}

// MARK: - Размеры полки (от них зависит высота острова)

enum ShelfLayout {
    static let columns = 3
    static let maxVisibleRows = 3
    static let itemHeight: CGFloat = 68
    static let spacing: CGFloat = 8
    static let panelWidth: CGFloat = 264
    static let baseHeight: CGFloat = 110

    static func rows(for count: Int) -> Int {
        min(maxVisibleRows, max(1, Int((Double(count) / Double(columns)).rounded(.up))))
    }

    /// 1 ряд — 110, каждый следующий +76 (максимум 3 ряда, дальше прокрутка)
    static func height(for count: Int) -> CGFloat {
        baseHeight + CGFloat(rows(for: count) - 1) * (itemHeight + spacing)
    }
}

// MARK: - Полка в раскрытом острове

struct ShelfView: View {
    @EnvironmentObject var shelf: ShelfModel
    @EnvironmentObject var model: NotchModel

    /// Над островом тащат чужой файл (не с нашей полки)
    private var isTargeted: Bool { model.isDropTargeted && !shelf.isDraggingOut }

    private let grid = Array(repeating: GridItem(.flexible(), spacing: ShelfLayout.spacing),
                             count: ShelfLayout.columns)

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
                        .symbolEffect(.bounce, value: isTargeted)
                    Text("Drop files here")
                        .font(.caption)
                }
                .foregroundStyle(.secondary)
                .transition(.blurFade)
            } else {
                ScrollView(.vertical, showsIndicators: false) {
                    LazyVGrid(columns: grid, spacing: ShelfLayout.spacing) {
                        ForEach(shelf.items, id: \.self) { url in
                            ShelfItemView(url: url)
                                .transition(.scale(scale: 0.6).combined(with: .opacity))
                        }
                    }
                    .padding(10)
                }
                // Прокрутка нужна только когда файлов больше, чем помещается
                .scrollDisabled(shelf.items.count <= ShelfLayout.columns * ShelfLayout.maxVisibleRows)
            }
        }
        .frame(width: ShelfLayout.panelWidth, height: ShelfLayout.height(for: shelf.items.count))
        .clipShape(RoundedRectangle(cornerRadius: 14))
        // Кнопка «очистить полку» и счётчик файлов
        .overlay(alignment: .topTrailing) {
            if !shelf.items.isEmpty {
                HStack(spacing: 4) {
                    if shelf.items.count > ShelfLayout.columns * ShelfLayout.maxVisibleRows {
                        Text(verbatim: "\(shelf.items.count)")
                            .font(.system(size: 10, weight: .semibold).monospacedDigit())
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(Capsule().fill(.white.opacity(0.15)))
                    }
                    Button {
                        withAnimation(NotchAnimation.content) { shelf.clear() }
                    } label: {
                        Image(systemName: "xmark.circle.fill")
                    }
                    .buttonStyle(.pressable)
                    .help("Clear shelf")
                }
                .foregroundStyle(.secondary)
                .padding(6)
            }
        }
        .animation(.easeInOut(duration: 0.15), value: isTargeted)
        .animation(NotchAnimation.content, value: shelf.items)
        // Открыли остров — убрать с полки файлы, которых больше нет
        .onAppear { shelf.pruneMissing() }
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
                .frame(width: 40, height: 40)
                .scaleEffect(hovering ? 1.08 : 1)
            Text(url.lastPathComponent)
                .font(.system(size: 10))
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: .infinity)
        }
        .padding(4)
        .frame(height: ShelfLayout.itemHeight)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(.white.opacity(hovering ? 0.1 : 0))
        )
        .overlay(alignment: .topTrailing) {
            // Убрать один файл, не открывая меню
            if hovering {
                Button {
                    withAnimation(NotchAnimation.content) { shelf.remove(url) }
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.system(size: 12))
                        .symbolRenderingMode(.palette)
                        .foregroundStyle(.white, .black.opacity(0.6))
                }
                .buttonStyle(.pressable)
                .help("Remove from shelf")
                .offset(x: 2, y: -2)
                .transition(.scale.combined(with: .opacity))
            }
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
        .animation(.spring(response: 0.25, dampingFraction: 0.7), value: hovering)
        // Утащить файл с полки в Finder или любое приложение
        .onDrag {
            shelf.beginDragOut()
            return NSItemProvider(object: url as NSURL)
        }
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
