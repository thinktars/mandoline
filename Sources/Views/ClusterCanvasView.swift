import SwiftUI
import AppKit

struct ClusterCanvasView: View {
    var clusters: [MediaCluster]
    var indexService: IndexService
    var onSlice: (MediaCluster) -> Void
    var onSliceFullFolder: () -> Void
    var onBackToOptions: () -> Void
    var onCloseFolder: () -> Void
    var processedPaths: Set<String> = []
    var onMoveCluster: (Int, CGPoint) -> Void = { _, _ in }

    var body: some View {
        VStack(spacing: 0) {
            header

            if clusters.isEmpty {
                Spacer()
                emptyState
                Spacer()
            } else {
                ClusterCanvasWorkspace(
                    clusters: clusters,
                    processedPaths: processedPaths,
                    onSlice: onSlice,
                    onMoveCluster: { id, position in
                        indexService.updateClusterPosition(id: id, position: position)
                        onMoveCluster(id, position)
                    }
                )
                .padding(.horizontal, 18)
                .padding(.bottom, 18)
            }
        }
        .background(Color.themeBackground)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 16) {
            VStack(alignment: .leading, spacing: 4) {
                Text("Indexed Clusters")
                    .font(.system(size: 22, weight: .semibold))
                    .foregroundColor(.themeText)

                HStack(spacing: 8) {
                    Text("Drag empty canvas to pan. Drag cluster clouds to move them. Pinch or ⌘ scroll to zoom.")
                    if !indexService.embedderName.isEmpty {
                        Text("•")
                        Text(indexService.embedderName)
                    }
                }
                .font(.system(size: 13))
                .foregroundColor(.themeSecondaryText)
                .lineLimit(1)
            }

            Spacer()

            HStack(spacing: 10) {
                Button("Slice Full Folder", action: onSliceFullFolder)
                Button("Options", action: onBackToOptions)
                Button("Close Folder", action: onCloseFolder)
            }
            .controlSize(.regular)
        }
        .padding(.horizontal, 24)
        .padding(.top, 44)
        .padding(.bottom, 14)
    }

    private var emptyState: some View {
        VStack(spacing: 14) {
            Text("No clusters were found.")
                .font(.system(size: 18, weight: .semibold))
                .foregroundColor(.themeText)
            Text("You can still review the folder directly or adjust indexing options.")
                .font(.system(size: 13))
                .foregroundColor(.themeSecondaryText)
                .multilineTextAlignment(.center)

            HStack(spacing: 12) {
                Button("Slice Full Folder", action: onSliceFullFolder)
                    .buttonStyle(.borderedProminent)
                Button("Back to Options", action: onBackToOptions)
                Button("Close Folder", role: .destructive, action: onCloseFolder)
            }
        }
        .padding(24)
        .cardSurface(cornerRadius: 18, fill: .themeCard)
    }
}

private struct ClusterCanvasWorkspace: View {
    var clusters: [MediaCluster]
    var processedPaths: Set<String>
    var onSlice: (MediaCluster) -> Void
    var onMoveCluster: (Int, CGPoint) -> Void

    private let cardSize = CGSize(width: 292, height: 250)
    private let cardSpacing = CGSize(width: 72, height: 76)
    private let canvasPadding: CGFloat = 96
    private let minZoom: CGFloat = 0.55
    private let maxZoom: CGFloat = 1.35

    @State private var zoom: CGFloat = 1.0
    @State private var viewportOffset: CGSize = .zero
    @State private var cardCenters: [Int: CGPoint] = [:]
    @State private var cardDragStartCenters: [Int: CGPoint] = [:]
    @State private var lastClusterIDs: [Int] = []
    @GestureState private var dragTranslation: CGSize = .zero

