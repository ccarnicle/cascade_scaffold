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
  - `Schedule { Daily, Weekly, Monthly, Yearly, OneTime, TenSeconds }`
  - `Action { Send, Swap }`
- Structs:
  - `AgentDetails` fields: `id`, `owner`, `organization`, `status`, `paymentAmount`, `paymentVaultType`, `schedule` (Schedule enum), `nextPaymentTimestamp`, `action` (Action enum)
  - `AgentOwnerIndex` (owner + [ids]) and `OrganizationIndex` (organization + [ids])
- Global State (present in code):
  - `nextAgentId: UInt64`
  - `agentDetailsById: {UInt64: AgentDetails}`
  - `agentsByOwner: {Address: AgentOwnerIndex}`
  - `agentsByOrganization: {String: OrganizationIndex}`
  - `verifiedOrganizations: [String]` (initialized to empty `[]`)
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
  access(contract) var handlerCap: Capability<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>?
  access(contract) var flowWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?
  access(contract) var lastCallback: FlowCallbackScheduler.ScheduledCallback?

  init(id: UInt64) { /* ... */ }

  access(FlowCallbackScheduler.Execute) fun executeCallback(id: UInt64, data: AnyStruct?) { /* ... */ }
  access(all) fun pauseUntil(resumeTimestamp: UFix64) { /* ... */ }
  access(all) fun setActive() { /* ... */ }
  access(all) fun cancel() { /* ... */ }
  access(all) fun updatePaymentAmount(newAmount: UFix64) { /* ... */ }
  access(all) fun updateOrganization(newOrganization: String) { /* ... */ }
  access(all) fun updateSchedule(newScheduleName: String, rescheduleAt: UFix64?) { /* ... */ }
  access(all) fun updateNextPaymentTimestamp(newTimestamp: UFix64) { /* ... */ }
  access(all) fun setCapabilities(
    handlerCap: Capability<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>,
    flowWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
  ) { /* ... */ }
  access(all) fun setLastCallback(receipt: FlowCallbackScheduler.ScheduledCallback) { /* ... */ }
  access(contract) fun registerAgent(owner: Address, organization: String, paymentAmount: UFix64, paymentVaultType: Type, schedule: Schedule, nextPaymentTimestamp: UFix64) { /* ... */ }
}
```

Notes:
- There is no separate handler resource. The `Agent` is the callback handler.
- All payment/schedule/organization details are tracked in `AgentDetails` keyed by the agent id and managed in `agentDetailsById`.
- `executeCallback` auto-registers the agent on first run using the provided `AgentCronConfig`. After registration, it reads live values from `AgentDetails` (organization, paymentAmount, schedule, action).
- Action dispatch: `Action.Send` sends FLOW to the mapped organization receiver (implemented). `Action.Swap` is planned.
- Pause/cancel via status only: if `status == Canceled`, return; if `status == Paused` and `now < nextPaymentTimestamp`, return; if paused but time has passed, set `Active` and proceed.
- `pauseUntil(resumeTimestamp)` sets status to Paused, asserts timestamp is in the future, updates `nextPaymentTimestamp`, and schedules a resume callback; `cancel()` sets status Canceled.
- The agent stores the last scheduled callback receipt (`lastCallback`) to enable cancel+reschedule when updating schedule or next timestamp.

---

## Admin Resource (CascadeAdmin) and Verified Organizations

- `CascadeAdmin` is stored in the contract account at `CascadeAdminStoragePath`.
- Purpose: manage a verified organization list.
- State: `verifiedOrganizations: [String]` (string array used as a set).
- Initialized as empty `[]`.
- Methods:
  - `addVerifiedOrganization(org: String, recipient: Address)`
    - Preconditions: non-empty, <= 40 chars, not already present, and no address mapped yet
    - Appends `org` to `verifiedOrganizations` and sets `organizationAddressByName[org] = recipient`
- View helpers:
  - `getVerifiedOrganizations(): [String]`
  - `getAgentStoragePath(id: UInt64): StoragePath` → `"CascadeAgent/{id}"`
  - `getAgentPublicPath(id: UInt64): PublicPath` → `"CascadeAgent/{id}"`
  - `getAgentDetails(id: UInt64): AgentDetails?`
  - `getAgentsByOwner(owner: Address): [UInt64]?`
  - `getAgentsByOrganization(organization: String): [UInt64]?`
  - `parseSchedule(name: String): Schedule`
  - `getIntervalSeconds(schedule: Schedule): UFix64`
  - `buildCronConfigFromName(name: String, organization: String, paymentAmount: UFix64, paymentVaultType: Type, nextPaymentTimestamp: UFix64, maxExecutions: UInt64?): AgentCronConfig`

---

## Transaction Templates (aligned with current design)

Key points:
- The handler capability should be issued directly to the stored `Agent` (which implements the handler interface). No separate handler storage path is needed.
- Registration is performed automatically by `Agent.executeCallback` on the first scheduled run using the provided `AgentCronConfig`. Transactions do not call `registerAgent` directly.
- `AgentDetails.action` defaults to `Send`. Only `Send` is implemented currently.

### create_and_schedule_registration.cdc (template)

```cadence
import "Cascade"
import "FlowCallbackScheduler"
import "FlowToken"
import "FungibleToken"

