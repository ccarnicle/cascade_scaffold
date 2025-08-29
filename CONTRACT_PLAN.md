## CONTRACT PLAN: Cascade.cdc (updated to match current contract)

References:
- Flow Actions – Scheduled Callbacks: [Introduction to Scheduled Callbacks](https://developers.flow.com/blockchain-development-tutorials/flow-actions/scheduled-callbacks-introduction)

---

## Contract Structure (Cascade.cdc)

Source of truth: current `cadence/contracts/Cascade.cdc`.

- Contract name: `Cascade`
- Imports: string imports for `FlowCallbackScheduler`, `FlowToken`, `FungibleToken`
- Events: `AgentCreated`, `AgentStatusChanged`, `AgentUpdated`, `CallbackScheduled`
- Enums:
  - `Status { Active, Paused, Canceled }`
  - `Schedule { Daily, Weekly, Monthly, Yearly, OneTime }`
- Structs:
  - `AgentDetails` fields: `id`, `owner`, `organization`, `status`, `paymentAmount`, `paymentVaultType`, `schedule` (Schedule enum), `nextPaymentTimestamp`
  - `AgentOwnerIndex` (owner + [ids]) and `OrganizationIndex` (organization + [ids])
- Global State (present in code):
  - `nextAgentId: UInt64`
  - `agentDetailsById: {UInt64: AgentDetails}`
  - `agentsByOwner: {Address: AgentOwnerIndex}`
  - `agentsByOrganization: {String: OrganizationIndex}`
  - `verifiedOrganizations: [String]` (initialized to `["AISPORTS"]`)
  - `organizationAddressByName: {String: Address}` (maps organization name → recipient address)
  - Named paths:
    - `CascadeAdminStoragePath: StoragePath`
    - `CascadeAgentStoragePath: StoragePath`
    - `CascadeAgentPublicPath: PublicPath`

Notes:
- The contract has removed auxiliary detail structs; `AgentDetails` is the authoritative, query-friendly record for agent metadata.

---

## Resource Structure (Agent)

In the current contract, `Agent` implements `FlowCallbackScheduler.CallbackHandler` and is the scheduled-callback handler itself. The agent resource itself stores only the `agentId`; all other metadata lives in `AgentDetails` and is recorded in the on-chain registry `agentDetailsById`.

Signature and members (as in code):

```cadence
access(all) resource Agent: FlowCallbackScheduler.CallbackHandler {
  access(all) let agentId: UInt64

  init(id: UInt64) { /* ... */ }

  access(FlowCallbackScheduler.Execute) fun executeCallback(id: UInt64, data: AnyStruct?) { /* ... */ }
  access(all) fun pause() { /* ... */ }
  access(all) fun unpause() { /* ... */ }
  access(all) fun cancel() { /* ... */ }
  access(all) fun updatePaymentDetails(newAmount: UFix64?, newSchedule: String?) { /* ... */ }
  access(contract) fun registerAgent(owner: Address, organization: String, paymentAmount: UFix64, paymentVaultType: Type, schedule: Schedule, nextPaymentTimestamp: UFix64) { /* ... */ }
}
```

Notes:
- There is no separate handler resource. The `Agent` is the callback handler.
- All payment/schedule/organization details are tracked in `AgentDetails` keyed by the agent id and managed in `agentDetailsById`.
- `executeCallback` will auto-register the agent if `data` is an `AgentRegistrationData` payload; otherwise it will panic when unregistered.
- `pause`, `unpause`, `cancel`, and `updatePaymentDetails` require registration.

---

## Admin Resource (CascadeAdmin) and Verified Organizations

- `CascadeAdmin` is stored in the contract account at `CascadeAdminStoragePath`.
- Purpose: manage a verified organization list.
- State: `verifiedOrganizations: [String]` (string array used as a set).
- Initialized with `["AISPORTS"]`.
- Methods:
  - `addVerifiedOrganization(org: String)`
    - Preconditions: non-empty, <= 40 chars, not already present
    - Appends `org` to `verifiedOrganizations`
- View helpers:
  - `isVerifiedOrganization(org: String): Bool`
  - `getVerifiedOrganizations(): [String]`
  - `getAgentStoragePath(id: UInt64): StoragePath` → `"CascadeAgent/{id}"`
  - `getAgentPublicPath(id: UInt64): PublicPath` → `"CascadeAgent/{id}"`
  - `getAgentDetails(id: UInt64): AgentDetails?`
  - `getAgentsByOwner(owner: Address): [UInt64]?`
  - `getAgentsByOrganization(organization: String): [UInt64]?`

---

## Transaction Templates (aligned with current design)

Key points:
- The handler capability should be issued directly to the stored `Agent` (which implements the handler interface). No separate handler storage path is needed.
- After creating and saving an `Agent`, register it in `agentDetailsById` via the internal `Agent.registerAgent` method (currently `access(contract)`), which updates `agentsByOwner` and `agentsByOrganization` and emits `AgentCreated`.

### create_agent.cdc (template)

```cadence
import "Cascade"
import "FlowCallbackScheduler"
import "FlowToken"
import "FungibleToken"

transaction(
  id: UInt64,
  paymentAmount: UFix64,
  paymentVaultType: Type,
  organization: String,
  schedule: Cascade.Schedule,
  firstDelaySeconds: UFix64,
  priority: UInt8,
  executionEffort: UInt64,
  flowFeeWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?,
  paymentProviderCap: Capability<&{FungibleToken.Provider}>?
) {
  prepare(signer: auth(Storage, Capabilities) &Account) {
    // 1) Create Agent with provided id
    let agentId = id
    let agent <- Cascade.createAgent(
      id: agentId,
      paymentAmount: paymentAmount,
      paymentVaultType: paymentVaultType,
      organization: organization,
      schedule: schedule,
      nextPaymentTimestamp: getCurrentBlock().timestamp + firstDelaySeconds
    )

    // 2) Save Agent at its per-id path
    let storagePath = Cascade.getAgentStoragePath(id: agentId)
    assert(signer.storage.borrow<&Cascade.Agent>(from: storagePath) == nil, message: "agent path occupied")
    signer.storage.save(<-agent, to: storagePath)

    // 3) Registration is performed lazily on first callback
    //    Build AgentRegistrationData as callback data and pass it to the scheduler below

    // 4) Estimate and schedule first callback using capability to the stored Agent
    let future = getCurrentBlock().timestamp + firstDelaySeconds
    let pr = priority == 0
      ? FlowCallbackScheduler.Priority.High
      : priority == 1
        ? FlowCallbackScheduler.Priority.Medium
        : FlowCallbackScheduler.Priority.Low

    let regData = Cascade.AgentRegistrationData(
      organization: organization,
      paymentAmount: paymentAmount,
      paymentVaultType: paymentVaultType,
      schedule: schedule,
      nextPaymentTimestamp: getCurrentBlock().timestamp + firstDelaySeconds
    )

    let est = FlowCallbackScheduler.estimate(
      data: regData,
      timestamp: future,
      priority: pr,
      executionEffort: executionEffort
    )
    assert(est.timestamp != nil || pr == FlowCallbackScheduler.Priority.Low, message: est.error ?? "estimation failed")

    let vaultRef = signer.storage
      .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
      ?? panic("missing FlowToken vault")
    let fees <- vaultRef.withdraw(amount: est.flowFee ?? 0.0) as! @FlowToken.Vault

    // let agentCap = signer.capabilities.storage.issue<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>(/storage/CascadeAgent_<id>)

    let receipt = FlowCallbackScheduler.schedule(
      callback: agentCap,
      data: regData,
      timestamp: future,
      priority: pr,
      executionEffort: executionEffort,
      fees: <-fees
    )

    log("Scheduled callback id: ".concat(receipt.id.toString()))
    emit Cascade.CallbackScheduled(id: agentId, at: future)
  }
}
```

### manage_agent.cdc (template)

```cadence
import "Cascade"

transaction(agentPath: StoragePath, action: String, newAmount: UFix64?, newSchedule: String?) {
  prepare(signer: auth(Storage) &Account) {
    let agentRef = signer.storage.borrow<&Cascade.Agent>(from: agentPath)
      ?? panic("Agent not found")

    if action == "pause" {
      agentRef.pause()
    } else if action == "unpause" {
      agentRef.unpause()
    } else if action == "cancel" {
      agentRef.cancel()
    } else if action == "update" {
      agentRef.updatePaymentDetails(newAmount: newAmount, newSchedule: newSchedule)
    } else {
      panic("Unsupported action")
    }
  }
}
```

### Simple read script (example)

```cadence
import "Cascade"

access(all) fun main(agentId: UInt64): Cascade.AgentDetails {
  return Cascade.agentDetailsById[agentId] ?? panic("Agent not found")
}
```

---

## Notes and Considerations

- Use `FlowCallbackScheduler.estimate` before scheduling and ensure the issued capability has the entitlement `auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}`.
- The `Agent` is the callback handler; there is no separate handler resource in the current contract.
- Registration is required: all `Agent` methods assert the agent is registered in `agentDetailsById`.
- Index structs align with Agent design; organization is a String and schedule uses the `Schedule` enum.
- Verified organizations are maintained by `CascadeAdmin`; start includes `"AISPORTS"`.
- Test on emulator with `flow emulator --scheduled-callbacks` and `flow-cli >= 2.4.1`.
