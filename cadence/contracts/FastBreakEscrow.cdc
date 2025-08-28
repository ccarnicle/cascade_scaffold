import "aiSportsEscrow"
import "FlowToken"
import "FastBreakV1"
import "FungibleToken"

access(all) contract FastBreakEscrow {

  access(all) let EscrowAdminStoragePath: StoragePath

  /// A game of Fast Break has the following status transitions
  access(all) enum EscrowStatus: UInt8 {
      access(all) case OPEN /// Game is open for submission
      access(all) case CLOSED /// Game is over and rewards are being distributed
  }

  access (all) let FBEscrowEntryById: {UInt64 : FastBreakEscrow.FBEscrowEntry}
  access (all) let UserFBEscrowsByAddress: {Address: [UInt64]}
  access (contract) var nextFBEscrowEntryId: UInt64
  access (all) let FBEscrowContestById: {UInt64 : FastBreakEscrow.FBEscrowContest}

  access (all) struct FBEscrowContest {
    access(all) let escrowID: UInt64
    access(all) let fastBreakGameId: String 
    access(all) var totalEntries: UInt64
    access(all) let FBEscrowEntries: [UInt64]
    access(all) let protocolFees: UFix64
    access(all) let dues: UFix64

    access(contract) fun addFundingEntries(numEntries: UInt64) {
      self.totalEntries = self.totalEntries + numEntries
    }

    access(contract) fun addNewEntry(entryId: UInt64, numEntries: UInt64) {
      self.totalEntries = self.totalEntries + numEntries
      self.FBEscrowEntries.append(entryId)
    }

    init(escrowID: UInt64, fastBreakGameId: String, protocolFees: UFix64, dues: UFix64) {
      self.escrowID = escrowID
      self.fastBreakGameId = fastBreakGameId
      self.totalEntries = 0
      self.FBEscrowEntries = []
      self.protocolFees = protocolFees
      self.dues = dues
    }
  }

  //represents an entry to the FBEscrow
  access(all) struct FBEscrowEntry {
    access(all) let escrowID: UInt64
    access(all) var points: UInt64
    access(all) var win: Bool
    access(all) var winnings: UFix64
    access(all) var submittedAt: UInt64
    access(all) let fastBreakPlayerId: UInt64
    access(all) var status: FastBreakEscrow.EscrowStatus
    access(all) let flowAddress: Address
    access(all) let fbAddress: Address
    access(all) let numEntries: UInt32
    access(all) let duesPaid: UFix64
    access(all) let FBEscrowEntryId: UInt64

    init(escrowID: UInt64, fastBreakPlayerId: UInt64, flowAddress: Address, fbAddress: Address, numEntries: UInt32, duesPaid: UFix64, id: UInt64) {
      self.escrowID = escrowID
      self.points = 0
      self.win = false
      self.winnings = 0.0
      self.submittedAt = UInt64(getCurrentBlock().timestamp)
      self.status = FastBreakEscrow.EscrowStatus.OPEN
      self.fastBreakPlayerId = fastBreakPlayerId
      self.flowAddress = flowAddress
      self.fbAddress = fbAddress
      self.numEntries = numEntries
      self.duesPaid = duesPaid
      self.FBEscrowEntryId = id
    }    

    access(contract) fun setResults(points: UInt64, win: Bool) {
      self.points = points
      self.win = win
      self.status = FastBreakEscrow.EscrowStatus.CLOSED
    }

    access(contract) fun setWinnings(winnings: UFix64) {
      self.winnings = winnings
    }

    access(contract) fun setClosed(points: UInt64) {
      self.status = FastBreakEscrow.EscrowStatus.CLOSED
      self.points = points
    }
  }

  access (all) fun getUserFBEscrows(userAddress: Address) : [FastBreakEscrow.FBEscrowEntry] {
    let userEscrowEntries = FastBreakEscrow.UserFBEscrowsByAddress[userAddress] ?? []
    let userFBEscrows: [FastBreakEscrow.FBEscrowEntry] = []

    for entryId in userEscrowEntries {
      let entry = FastBreakEscrow.FBEscrowEntryById[entryId] ?? panic("Entry not found")
      userFBEscrows.append(entry)
    }
    return userFBEscrows
  }

  access(all) fun fundFBEscrow(escrowAddress: Address, escrowID: UInt64, flowTokenVault: @{FungibleToken.Vault}){

    let amount: UFix64 = flowTokenVault.balance
    assert(UFix64(UInt64(amount)) == amount, message: "Amount must be a whole number")

    let amountUInt64: UInt64 = UInt64(amount)

    let escrowAccount = getAccount(escrowAddress)
    let escrowRef = escrowAccount.capabilities.borrow<&aiSportsEscrow.EscrowMinter>(aiSportsEscrow.EscrowMinterPublicPath)
                      ?? panic("Resource does not exist.")
    escrowRef.addFunds(escrowID: escrowID, tokens: <-flowTokenVault)

    let contestsRef: &{UInt64 : FastBreakEscrow.FBEscrowContest} = &FastBreakEscrow.FBEscrowContestById
    let fastBreakEscrowContestRef = contestsRef[escrowID] ?? panic("No escrow found")
    fastBreakEscrowContestRef.addFundingEntries(numEntries: amountUInt64)
  }


  access(all) fun joinFBEscrow(escrowAddress: Address, escrowID: UInt64, entries: Int, flowTokenVault: @{FungibleToken.Vault}, signerAddress: Address, fbAddress: Address){

    let escrowAccount = getAccount(escrowAddress) //Hardcode emulator account address - CHANGE TO GLOBAL
    let escrowRef = escrowAccount.capabilities.borrow<&aiSportsEscrow.Escrow>(aiSportsEscrow.getEscrowPublicPath(id: escrowID)) ?? panic("Could not borrow escrow reference")
    let leagueDues = escrowRef.leagueDues * UFix64(entries)

    assert(flowTokenVault.balance >= leagueDues, message: "Not enough tokens to join escrow.")

    let minterRef = escrowAccount.capabilities.borrow<&aiSportsEscrow.EscrowMinter>(aiSportsEscrow.EscrowMinterPublicPath)
      ?? panic("Resource does not exist.")

    minterRef.joinEscrow(escrowID: escrowID, tokens: <- flowTokenVault, sender: signerAddress, nfts: <-[], entries: entries)

    let entryId = FastBreakEscrow.nextFBEscrowEntryId
    FastBreakEscrow.nextFBEscrowEntryId = entryId + 1

    var fastBreakPlayerId = FastBreakV1.getPlayerIdByAccount(accountAddress: fbAddress)

    let contestsRef: &{UInt64 : FastBreakEscrow.FBEscrowContest} = &FastBreakEscrow.FBEscrowContestById
    let fastBreakEscrowContestRef = contestsRef[escrowID] ?? panic("No escrow found")
    fastBreakEscrowContestRef.addNewEntry(entryId: entryId, numEntries: UInt64(entries))

    //get the users submissioin to the FB contest
    let gameDict = FastBreakV1.getFastBreakGame(id: fastBreakEscrowContestRef.fastBreakGameId) ?? panic("Game does not exist")
    assert(gameDict.getFastBreakSubmissionByPlayerId(playerId: fastBreakPlayerId) != nil, message: "No submission found for player")

    let fastBreakGameId = fastBreakEscrowContestRef.fastBreakGameId
    
    let userEntry = FastBreakEscrow.FBEscrowEntry(escrowID: escrowID, fastBreakPlayerId: fastBreakPlayerId, flowAddress: signerAddress, fbAddress: fbAddress, numEntries: UInt32(entries), duesPaid: leagueDues, id: entryId)
    
    //get users Escrow entries
    let userEscrowEntries = FastBreakEscrow.UserFBEscrowsByAddress[signerAddress] ?? []

    userEscrowEntries.append(entryId)

    FastBreakEscrow.UserFBEscrowsByAddress.insert(key: signerAddress, userEscrowEntries)  

    FastBreakEscrow.FBEscrowEntryById.insert(key: entryId, userEntry)

  }

  access(all) resource FBEscrowAdmin {
    
    access(all) fun createFBEscrow(escrowID: UInt64, fastBreakGameId: String, protocolFees: UFix64, dues: UFix64) {
      assert(FastBreakV1.getFastBreakGame(id: fastBreakGameId) != nil, message: "Game does not exist")
      let newFBEscrowEntry = FastBreakEscrow.FBEscrowContest(escrowID: escrowID, fastBreakGameId: fastBreakGameId, protocolFees: protocolFees, dues: dues)
      FastBreakEscrow.FBEscrowContestById.insert(key: escrowID, newFBEscrowEntry)
    }

    access (all) fun closeFBEscrow(escrowAddress: Address, escrowID: UInt64): {Address: UFix64} {
      let escrow = FastBreakEscrow.FBEscrowContestById[escrowID] ?? panic("No escrow found")
      let escrowEntries = escrow.FBEscrowEntries

      let escrowAccount = getAccount(escrowAddress) //Hardcode emulator account address - CHANGE TO GLOBAL
      let escrowRef = escrowAccount.capabilities.borrow<&aiSportsEscrow.Escrow>(aiSportsEscrow.getEscrowPublicPath(id: escrowID)) ?? panic("Could not borrow escrow reference")

      let winners: [UInt64] = []
      var totalWinningEntries: UInt32 = 0

      for entryId in escrowEntries {
        let entriesRef: &{UInt64 : FastBreakEscrow.FBEscrowEntry} = &FastBreakEscrow.FBEscrowEntryById
        let entry = entriesRef[entryId] ?? panic("Entry not found")
        
        //get the users submissioin to the FB contest
        let gameDict = FastBreakV1.getFastBreakGame(id: escrow.fastBreakGameId) ?? panic("Game does not exist")
        let submission = gameDict.getFastBreakSubmissionByPlayerId(playerId: entry.fastBreakPlayerId) ?? panic("No submission found for player")

        if submission.win == true {
          winners.append(entryId)
          totalWinningEntries = totalWinningEntries + entry.numEntries
          entry.setResults(points: submission.points, win: submission.win)
        } else {
          entry.setClosed(points: submission.points)
        }
      }

      let totalDistro = escrowRef.tokens.balance - (escrowRef.tokens.balance * escrow.protocolFees/100.0)
      let winnerDistro: {Address: UFix64} = {}

      for winner in winners {
        let entriesRef: &{UInt64:FastBreakEscrow.FBEscrowEntry} = &FastBreakEscrow.FBEscrowEntryById
        let entry = entriesRef[winner] ?? panic("Entry not found")

        let winnings = totalDistro * (UFix64(entry.numEntries) / UFix64(totalWinningEntries))
        entry.setWinnings(winnings: winnings)

        winnerDistro[entry.flowAddress] = winnings
      }

      return winnerDistro
    }

  }

  init(){
    self.FBEscrowEntryById = {}
    self.UserFBEscrowsByAddress = {}
    self.FBEscrowContestById = {}
    self.nextFBEscrowEntryId = 1

        // Set the named paths
    self.EscrowAdminStoragePath = /storage/FBEscrowAdmin

    self.account.storage.save(<-create FBEscrowAdmin(), to: self.EscrowAdminStoragePath)
  }

}