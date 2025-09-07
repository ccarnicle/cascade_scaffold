import "Cascade"

access(all) fun main(agentId: UInt64): Cascade.AgentDetails {
  let details = Cascade.getAgentDetails(id: agentId)
    ?? panic("Agent not found")
  return details
}


