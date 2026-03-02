// SPDX-License-Identifier: (see LICENSE)
// Mayam — Admin Worklist & Webhook Handler

import Foundation
import MayamCore

// MARK: - AdminWorklistHandler

/// Manages the in-memory worklist of scheduled procedure steps and exposes
/// CRUD operations for the Admin REST API.
///
/// This handler maintains a registry of ``ScheduledProcedureStep`` records
/// that the Modality Worklist SCP serves to modalities. In a production
/// deployment these records are typically populated from an RIS via HL7 ORM
/// messages; the Admin API provides a direct management interface.
public actor AdminWorklistHandler {

    // MARK: - Stored Properties

    /// Scheduled procedure steps keyed by ``ScheduledProcedureStep/id``.
    private var steps: [String: ScheduledProcedureStep] = [:]

    // MARK: - Initialiser

    /// Creates a new worklist handler with an empty worklist.
    public init() {}

    // MARK: - Public Methods

    /// Returns all scheduled procedure steps, optionally filtered by status.
    ///
    /// - Parameter status: Optional status filter.
    /// - Returns: Matching steps sorted by scheduled start date (ascending).
    public func listSteps(status: ScheduledProcedureStep.Status? = nil) -> [ScheduledProcedureStep] {
        let all = Array(steps.values)
        let filtered = status.map { s in all.filter { $0.status == s } } ?? all
        return filtered.sorted { $0.scheduledStartDate < $1.scheduledStartDate }
    }

    /// Returns a single scheduled procedure step by identifier.
    ///
    /// - Parameter id: The ``ScheduledProcedureStep/scheduledProcedureStepID``.
    /// - Returns: The matching step.
    /// - Throws: ``AdminError/notFound(resource:)`` if no step exists with that identifier.
    public func getStep(id: String) throws -> ScheduledProcedureStep {
        guard let step = steps[id] else {
            throw AdminError.notFound(resource: "scheduled procedure step \(id)")
        }
        return step
    }

    /// Creates a new scheduled procedure step.
    ///
    /// - Parameter step: The step to create.
    /// - Returns: The stored ``ScheduledProcedureStep``.
    /// - Throws: ``AdminError/badRequest(reason:)`` if a step with the same identifier already exists.
    public func createStep(_ step: ScheduledProcedureStep) throws -> ScheduledProcedureStep {
        guard steps[step.scheduledProcedureStepID] == nil else {
            throw AdminError.badRequest(reason: "Scheduled procedure step '\(step.scheduledProcedureStepID)' already exists")
        }
        steps[step.scheduledProcedureStepID] = step
        return step
    }

    /// Updates an existing scheduled procedure step.
    ///
    /// - Parameter step: The updated step (must carry the same identifier as the existing record).
    /// - Returns: The updated ``ScheduledProcedureStep``.
    /// - Throws: ``AdminError/notFound(resource:)`` if no step exists with that identifier.
    public func updateStep(_ step: ScheduledProcedureStep) throws -> ScheduledProcedureStep {
        guard steps[step.scheduledProcedureStepID] != nil else {
            throw AdminError.notFound(resource: "scheduled procedure step \(step.scheduledProcedureStepID)")
        }
        steps[step.scheduledProcedureStepID] = step
        return step
    }

    /// Deletes a scheduled procedure step.
    ///
    /// - Parameter id: The ``ScheduledProcedureStep/scheduledProcedureStepID`` to delete.
    /// - Throws: ``AdminError/notFound(resource:)`` if no step exists with that identifier.
    public func deleteStep(id: String) throws {
        guard steps.removeValue(forKey: id) != nil else {
            throw AdminError.notFound(resource: "scheduled procedure step \(id)")
        }
    }
}

// MARK: - AdminMPPSHandler

