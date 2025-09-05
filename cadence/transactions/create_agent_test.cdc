import "Cascade"
import "FlowToken"

// Creates an Agent with provided id, saves it at the per-id path,
// and immediately registers it without scheduling any callbacks.
transaction(
  id: UInt64,
  organization: String,
  paymentAmount: UFix64,
  scheduleName: String,
  nextPaymentTimestamp: UFix64
) {
  prepare(signer: auth(Storage, Capabilities) &Account) {
    let vaultType: Type = Type<@FlowToken.Vault>()
    var sched: Cascade.Schedule = Cascade.Schedule.OneTime
    if scheduleName == "daily" || scheduleName == "Daily" {
      sched = Cascade.Schedule.Daily
    } else if scheduleName == "weekly" || scheduleName == "Weekly" || scheduleName == "week" || scheduleName == "Week" {
      sched = Cascade.Schedule.Weekly
    } else if scheduleName == "monthly" || scheduleName == "Monthly" || scheduleName == "month" || scheduleName == "Month" {
      sched = Cascade.Schedule.Monthly
    } else if scheduleName == "yearly" || scheduleName == "Yearly" || scheduleName == "year" || scheduleName == "Year" {
      sched = Cascade.Schedule.Yearly
    } else if scheduleName == "onetime" || scheduleName == "OneTime" || scheduleName == "one-time" || scheduleName == "one_time" || scheduleName == "once" || scheduleName == "Once" {
      sched = Cascade.Schedule.OneTime
    } else {
      panic("Unsupported schedule name")
    }
    let agent <- Cascade.createAgent(
      id: id,
      paymentAmount: paymentAmount,
      paymentVaultType: vaultType,
      organization: organization,
      schedule: sched,
      nextPaymentTimestamp: nextPaymentTimestamp
    )

    let storagePath = Cascade.getAgentStoragePath(id: id)
    assert(signer.storage.borrow<&Cascade.Agent>(from: storagePath) == nil, message: "agent path occupied")
    signer.storage.save(<-agent, to: storagePath)

    let agentRef = signer.storage.borrow<&Cascade.Agent>(from: storagePath)
      ?? panic("Agent not found after save")

    Cascade.registerAgentWithRef(
      agent: agentRef,
      owner: signer.address,
      organization: organization,
      paymentAmount: paymentAmount,
      paymentVaultType: vaultType,
      schedule: sched,
      nextPaymentTimestamp: nextPaymentTimestamp
    )
  }
}