    var body: some View {
        GeometryReader { proxy in
            let viewportSize = proxy.size
            let layout = makeLayout(viewportSize: viewportSize)
            let effectiveOffset = clampedOffset(
                CGSize(
                    width: viewportOffset.width + dragTranslation.width,
                    height: viewportOffset.height + dragTranslation.height
                ),
                viewportSize: viewportSize,
                canvasSize: layout.canvasSize,
                zoom: zoom
            )

            ZStack(alignment: .topLeading) {
                canvasBackground
                    .gesture(panGesture(viewportSize: viewportSize, canvasSize: layout.canvasSize))

                CanvasField()
                    .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                    .scaleEffect(zoom, anchor: .topLeading)
                    .offset(effectiveOffset)
                    .allowsHitTesting(false)

                ZStack(alignment: .topLeading) {
                    ForEach(layout.items) { item in
                        let center = cardCenters[item.id] ?? item.center
                        ClusterCloudNode(
                            cluster: item.cluster,
                            progress: progress(for: item.cluster),
                            accent: accentColor(for: item.id)
                        ) { onSlice(item.cluster) }
                        .frame(width: cardSize.width, height: cardSize.height, alignment: .center)
                        .position(center)
                        .gesture(cardDragGesture(for: item, canvasSize: layout.canvasSize))
                    }
                }
                .frame(width: layout.canvasSize.width, height: layout.canvasSize.height)
                .scaleEffect(zoom, anchor: .topLeading)
                .offset(effectiveOffset)

                canvasHint
                    .padding(14)

                zoomControls(viewportSize: viewportSize, canvasSize: layout.canvasSize)
                    .padding(14)
                    .frame(maxWidth: .infinity, alignment: .topTrailing)

                CanvasInputBridge { delta, anchor in
                    zoomBy(delta, around: anchor, viewportSize: viewportSize, canvasSize: layout.canvasSize)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .allowsHitTesting(false)
            }
            .clipShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: 22, style: .continuous)
                    .strokeBorder(Color.black.opacity(0.08), lineWidth: 1)
            )
            .overlay(
                CanvasScrollIndicators(
                    viewportSize: viewportSize,
                    canvasSize: layout.canvasSize,
                    zoom: zoom,
                    offset: effectiveOffset
                )
            )
            .contentShape(RoundedRectangle(cornerRadius: 22, style: .continuous))
            .onAppear {
                resetForLayout(layout, viewportSize: viewportSize)
            }
            .onChange(of: clusters.map(\.id)) { _, newIDs in
                if newIDs != lastClusterIDs {
                    resetForLayout(layout, viewportSize: viewportSize)
                }
            }
            .onChange(of: viewportSize) { _, _ in
                viewportOffset = clampedOffset(viewportOffset, viewportSize: viewportSize, canvasSize: layout.canvasSize, zoom: zoom)
            }
        }
    }

    private var canvasBackground: some View {
        Color.themeSubtleBackground
            .overlay(Color.white.opacity(0.35))
            .contentShape(Rectangle())
    }

    private var canvasHint: some View {
        HStack(spacing: 8) {
            Image(systemName: "hand.draw")
                .font(.system(size: 12, weight: .semibold))
            Text("Drag canvas to pan • Drag clouds to move • Pinch or ⌘ scroll to zoom")
                .font(.system(size: 12, weight: .medium))
        }
        .foregroundColor(.themeSecondaryText)
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.06), lineWidth: 1))
        .allowsHitTesting(false)
    }

    private func zoomControls(viewportSize: CGSize, canvasSize: CGSize) -> some View {
        HStack(spacing: 6) {
            Button {
                setZoom(zoom - 0.1, viewportSize: viewportSize, canvasSize: canvasSize)
            } label: {
                Image(systemName: "minus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Zoom out")

            Text("\(Int((zoom * 100).rounded()))%")
                .font(.system(size: 12, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.themeSecondaryText)
                .frame(width: 46)

            Button {
                setZoom(zoom + 0.1, viewportSize: viewportSize, canvasSize: canvasSize)
            } label: {
                Image(systemName: "plus")
                    .frame(width: 28, height: 28)
            }
            .buttonStyle(.plain)
            .contentShape(Rectangle())
            .help("Zoom in")

            Divider()
                .frame(height: 18)

            Button("Fit") {
                fitCanvas(viewportSize: viewportSize, canvasSize: canvasSize)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .help("Fit visible clusters")

            Button("Reset") {
                zoom = 1.0
                viewportOffset = clampedOffset(.zero, viewportSize: viewportSize, canvasSize: canvasSize, zoom: zoom)
            }
            .buttonStyle(.plain)
            .padding(.horizontal, 6)
            .frame(height: 28)
            .help("Reset zoom and position")
        }
        .padding(5)
        .background(.regularMaterial, in: Capsule())
        .overlay(Capsule().strokeBorder(Color.black.opacity(0.07), lineWidth: 1))
    }

    private func panGesture(viewportSize: CGSize, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 1, coordinateSpace: .local)
            .updating($dragTranslation) { value, state, _ in
                state = value.translation
            }
            .onEnded { value in
                let proposed = CGSize(
                    width: viewportOffset.width + value.translation.width,
                    height: viewportOffset.height + value.translation.height
                )
                viewportOffset = clampedOffset(proposed, viewportSize: viewportSize, canvasSize: canvasSize, zoom: zoom)
            }
    }

    private func cardDragGesture(for item: ClusterCanvasItem, canvasSize: CGSize) -> some Gesture {
        DragGesture(minimumDistance: 4, coordinateSpace: .local)
            .onChanged { value in
                let start = cardDragStartCenters[item.id] ?? (cardCenters[item.id] ?? item.center)
                if cardDragStartCenters[item.id] == nil {
                    cardDragStartCenters[item.id] = start
                }

                let proposed = CGPoint(
                    x: start.x + value.translation.width / max(zoom, 0.001),
                    y: start.y + value.translation.height / max(zoom, 0.001)
                )
                cardCenters[item.id] = clampedCardCenter(proposed, canvasSize: canvasSize)
            }
            .onEnded { _ in
                let center = cardCenters[item.id] ?? item.center
                cardDragStartCenters[item.id] = nil
                onMoveCluster(item.id, normalizedPosition(for: center, canvasSize: canvasSize))
            }
    }

    private func progress(for cluster: MediaCluster) -> ClusterProgress {
        let processed = cluster.fileURLs.reduce(0) { count, url in
            processedPaths.contains(url.standardizedFileURL.path) ? count + 1 : count
        }
        return ClusterProgress(total: cluster.fileURLs.count, processed: processed)
    }

    private func accentColor(for id: Int) -> Color {
        let palette: [Color] = [
            Color(red: 0.23, green: 0.48, blue: 0.95),
            Color(red: 0.96, green: 0.62, blue: 0.22),
            Color(red: 0.22, green: 0.68, blue: 0.50),
            Color(red: 0.58, green: 0.43, blue: 0.92),
            Color(red: 0.92, green: 0.42, blue: 0.38),
            Color(red: 0.28, green: 0.64, blue: 0.82),
            Color(red: 0.62, green: 0.62, blue: 0.66)
        ]
        return palette[abs(id) % palette.count]
    }

    private func setZoom(_ proposedZoom: CGFloat, viewportSize: CGSize, canvasSize: CGSize) {
        zoomTo(proposedZoom, around: CGPoint(x: viewportSize.width / 2, y: viewportSize.height / 2), viewportSize: viewportSize, canvasSize: canvasSize)
    }

    private func zoomBy(_ delta: CGFloat, around anchor: CGPoint, viewportSize: CGSize, canvasSize: CGSize) {
        let scaledDelta = min(max(delta, -0.22), 0.22)
        zoomTo(zoom * (1 + scaledDelta), around: anchor, viewportSize: viewportSize, canvasSize: canvasSize)
    }

    private func zoomTo(_ proposedZoom: CGFloat, around anchor: CGPoint, viewportSize: CGSize, canvasSize: CGSize) {
        let newZoom = min(max(proposedZoom, minZoom), maxZoom)
        guard abs(newZoom - zoom) > 0.0001 else { return }

        let contentAnchor = CGPoint(
            x: (anchor.x - viewportOffset.width) / max(zoom, 0.001),
            y: (anchor.y - viewportOffset.height) / max(zoom, 0.001)
        )
        let proposedOffset = CGSize(
            width: anchor.x - contentAnchor.x * newZoom,
            height: anchor.y - contentAnchor.y * newZoom
        )

        zoom = newZoom
        viewportOffset = clampedOffset(proposedOffset, viewportSize: viewportSize, canvasSize: canvasSize, zoom: newZoom)
    }

    private func fitCanvas(viewportSize: CGSize, canvasSize: CGSize) {
        let availableWidth = max(viewportSize.width - 56, 1)
        let availableHeight = max(viewportSize.height - 104, 1)
        let fittedZoom = min(1.0, max(minZoom, min(availableWidth / canvasSize.width, availableHeight / canvasSize.height)))
        zoom = fittedZoom
        let scaledSize = CGSize(width: canvasSize.width * fittedZoom, height: canvasSize.height * fittedZoom)
        let centered = CGSize(
            width: max((viewportSize.width - scaledSize.width) / 2, 0),
            height: max((viewportSize.height - scaledSize.height) / 2, 0)
        )
        viewportOffset = clampedOffset(centered, viewportSize: viewportSize, canvasSize: canvasSize, zoom: fittedZoom)
    }

    private func resetForLayout(_ layout: ClusterCanvasLayout, viewportSize: CGSize) {
        lastClusterIDs = clusters.map(\.id)
        cardCenters = Dictionary(uniqueKeysWithValues: layout.items.map { ($0.id, $0.center) })
        cardDragStartCenters = [:]
        zoom = 1.0
        viewportOffset = clampedOffset(.zero, viewportSize: viewportSize, canvasSize: layout.canvasSize, zoom: zoom)
    }

    private func clampedCardCenter(_ proposed: CGPoint, canvasSize: CGSize) -> CGPoint {
        CGPoint(
            x: min(max(proposed.x, canvasPadding + cardSize.width / 2), canvasSize.width - canvasPadding - cardSize.width / 2),
            y: min(max(proposed.y, canvasPadding + cardSize.height / 2), canvasSize.height - canvasPadding - cardSize.height / 2)
        )
    }

    private func normalizedPosition(for center: CGPoint, canvasSize: CGSize) -> CGPoint {
        let minX = canvasPadding + cardSize.width / 2
        let maxX = canvasSize.width - canvasPadding - cardSize.width / 2
        let minY = canvasPadding + cardSize.height / 2
        let maxY = canvasSize.height - canvasPadding - cardSize.height / 2
        return CGPoint(
            x: (center.x - minX) / max(maxX - minX, 1),
            y: (center.y - minY) / max(maxY - minY, 1)
        )
    }

    private func clampedOffset(_ proposed: CGSize, viewportSize: CGSize, canvasSize: CGSize, zoom: CGFloat) -> CGSize {
        let scaledWidth = canvasSize.width * zoom
        let scaledHeight = canvasSize.height * zoom
        return CGSize(
            width: clampAxis(proposed.width, viewportLength: viewportSize.width, contentLength: scaledWidth),
            height: clampAxis(proposed.height, viewportLength: viewportSize.height, contentLength: scaledHeight)
        )
    }

    private func clampAxis(_ proposed: CGFloat, viewportLength: CGFloat, contentLength: CGFloat) -> CGFloat {
        if contentLength <= viewportLength {
            return (viewportLength - contentLength) / 2
        }
        return min(0, max(viewportLength - contentLength, proposed))
    }

    private func makeLayout(viewportSize: CGSize) -> ClusterCanvasLayout {
        guard !clusters.isEmpty else {
            return ClusterCanvasLayout(items: [], canvasSize: viewportSize)
        }

        let count = clusters.count
        let aspect = max(viewportSize.width / max(viewportSize.height, 1), 1.15)
        let columns = max(1, min(count, Int(ceil(sqrt(Double(count) * Double(aspect))))))
        let rows = Int(ceil(Double(count) / Double(columns)))
        let gridWidth = canvasPadding * 2 + CGFloat(columns) * cardSize.width + CGFloat(max(columns - 1, 0)) * cardSpacing.width
        let gridHeight = canvasPadding * 2 + CGFloat(rows) * cardSize.height + CGFloat(max(rows - 1, 0)) * cardSpacing.height
        let canvasWidth = max(viewportSize.width * 1.9, gridWidth)
        let canvasHeight = max(viewportSize.height * 1.9, gridHeight)
        let canvasSize = CGSize(width: canvasWidth, height: canvasHeight)

        let sortedClusters = clusters.sorted {
            if abs($0.position.y - $1.position.y) > 0.04 {
                return $0.position.y < $1.position.y
            }
            if abs($0.position.x - $1.position.x) > 0.04 {
                return $0.position.x < $1.position.x
            }
            return $0.id < $1.id
        }

        var placedCenters: [CGPoint] = []
        let items = sortedClusters.map { cluster in
            let projected = projectedCenter(for: cluster.position, canvasSize: canvasSize)
            let center = nearestAvailableCenter(to: projected, placedCenters: placedCenters, canvasSize: canvasSize)
            placedCenters.append(center)
            return ClusterCanvasItem(id: cluster.id, cluster: cluster, center: center)
        }

        return ClusterCanvasLayout(items: items, canvasSize: canvasSize)
    }

    private func projectedCenter(for position: CGPoint, canvasSize: CGSize) -> CGPoint {
        let minX = canvasPadding + cardSize.width / 2
        let maxX = canvasSize.width - canvasPadding - cardSize.width / 2
        let minY = canvasPadding + cardSize.height / 2
        let maxY = canvasSize.height - canvasPadding - cardSize.height / 2
        return CGPoint(
            x: minX + min(max(position.x, 0), 1) * max(maxX - minX, 1),
            y: minY + min(max(position.y, 0), 1) * max(maxY - minY, 1)
        )
    }

    private func nearestAvailableCenter(to proposed: CGPoint, placedCenters: [CGPoint], canvasSize: CGSize) -> CGPoint {
        let base = clampedCardCenter(proposed, canvasSize: canvasSize)
        guard overlapsAnyCard(base, placedCenters: placedCenters) else { return base }

        let stepX = cardSize.width + cardSpacing.width
        let stepY = cardSize.height + cardSpacing.height
        var best = base
        var bestDistance = CGFloat.greatestFiniteMagnitude

        for ring in 1...10 {
            for dx in -ring...ring {
                for dy in -ring...ring where abs(dx) == ring || abs(dy) == ring {
                    let candidate = clampedCardCenter(
                        CGPoint(x: base.x + CGFloat(dx) * stepX, y: base.y + CGFloat(dy) * stepY),
                        canvasSize: canvasSize
                    )
                    guard !overlapsAnyCard(candidate, placedCenters: placedCenters) else { continue }
                    let distance = hypot(candidate.x - base.x, candidate.y - base.y)
                    if distance < bestDistance {
                        best = candidate
                        bestDistance = distance
                    }
                }
            }
            if bestDistance < CGFloat.greatestFiniteMagnitude { return best }
        }

        return best
    }

    private func overlapsAnyCard(_ center: CGPoint, placedCenters: [CGPoint]) -> Bool {
        placedCenters.contains { placed in
            abs(center.x - placed.x) < cardSize.width + cardSpacing.width &&
            abs(center.y - placed.y) < cardSize.height + cardSpacing.height
        }
    }
}

private struct CanvasInputBridge: NSViewRepresentable {
    var onZoom: (CGFloat, CGPoint) -> Void

    func makeNSView(context: Context) -> CanvasInputView {
        let view = CanvasInputView()
        view.onZoom = onZoom
        return view
    }

    func updateNSView(_ nsView: CanvasInputView, context: Context) {
        nsView.onZoom = onZoom
    }
}

private final class CanvasInputView: NSView {
    var onZoom: ((CGFloat, CGPoint) -> Void)?
    private var eventMonitor: Any?

    override var isFlipped: Bool { true }

    override func hitTest(_ point: NSPoint) -> NSView? {
        // Do not steal clicks, drags, or button presses from SwiftUI. The local
        // event monitor below handles only scoped zoom gestures.
        nil
    }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        updateEventMonitor()
    }

    deinit {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
        }
    }

    private func updateEventMonitor() {
        if let eventMonitor {
            NSEvent.removeMonitor(eventMonitor)
            self.eventMonitor = nil
        }

        guard window != nil else { return }

        eventMonitor = NSEvent.addLocalMonitorForEvents(matching: [.scrollWheel, .magnify]) { [weak self] event in
            guard let self, self.window === event.window else { return event }
            let localPoint = self.convert(event.locationInWindow, from: nil)
            guard self.bounds.contains(localPoint) else { return event }

            switch event.type {
            case .magnify:
                let delta = CGFloat(event.magnification) * 1.35
                self.emitZoom(delta: delta, at: localPoint)
                return nil
            case .scrollWheel where event.modifierFlags.contains(.command):
                let rawDelta = event.scrollingDeltaY != 0 ? event.scrollingDeltaY : -event.scrollingDeltaX
                let directionAdjustedDelta = event.isDirectionInvertedFromDevice ? rawDelta : rawDelta
                let scale: CGFloat = event.hasPreciseScrollingDeltas ? 0.006 : 0.04
                self.emitZoom(delta: CGFloat(directionAdjustedDelta) * scale, at: localPoint)
                return nil
            default:
                return event
            }
        }
    }

    private func emitZoom(delta: CGFloat, at point: CGPoint) {
        guard abs(delta) > 0.0001 else { return }
        DispatchQueue.main.async { [weak self] in
            self?.onZoom?(delta, point)
        }
    }
}

