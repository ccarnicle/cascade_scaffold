# Project Plan: CascadeAgent.cdc Smart Contract

## 1. Project Objective

The primary objective is to create a Cadence smart contract named `CascadeAgent.cdc` that manages on-chain subscriptions for the Cascade protocol on the Flow blockchain. This contract will serve as the "Registry of Truth" for all subscription agents and will define the `Agent` resource that users will store in their accounts to manage their individual subscriptions. The architecture must be efficient, secure, and easily queryable via an external API.

This contract is a core component of the Cascade MVP and is critically dependent on the functionality provided by FLIP330 for Scheduled Callbacks.

---

## 2. Core Components & Requirements

### A. Contract-Level State & Logic

The `CascadeAgent.cdc` contract will be responsible for global state management and will serve as the factory for creating new `Agent` resources.

-   **Agent Registry:**
    -   The contract must maintain a dictionary or similar data structure to track every `Agent` created and their status.
    -   This registry will map a unique Agent ID to metadata, including the owner's address and the agent's current status (e.g., `active`, `paused`, `canceled`).
    -   This is the "Registry of Truth" and must be the definitive source for agent status.

-   **Scheduled Callback Handler (Inside of Agent Resource):**
    -   The contract must use the proper contracts from the Flow Scheduled Callback documentation.
    -   It needs a callback handler resource that will implement the scheduled callback functionality. This resource will live inside of the Agent. It will contain the logic to create a subscription on the user that holds the `Agent` resource.

-   **API-Facing Scripts (Public Functions):**
    -   The contract needs to provide simple, efficient public functions (scripts) for reading data. These are crucial for the backend API and analytics dashboard.
    -   **`getAgentStatus(agentId: UInt64): String`**: Returns the current status of a specific agent.
    -   **`getAgentsByUser(userAddress: Address): [UInt64]`**: Returns a list of all Agent IDs owned by a specific user.
    -   **`getLiveAgentsByUser(userAddress: Address): [UInt64]`**: A helper function that returns only the Agent IDs for a user that are currently in an `active` state.
    -   **`getAgentDetails(agentId: UInt64): AgentDetailsStruct`**: Returns a custom struct containing read-only details about an agent (owner, schedule, amount, next payment date, etc.) for easy consumption by the API.

---

### B. The `Agent` Resource

The `Agent` is a resource object that will be stored directly in a user's account (`/storage/CascadeAgent`). This resource holds the specific parameters for one subscription and empowers the user with direct control.

-   **Resource State (Fields):**
    -   `uuid`: Unique identifier.
    -   `status`: The current state of the subscription (e.g., `active`, `paused`, `canceled`).
    -   `paymentAmount`: The amount of a specific Fungible Token to be transferred per cycle.
    -   `paymentVaultType`: The type of the Fungible Token vault to withdraw from (e.g., `FlowToken.Vault`, `FUSD.Vault`).
    -   `beneficiary`: The address that will receive the payment.
    -   `schedule`: The subscription frequency (e.g., "weekly", "monthly") or a specific cron expression.
    -   `capability`: A private capability to the user's Fungible Token vault, used to execute payments. (Only include if needed)

-   **Resource Logic (Functions):**
    -   **`init()`**: The resource initializer, called when a new agent is created.
    -   **`executeSubscription()`**: This is the core payment logic. It will be called by the contract's callback function. It attempts to withdraw the `paymentAmount` from the user's vault and transfer it to the `beneficiary`. It should handle success and failure cases gracefully. It will also set up recurring payments.
    -   **`pause()`**: A function the user can call to change the agent's status to `paused` and update the central registry.
    -   **`unpause()`**: A function the user can call to reactivate a `paused` subscription.
    -   **`cancel()`**: A function the user can call to permanently terminate the subscription. This should destroy the resource and update the central registry.
    -   **`updatePaymentDetails(newAmount: UFix64?, newSchedule: String?)`**: A function allowing the user to adjust their subscription parameters.

---

## 3. Transactions

A series of Cadence transactions will be required to interact with the contract and `Agent` resources.

-   **`create_agent.cdc`**:
    -   Accepts parameters for a new subscription (amount, schedule, beneficiary, etc.).
    -   Creates a new `Agent` resource.
    -   Saves the `Agent` to the user's account storage.
    -   Registers the new agent in the `CascadeAgent.cdc` contract's public registry.
    -   Schedules the first callback with the `Scheduler` contract.

-   **`manage_agent.cdc`**:
    -   A versatile transaction that allows a user to call management functions on their `Agent` resource.
    -   Could take an `action` parameter (e.g., "pause", "cancel", "unpause") to call the corresponding function on the resource.