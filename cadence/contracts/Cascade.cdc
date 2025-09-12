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

  // Agent action type: determines what work the agent does on execution
  access(all) enum Action: UInt8 {
    access(all) case Send
    access(all) case Swap
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
    access(all) var action: Action

    init(
      id: UInt64,
      owner: Address,
      organization: String,
      status: Status,
      paymentAmount: UFix64,
      paymentVaultType: Type,
      schedule: Schedule,
      nextPaymentTimestamp: UFix64,
      action: Action
    ) {
      self.id = id
      self.owner = owner
      self.organization = organization
      self.status = status
      self.paymentAmount = paymentAmount
      self.paymentVaultType = paymentVaultType
      self.schedule = schedule
      self.nextPaymentTimestamp = nextPaymentTimestamp
      self.action = action
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
    access(all) let name: String
    access(all) let description: String
    access(contract) var handlerCap: Capability<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>?
    access(contract) var flowWithdrawCap: Capability<auth(FungibleToken.Withdraw) &FlowToken.Vault>?
    access(contract) var lastCallback: @FlowCallbackScheduler.ScheduledCallback?

    init(
      name: String,
      description: String
    ) {
      let newId: UInt64 = Cascade.nextAgentId
      self.agentId = newId
      Cascade.nextAgentId = newId + 1
      self.handlerCap = nil
      self.flowWithdrawCap = nil
      self.lastCallback <- nil
      self.name = name
      self.description = description
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
            self.registerAgent( //register agent - Agent is set to "active" upon registration
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
        // Parse cron data for timing/registration only
        let cronConfig = data as! AgentCronConfig? ?? panic("AgentCronConfig data is required")
        
        // If the agent is paused and not yet at the resume time, skip execution
        let currentDetails = Cascade.agentDetailsById[self.agentId] ?? panic("Agent not registered")
        if currentDetails.status == Status.Canceled {
          return
        }
        if currentDetails.status == Status.Paused {
          let now = getCurrentBlock().timestamp
          if now < currentDetails.nextPaymentTimestamp {
            return
          }
          Cascade.setAgentStatus(id: self.agentId, status: Status.Active)
        }

        // Dispatch by action
        if currentDetails.action == Action.Send {  //this deposits the funds from the user's account to the organization's account - we will change this to swapping for in the future

          let recipientAddress = Cascade.organizationAddressByName[currentDetails.organization]
            ?? panic("unknown organization recipient")
          let payWithdrawCap = self.flowWithdrawCap ?? panic("flow withdraw capability not set on agent")
          let userVaultRef = payWithdrawCap.borrow() ?? panic("invalid flow withdraw capability")

          assert(userVaultRef.getType() == currentDetails.paymentVaultType, message: "payment vault type mismatch")

          let payment <- userVaultRef.withdraw(amount: currentDetails.paymentAmount) as! @FlowToken.Vault
          let recipientAccount = getAccount(recipientAddress)
          let receiverRef = recipientAccount.capabilities
            .borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
            ?? panic("recipient missing FlowToken receiver")
          receiverRef.deposit(from: <-payment)
        } else if currentDetails.action == Action.Swap {
          panic("Swap action not implemented yet")
        }


        //schedule the next callback
        let updatedConfig = cronConfig.withIncrementedCount()

        // Check if we should continue scheduling
        if !updatedConfig.shouldContinue() {
            log("Counter cron job completed after ".concat(updatedConfig.executionCount.toString()).concat(" executions"))
            return
        }

        // Calculate the next precise execution time using current schedule
        let intervalSeconds = Cascade.getIntervalSeconds(schedule: currentDetails.schedule)
        let nowTs = getCurrentBlock().timestamp
        var nextExecutionTime: UFix64 = nowTs + 1.0
        if intervalSeconds > 0.0 {
          // align based on last recorded nextPaymentTimestamp if in the future, else now
          let base = currentDetails.nextPaymentTimestamp > nowTs ? currentDetails.nextPaymentTimestamp : nowTs
          nextExecutionTime = UFix64(UInt64(base + intervalSeconds))
        }

        // Persist next execution and active status using currentDetails snapshot
        Cascade.agentDetailsById[self.agentId] = AgentDetails(
          id: currentDetails.id,
          owner: currentDetails.owner,
          organization: currentDetails.organization,
          status: Status.Active,
          paymentAmount: currentDetails.paymentAmount,
          paymentVaultType: currentDetails.paymentVaultType,
          schedule: currentDetails.schedule,
          nextPaymentTimestamp: nextExecutionTime,
          action: currentDetails.action
        )

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
        let receipt <- FlowCallbackScheduler.schedule(
            callback: handlerCap,
            data: updatedConfig,
            timestamp: nextExecutionTime,
            priority: priority,
            executionEffort: executionEffort,
            fees: <-fees
        )

        emit CallbackScheduled(id: self.agentId, at: receipt.timestamp)
        self.lastCallback <-! receipt
      } else {
        panic("No data provided")
      }
    }

    access(all) fun pauseUntil(resumeTimestamp: UFix64) {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      let existing = Cascade.agentDetailsById[self.agentId] ?? panic("Agent not registered")
      let now = getCurrentBlock().timestamp
      let resumeAt: UFix64 = resumeTimestamp
      assert(resumeAt > now, message: "resume timestamp must be in the future")

      // Update registry to paused and record resume time
      Cascade.agentDetailsById[self.agentId] = AgentDetails(
        id: existing.id,
        owner: existing.owner,
        organization: existing.organization,
        status: Status.Paused,
        paymentAmount: existing.paymentAmount,
        paymentVaultType: existing.paymentVaultType,
        schedule: existing.schedule,
        nextPaymentTimestamp: resumeAt,
        action: existing.action
      )
      emit AgentStatusChanged(id: self.agentId, status: Status.Paused.rawValue)

      // Build a config for resuming normal execution
      let interval = Cascade.getIntervalSeconds(schedule: existing.schedule)
      let resumeConfig = AgentCronConfig(
        intervalSeconds: interval,
        baseTimestamp: now,
        maxExecutions: nil,
        executionCount: 0,
        action: nil,
        organization: existing.organization,
        paymentAmount: existing.paymentAmount,
        paymentVaultType: existing.paymentVaultType,
        schedule: existing.schedule,
        nextPaymentTimestamp: resumeAt
      )

      let priority = FlowCallbackScheduler.Priority.Medium
      let executionEffort: UInt64 = 1000
      let estimate = FlowCallbackScheduler.estimate(
        data: resumeConfig,
        timestamp: resumeAt,
        priority: priority,
        executionEffort: executionEffort
      )
      assert(
        estimate.timestamp != nil || priority == FlowCallbackScheduler.Priority.Low,
        message: estimate.error ?? "estimation failed"
      )

      let withdrawCap = self.flowWithdrawCap ?? panic("flow withdraw capability not set on agent")
      let vaultRef = withdrawCap.borrow() ?? panic("invalid flow withdraw capability")
      let fees <- vaultRef.withdraw(amount: estimate.flowFee ?? 0.0) as! @FlowToken.Vault

      let handlerCap = self.handlerCap ?? panic("handler capability not set on agent")
      let receipt <- FlowCallbackScheduler.schedule(
        callback: handlerCap,
        data: resumeConfig,
        timestamp: resumeAt,
        priority: priority,
        executionEffort: executionEffort,
        fees: <-fees
      )
      emit CallbackScheduled(id: self.agentId, at: receipt.timestamp)
      self.lastCallback <-! receipt

    }

    access(all) fun cancel() {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      let existing = Cascade.agentDetailsById[self.agentId] ?? panic("Agent not registered")
      Cascade.agentDetailsById[self.agentId] = AgentDetails(
        id: existing.id,
        owner: existing.owner,
        organization: existing.organization,
        status: Status.Canceled,
        paymentAmount: existing.paymentAmount,
        paymentVaultType: existing.paymentVaultType,
        schedule: existing.schedule,
        nextPaymentTimestamp: 0.0,
        action: existing.action
      )
      emit AgentStatusChanged(id: self.agentId, status: Status.Canceled.rawValue)
    }

    access(all) fun updatePaymentAmount(newAmount: UFix64) {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      let existing = Cascade.agentDetailsById[self.agentId] ?? panic("Agent not registered")
      Cascade.agentDetailsById[self.agentId] = AgentDetails(
        id: existing.id,
        owner: existing.owner,
        organization: existing.organization,
        status: existing.status,
        paymentAmount: newAmount,
        paymentVaultType: existing.paymentVaultType,
        schedule: existing.schedule,
        nextPaymentTimestamp: existing.nextPaymentTimestamp,
        action: existing.action
      )
      emit AgentUpdated(id: self.agentId)
    }

    access(all) fun updateOrganization(newOrganization: String) {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      // Ensure the organization is verified and has a recipient address
      assert(Cascade.verifiedOrganizations.contains(newOrganization), message: "organization not verified")
      assert(Cascade.organizationAddressByName[newOrganization] != nil, message: "organization recipient not set")

      let existing = Cascade.agentDetailsById[self.agentId] ?? panic("Agent not registered")

      // Update organization index
      let oldOrg = existing.organization
      if Cascade.agentsByOrganization[oldOrg] != nil {
        let idx = Cascade.agentsByOrganization[oldOrg]!.agentIds
        var filtered: [UInt64] = []
        for v in idx {
          if v != self.agentId {
            filtered.append(v)
          }
        }
        Cascade.agentsByOrganization[oldOrg] = OrganizationIndex(organization: oldOrg, agentIds: filtered)
      }
      if Cascade.agentsByOrganization[newOrganization] == nil {
        Cascade.agentsByOrganization[newOrganization] = OrganizationIndex(organization: newOrganization, agentIds: [])
      }
      Cascade.agentsByOrganization[newOrganization]!.agentIds.append(self.agentId)

      // Persist update
      Cascade.agentDetailsById[self.agentId] = AgentDetails(
        id: existing.id,
        owner: existing.owner,
        organization: newOrganization,
        status: existing.status,
        paymentAmount: existing.paymentAmount,
        paymentVaultType: existing.paymentVaultType,
        schedule: existing.schedule,
        nextPaymentTimestamp: existing.nextPaymentTimestamp,
        action: existing.action
      )
      emit AgentUpdated(id: self.agentId)
    }

    access(all) fun setLastCallback(receipt: @FlowCallbackScheduler.ScheduledCallback) {
      self.lastCallback <-! receipt
    }

    access(all) fun setActive() {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      let existing = Cascade.agentDetailsById[self.agentId] ?? panic("Agent not registered")
      Cascade.agentDetailsById[self.agentId] = AgentDetails(
        id: existing.id,
        owner: existing.owner,
        organization: existing.organization,
        status: Status.Active,
        paymentAmount: existing.paymentAmount,
        paymentVaultType: existing.paymentVaultType,
        schedule: existing.schedule,
        nextPaymentTimestamp: existing.nextPaymentTimestamp,
        action: existing.action
      )
      emit AgentStatusChanged(id: self.agentId, status: Status.Active.rawValue)
    }

    access(all) fun updateSchedule(newScheduleName: String, rescheduleAt: UFix64?) {
      pre {
        Cascade.agentDetailsById[self.agentId] != nil: "Agent not registered"
      }
      let existing = Cascade.agentDetailsById[self.agentId] ?? panic("Agent not registered")

      // Cancel pending callback if exists and refund
      if self.lastCallback != nil {
        let callback <- self.lastCallback <-! nil
        let refund <- FlowCallbackScheduler.cancel(callback: <-callback!)
        // deposit refund back to owner
        let ownerAcct = getAccount(existing.owner)
        let ownerReceiver = ownerAcct.capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
          ?? panic("owner missing FlowToken receiver")
        ownerReceiver.deposit(from: <-refund)
      }

      let newSchedule = Cascade.parseSchedule(name: newScheduleName)
      let nowTs = getCurrentBlock().timestamp
      let resumeAt = rescheduleAt != nil ? rescheduleAt! : (existing.nextPaymentTimestamp > nowTs ? existing.nextPaymentTimestamp : nowTs + 1.0)

      // Persist schedule change and new next timestamp
      Cascade.agentDetailsById[self.agentId] = AgentDetails(
        id: existing.id,
        owner: existing.owner,
        organization: existing.organization,
        status: Status.Active,
        paymentAmount: existing.paymentAmount,
        paymentVaultType: existing.paymentVaultType,
        schedule: newSchedule,
        nextPaymentTimestamp: resumeAt,
        action: existing.action
      )

      // Build new cron config and schedule
      let cronConfig = AgentCronConfig(
        intervalSeconds: Cascade.getIntervalSeconds(schedule: newSchedule),
        baseTimestamp: nowTs,
        maxExecutions: nil,
        executionCount: 0,
        action: nil,
        organization: existing.organization,
        paymentAmount: existing.paymentAmount,
        paymentVaultType: existing.paymentVaultType,
        schedule: newSchedule,
        nextPaymentTimestamp: resumeAt
      )

      let priority = FlowCallbackScheduler.Priority.Medium
      let executionEffort: UInt64 = 1000
      let estimate = FlowCallbackScheduler.estimate(
        data: cronConfig,
        timestamp: resumeAt,
        priority: priority,
        executionEffort: executionEffort
      )
      assert(estimate.timestamp != nil || priority == FlowCallbackScheduler.Priority.Low, message: estimate.error ?? "estimation failed")

      let withdrawCap = self.flowWithdrawCap ?? panic("flow withdraw capability not set on agent")
      let vaultRef = withdrawCap.borrow() ?? panic("invalid flow withdraw capability")
      let fees <- vaultRef.withdraw(amount: estimate.flowFee ?? 0.0) as! @FlowToken.Vault

      let handlerCap = self.handlerCap ?? panic("handler capability not set on agent")
      let receipt <- FlowCallbackScheduler.schedule(
        callback: handlerCap,
        data: cronConfig,
        timestamp: resumeAt,
        priority: priority,
        executionEffort: executionEffort,
        fees: <-fees
      )
      emit CallbackScheduled(id: self.agentId, at: receipt.timestamp)
      self.lastCallback <-! receipt
      emit AgentUpdated(id: self.agentId)
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
        status: Status.Active, // agent starts Active upon registration (contract-controlled)
        paymentAmount: paymentAmount,
        paymentVaultType: paymentVaultType,
        schedule: schedule,
        nextPaymentTimestamp: nextPaymentTimestamp,
        action: Action.Send
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

  access(all) fun createAgent(): @Agent {
    let id = Cascade.nextAgentId
    let name = "cascade_".concat(id.toString())
    return <-create Agent(name: name, description: "Flow Agent automation handler")
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
      nextPaymentTimestamp: existing.nextPaymentTimestamp,
      action: existing.action
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
    return AgentCronConfig(
      intervalSeconds: interval,
      baseTimestamp: now,
      maxExecutions: maxExecutions,
      executionCount: 0,
      action: nil,
      organization: organization,
      paymentAmount: paymentAmount,
      paymentVaultType: paymentVaultType,
      schedule: sched,
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