private struct ClusterCanvasLayout {
    var items: [ClusterCanvasItem]
    var canvasSize: CGSize
}

private struct ClusterCanvasItem: Identifiable {
    var id: Int
    var cluster: MediaCluster
    var center: CGPoint
}

private struct CanvasField: View {
    var body: some View {
        Canvas { context, size in
            let spacing: CGFloat = 72
            var path = Path()

            var x: CGFloat = 0
            while x <= size.width {
                path.move(to: CGPoint(x: x, y: 0))
                path.addLine(to: CGPoint(x: x, y: size.height))
                x += spacing
            }

            var y: CGFloat = 0
            while y <= size.height {
                path.move(to: CGPoint(x: 0, y: y))
                path.addLine(to: CGPoint(x: size.width, y: y))
                y += spacing
            }

            context.stroke(path, with: .color(Color.black.opacity(0.018)), lineWidth: 1)
        }
    }
}

private struct CanvasScrollIndicators: View {
    var viewportSize: CGSize
    var canvasSize: CGSize
    var zoom: CGFloat
    var offset: CGSize

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsHorizontalIndicator {
                indicatorTrack(isHorizontal: true)
                    .frame(width: horizontalTrackLength, height: 6)
                    .offset(x: 16, y: viewportSize.height - 16)
            }

