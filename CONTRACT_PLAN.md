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
  - `AgentIndex` fields: `id`, `owner`, `organization`, `status`, `paymentAmount`, `paymentVaultType`, `beneficiary`, `schedule` (String), `nextPaymentTimestamp`
  - `AgentDetails` fields: `id`, `owner`, `organization`, `status` (String), `paymentAmount`, `paymentVaultType`, `beneficiary`, `schedule` (String), `nextPaymentTimestamp`
  - `AgentOwnerIndex` (owner + [ids]) and `OrganizationIndex` (organization + [ids])
- Global State (present in code):
  - `nextAgentId: UInt64`
  - `agentIndexById: {UInt64: AgentIndex}`
  - `agentsByOwner: {Address: AgentOwnerIndex}`
  - `agentsByOrganization: {String: OrganizationIndex}`

Note: The `Agent` resource stores `organization: String` and `schedule: Schedule` (enum), while index structs currently store `beneficiary: Address` and `schedule: String`. This is intentional as of now and the plan reflects the code as-is.

---

## Resource Structure (Agent)

In the current contract, `Agent` implements `FlowCallbackScheduler.CallbackHandler` and is the scheduled-callback handler itself.

Signature and fields (as in code):

```cadence
access(all) resource Agent: FlowCallbackScheduler.CallbackHandler {
  access(all) let agentId: UInt64
  access(all) var status: Status
  access(all) var paymentAmount: UFix64
  access(all) var paymentVaultType: Type
  access(all) var organization: String
  access(all) var schedule: Schedule
  access(all) var nextPaymentTimestamp: UFix64
  access(all) let flowFeeWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?
  access(all) let paymentProviderCap: Capability<&{FungibleToken.Provider}>?

  init(
    id: UInt64,
    status: Status,
    paymentAmount: UFix64,
    paymentVaultType: Type,
    organization: String,
    schedule: Schedule,
    nextPaymentTimestamp: UFix64,
    flowFeeWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?,
    paymentProviderCap: Capability<&{FungibleToken.Provider}>?
  ) { /* ... */ }

  access(FlowCallbackScheduler.Execute) fun executeCallback(id: UInt64, data: AnyStruct?) { /* ... */ }
  access(all) fun pause() { /* ... */ }
  access(all) fun unpause() { /* ... */ }
  access(all) fun cancel() { /* ... */ }
  access(all) fun updatePaymentDetails(newAmount: UFix64?, newSchedule: String?) { /* ... */ }
}
```

Notes:
- There is no separate `AgentHandler` resource. The `Agent` itself is the callback handler.
- `executeSubscription` and `scheduleNextCallback` are not used in the current design.

---

## Transaction Templates (aligned with current design)

Key differences vs the earlier plan:
- The handler capability should be issued directly to the stored `Agent` (which implements the handler interface). No separate handler storage path is needed.

### create_agent.cdc (template)

```cadence
import "Cascade"
import "FlowCallbackScheduler"
import "FlowToken"
import "FungibleToken"

transaction(
  paymentAmount: UFix64,
  paymentVaultType: Type,
  organization: String,
  schedule: Cascade.Schedule,
  firstDelaySeconds: UFix64,
  priority: UInt8,
  executionEffort: UInt64,
  callbackData: AnyStruct?,
  flowFeeWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?,
  paymentProviderCap: Capability<&{FungibleToken.Provider}>?
) {
  prepare(signer: auth(Storage, Capabilities) &Account) {
    // Save Agent to a chosen path (path helpers not present in code; pick a static path or per-id path in implementation)
    let agent <- create Cascade.Agent(
      id: Cascade.nextAgentId,
      status: Cascade.Status.Active,
      paymentAmount: paymentAmount,
      paymentVaultType: paymentVaultType,
      organization: organization,
      schedule: schedule,
      nextPaymentTimestamp: getCurrentBlock().timestamp + firstDelaySeconds,
      flowFeeWithdrawCap: flowFeeWithdrawCap,
      paymentProviderCap: paymentProviderCap
    )
    // signer.storage.save(<-agent, to: /storage/CascadeAgent_<id>) // to be defined in implementation

    let future = getCurrentBlock().timestamp + firstDelaySeconds
    let pr = priority == 0
      ? FlowCallbackScheduler.Priority.High
      : priority == 1
        ? FlowCallbackScheduler.Priority.Medium
        : FlowCallbackScheduler.Priority.Low

    let est = FlowCallbackScheduler.estimate(
      data: callbackData,
      timestamp: future,
      priority: pr,
      executionEffort: executionEffort
    )
    assert(est.timestamp != nil || pr == FlowCallbackScheduler.Priority.Low, message: est.error ?? "estimation failed")

    let vaultRef = signer.storage
      .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
      ?? panic("missing FlowToken vault")
    let fees <- vaultRef.withdraw(amount: est.flowFee ?? 0.0) as! @FlowToken.Vault

    // Issue capability to the stored Agent resource implementing CallbackHandler
    // let agentCap = signer.capabilities.storage.issue<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>(/storage/CascadeAgent_<id>)

    let receipt = FlowCallbackScheduler.schedule(
      callback: agentCap,
      data: callbackData,
      timestamp: future,
      priority: pr,
      executionEffort: executionEffort,
      fees: <-fees
    )

    log("Scheduled callback id: ".concat(receipt.id.toString()))
    emit Cascade.CallbackScheduled(id: Cascade.nextAgentId, at: future)
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
  // map from Cascade.agentIndexById to AgentDetails per your backend needs
  panic("stub")
}
```

---

## Notes and Considerations

- Use `FlowCallbackScheduler.estimate` before scheduling and ensure the issued capability has the entitlement `auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}`.
- The `Agent` is the callback handler; there is no separate handler resource in the current contract.
- Index structs currently track `beneficiary` and `schedule` as `String`; reconcile with `Agent` fields in future iterations if desired.
- Test on emulator with `flow emulator --scheduled-callbacks` and `flow-cli >= 2.4.1`.
