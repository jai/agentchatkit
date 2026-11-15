import Foundation

public struct ChatThreadActionIdentifiers {
    public var archive: String?
    public var delete: String?
    public var confirmDelete: String?
    public var cancelDelete: String?
    public var dismissError: String?
    public var progress: String?

    public init(archive: String? = "thread-archive", delete: String? = "thread-delete",
                confirmDelete: String? = "thread-confirm-delete", cancelDelete: String? = "thread-cancel-delete",
                dismissError: String? = "thread-dismiss-error", progress: String? = "thread-action-pending") {
        self.archive = archive
        self.delete = delete
        self.confirmDelete = confirmDelete
        self.cancelDelete = cancelDelete
        self.dismissError = dismissError
        self.progress = progress
    }
}