            if showsVerticalIndicator {
                indicatorTrack(isHorizontal: false)
                    .frame(width: 6, height: verticalTrackLength)
                    .offset(x: viewportSize.width - 16, y: 16)
            }
        }
        .allowsHitTesting(false)
    }

    private var scaledContentSize: CGSize {
        CGSize(width: canvasSize.width * zoom, height: canvasSize.height * zoom)
    }

    private var showsHorizontalIndicator: Bool {
        scaledContentSize.width > viewportSize.width + 1
    }

    private var showsVerticalIndicator: Bool {
        scaledContentSize.height > viewportSize.height + 1
    }

    private var horizontalTrackLength: CGFloat {
        max(viewportSize.width - 32 - (showsVerticalIndicator ? 12 : 0), 1)
    }

    private var verticalTrackLength: CGFloat {
        max(viewportSize.height - 32 - (showsHorizontalIndicator ? 12 : 0), 1)
    }

    private func indicatorTrack(isHorizontal: Bool) -> some View {
        GeometryReader { proxy in
            let length = isHorizontal ? proxy.size.width : proxy.size.height
            let viewportLength = isHorizontal ? viewportSize.width : viewportSize.height
            let contentLength = isHorizontal ? scaledContentSize.width : scaledContentSize.height
            let currentOffset = isHorizontal ? offset.width : offset.height
            let thumbLength = max(42, length * min(viewportLength / max(contentLength, 1), 1))
            let travel = max(length - thumbLength, 0)
            let progress = min(max(-currentOffset / max(contentLength - viewportLength, 1), 0), 1)
            let thumbOffset = travel * progress

            ZStack(alignment: isHorizontal ? .leading : .top) {
                Capsule()
                    .fill(Color.black.opacity(0.08))
                Capsule()
                    .fill(Color.black.opacity(0.28))
                    .frame(
                        width: isHorizontal ? thumbLength : proxy.size.width,
                        height: isHorizontal ? proxy.size.height : thumbLength
                    )
                    .offset(x: isHorizontal ? thumbOffset : 0, y: isHorizontal ? 0 : thumbOffset)
            }
        }
    }
}