/// Provides read-only access to MPPS instances for the Admin REST API.
///
/// MPPS instances are created and updated by modalities via the DICOM
/// N-CREATE / N-SET services. This handler surfaces those records for
/// monitoring and audit via the Admin API.
public actor AdminMPPSHandler {

    // MARK: - Stored Properties

    /// In-memory MPPS instances keyed by SOP Instance UID.
    private var instances: [String: PerformedProcedureStep] = [:]

    // MARK: - Initialiser

    /// Creates a new MPPS handler with no instances.
    public init() {}

    // MARK: - Public Methods

    /// Returns all MPPS instances, optionally filtered by status.
    ///
    /// - Parameter status: Optional status filter.
    /// - Returns: Matching instances sorted by creation time (newest first).
    public func listInstances(status: PerformedProcedureStep.Status? = nil) -> [PerformedProcedureStep] {
        let all = Array(instances.values)
        let filtered = status.map { s in all.filter { $0.status == s } } ?? all
        return filtered.sorted { $0.createdAt > $1.createdAt }
    }

    /// Returns a single MPPS instance by SOP Instance UID.
    ///
    /// - Parameter uid: The SOP Instance UID to look up.
    /// - Returns: The matching ``PerformedProcedureStep``.
    /// - Throws: ``AdminError/notFound(resource:)`` if not found.
    public func getInstance(uid: String) throws -> PerformedProcedureStep {
        guard let instance = instances[uid] else {
            throw AdminError.notFound(resource: "MPPS instance \(uid)")
        }
        return instance
    }

    /// Stores or updates an MPPS instance (used internally when the MPPS SCP
    /// creates or updates a procedure step).
    ///
    /// - Parameter instance: The instance to store.
    public func storeInstance(_ instance: PerformedProcedureStep) {
        instances[instance.sopInstanceUID] = instance
    }
}

// MARK: - AdminWebhookHandler

/// Manages webhook subscriptions for the Admin REST API.
///
/// Webhook subscriptions configure the set of endpoints that receive
/// study lifecycle events (``RISEvent``) via JSON/HTTPS POST with
/// HMAC-SHA256 signatures.
public actor AdminWebhookHandler {

    // MARK: - Stored Properties

    /// Registered webhook subscriptions keyed by subscription identifier.
    private var subscriptions: [UUID: WebhookSubscription] = [:]

    // MARK: - Initialiser

    /// Creates a new webhook handler with no subscriptions.
    public init() {}

    // MARK: - Public Methods

    /// Returns all webhook subscriptions, sorted by name.
    ///
    /// - Returns: An array of all ``WebhookSubscription`` records.
    public func listSubscriptions() -> [WebhookSubscription] {
        Array(subscriptions.values).sorted { $0.name < $1.name }
    }

    /// Returns a single webhook subscription by identifier.
    ///
    /// - Parameter id: The subscription identifier.
    /// - Returns: The matching ``WebhookSubscription``.
    /// - Throws: ``AdminError/notFound(resource:)`` if not found.
    public func getSubscription(id: UUID) throws -> WebhookSubscription {
        guard let sub = subscriptions[id] else {
            throw AdminError.notFound(resource: "webhook subscription \(id)")
        }
        return sub
    }

    /// Creates a new webhook subscription.
    ///
    /// - Parameter subscription: The subscription to create.
    /// - Returns: The stored ``WebhookSubscription``.
    public func createSubscription(_ subscription: WebhookSubscription) -> WebhookSubscription {
        subscriptions[subscription.id] = subscription
        return subscription
    }

    /// Updates an existing webhook subscription.
    ///
    /// - Parameter subscription: The updated subscription.
    /// - Returns: The updated ``WebhookSubscription``.
    /// - Throws: ``AdminError/notFound(resource:)`` if not found.
    public func updateSubscription(_ subscription: WebhookSubscription) throws -> WebhookSubscription {
        guard subscriptions[subscription.id] != nil else {
            throw AdminError.notFound(resource: "webhook subscription \(subscription.id)")
        }
        subscriptions[subscription.id] = subscription
        return subscription
    }

    /// Deletes a webhook subscription.
    ///
    /// - Parameter id: The subscription identifier to delete.
    /// - Throws: ``AdminError/notFound(resource:)`` if not found.
    public func deleteSubscription(id: UUID) throws {
        guard subscriptions.removeValue(forKey: id) != nil else {
            throw AdminError.notFound(resource: "webhook subscription \(id)")
        }
    }
}
