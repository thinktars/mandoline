import Foundation
import SwiftData

@Model
final class ProcessedFile {
    @Attribute(.unique) var filePath: String
    var processedAt: Date
    var action: ActionType
    
    enum ActionType: String, Codable {
        case kept
        case trashed // We might not track trashed if it's literally in the trash, but tracking it allows Undo
    }
    
    init(filePath: String, action: ActionType) {
        self.filePath = filePath
        self.processedAt = Date()
        self.action = action
    }
}