private struct ClusterProgress: Equatable {
    var total: Int
    var processed: Int

    var remaining: Int { max(total - processed, 0) }
    var isComplete: Bool { total > 0 && remaining == 0 }

    var displayText: String {
        if total == 0 { return "No items" }
        if processed == 0 { return "\(total) items" }
        if isComplete { return "All sliced" }
        return "\(remaining) left of \(total)"
    }
}

private struct ClusterCloudNode: View {
    var cluster: MediaCluster
    var progress: ClusterProgress
    var accent: Color
    var onSlice: () -> Void

    private var cloudDiameter: CGFloat {
        let count = Double(max(cluster.fileURLs.count, 1))
        return min(182, max(132, 116 + CGFloat(log10(count + 1)) * 42))
    }

    var body: some View {
        VStack(spacing: 10) {
            ZStack {
                CloudBlob(accent: accent)
                    .frame(width: cloudDiameter + 58, height: cloudDiameter + 34)
                    .shadow(color: accent.opacity(0.16), radius: 24, x: 0, y: 14)
                    .shadow(color: Color.black.opacity(0.08), radius: 12, x: 0, y: 8)

                ThumbnailCloud(urls: cluster.previewURLs, accent: accent)
                    .frame(width: cloudDiameter + 42, height: cloudDiameter + 10)
            }
            .frame(width: 246, height: 154)

            labelPill
        }
        .frame(width: 292, height: 250)
        .contentShape(RoundedRectangle(cornerRadius: 34, style: .continuous))
    }

