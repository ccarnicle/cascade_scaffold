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

  // Data payload used to auto-register an Agent during callback execution
  access(all) struct AgentRegistrationData {
    access(all) let organization: String
    access(all) let paymentAmount: UFix64
    access(all) let paymentVaultType: Type
    access(all) let schedule: Schedule
    access(all) let nextPaymentTimestamp: UFix64

    init(
      organization: String,
      paymentAmount: UFix64,
      paymentVaultType: Type,
      schedule: Schedule,
      nextPaymentTimestamp: UFix64
    ) {
      self.organization = organization
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

  access(all) resource Agent: FlowCallbackScheduler.CallbackHandler {
    //All Agent metadata is stored in the AgentDetails struct
    access(all) let agentId: UInt64

    init(
      id: UInt64
    ) {
      self.agentId = id
    }

    access(FlowCallbackScheduler.Execute) fun executeCallback(id: UInt64, data: AnyStruct?) {
      if Cascade.agentDetailsById[self.agentId] == nil {
        if data != nil {
          let reg = data as? AgentRegistrationData
          if reg != nil {
            self.registerAgent(
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
        } else {
          panic("No data")
        }
      }
      panic("stub")
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

  access(all) view fun getAgentStoragePath(id: UInt64): StoragePath {
    return StoragePath(identifier: "CascadeAgent/".concat(id.toString()))!
  }

  access(all) view fun getAgentPublicPath(id: UInt64): PublicPath {
    return PublicPath(identifier: "CascadeAgent/".concat(id.toString()))!
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

  init() {
    self.CascadeAdminStoragePath = /storage/CascadeAdmin
    self.CascadeAgentStoragePath = /storage/CascadeAgent
    self.CascadeAgentPublicPath = /public/CascadeAgent
    self.nextAgentId = 1
    self.agentDetailsById = {}
    self.agentsByOwner = {}
    self.agentsByOrganization = {}
    self.verifiedOrganizations = ["AISPORTS"]
    self.organizationAddressByName = {}

    // Save admin resource to contract account and publish capability
    self.account.storage.save(<-create CascadeAdmin(), to: self.CascadeAdminStoragePath)
  }
}