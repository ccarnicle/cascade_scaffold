import "FlowCallbackScheduler"
import "FlowToken"
import "FungibleToken"

access(all) contract Cascade {

  access(all) event AgentCreated(id: UInt64, owner: Address)
  access(all) event AgentStatusChanged(id: UInt64, status: UInt8)
  access(all) event AgentUpdated(id: UInt64)
  access(all) event CallbackScheduled(id: UInt64, at: UFix64)

  access(all) enum Status: UInt8 {
    access(all) case Active
    access(all) case Paused
    access(all) case Canceled
  }

  access(all) enum Schedule: UInt8 {
    access(all) case Daily
    access(all) case Weekly
    access(all) case Monthly
    access(all) case Yearly
    access(all) case OneTime
    access(all) case TenSeconds
  }

  access(all) struct AgentDetails {
    access(all) let id: UInt64
    access(all) let owner: Address
    access(all) let organization: String
    access(all) var status: Status
    access(all) var paymentAmount: UFix64
    access(all) var paymentVaultType: Type
    access(all) var schedule: Schedule
    access(all) var nextPaymentTimestamp: UFix64

    init(
      id: UInt64,
      owner: Address,
      organization: String,
      status: Status,
      paymentAmount: UFix64,
      paymentVaultType: Type,
      schedule: Schedule,
      nextPaymentTimestamp: UFix64
    ) {
      self.id = id
      self.owner = owner
      self.organization = organization
      self.status = status
      self.paymentAmount = paymentAmount
      self.paymentVaultType = paymentVaultType
      self.schedule = schedule
      self.nextPaymentTimestamp = nextPaymentTimestamp
    }
  }

  access(all) struct AgentOwnerIndex {
    access(all) let owner: Address
    access(all) var agentIds: [UInt64]

    init(owner: Address, agentIds: [UInt64]) {
      self.owner = owner
      self.agentIds = agentIds
    }
  }

  access(all) struct OrganizationIndex {
    access(all) let organization: String
    access(all) var agentIds: [UInt64]

    init(organization: String, agentIds: [UInt64]) {
      self.organization = organization
      self.agentIds = agentIds
    }
  }

  access(all) let CascadeAdminStoragePath: StoragePath
  access(all) let CascadeAgentStoragePath: StoragePath
  access(all) let CascadeAgentPublicPath: PublicPath

  access(contract) var nextAgentId: UInt64
  access(contract) let agentDetailsById: {UInt64: AgentDetails} //source of truth for all agents
  access(contract) let agentsByOwner: {Address: AgentOwnerIndex} //index of agents by owner
  access(contract) let agentsByOrganization: {String: OrganizationIndex} //index of agents by organization
  access(contract) var verifiedOrganizations: [String]
  access(contract) var organizationAddressByName: {String: Address}

  /// Struct to hold cron configuration data (immutable for callback serialization) - to do: schedule chron timing in the contract (eg: daily), instead of passing it in, then we can get rid of redundant timing data
  access(all) struct AgentCronConfig {
      access(all) let intervalSeconds: UFix64
      access(all) let baseTimestamp: UFix64
      access(all) let maxExecutions: UInt64?
      access(all) let executionCount: UInt64
      access(all) let action: String?
      //all fields below are imported from old struct: AgentRegistrationData
      access(all) let organization: String
      access(all) let paymentAmount: UFix64
      access(all) let paymentVaultType: Type
      access(all) let schedule: Schedule
      access(all) let nextPaymentTimestamp: UFix64

      init(
        intervalSeconds: UFix64, 
        baseTimestamp: UFix64, 
        maxExecutions: UInt64?, 
        executionCount: UInt64,
        action: String?,
        organization: String,
        paymentAmount: UFix64,
        paymentVaultType: Type,
        schedule: Schedule,
        nextPaymentTimestamp: UFix64) {
          self.intervalSeconds = intervalSeconds
          self.baseTimestamp = baseTimestamp
          self.maxExecutions = maxExecutions
          self.executionCount = executionCount
          self.action = action
          self.organization = organization
          self.paymentAmount = paymentAmount
          self.paymentVaultType = paymentVaultType
          self.schedule = schedule
          self.nextPaymentTimestamp = nextPaymentTimestamp
        }

      access(all) fun withIncrementedCount(): AgentCronConfig {
          return AgentCronConfig(
              intervalSeconds: self.intervalSeconds,
              baseTimestamp: self.baseTimestamp,
              maxExecutions: self.maxExecutions,
              executionCount: self.executionCount + 1,
              action: self.action,
              organization: self.organization,
              paymentAmount: self.paymentAmount,
              paymentVaultType: self.paymentVaultType,
              schedule: self.schedule,
              nextPaymentTimestamp: self.nextPaymentTimestamp
          )
      }

      access(all) fun shouldContinue(): Bool {
          if let max = self.maxExecutions {
              return self.executionCount < max
          }
          return true
      }

      access(all) fun getNextExecutionTime(): UFix64 {
          let currentTime = getCurrentBlock().timestamp
          if self.intervalSeconds <= 0.0 {
              return currentTime + 1.0
          }
          
          // If baseTimestamp is in the future, use it as the first execution time
          if self.baseTimestamp > currentTime {
              return self.baseTimestamp
          }
          
          // Calculate next execution time based on elapsed intervals
          let elapsed = currentTime - self.baseTimestamp
          let intervals = UFix64(UInt64(elapsed / self.intervalSeconds)) + 1.0
          return self.baseTimestamp + (intervals * self.intervalSeconds)
      }
  }

  access(all) resource Agent: FlowCallbackScheduler.CallbackHandler {
    //All Agent metadata is stored in the AgentDetails struct
    access(all) let agentId: UInt64
    access(contract) var handlerCap: Capability<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>?
    access(contract) var flowWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?

    init(
      id: UInt64
    ) {
      self.agentId = id
      self.handlerCap = nil
      self.flowWithdrawCap = nil
    }

    access(all) fun setCapabilities(
      handlerCap: Capability<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>,
      flowWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>
    ) {
      self.handlerCap = handlerCap
      self.flowWithdrawCap = flowWithdrawCap
    }

    access(FlowCallbackScheduler.Execute) fun executeCallback(id: UInt64, data: AnyStruct?) {
      
      if data != nil {
        if Cascade.agentDetailsById[self.agentId] == nil { //if the agent is not registered, register it
          let reg = data as? AgentCronConfig //get the registration data
          if reg != nil {
            self.registerAgent( //register the agent
              owner: self.owner?.address ?? panic("Owner not found"),
              organization: reg!.organization,
              paymentAmount: reg!.paymentAmount,
              paymentVaultType: reg!.paymentVaultType,
              schedule: reg!.schedule,
              nextPaymentTimestamp: reg!.nextPaymentTimestamp
            )
          } else {
            panic("Invalid data")
          }
        }
        // Handle action-only callbacks (pause/cancel)
        let cronConfig = data as! AgentCronConfig? ?? panic("CounterCronConfig data is required")
        if cronConfig.action != nil {
            let a = cronConfig.action!
            if a == "pause" {
                //DO PAUSE ACTION LOGIC HERE
                self.pause()
                return
            } else if a == "cancel" {
                //DO CANCEL ACTION LOGIC HERE
                self.cancel()
                return
            }
        }

        // Take funds from the user's account and send to beneficiary (organization recipient)
        let recipientAddress = Cascade.organizationAddressByName[cronConfig.organization]
          ?? panic("unknown organization recipient")
        let payWithdrawCap = self.flowWithdrawCap ?? panic("flow withdraw capability not set on agent")
        let userVaultRef = payWithdrawCap.borrow() ?? panic("invalid flow withdraw capability")
        assert(userVaultRef.getType() == cronConfig.paymentVaultType, message: "payment vault type mismatch")

        let payment <- userVaultRef.withdraw(amount: cronConfig.paymentAmount) as! @FlowToken.Vault
        let recipientAccount = getAccount(recipientAddress)
        let receiverRef = recipientAccount.capabilities
          .borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
          ?? panic("recipient missing FlowToken receiver")
        receiverRef.deposit(from: <-payment)

        //schedule the callback
        //1. Extract cron configuration from callback data
        let updatedConfig = cronConfig.withIncrementedCount()

        // Check if we should continue scheduling
        if !updatedConfig.shouldContinue() {
            log("Counter cron job completed after ".concat(updatedConfig.executionCount.toString()).concat(" executions"))
            return
        }

        // Calculate the next precise execution time
        let nextExecutionTime = cronConfig.getNextExecutionTime()
        let priority = FlowCallbackScheduler.Priority.Medium
        let executionEffort: UInt64 = 1000

        let estimate = FlowCallbackScheduler.estimate(
            data: updatedConfig,
            timestamp: nextExecutionTime,
            priority: priority,
            executionEffort: executionEffort
        )

        assert(
            estimate.timestamp != nil || priority == FlowCallbackScheduler.Priority.Low,
            message: estimate.error ?? "estimation failed"
        )

        // Borrow FLOW withdraw capability from the user's account and withdraw fees
        let withdrawCap = self.flowWithdrawCap ?? panic("flow withdraw capability not set on agent")
        let vaultRef = withdrawCap.borrow() ?? panic("invalid flow withdraw capability")
        let fees <- vaultRef.withdraw(amount: estimate.flowFee ?? 0.0) as! @FlowToken.Vault

        // Use stored handler capability to schedule the next callback
        let handlerCap = self.handlerCap ?? panic("handler capability not set on agent")
        let receipt = FlowCallbackScheduler.schedule(
            callback: handlerCap,
            data: updatedConfig,
            timestamp: nextExecutionTime,
            priority: priority,
            executionEffort: executionEffort,
            fees: <-fees
        )

        emit CallbackScheduled(id: self.agentId, at: receipt.timestamp)
      } else {
        panic("No data provided")
      }
    }

    access(all) fun pause() {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      Cascade.setAgentStatus(id: self.agentId, status: Status.Paused)
    }

    access(all) fun unpause() {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      Cascade.setAgentStatus(id: self.agentId, status: Status.Active)
    }

    access(all) fun cancel() {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      Cascade.setAgentStatus(id: self.agentId, status: Status.Canceled)
    }

    access(all) fun updatePaymentDetails(newAmount: UFix64?, newSchedule: String?) {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      panic("stub")
    }

    access(contract) fun registerAgent(
      owner: Address,
      organization: String,
      paymentAmount: UFix64,
      paymentVaultType: Type,
      schedule: Schedule,
      nextPaymentTimestamp: UFix64
    ) {
      pre {
        Cascade.agentDetailsById[self.agentId] == nil: "Agent already registered"
      }

      Cascade.agentDetailsById[self.agentId] = AgentDetails(
        id: self.agentId,
        owner: owner,
        organization: organization,
        status: Status.Active,
        paymentAmount: paymentAmount,
        paymentVaultType: paymentVaultType,
        schedule: schedule,
        nextPaymentTimestamp: nextPaymentTimestamp
      )

      if Cascade.agentsByOwner[owner] == nil {
        Cascade.agentsByOwner[owner] = AgentOwnerIndex(owner: owner, agentIds: [])
      }

      Cascade.agentsByOwner[owner]!.agentIds.append(self.agentId)

      if Cascade.agentsByOrganization[organization] == nil {
        Cascade.agentsByOrganization[organization] = OrganizationIndex(organization: organization, agentIds: [])
      }

      Cascade.agentsByOrganization[organization]!.agentIds.append(self.agentId)

      emit AgentCreated(id: self.agentId, owner: owner)

      Cascade.nextAgentId = self.agentId + 1
    }
  }

  access(all) resource CascadeAdmin {
    access(all) fun addVerifiedOrganization(org: String, recipient: Address) {
      pre {
        org.length > 0: "organization cannot be empty"
        org.length <= 40: "organization too long"
        Cascade.verifiedOrganizations.contains(org) == false: "organization already verified"
        Cascade.organizationAddressByName[org] == nil: "organization address already set"
      }
      Cascade.verifiedOrganizations.append(org)
      Cascade.organizationAddressByName[org] = recipient
    }
  }

  access(all) fun createAgent(
    id: UInt64,
    paymentAmount: UFix64,
    paymentVaultType: Type,
    organization: String,
    schedule: Schedule,
    nextPaymentTimestamp: UFix64
  ): @Agent {
    return <-create Agent(id: id)
  }

  access(contract) fun setAgentStatus(id: UInt64, status: Status) {
    let existing = Cascade.agentDetailsById[id] ?? panic("Agent not found")
    Cascade.agentDetailsById[id] = AgentDetails(
      id: existing.id,
      owner: existing.owner,
      organization: existing.organization,
      status: status,
      paymentAmount: existing.paymentAmount,
      paymentVaultType: existing.paymentVaultType,
      schedule: existing.schedule,
      nextPaymentTimestamp: existing.nextPaymentTimestamp
    )
    emit AgentStatusChanged(id: id, status: status.rawValue)
  }

  access(all) view fun getAgentStoragePath(id: UInt64): StoragePath {
    return StoragePath(identifier: "CascadeAgent/".concat(id.toString()))!
  }

  access(all) view fun getAgentPublicPath(id: UInt64): PublicPath {
    return PublicPath(identifier: "CascadeAgent/".concat(id.toString()))!
  }

  access(all) view fun getAgentDetails(id: UInt64): AgentDetails? {
    return Cascade.agentDetailsById[id]
  }

  access(all) view fun getAgentsByOwner(owner: Address): [UInt64]? {
    return Cascade.agentsByOwner[owner]?.agentIds
  }

  access(all) view fun getAgentsByOrganization(organization: String): [UInt64]? {
    return Cascade.agentsByOrganization[organization]?.agentIds
  }

  access(all) view fun getVerifiedOrganizations(): [String] {
    return Cascade.verifiedOrganizations
  }

  // Helper: parse human-friendly schedule name to enum
  access(all) view fun parseSchedule(name: String): Schedule {
    if name == "daily" || name == "Daily" { return Schedule.Daily }
    if name == "weekly" || name == "Weekly" || name == "week" || name == "Week" { return Schedule.Weekly }
    if name == "monthly" || name == "Monthly" || name == "month" || name == "Month" { return Schedule.Monthly }
    if name == "yearly" || name == "Yearly" || name == "year" || name == "Year" { return Schedule.Yearly }
    if name == "10s" || name == "TenSeconds" { return Schedule.TenSeconds }
    return Schedule.OneTime
  }

  // Helper: map schedule to standard interval seconds
  access(all) view fun getIntervalSeconds(schedule: Schedule): UFix64 {
    if schedule == Schedule.Daily { return 86400.0 }
    if schedule == Schedule.Weekly { return 604800.0 }
    if schedule == Schedule.Monthly { return 2592000.0 }
    if schedule == Schedule.Yearly { return 31536000.0 }
    if schedule == Schedule.TenSeconds { return 10.0 }
    return 0.0 // OneTime or unsupported
  }

  // Build a canonical cron config from a schedule name and details
  access(all) fun buildCronConfigFromName(
    name: String,
    organization: String,
    paymentAmount: UFix64,
    paymentVaultType: Type,
    nextPaymentTimestamp: UFix64,
    maxExecutions: UInt64?
  ): AgentCronConfig {
    let sched = Cascade.parseSchedule(name: name)
    let interval = Cascade.getIntervalSeconds(schedule: sched)
    let now = getCurrentBlock().timestamp
    var action: String? = nil
    if name == "pause" || name == "Pause" { action = "pause" }
    if name == "cancel" || name == "Cancel" { action = "cancel" }
    return AgentCronConfig(
      intervalSeconds: interval,
      baseTimestamp: now,
      maxExecutions: maxExecutions,
      executionCount: 0,
      action: action,
      organization: organization,
      paymentAmount: paymentAmount,
      paymentVaultType: paymentVaultType,
      schedule: sched,
      nextPaymentTimestamp: nextPaymentTimestamp
    )
  }

  //REMOVE FOR PRODUCTION
  access(all) fun registerAgentWithRef(
    agent: &Cascade.Agent,
    owner: Address,
    organization: String,
    paymentAmount: UFix64,
    paymentVaultType: Type,
    schedule: Schedule,
    nextPaymentTimestamp: UFix64
  ) {
    agent.registerAgent(
      owner: owner,
      organization: organization,
      paymentAmount: paymentAmount,
      paymentVaultType: paymentVaultType,
      schedule: schedule,
      nextPaymentTimestamp: nextPaymentTimestamp
    )
  }

  init() {
    self.CascadeAdminStoragePath = /storage/CascadeAdmin
    self.CascadeAgentStoragePath = /storage/CascadeAgent
    self.CascadeAgentPublicPath = /public/CascadeAgent
    self.nextAgentId = 1
    self.agentDetailsById = {}
    self.agentsByOwner = {}
    self.agentsByOrganization = {}
    self.verifiedOrganizations = []
    self.organizationAddressByName = {}

    // Save admin resource to contract account and publish capability
    self.account.storage.save(<-create CascadeAdmin(), to: self.CascadeAdminStoragePath)
  }
}