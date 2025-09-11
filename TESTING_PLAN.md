## Testing Plan for Cascade (Agents, Scheduling, and Management)

### Scope

- Validate agent lifecycle, scheduled callbacks, funds movement (Send action), pausing/resuming, canceling, and update flows.
- Confirm indexes and read scripts return accurate state.
- Exercise cancel+reschedule flows for schedule and next timestamp updates.

## Environment Setup

- Start emulator with scheduled callbacks enabled.
- Deploy contracts.
- Create test accounts; fund primary signer with FLOW.
- Add a verified organization and confirm mapping exists.

### Scripts to verify

- get_verified_organizations
- get_agents_by_owner
- get_agents_by_organization
- get_agent_details

## Create and First Schedule

- Run create_and_schedule_registration with:
  - id, organization=TESTORG, paymentAmount=X, scheduleName="10s", nextPaymentTimestamp=0.0, priority, executionEffort.
- Assert:
  - Agent saved at `Cascade.getAgentStoragePath(id)`.
  - AgentDetails.status == Canceled (pre-first run)
  - Agent has lastCallback set (receipt recorded)
  - CallbackScheduled event emitted

## First Execution Behavior (Action.Send)

- Wait for execution window.
- Assert:
  - AgentDetails.status == Active (set at start of resumed/first work)
  - Recipient FLOW increased by paymentAmount
  - Signer FLOW decreased accordingly (payment + any fees)
  - AgentDetails.nextPaymentTimestamp advanced per cadence logic
  - New lastCallback recorded and CallbackScheduled emitted

## Pause Until (Timed Pause)

- Call pauseUntil(resumeTimestamp > now).
- Assert immediately:
  - status == Paused
  - nextPaymentTimestamp == resumeTimestamp
  - lastCallback updated to the resume schedule
- Before resume time:
  - No payment executed
  - No new CallbackScheduled beyond the resume callback
- After resume time:
  - status flips to Active at start of execution
  - Payment executes and scheduling continues

## Cancel

- Call cancel().
- Assert:
  - status == Canceled
  - Any scheduled callback that fires will early-return without payment or rescheduling

## Manual Activation

- Call setActive().
- Assert:
  - status == Active
  - No schedule is created by this call alone (until updateSchedule or existing scheduled run occurs)

## Update Organization

- Add another verified org; call updateOrganization(newOrg).
- Assert:
  - AgentDetails.organization updated
  - agentsByOrganization index moved (removed from old, added to new)
  - Next execution pays the new org

## Update Payment Amount

- Call updatePaymentAmount(newAmount).
- Assert:
  - AgentDetails.paymentAmount updated
  - Next execution uses new amount

## Update Schedule (Cadence and/or Next Timestamp)

- Case A: Change cadence only
  - updateSchedule(newScheduleName, rescheduleAt: nil)
  - Assert:
    - Previous lastCallback canceled; refund deposited to owner
    - AgentDetails.schedule updated; status set to Active
    - New receipt saved (lastCallback); nextPaymentTimestamp updated

- Case B: Change next timestamp only

  - updateSchedule(same schedule, rescheduleAt: T_future)
  - Assert:
    - Previous lastCallback canceled; refund deposited to owner
    - Status set to Active
    - Rescheduled at T_future; lastCallback saved; nextPaymentTimestamp == T_future

- Case C: Repeated updates
  - Call updateSchedule twice in a row
  - Assert first replacement canceled and refunded; only the latest receipt remains

## Action Dispatch

- Confirm default AgentDetails.action == Send and Send path executes.
- (Optional) If action is set to Swap manually, confirm it panics "Swap action not implemented" for now.

## Read Scripts Validation

- get_agent_details returns full AgentDetails including action and updated fields
- get_agents_by_owner returns expected ids
- get_agents_by_organization returns expected ids
- get_verified_organizations contains added orgs and addresses are mapped

## Events Validation

- Observe and verify ordering and presence of:
  - AgentCreated
  - AgentStatusChanged (Active/Paused/Canceled) when applicable
  - CallbackScheduled on each schedule

## Error Cases to Exercise

- pauseUntil with resumeTimestamp <= now should assert
- updateOrganization with unverified org should assert
- Insufficient FLOW to fund schedule fees: estimate/withdraw should fail

## Transactions to Implement (for test.sh integration)

- add_organization
- create_and_schedule_registration
- pause_until(resumeTimestamp)
- cancel
- set_active
- update_organization(newOrganization)
- update_payment_amount(newAmount)
- update_schedule(newScheduleName, rescheduleAt?)

## Suggested CLI Flow (High-Level)

1) Deploy, create accounts, add org, fund signer
2) Create agent and schedule first run; verify initial state
3) Wait and verify first execution (payment, status, next schedule)
4) Pause until T; verify paused state; verify resume behavior at T
5) Cancel; verify no further execution
6) setActive; verify status only
7) updateOrganization; verify index and next payment route
8) updatePaymentAmount; verify new amount on next run
9) updateSchedule cases (cadence and timestamp); verify cancel+refund+reschedule
10) Run read scripts after each step to confirm state


