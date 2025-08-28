import "FlowToken"
import "FungibleToken"
import "NonFungibleToken"

access(all) contract aiSportsEscrow {

  access(all) entitlement Withdraw
  access(all) entitlement LeagueOwner
  access(all) entitlement EmptyEscrow

  access (all) event EscrowCreated(escrowID: UInt64)
  access (all) event EscrowJoined(escrowID: UInt64)
  access (all) event EscrowClosed(escrowID: UInt64)
  access (all) event EscrowFunded(escrowID: UInt64)

  //list of open escrows
  access(all) var openEscrows: {UInt64: Bool}

  // ID tracker for escrows
  access(all) var nextEscrowID: UInt64

  // Standard Paths
  access(all) let EscrowMinterStoragePath: StoragePath
  access(all) let EscrowMinterPublicPath: PublicPath
  access(all) let EscrowStoragePath: StoragePath

  access(all) resource Escrow {
    //fungible tokens held in escrow
    access(all) let tokens: @{FungibleToken.Vault} 
    //Time when the escrow can be released
    access(all) let releaseTime: UFix64
    //time when the contest start - people cannot join the escrow after the start time
    access(all) let startTime: UFix64
    access(all) let escrowID: UInt64
    access(all) let leagueName: String
    access(all) var isEscrowOpen: Bool
    
    access (all) let leagueHost: String
    //Yahoo/ESPN LeagueID - optional
    access(all) let leagueID: UInt64 
    //Maximum amount of players that can join
    access(all) let totalMembers: UInt32
    //How many tokens each member has to pay for dues
    access(all) let leagueDues: UFix64
    //league creator is always 1st member - leagueMembers[0]
    access(all) var leagueMembers: [Address]

    //dictionary of NFTs held in Escrow
    access(all) var nftEscrow: @{Address: [{NonFungibleToken.NFT}]}

    //Required number of NFTs to escrow to join league
    access(all) let requiredNFTs: UInt64
    //Path To NFT Collection
    access(all) let nftCollectionPath: PublicPath

    //getNftType
    access(all) let nftType: Type

    access(all) fun getTokenType(): Type {
        return self.tokens.getType()
    }

    // Initialize the Escrow resource with tokens and the release time
    init(tokens: @{FungibleToken.Vault}, startTime: UFix64?, releaseTime: UFix64, escrowID: UInt64, leagueHost: String?, leagueName: String, leagueID: UInt64?, totalMembers: UInt32, leagueDues: UFix64, creatorAddress: Address?, nfts: @[{NonFungibleToken.NFT}], path: PublicPath?) {
      
        self.tokens <- tokens
        self.isEscrowOpen = true
        self.startTime = startTime != nil ? startTime! : 0.0
        self.releaseTime = releaseTime
        self.escrowID = escrowID
        self.leagueName = leagueName
        self.leagueHost = leagueHost != nil ? leagueHost! : ""
        self.leagueID = leagueID != nil ? leagueID! : 0
        self.totalMembers = totalMembers
        self.leagueDues = leagueDues
        self.leagueMembers = creatorAddress != nil ? [creatorAddress!] : []
        self.requiredNFTs = nfts.length > 0 ? UInt64(nfts.length) : 0
        self.nftCollectionPath = path != nil ? path! : PublicPath(identifier: "")!

        if nfts.length > 0 {
          self.nftType = nfts[0].getType()

          var i = 1
          while i < nfts.length {
            assert( nfts[i].getType() == self.nftType, message: "All NFTs must be of the same type")
            i = i + 1
          }

        } else {
          //nft type is not needed, so we just set it to a generic NFT
          self.nftType = Type<@{NonFungibleToken.NFT}>()
        } 

        //if there is a creator && the league accepts NFTS, then creator will escrow their NFTs
        if(creatorAddress != nil) {
          let createAddress = creatorAddress!
          self.nftEscrow <- {createAddress: <-nfts}
        } else { //if there is not a creator, 0 NFTs are escrowed, and the nft resource that is passed in is destroyed
          assert(nfts.length == 0, message: "NFTs passed in, but no NFT requirement for this escrow")
          self.nftEscrow <- {}
          destroy nfts
        }

    }

    // Entitlement for withdrawal
    access(Withdraw) fun withdraw(amount: UFix64): @{FungibleToken.Vault} {
        pre {
            // Ensure that the current time is past the release time
            getCurrentBlock().timestamp >= self.releaseTime: "Escrow period has not yet ended"
            Int(self.tokens.balance) >= Int(amount): "Insufficient balance"
        }

        // Return the held Flow tokens
        return <-self.tokens.withdraw(amount: amount)
    }

    access(Withdraw) fun refund(): @{FungibleToken.Vault} {

        pre {
            // Ensure that the start time is null or has not yet occured
            getCurrentBlock().timestamp < self.startTime || self.startTime == 0.0: "Cannot refund, Escrow has already started"
            Int(self.tokens.balance) >= Int(self.leagueDues): "Insufficient balance"
        }

        // Return the held Flow tokens
        return <-self.tokens.withdraw(amount: self.leagueDues)
    }

    access(contract) fun addMember(address: Address, nfts: @[{NonFungibleToken.NFT}]) {
      
      pre {
        // Ensure that the address is not already a member
        self.leagueMembers.contains(address) == false: "Address is already a member"
        Int(self.requiredNFTs) == nfts.length: "Incorrect number of NFTs"
      }

      self.leagueMembers.append(address)

      if nfts.length > 0 { //this is a league with an nft requirement

        var i = 0
        while i < nfts.length {
          assert( nfts[i].getType() == self.nftType, message: "All NFTs in Escrow must be of the same type")
          i = i + 1
        }
        self.nftEscrow[address] <-! nfts
      } else { //this league does not require nfts, and this array contained 0 resources
        destroy nfts
      }

    }

    access(contract) fun releaseEscrowedNfts(address: Address){

      let nfts: @[{NonFungibleToken.NFT}] <- self.nftEscrow.remove(key: address) ?? panic("Address does not exist in the dictionary")
      let receiver = getAccount(address)
      let receiverCap = receiver.capabilities.get<&{NonFungibleToken.CollectionPublic}>(self.nftCollectionPath)
      let receiverRef = receiverCap.borrow() ?? panic("Could not borrow reference to the recipient's receiver")

      while nfts.length > 0 {
        let nft <- nfts.remove(at: 0)
        receiverRef.deposit(token: <-nft)
      }

      assert(nfts.length == 0, message: "NFTs were not transferred to account")
      //destroy empty nft array
      destroy nfts
    }

    access (contract) fun closeEscrowStatus() {
      self.isEscrowOpen = false
    }

  }

  access(all) view fun getEscrowStoragePath(id: UInt64): StoragePath {
    return StoragePath(identifier: "escrows/".concat(id.toString()))!
  }

  access(all) view fun getEscrowPublicPath(id: UInt64): PublicPath {
    return PublicPath(identifier: "escrows/".concat(id.toString()))!
  }

  /// createEmptyCollection creates an empty Closer Collection
  /// and returns it to the caller so that they can store EscrowClosers
  access(all) fun createCloserCollection(): @EscrowCloserCollection {    
      return <- create EscrowCloserCollection()
  }

  /// Minter
  ///
  /// Resource object that token admin accounts can hold to create new Escrows
  ///
  access(all) resource EscrowMinter {
    // Create a new escrow
    access(all) fun createEscrow(tokens: @{FungibleToken.Vault}, startTime: UFix64?, releaseTime: UFix64, leagueHost: String?, leagueName: String, leagueID: UInt64?, totalMembers:UInt32, dues: UFix64, creator: Address, nfts: @[{NonFungibleToken.NFT}], path: PublicPath?): @EscrowCloser {

      pre {
        dues >= 1.0: "Dues Must be at least 1 Token"
        totalMembers >= 2: "League must have at least 2 members"
        getCurrentBlock().timestamp < releaseTime: "Release time must be in the future"
        tokens.balance >= dues: "Insufficient dues"
        startTime == nil || startTime! <= releaseTime: "Start time must be before release time"
        startTime == nil || getCurrentBlock().timestamp < startTime!: "Start time must be in the future"
      }

      // Store it in the contract
      let escrowID = aiSportsEscrow.nextEscrowID
      // Create the escrow resource
      let escrow <- create Escrow(tokens: <-tokens, startTime: startTime, releaseTime: releaseTime, escrowID: escrowID, leagueHost: leagueHost, leagueName: leagueName, leagueID: leagueID, totalMembers: totalMembers, leagueDues: dues, creatorAddress: creator, nfts: <-nfts, path: path)

      let escrowStoragePath = aiSportsEscrow.getEscrowStoragePath(id: escrowID)
      let escrowPublicPath = aiSportsEscrow.getEscrowPublicPath(id: escrowID)

      aiSportsEscrow.account.storage.save(<-escrow, to: escrowStoragePath)

      //publish a capability to the escrow in storage so others can join
      let escrowCap = aiSportsEscrow.account.capabilities.storage.issue<&aiSportsEscrow.Escrow>(escrowStoragePath)
      aiSportsEscrow.account.capabilities.publish(escrowCap, at: escrowPublicPath)
      //create an escrowCloser to save to creators account
      let escrowCloser <- create aiSportsEscrow.EscrowCloser(escrowID: escrowID)
      //add this escrow to open escrows
      aiSportsEscrow.openEscrows.insert(key: escrowID, true)
      // Increment the escrow ID counter
      aiSportsEscrow.nextEscrowID = escrowID + 1
      //emit escrow created event
      emit EscrowCreated(escrowID: escrowID)

      return <- escrowCloser

    }

    access(all) fun joinEscrow(escrowID: UInt64, tokens: @{FungibleToken.Vault}, sender: Address, nfts: @[{NonFungibleToken.NFT}], entries: Int?) {

      let joinEscrowRef = aiSportsEscrow.account.storage.borrow<&aiSportsEscrow.Escrow>(from: aiSportsEscrow.getEscrowStoragePath(id: escrowID)) ?? panic("Could not borrow a reference to the escrow resource")
      let updatedLeagueMembers = *joinEscrowRef.leagueMembers

      let userEntries = entries ?? 1

      if(joinEscrowRef.startTime > 0.0) { //if start time is 0.0, there is not start time requirement
        assert(getCurrentBlock().timestamp < joinEscrowRef.startTime, message: "Cannot Join Escrow after start time")
      }

      assert(getCurrentBlock().timestamp < joinEscrowRef.releaseTime, message: "Cannot Join Escrow after release time")
      assert(joinEscrowRef.tokens.getType() == tokens.getType(), message: "Incorrect Token Type")
      assert(updatedLeagueMembers.length < Int(joinEscrowRef.totalMembers), message: "League At Capacity")
      assert((joinEscrowRef.leagueDues * UFix64(userEntries)) == tokens.balance, message: "Incorrect Dues")

      joinEscrowRef.tokens.deposit(from: <-tokens)
      joinEscrowRef.addMember(address: sender, nfts: <-nfts)

      //emit escrow joined event
      emit EscrowJoined(escrowID: escrowID)
    }

    access(all) fun addFunds(escrowID: UInt64, tokens: @{FungibleToken.Vault}) { 
      let joinEscrowRef = aiSportsEscrow.account.storage.borrow<&aiSportsEscrow.Escrow>(from: aiSportsEscrow.getEscrowStoragePath(id: escrowID)) ?? panic("Could not borrow a reference to the escrow resource")
      assert(joinEscrowRef.tokens.getType() == tokens.getType(), message: "Incorrect Token Type")

      let addFundsRef = aiSportsEscrow.account.storage.borrow<&aiSportsEscrow.Escrow>(from: aiSportsEscrow.getEscrowStoragePath(id: escrowID)) ?? panic("Could not borrow a reference to the escrow resource")
      addFundsRef.tokens.deposit(from: <-tokens)
      emit EscrowFunded(escrowID: escrowID)
    }

    access (EmptyEscrow) fun createEmptyEscrow(tokens: @{FungibleToken.Vault}, startTime: UFix64?, releaseTime: UFix64, leagueName: String, totalMembers:UInt32, dues: UFix64 ): @EscrowCloser {
      
      pre {
        totalMembers >= 1: "League must have at least 1 members"
        getCurrentBlock().timestamp < releaseTime: "Release time must be in the future"
        startTime == nil || startTime! <= releaseTime: "Start time must be before release time"
        startTime == nil || getCurrentBlock().timestamp < startTime!: "Start time must be in the future"
      }

      // Store it in the contract
      let escrowID = aiSportsEscrow.nextEscrowID
      // Create the escrow resource
      let escrow <- create Escrow(tokens: <-tokens, startTime: startTime, releaseTime: releaseTime, escrowID: escrowID, leagueHost: nil, leagueName: leagueName, leagueID: nil, totalMembers: totalMembers, leagueDues: dues, creatorAddress: nil , nfts: <-[], path: nil)

      let escrowStoragePath = aiSportsEscrow.getEscrowStoragePath(id: escrowID)
      let escrowPublicPath = aiSportsEscrow.getEscrowPublicPath(id: escrowID)

      aiSportsEscrow.account.storage.save(<-escrow, to: escrowStoragePath)

      //publish a capability to the escrow in storage so others can join
      let escrowCap = aiSportsEscrow.account.capabilities.storage.issue<&aiSportsEscrow.Escrow>(escrowStoragePath)
      aiSportsEscrow.account.capabilities.publish(escrowCap, at: escrowPublicPath)
      //create an escrowCloser to save to creators account
      let escrowCloser <- create aiSportsEscrow.EscrowCloser(escrowID: escrowID)
      //add this escrow to open escrows
      aiSportsEscrow.openEscrows.insert(key: escrowID, true)
      // Increment the escrow ID counter
      aiSportsEscrow.nextEscrowID = escrowID + 1
      //emit escrow created event
      emit EscrowCreated(escrowID: escrowID)

      return <- escrowCloser
    }

  }

  access(all) resource EscrowCloserCollection {
    
    access(all) var escrows: @{UInt64: aiSportsEscrow.EscrowCloser}

    access(all) fun deposit(escrowCloser: @EscrowCloser) {
      self.escrows[escrowCloser.escrowID] <-! escrowCloser
    }

    access(LeagueOwner) fun closeEscrow(escrowID: UInt64, winners: {Address: UFix64}) {
      self.escrows[escrowID]?.releaseEscrow(winners: winners, path: nil, overflow: nil) ?? panic("Could not access EscrowID")
    }

    access(LeagueOwner) fun closeEscrowGeneric(escrowID: UInt64, winners: {Address: UFix64}, path: PublicPath?, overflow: Address) {
      self.escrows[escrowID]?.releaseEscrow(winners: winners, path: path, overflow: overflow) ?? panic("Could not access EscrowID")
    }

    access(LeagueOwner) fun cancelEscrow(escrowID: UInt64) {
      self.escrows[escrowID]?.refundEscrow() ?? panic("Could not access EscrowID")
    }

    access(all) fun getEscrowIDs(): [UInt64] {
      return self.escrows.keys
    }

    init() {
      self.escrows <- {}
    }
  }

  access(all) resource EscrowCloser {
    
    access (all) let escrowID: UInt64

    //function to make sure the winners array has only unique elements
    access (all) fun hasUniqueElements(winners: [Address]): Bool {

      let readWinners:[Address] = []

      for index, element in winners {
          if readWinners.contains(element) {
            return false
          } else {
            readWinners.append(element)
          }
      }

      return true
    }
    
    // Release the escrow by ID
    access(all) fun releaseEscrow(winners: {Address: UFix64}, path: PublicPath?, overflow: Address?) {

      pre {
        aiSportsEscrow.openEscrows.containsKey(self.escrowID): "Escrow is not open"
      }

      var tokenPath = PublicPath(identifier: "flowTokenReceiver")!

      if path != nil {
        tokenPath = path!
      }

      assert (self.hasUniqueElements(winners: winners.keys), message: "Winners must be unique")

      let releaseEscrowRef = aiSportsEscrow.account.storage.borrow<auth(Withdraw) &aiSportsEscrow.Escrow>(from: aiSportsEscrow.getEscrowStoragePath(id: self.escrowID)) ?? panic("Could not borrow a reference to the escrow resource")

      assert (getCurrentBlock().timestamp >= releaseEscrowRef.releaseTime, message: "Escrow period has not yet ended")

      var totalPayout = 0.0

      for element in winners.values {
        totalPayout = totalPayout + element
      }

      if (overflow == nil) {
        assert(totalPayout == releaseEscrowRef.tokens.balance, message: "Pay out does not match escrow balance")
      }

      //pay out each winners FLOW tokens
      for element in winners.keys {

        assert(releaseEscrowRef.leagueMembers.contains(element), message: "Winner is not a member of the league")

        let winnerAccount = getAccount(element)
        let payout <- releaseEscrowRef.withdraw(amount: winners[element] ?? panic("Could not find winner in winners dictionary"))

        // get the Winner Account's Receiver reference to their Vault
        // by borrowing the reference from the public capability
        let receiverRef = winnerAccount.capabilities.borrow<&{FungibleToken.Receiver}>(tokenPath)
                          ?? panic("Could not borrow a reference to the receiver")

        // deposit tokens to their Vault
        receiverRef.deposit(from: <-payout)
      }

      if(overflow != nil && releaseEscrowRef.tokens.balance > 0.0) { // if there is a token balance, payout the rest of the escrow to the league creator
        let creatorAccount = getAccount(overflow!)
        let payout <- releaseEscrowRef.withdraw(amount: releaseEscrowRef.tokens.balance)

        // get the Winner Account's Receiver reference to their Vault
        // by borrowing the reference from the public capability
        let receiverRef = creatorAccount.capabilities.borrow<&{FungibleToken.Receiver}>(tokenPath)
                          ?? panic("Could not borrow a reference to the receiver")

        // deposit the rest of the tokens to their Vault
        receiverRef.deposit(from: <-payout)
      }
    
      //return all user NFTs
      if releaseEscrowRef.requiredNFTs > 0 {
        for member in releaseEscrowRef.leagueMembers {
          releaseEscrowRef.releaseEscrowedNfts(address: member)
        }
      }

      //change escrow status to closed
      releaseEscrowRef.closeEscrowStatus()

      //remove the escrow from the openEscrows dictionary
      aiSportsEscrow.openEscrows.remove(key: releaseEscrowRef.escrowID)

    }

    //cancel the league and refund winners before league start
    access (all) fun refundEscrow(){

      pre {
        aiSportsEscrow.openEscrows.containsKey(self.escrowID): "Escrow is not open"
      }

      let releaseEscrowRef = aiSportsEscrow.account.storage.borrow<auth(Withdraw) &aiSportsEscrow.Escrow>(from: aiSportsEscrow.getEscrowStoragePath(id: self.escrowID)) ?? panic("Could not borrow a reference to the escrow resource")
      
      assert(getCurrentBlock().timestamp < releaseEscrowRef.startTime || releaseEscrowRef.startTime == 0.0, message: "League has already started")

      for member in releaseEscrowRef.leagueMembers {
        let returnDues <- releaseEscrowRef.refund()
        let returnAccount = getAccount(member)

        let receiverRef = returnAccount.capabilities.borrow<&{FungibleToken.Receiver}>(/public/flowTokenReceiver)
                  ?? panic("Could not borrow a reference to the receiver")

        // deposit your tokens to their Vault
        receiverRef.deposit(from: <-returnDues)

        //return all user NFTs
        if releaseEscrowRef.requiredNFTs > 0 {
          releaseEscrowRef.releaseEscrowedNfts(address: member)
        }
      }

      //change escrow status to closed
      releaseEscrowRef.closeEscrowStatus()

      //remove the escrow from the openEscrows dictionary
      aiSportsEscrow.openEscrows.remove(key: releaseEscrowRef.escrowID)

    }

    init(escrowID: UInt64){
      self.escrowID = escrowID
    }

  }

  init(){
    self.nextEscrowID = 0
    self.openEscrows = {}

    // Set the named paths
    self.EscrowMinterStoragePath = /storage/aiSportsEscrowMinter
    self.EscrowMinterPublicPath = /public/aiSportsEscrowMinter

    self.EscrowStoragePath = /storage/escrows

    self.account.storage.save(<-create EscrowMinter(), to: self.EscrowMinterStoragePath)
    
    //create a public capability to the EscrowMinter resource
    let escrowMinterCap = self.account.capabilities.storage.issue<&aiSportsEscrow.EscrowMinter>(self.EscrowMinterStoragePath)
    self.account.capabilities.publish(escrowMinterCap, at: self.EscrowMinterPublicPath)
  }
}