# 👋 Welcome to the Flow Agent Protocol (Cascade v2)

This project is building a platform for autonomous DeFi agents on the Flow blockchain. Flow Agents are smart contract resources that live in a user's account, waking up on a timer using Scheduled Callbacks to perform powerful DeFi actions on the user's behalf.

The goal is to provide a simple, secure, and extensible way for users to "set and forget" complex DeFi strategies, starting with Dollar-Cost Averaging and expanding to a suite of automated actions.

### Project Status

This project is a work-in-progress. The core contract architecture is being developed, and the initial feature set is defined in the roadmap below.

**Action Items:**
*   Rename the project from `cascade_v2` to a final production name.

---

## 🗺️ Project Roadmap & Vision

This protocol will be developed and released in phases, building a powerful ecosystem of autonomous agents over time.

### Phase 1: Autonomous Swapping (Dollar-Cost Averaging)
The first phase focuses on creating a reliable agent capable of performing automated token swaps on a recurring schedule. This allows users to easily Dollar-Cost Average (DCA) into positions.

*   **Core Deliverable:** A `Cascade` smart contract that allows users to create, manage, and store an `Agent` resource in their account.
*   **Agent Action:** The `Agent` will be able to execute a token swap (e.g., FLOW to FUSD) by integrating with a DEX on Flow.
*   **User Control:** Users will have transactions to create, pause, unpause, and cancel their DCA agents.

### Phase 2: Expanded DeFi Actions
Building on the foundation of Phase 1, we will introduce more sophisticated DeFi strategies, allowing agents to interact with a wider range of on-chain protocols. This will be highly dependent on integrations with emerging **Flow Actions**.

*   **Agent Action:** Manage positions in liquidity pools (e.g., add or remove liquidity).
*   **Agent Action:** Automatically harvest and reinvest yields from staking or liquidity farming.
*   **Agent Action:** Rebalance a portfolio of tokens based on predefined rules.

### Future Phases: Organization & Subscription Model
The original Cascade plan for enabling organizations to manage subscriptions and payments will be integrated as a core feature. This will allow DAOs, creators, and businesses to build on the Flow Agent Protocol for recurring on-chain revenue.

---

## 🤖 What are Scheduled Callbacks?

Scheduled Callbacks are the core technology that powers Flow Agents. They let smart contracts execute code at (or after) a chosen time without an external transaction. You schedule work now; the network executes it later. This enables recurring jobs, deferred actions, and autonomous workflows.

Core pieces:

-   Capability to a handler implementing `FlowCallbackScheduler.CallbackHandler`
-   Parameters: `timestamp`, `priority`, `executionEffort`, `fees`, optional `callbackData`
-   Estimate first (`FlowCallbackScheduler.estimate`), then schedule (`FlowCallbackScheduler.schedule`)

---

## 🔨 Getting Started

Here are some necessary flow resources:

-   **[Flow Documentation](https://developers.flow.com/)** - The official Flow Documentation.
-   **[Cadence Documentation](https://cadence-lang.org/docs/language)** - The native resource-oriented language for Flow.
-   **[Visual Studio Code](https://code.visualstudio.com/)** and the **[Cadence Extension](https://marketplace.visualstudio.com/items?itemName=onflow.cadence)** - The recommended IDE for Cadence development.
-   **[Block Explorers](https://developers.flow.com/ecosystem/block-explorers)** - Tools to explore on-chain data. [Flowser](https://flowser.dev/) is excellent for local development.

---

## 📦 Project Structure

-   `flow.json` – Project configuration and dependencies.
-   `/cadence/contracts` – Cadence smart contracts.
-   `/cadence/scripts` – Read-only scripts.
-   `/cadence/transactions` – State-changing transactions.
-   `/core-contracts` – Local copies of core Flow contracts for the emulator.