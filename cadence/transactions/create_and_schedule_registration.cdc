import "Cascade"
import "FlowCallbackScheduler"
import "FlowToken"
import "FungibleToken"

// Creates an Agent, saves it, issues/stores capabilities, and schedules the first cron callback.
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
    // Resolve schedule from string
    var sched: Cascade.Schedule = Cascade.Schedule.OneTime
    if scheduleName == "daily" || scheduleName == "Daily" {
      sched = Cascade.Schedule.Daily
    } else if scheduleName == "weekly" || scheduleName == "Weekly" || scheduleName == "week" || scheduleName == "Week" {
      sched = Cascade.Schedule.Weekly
    } else if scheduleName == "monthly" || scheduleName == "Monthly" || scheduleName == "month" || scheduleName == "Month" {
      sched = Cascade.Schedule.Monthly
    } else if scheduleName == "yearly" || scheduleName == "Yearly" || scheduleName == "year" || scheduleName == "Year" {
      sched = Cascade.Schedule.Yearly
    } else if scheduleName == "10s" || scheduleName == "TenSeconds" {
      sched = Cascade.Schedule.TenSeconds
    } else if scheduleName == "pause" || scheduleName == "Pause" {
      sched = Cascade.Schedule.OneTime
    } else if scheduleName == "cancel" || scheduleName == "Cancel" {
      sched = Cascade.Schedule.OneTime
    } else if scheduleName == "onetime" || scheduleName == "OneTime" || scheduleName == "one-time" || scheduleName == "one_time" || scheduleName == "once" || scheduleName == "Once" {
      sched = Cascade.Schedule.OneTime
    } else {
      panic("Unsupported schedule name")
    }

    // Create and save the Agent
    let vaultType: Type = Type<@FlowToken.Vault>()
    let agent <- Cascade.createAgent(
      id: id,
      paymentAmount: paymentAmount,
      paymentVaultType: vaultType,
      organization: organization,
      schedule: sched,
      nextPaymentTimestamp: nextPaymentTimestamp
    )

    // Save the Agent at its per-id path
    let storagePath = Cascade.getAgentStoragePath(id: id)
    assert(signer.storage.borrow<&Cascade.Agent>(from: storagePath) == nil, message: "agent path occupied")
    signer.storage.save(<-agent, to: storagePath)

    // Issue capabilities and store them on the Agent
    let agentCap = signer.capabilities.storage
      .issue<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>(storagePath)
    let flowCap = signer.capabilities.storage
      .issue<auth(FungibleToken.Withdraw) &FlowToken.Vault>(/storage/flowTokenVault)

    let agentRef = signer.storage.borrow<&Cascade.Agent>(from: storagePath)
      ?? panic("agent not found after save")
    agentRef.setCapabilities(handlerCap: agentCap, flowWithdrawCap: flowCap)

    // Build cron configuration payload in-contract (standardized intervals)
    let cronConfig = Cascade.buildCronConfigFromName(
      name: scheduleName,
      organization: organization,
      paymentAmount: paymentAmount,
      paymentVaultType: vaultType,
      nextPaymentTimestamp: nextPaymentTimestamp,
      maxExecutions: maxExecutions
    )

    // Compute first execution time using config helper
    let firstExecutionTime = cronConfig.getNextExecutionTime()

    // Priority mapping
    let pr = priority == 0
      ? FlowCallbackScheduler.Priority.High
      : priority == 1
        ? FlowCallbackScheduler.Priority.Medium
        : FlowCallbackScheduler.Priority.Low

    // Estimate fees
    let est = FlowCallbackScheduler.estimate(
      data: cronConfig,
      timestamp: firstExecutionTime,
      priority: pr,
      executionEffort: executionEffort
    )

    assert(
      est.timestamp != nil || pr == FlowCallbackScheduler.Priority.Low,
      message: est.error ?? "estimation failed"
    )

    // Withdraw fees from FlowToken Vault
    let vaultRef = signer.storage
      .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
      ?? panic("missing FlowToken vault")
    let fees <- vaultRef.withdraw(amount: est.flowFee ?? 0.0) as! @FlowToken.Vault

    // Schedule the first callback using the handler capability
    let _receipt = FlowCallbackScheduler.schedule(
      callback: agentCap,
      data: cronConfig,
      timestamp: firstExecutionTime,
      priority: pr,
      executionEffort: executionEffort,
      fees: <-fees
    )
  }
}


