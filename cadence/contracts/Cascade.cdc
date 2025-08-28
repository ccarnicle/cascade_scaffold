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

  access(all) struct AgentIndex {
    access(all) let id: UInt64
    access(all) let owner: Address
    access(all) let organization: String
    access(all) var status: Status
    access(all) var paymentAmount: UFix64
    access(all) var paymentVaultType: Type
    access(all) var beneficiary: Address
    access(all) var schedule: String
    access(all) var nextPaymentTimestamp: UFix64

    init(
      id: UInt64,
      owner: Address,
      organization: String,
      status: Status,
      paymentAmount: UFix64,
      paymentVaultType: Type,
      beneficiary: Address,
      schedule: String,
      nextPaymentTimestamp: UFix64
    ) {
      self.id = id
      self.owner = owner
      self.organization = organization
      self.status = status
      self.paymentAmount = paymentAmount
      self.paymentVaultType = paymentVaultType
      self.beneficiary = beneficiary
      self.schedule = schedule
      self.nextPaymentTimestamp = nextPaymentTimestamp
    }
  }

  access(all) struct AgentDetails {
    access(all) let id: UInt64
    access(all) let owner: Address
    access(all) let organization: String
    access(all) let status: String
    access(all) let paymentAmount: UFix64
    access(all) let paymentVaultType: Type
    access(all) let beneficiary: Address
    access(all) let schedule: String
    access(all) let nextPaymentTimestamp: UFix64

    init(
      id: UInt64,
      owner: Address,
      organization: String,
      status: String,
      paymentAmount: UFix64,
      paymentVaultType: Type,
      beneficiary: Address,
      schedule: String,
      nextPaymentTimestamp: UFix64
    ) {
      self.id = id
      self.owner = owner
      self.organization = organization
      self.status = status
      self.paymentAmount = paymentAmount
      self.paymentVaultType = paymentVaultType
      self.beneficiary = beneficiary
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
    ) {
      self.agentId = id
      self.status = status
      self.paymentAmount = paymentAmount
      self.paymentVaultType = paymentVaultType
      self.organization = organization
      self.schedule = schedule
      self.nextPaymentTimestamp = nextPaymentTimestamp
      self.flowFeeWithdrawCap = flowFeeWithdrawCap
      self.paymentProviderCap = paymentProviderCap
    }

    access(FlowCallbackScheduler.Execute) fun executeCallback(id: UInt64, data: AnyStruct?) {
      panic("stub")
    }

    access(all) fun pause() {
      panic("stub")
    }

    access(all) fun unpause() {
      panic("stub")
    }

    access(all) fun cancel() {
      panic("stub")
    }

    access(all) fun updatePaymentDetails(newAmount: UFix64?, newSchedule: String?) {
      panic("stub")
    }
  }

  access(contract) var nextAgentId: UInt64
  access(contract) let agentIndexById: {UInt64: AgentIndex}
  access(contract) let agentsByOwner: {Address: AgentOwnerIndex}
  access(contract) let agentsByOrganization: {String: OrganizationIndex}

  init() {
    self.nextAgentId = 1
    self.agentIndexById = {}
    self.agentsByOwner = {}
    self.agentsByOrganization = {}
  }
}