    private var labelPill: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 4) {
                Text(cluster.label)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.themeText)
                    .lineLimit(1)
                    .truncationMode(.tail)

                HStack(spacing: 7) {
                    Text(progress.displayText)
                    if !progress.isComplete {
                        Text("•")
                        Text(byteString(cluster.totalBytes))
                    }
                }
                .font(.system(size: 11, weight: .medium))
                .monospacedDigit()
                .foregroundColor(.themeSecondaryText)
                .lineLimit(1)
            }

            Spacer(minLength: 8)

            if progress.isComplete {
                Button("Done") {}
                    .font(.system(size: 11, weight: .semibold))
                    .frame(minWidth: 48, minHeight: 28)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(true)
            } else {
                Button(action: onSlice) {
                    Text("Slice")
                        .font(.system(size: 11, weight: .semibold))
                        .frame(minWidth: 48, minHeight: 28)
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
            }
        }
        .padding(.leading, 14)
        .padding(.trailing, 8)
        .padding(.vertical, 8)
        .frame(width: 250)
        .background(.regularMaterial, in: Capsule())
        .overlay(
            Capsule()
                .strokeBorder(Color.black.opacity(0.07), lineWidth: 1)
        )
        .shadow(color: Color.black.opacity(0.08), radius: 10, x: 0, y: 6)
    }

    private func byteString(_ bytes: Int64) -> String {
        let formatter = ByteCountFormatter()
        formatter.allowedUnits = [.useKB, .useMB, .useGB]
        formatter.countStyle = .file
        return formatter.string(fromByteCount: bytes)
    }
}

