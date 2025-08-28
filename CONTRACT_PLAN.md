## CONTRACT PLAN: CascadeAgent.cdc

References:
- Flow Actions – Scheduled Callbacks: [Introduction to Scheduled Callbacks](https://developers.flow.com/blockchain-development-tutorials/flow-actions/scheduled-callbacks-introduction)

---

## Contract Structure (CascadeAgent.cdc)

High-level goals from PROJECT_PLAN.md:
- Maintain a global registry mapping Agent IDs to owner, status, and metadata.
- Provide an `Agent` resource users store in their account to manage a subscription.
- Implement scheduled callbacks with `FlowCallbackScheduler`, where a handler invokes `Agent.executeSubscription()`.
- Expose read-friendly view functions for API queries.

### Imports (string-based)

```cadence
import "FlowCallbackScheduler"
import "FlowToken"
import "FungibleToken"
```

### Events

```cadence
access(all) event AgentCreated(id: UInt64, owner: Address)
access(all) event AgentStatusChanged(id: UInt64, status: UInt8)
access(all) event AgentUpdated(id: UInt64)
access(all) event CallbackScheduled(id: UInt64, at: UFix64)
```

### Enums and Structs

```cadence
access(all) enum Status: UInt8 {
  access(all) case Active
  access(all) case Paused
  access(all) case Canceled
}

// Lightweight index record stored on-chain for API friendliness.
access(all) struct AgentIndex {
  access(all) let id: UInt64
  access(all) let owner: Address
  access(all) var status: Status
  access(all) var paymentAmount: UFix64
  access(all) var paymentVaultType: Type
  access(all) var beneficiary: Address
  access(all) var schedule: String
  access(all) var nextPaymentTimestamp: UFix64

  init(
    id: UInt64,
    owner: Address,
    status: Status,
    paymentAmount: UFix64,
    paymentVaultType: Type,
    beneficiary: Address,
    schedule: String,
    nextPaymentTimestamp: UFix64
  ) {
    self.id = id
    self.owner = owner
    self.status = status
    self.paymentAmount = paymentAmount
    self.paymentVaultType = paymentVaultType
    self.beneficiary = beneficiary
    self.schedule = schedule
    self.nextPaymentTimestamp = nextPaymentTimestamp
  }
}

// Details struct returned by API-facing function
access(all) struct AgentDetails {
  access(all) let id: UInt64
  access(all) let owner: Address
  access(all) let status: String
  access(all) let paymentAmount: UFix64
  access(all) let paymentVaultType: Type
  access(all) let beneficiary: Address
  access(all) let schedule: String
  access(all) let nextPaymentTimestamp: UFix64

  init(
    id: UInt64,
    owner: Address,
    status: String,
    paymentAmount: UFix64,
    paymentVaultType: Type,
    beneficiary: Address,
    schedule: String,
    nextPaymentTimestamp: UFix64
  ) {
    self.id = id
    self.owner = owner
    self.status = status
    self.paymentAmount = paymentAmount
    self.paymentVaultType = paymentVaultType
    self.beneficiary = beneficiary
    self.schedule = schedule
    self.nextPaymentTimestamp = nextPaymentTimestamp
  }
}
```

### Named Paths (helpers)

```cadence
access(all) view fun getAgentStoragePath(id: UInt64): StoragePath {
  return StoragePath(identifier: "cascade/agent/".concat(id.toString()))!
}

access(all) view fun getAgentPublicPath(id: UInt64): PublicPath {
  return PublicPath(identifier: "cascade/agent/".concat(id.toString()))!
}

access(all) view fun getHandlerStoragePath(id: UInt64): StoragePath {
  return StoragePath(identifier: "cascade/agent-handler/".concat(id.toString()))!
}
```

### Global State (Registry of Truth)

```cadence
// Next ID for newly created Agents
access(contract) var nextAgentId: UInt64

// Index of owners for each agent id
access(contract) let agentOwnerById: {UInt64: Address}

// Index of status for each agent id
access(contract) let agentStatusById: {UInt64: Status}

// Agent IDs per owner
access(contract) let agentsByOwner: {Address: [UInt64]}

// Rich index for API (denormalized; maintained by resource ops)
access(contract) let agentIndexById: {UInt64: AgentIndex}
```

### Contract-level Functions (Factories + Registry Management)

```cadence
// Create a new Agent resource with provided parameters. The transaction should
// save it into signer storage and then call `registerAgent`.
access(all) fun createAgent(
  paymentAmount: UFix64,
  paymentVaultType: Type,
  beneficiary: Address,
  schedule: String,
  initialNextPaymentTimestamp: UFix64,
  // Capability for withdrawing callback fees (FlowToken)
  flowFeeWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?,
  // Capability for withdrawing payment tokens from the user (Provider)
  paymentProviderCap: Capability<&{FungibleToken.Provider}>?
): @Agent {
  // stub: return <-create Agent(...)
  panic("stub")
}

// Register the Agent in the central registry after it is saved in user storage.
access(contract) fun registerAgent(owner: Address, agentId: UInt64, index: AgentIndex) {
  // stub: update maps and emit AgentCreated
}

// Update status in registry (called by Agent methods)
access(contract) fun setStatus(agentId: UInt64, status: Status) {
  // stub: update status map, index, and emit AgentStatusChanged
}

// Update denormalized index (called by Agent methods)
access(contract) fun setIndex(agentId: UInt64, index: AgentIndex) {
  // stub: update agentIndexById and emit AgentUpdated
}
```

### API-facing View Functions (for Scripts)

```cadence
access(all) view fun getAgentStatus(agentId: UInt64): String {
  // stub: return Status as string ("active"|"paused"|"canceled")
  return ""
}

access(all) view fun getAgentsByUser(userAddress: Address): [UInt64] {
  // stub: return list of agent IDs for owner
  return []
}

access(all) view fun getLiveAgentsByUser(userAddress: Address): [UInt64] {
  // stub: filter agentsByOwner by status Active
  return []
}

access(all) view fun getAgentDetails(agentId: UInt64): AgentDetails {
  // stub: map AgentIndex to AgentDetails string status
  return AgentDetails(
    id: 0,
    owner: 0x0,
    status: "",
    paymentAmount: 0.0,
    paymentVaultType: Type<@AnyResource>(),
    beneficiary: 0x0,
    schedule: "",
    nextPaymentTimestamp: 0.0
  )
}
```

### init()

```cadence
init() {
  self.nextAgentId = 1
  self.agentOwnerById = {}
  self.agentStatusById = {}
  self.agentsByOwner = {}
  self.agentIndexById = {}
}
```

---

## Resource Structure (Agent)

The `Agent` resource is stored in the user's account at a dynamic path (see helpers above). It encapsulates subscription parameters and performs token movements during execution. It also orchestrates scheduling of subsequent callbacks via `FlowCallbackScheduler`.

```cadence
access(all) resource Agent {
  // Identity / lifecycle
  access(all) let uuid: UInt64 // equals assigned agent id for index consistency
  access(all) var status: Status

  // Payment configuration
  access(all) var paymentAmount: UFix64
  access(all) var paymentVaultType: Type
  access(all) var beneficiary: Address
  access(all) var schedule: String

  // Next execution time (seconds since epoch)
  access(all) var nextPaymentTimestamp: UFix64

  // Optional capabilities to operate autonomously from callbacks
  // - Fees for scheduling callbacks (FlowToken): needs Withdraw entitlement
  access(all) let flowFeeWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?
  // - Source of the subscription payment (Provider interface)
  access(all) let paymentProviderCap: Capability<&{FungibleToken.Provider}>?

  // Storage path for the per-agent handler resource
  access(all) let handlerStoragePath: StoragePath

  // Constructor
  access(all) fun init(
    id: UInt64,
    paymentAmount: UFix64,
    paymentVaultType: Type,
    beneficiary: Address,
    schedule: String,
    initialNextPaymentTimestamp: UFix64,
    flowFeeWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?,
    paymentProviderCap: Capability<&{FungibleToken.Provider}>?,
    handlerStoragePath: StoragePath
  ) {
    self.uuid = id
    self.status = Status.Active
    self.paymentAmount = paymentAmount
    self.paymentVaultType = paymentVaultType
    self.beneficiary = beneficiary
    self.schedule = schedule
    self.nextPaymentTimestamp = initialNextPaymentTimestamp
    self.flowFeeWithdrawCap = flowFeeWithdrawCap
    self.paymentProviderCap = paymentProviderCap
    self.handlerStoragePath = handlerStoragePath
  }

  // Core operation invoked by the scheduled callback handler
  access(all) fun executeSubscription(): Bool {
    // stub: verify status Active, withdraw payment from provider, deposit to beneficiary, update index
    // stub: compute nextPaymentTimestamp from schedule, then scheduleNextCallback(...)
    return false
  }

  // Change lifecycle state
  access(all) fun pause() {
    // stub: set status Paused; update registry
  }

  access(all) fun unpause() {
    // stub: set status Active; update registry
  }

  access(all) fun cancel() {
    // stub: set status Canceled; update registry; prepare for destruction
  }

  // Update key parameters
  access(all) fun updatePaymentDetails(newAmount: UFix64?, newSchedule: String?) {
    // stub: apply non-nil updates; update registry index
  }

  // Internal helper to schedule the next callback. Uses FlowCallbackScheduler.
  access(all) fun scheduleNextCallback(
    timestamp: UFix64,
    priority: UInt8,
    executionEffort: UInt64,
    callbackData: AnyStruct?
  ) {
    // stub: estimate fees, withdraw via flowFeeWithdrawCap, issue handler capability, and call schedule
  }
}
```

---

## The Handler (Scheduled Callback Resource)

Design: A per-agent handler that implements `FlowCallbackScheduler.CallbackHandler`. It lives in the user's account storage at `getHandlerStoragePath(id)`. This follows the tutorial pattern while allowing each Agent to autonomously execute and reschedule. See reference tutorial: [Introduction to Scheduled Callbacks](https://developers.flow.com/blockchain-development-tutorials/flow-actions/scheduled-callbacks-introduction).

```cadence
access(all) resource AgentHandler: FlowCallbackScheduler.CallbackHandler {
  // The owning agent id this handler serves.
  access(all) let agentId: UInt64

  access(all) fun init(agentId: UInt64) {
    self.agentId = agentId
  }

  // Executes when the scheduler triggers the callback.
  access(FlowCallbackScheduler.Execute) fun executeCallback(id: UInt64, data: AnyStruct?) {
    // stub: load the Agent from the owner's storage path using self.agentId
    // stub: call agent.executeSubscription()
    // stub: optionally log or emit events
  }
}
```

Helper to create the handler (invoked by create-agent transaction):

```cadence
access(all) fun createAgentHandler(agentId: UInt64): @AgentHandler {
  return <-create AgentHandler(agentId: agentId)
}
```

Notes:
- The `executeCallback` entitlement and interface match the reference tutorial.
- Fees for scheduling the next callback should be paid via the `flowFeeWithdrawCap` stored in the `Agent`, withdrawn inside `Agent.scheduleNextCallback`.
- `callbackData` convention should include the `agentId` to make the handler stateless beyond `agentId` if desired.

---

## Transaction Templates

These follow the required scheduled-callback parameters: `timestamp: UFix64`, `priority: UInt8 (0=High, 1=Medium, 2=Low)`, `executionEffort: UInt64 (>=10)`, `handlerStoragePath: StoragePath`, `callbackData: AnyStruct?`. See: [Introduction to Scheduled Callbacks](https://developers.flow.com/blockchain-development-tutorials/flow-actions/scheduled-callbacks-introduction).

### create_agent.cdc (template)

```cadence
import "CascadeAgent" // placeholder name for the contract you will deploy
import "FlowCallbackScheduler"
import "FlowToken"
import "FungibleToken"

transaction(
  paymentAmount: UFix64,
  paymentVaultType: Type,
  beneficiary: Address,
  schedule: String,

  // first callback scheduling params
  firstDelaySeconds: UFix64,        // e.g., 604800.0 for weekly
  priority: UInt8,                  // 0,1,2
  executionEffort: UInt64,          // >= 10
  callbackData: AnyStruct?,         // should encode agentId once known

  // capabilities (optional, but recommended for autonomy)
  flowFeeWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?,
  paymentProviderCap: Capability<&{FungibleToken.Provider}>?
) {
  prepare(signer: auth(Storage, Capabilities) &Account) {
    // 1) Assign id and compute storage paths
    let id = CascadeAgent.nextAgentId // view or public getter if needed
    let agentStoragePath = CascadeAgent.getAgentStoragePath(id: id)
    let handlerStoragePath = CascadeAgent.getHandlerStoragePath(id: id)

    // 2) Create Agent resource (factory call)
    let agent <- CascadeAgent.createAgent(
      paymentAmount: paymentAmount,
      paymentVaultType: paymentVaultType,
      beneficiary: beneficiary,
      schedule: schedule,
      initialNextPaymentTimestamp: getCurrentBlock().timestamp + firstDelaySeconds,
      flowFeeWithdrawCap: flowFeeWithdrawCap,
      paymentProviderCap: paymentProviderCap
    )

    // 3) Save Agent to storage
    signer.storage.save(<-agent, to: agentStoragePath)

    // 4) Create and save per-agent handler
    if signer.storage.borrow<&AnyResource>(from: handlerStoragePath) == nil {
      let handler <- CascadeAgent.createAgentHandler(agentId: id)
      signer.storage.save(<-handler, to: handlerStoragePath)
    }

    // 5) Registry entry
    let index = CascadeAgent.AgentIndex(
      id: id,
      owner: signer.address,
      status: CascadeAgent.Status.Active,
      paymentAmount: paymentAmount,
      paymentVaultType: paymentVaultType,
      beneficiary: beneficiary,
      schedule: schedule,
      nextPaymentTimestamp: getCurrentBlock().timestamp + firstDelaySeconds
    )
    CascadeAgent.registerAgent(owner: signer.address, agentId: id, index: index)

    // 6) Estimate fees and schedule first callback
    let pr = priority == 0
      ? FlowCallbackScheduler.Priority.High
      : priority == 1
        ? FlowCallbackScheduler.Priority.Medium
        : FlowCallbackScheduler.Priority.Low

    let future = getCurrentBlock().timestamp + firstDelaySeconds

    let est = FlowCallbackScheduler.estimate(
      data: callbackData, // should include id
      timestamp: future,
      priority: pr,
      executionEffort: executionEffort
    )

    assert(
      est.timestamp != nil || pr == FlowCallbackScheduler.Priority.Low,
      message: est.error ?? "estimation failed"
    )

    // withdraw fees from signer's FlowToken vault for the first schedule
    let vaultRef = signer.storage
      .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
      ?? panic("missing FlowToken vault")
    let fees <- vaultRef.withdraw(amount: est.flowFee ?? 0.0) as! @FlowToken.Vault

    // issue handler capability
    let handlerCap = signer.capabilities.storage
      .issue<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>(handlerStoragePath)

    let receipt = FlowCallbackScheduler.schedule(
      callback: handlerCap,
      data: callbackData,
      timestamp: future,
      priority: pr,
      executionEffort: executionEffort,
      fees: <-fees
    )

    log("CascadeAgent scheduled callback id: ".concat(receipt.id.toString()))
    emit CascadeAgent.CallbackScheduled(id: id, at: future)
  }
}
```

### manage_agent.cdc (template)

```cadence
import "CascadeAgent"

// Manage a stored Agent by action string; extend as needed
transaction(
  agentId: UInt64,
  action: String, // "pause" | "unpause" | "cancel" | "update"
  newAmount: UFix64?,
  newSchedule: String?
) {
  prepare(signer: auth(Storage) &Account) {
    let agentPath = CascadeAgent.getAgentStoragePath(id: agentId)
    let agentRef = signer.storage.borrow<&CascadeAgent.Agent>(from: agentPath)
      ?? panic("Agent not found in signer storage")

    if action == "pause" {
      agentRef.pause()
    } else if action == "unpause" {
      agentRef.unpause()
    } else if action == "cancel" {
      // optional: clean up handler in storage before cancel
      agentRef.cancel()
      // optional: remove from storage afterward, or convert cancel to destructive op
    } else if action == "update" {
      agentRef.updatePaymentDetails(newAmount: newAmount, newSchedule: newSchedule)
    } else {
      panic("Unsupported action")
    }
  }
}
```

### Script: Read Basic CascadeAgent Data (template)

```cadence
import "CascadeAgent"

access(all) fun main(agentId: UInt64): CascadeAgent.AgentDetails {
  return CascadeAgent.getAgentDetails(agentId: agentId)
}
```

---

## Notes and Considerations

- Follow the Scheduled Callbacks sanity checklist from the tutorial: estimate fees before scheduling; validate timestamps; ensure correct capability entitlement: `Capability<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>`; minimum `executionEffort = 10`.
- Store `agentId` inside `callbackData` so the handler can reliably locate the correct `Agent` in storage when `executeCallback` fires.
- The `Agent` stores optional capabilities to enable paying fees and executing token transfers during callbacks without a new transaction, consistent with capability-based security in Cadence.
- Status transitions must update both `agentStatusById` and `agentIndexById` to keep API responses consistent with on-chain actions.
- Use view functions (`access(all) view fun`) for read-only API endpoints.
- Test on emulator with `flow emulator --scheduled-callbacks` and `flow-cli >= 2.4.1` as in the tutorial.
