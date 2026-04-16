import Foundation

public final class FileWatcher: @unchecked Sendable {

    private var source: DispatchSourceFileSystemObject?
    private var fileDescriptor: Int32 = -1
    private let debounceInterval: TimeInterval
    private var debounceWorkItem: DispatchWorkItem?
    private let queue = DispatchQueue(label: "com.slantedt.markdownviewer.filewatcher")

    public var onChange: (@Sendable () -> Void)?

    public init(debounceInterval: TimeInterval = 0.2) {
        self.debounceInterval = debounceInterval
    }

    deinit {
        stop()
    }

    public func watch(path: String) {
        stop()

        fileDescriptor = open(path, O_EVTONLY)
        guard fileDescriptor >= 0 else { return }

        let source = DispatchSource.makeFileSystemObjectSource(
            fileDescriptor: fileDescriptor,
            eventMask: [.write, .rename, .delete],
            queue: queue
        )

        source.setEventHandler { [weak self] in
            self?.handleEvent()
        }

        source.setCancelHandler { [weak self] in
            guard let self else { return }
            if self.fileDescriptor >= 0 {
                close(self.fileDescriptor)
                self.fileDescriptor = -1
            }
        }

        self.source = source
        source.resume()
    }

    public func stop() {
        debounceWorkItem?.cancel()
        debounceWorkItem = nil
        source?.cancel()
        source = nil
    }

    private func handleEvent() {
        debounceWorkItem?.cancel()
        let onChange = self.onChange
        let workItem = DispatchWorkItem {
            DispatchQueue.main.async {
                onChange?()
            }
        }
        debounceWorkItem = workItem
        queue.asyncAfter(deadline: .now() + debounceInterval, execute: workItem)
    }
}
