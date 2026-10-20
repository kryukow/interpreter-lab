import Foundation

enum LabBudgetEvents {
    static let changed = Notification.Name("LabBudgetChanged")
    static let elevenCharged = Notification.Name("LabElevenCharged")
    static let credentialsChanged = Notification.Name("LabBudgetCredentialsChanged")
}
