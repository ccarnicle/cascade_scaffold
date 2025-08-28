import "FlowCallbackScheduler"
import "FlowToken"
import "FungibleToken"

access(all) contract RickRoll {

    /// Handler resource that implements the Scheduled Callback interface
    access(all) resource Handler: FlowCallbackScheduler.CallbackHandler {
        access(FlowCallbackScheduler.Execute) fun executeCallback(id: UInt64, data: AnyStruct?) {

            var delay: UFix64 = 5.0
            let future = getCurrentBlock().timestamp + delay
            let priority = FlowCallbackScheduler.Priority.Medium
            let executionEffort: UInt64 = 1000

            let estimate = FlowCallbackScheduler.estimate(
                data: data,
                timestamp: future,
                priority: priority,
                executionEffort: executionEffort
            )

            assert(
                estimate.timestamp != nil || priority == FlowCallbackScheduler.Priority.Low,
                message: estimate.error ?? "estimation failed"
            )

             // Ensure a handler resource exists in the contract account storage
            if RickRoll.account.storage.borrow<&AnyResource>(from: /storage/RickRollCallbackHandler) == nil {
                let handler <- RickRoll.createHandler()
                RickRoll.account.storage.save(<-handler, to: /storage/RickRollCallbackHandler)
            }

            let vaultRef = RickRoll.account.storage
                .borrow<auth(FungibleToken.Withdraw) &FlowToken.Vault>(from: /storage/flowTokenVault)
                ?? panic("missing FlowToken vault on contract account")
            let fees <- vaultRef.withdraw(amount: estimate.flowFee ?? 0.0) as! @FlowToken.Vault

            // Issue a capability to the handler stored in this contract account
            let handlerCap = RickRoll.account.capabilities.storage
                .issue<auth(FlowCallbackScheduler.Execute) &{FlowCallbackScheduler.CallbackHandler}>(/storage/RickRollCallbackHandler)

            let receipt = FlowCallbackScheduler.schedule(
                callback: handlerCap,
                data: data,
                timestamp: future,
                priority: priority,
                executionEffort: executionEffort,
                fees: <-fees
            )

            switch (RickRoll.messageNumber) {
                case 0:
                    RickRoll.message1()
                case 1:
                    RickRoll.message2()
                case 2:
                    RickRoll.message3()
                case 3:
                    RickRoll.resetMessageNumber()
                    return
                default:
                    panic("Invalid message number")
            }
        }
    }

    access(all) var messageNumber: UInt8

    /// Factory for the handler resource
    access(all) fun createHandler(): @Handler {
        return <- create Handler()
    }

    // Reminder: Anyone can call these functions!
    access(all) fun message1() {
        log("Never gonna give you up")
        self.messageNumber = 1
    }

    access(all) fun message2() {
        log("Never gonna let you down")
        self.messageNumber = 2
    }

    access(all) fun message3() {
        log("Never gonna run around and desert you")
        self.messageNumber = 3
    }

    access(all) fun resetMessageNumber() {
        self.messageNumber = 0
    }

    init() {
        self.messageNumber = 0
    }

}