transaction(
  id: UInt64,
  organization: String,
  paymentAmount: UFix64,
  scheduleName: String,
  nextPaymentTimestamp: UFix64,
  maxExecutions: UInt64?,
  priority: UInt8,
  executionEffort: UInt64
) {
  prepare(signer: auth(Storage, Capabilities) &Account) {
    // 1) Create and save Agent
    let agent <- Cascade.createAgent(
      id: id,
      paymentAmount: paymentAmount,
      paymentVaultType: Type<@FlowToken.Vault>(),
      organization: organization,
      schedule: Cascade.parseSchedule(name: scheduleName),
      nextPaymentTimestamp: nextPaymentTimestamp
    )
    let storagePath = Cascade.getAgentStoragePath(id: id)
    assert(signer.storage.borrow<&Cascade.Agent>(from: storagePath) == nil, message: "agent path occupied")
    signer.storage.save(<-agent, to: storagePath)

    // 2) Issue and set capabilities on Agent
    let agentCap = signer.capabilities.storage
      .issue<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>(storagePath)
    let flowCap = signer.capabilities.storage
      .issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(/storage/flowTokenVault)
    let agentRef = signer.storage.borrow<&Cascade.Agent>(from: storagePath) ?? panic("Agent not found")
    agentRef.setCapabilities(handlerCap: agentCap, flowWithdrawCap: flowCap)

    // 3) Build canonical cron config in-contract
    let cronConfig: Cascade.AgentCronConfig = Cascade.buildCronConfigFromName(
      name: scheduleName,
      organization: organization,
      paymentAmount: paymentAmount,
      paymentVaultType: Type<@FlowToken.Vault>(),
      nextPaymentTimestamp: nextPaymentTimestamp,
      maxExecutions: maxExecutions
    )

    // 4) Estimate and schedule first callback (next block)
    let pr = priority == 0 ? FlowCallbackScheduler.Priority.High : priority == 1 ? FlowCallbackScheduler.Priority.Medium : FlowCallbackScheduler.Priority.Low
    let firstExecutionTime: UFix64 = getCurrentBlock().timestamp + 1.0
    let est = FlowCallbackScheduler.estimate(data: cronConfig, timestamp: firstExecutionTime, priority: pr, executionEffort: executionEffort)
    assert(est.timestamp != nil || pr == FlowCallbackScheduler.Priority.Low, message: est.error ?? "estimation failed")
    let vaultRef = signer.storage.borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault) ?? panic("missing FlowToken vault")
    let fees <- vaultRef.withdraw(amount: est.flowFee ?? 0.0) as! @FlowToken.Vault
    let _receipt = FlowCallbackScheduler.schedule(callback: agentCap, data: cronConfig, timestamp: firstExecutionTime, priority: pr, executionEffort: executionEffort, fees: <-fees)
    agentRef.setLastCallback(receipt: _receipt)
  }
}
```

### Management functions (available on `Agent`)

- `updateOrganization(newOrganization: String)` – validates verified org, updates index and details
- `updatePaymentAmount(newAmount: UFix64)` – updates amount
- `setActive()` – sets status to Active
- `pauseUntil(resumeTimestamp: UFix64)` – pauses and schedules resume at the given timestamp (must be in the future)
- `cancel()` – sets status to Canceled
- `updateSchedule(newScheduleName: String, rescheduleAt: UFix64?)` – cancels current receipt (refund to owner) and reschedules with new cadence/timestamp, sets status to Active, and persists `lastCallback`. Passing the same schedule but a new `rescheduleAt` effectively updates only the next timestamp.

### Simple read script (example)

```cadence
import "Cascade"

access(all) fun main(agentId: UInt64): Cascade.AgentDetails {
  return Cascade.getAgentDetails(id: agentId) ?? panic("Agent not found")
}
```

---

## Notes and Considerations

- Use `FlowCallbackScheduler.estimate` before scheduling and ensure the issued capability has the entitlement `auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}`.
- The `Agent` is the callback handler; there is no separate handler resource.
- Intervals are computed in-contract via `buildCronConfigFromName`; the first execution is scheduled for the next block using `getCurrentBlock().timestamp + 1.0` in the transaction template.
- `TenSeconds` is provided for quick emulator testing.
- Payments withdraw from the user's FlowToken vault using the user-issued capability stored on the `Agent` and deposit to the mapped organization recipient.
- Verified organizations are maintained by `CascadeAdmin`; the list starts empty and can be populated via the admin transaction (e.g., `add_organization.cdc`).
- Test on emulator with `flow emulator --scheduled-callbacks` and `flow-cli >= 2.4.1`.