private struct CloudBlob: View {
    var accent: Color

    var body: some View {
        ZStack {
            Circle()
                .fill(accent.opacity(0.16))
                .frame(width: 150, height: 150)
                .offset(x: -32, y: 4)
            Circle()
                .fill(accent.opacity(0.12))
                .frame(width: 128, height: 128)
                .offset(x: 36, y: -18)
            Circle()
                .fill(accent.opacity(0.10))
                .frame(width: 118, height: 118)
                .offset(x: 48, y: 28)
            Circle()
                .fill(Color.white.opacity(0.64))
                .frame(width: 104, height: 104)
                .offset(x: -6, y: -8)
                .blur(radius: 16)
            Capsule()
                .fill(accent.opacity(0.08))
                .frame(width: 212, height: 96)
                .offset(x: 4, y: 28)
                .blur(radius: 8)
        }
        .compositingGroup()
    }
}

private struct ThumbnailCloud: View {
    var urls: [URL]
    var accent: Color

    private let placements: [ThumbnailPlacement] = [
        ThumbnailPlacement(size: 92, x: -42, y: -20, rotation: -5),
        ThumbnailPlacement(size: 84, x: 35, y: -28, rotation: 6),
        ThumbnailPlacement(size: 78, x: 54, y: 38, rotation: -3),
        ThumbnailPlacement(size: 72, x: -30, y: 42, rotation: 4),
        ThumbnailPlacement(size: 56, x: -72, y: 26, rotation: -8),
        ThumbnailPlacement(size: 52, x: 82, y: -4, rotation: 9)
    ]

    var body: some View {
        ZStack {
            ForEach(Array(urls.prefix(6).enumerated()), id: \.element.path) { index, url in
                let placement = placements[index % placements.count]
                ThumbnailView(url: url)
                    .frame(width: placement.size, height: placement.size * 0.74)
                    .clipShape(RoundedRectangle(cornerRadius: max(10, placement.size * 0.12), style: .continuous))
                    .imageOutline(cornerRadius: max(10, placement.size * 0.12))
                    .rotationEffect(.degrees(placement.rotation))
                    .shadow(color: Color.black.opacity(0.15), radius: 12, x: 0, y: 8)
                    .offset(x: placement.x, y: placement.y)
                    .zIndex(Double(index))
            }

            if urls.isEmpty {
                Image(systemName: "photo.on.rectangle.angled")
                    .font(.system(size: 34, weight: .medium))
                    .foregroundColor(accent.opacity(0.64))
            }
        }
    }
}

private struct ThumbnailPlacement {
    var size: CGFloat
    var x: CGFloat
    var y: CGFloat
    var rotation: Double
}
