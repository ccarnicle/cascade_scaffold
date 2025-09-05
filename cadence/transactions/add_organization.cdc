import "Cascade"

transaction(org: String, recipient: Address) {
  prepare(signer: auth(Storage) &Account) {
    let adminRef = signer.storage.borrow<&Cascade.CascadeAdmin>(from: Cascade.CascadeAdminStoragePath)
      ?? panic("CascadeAdmin not found in signer storage")

    adminRef.addVerifiedOrganization(org: org, recipient: recipient)
  }
}


