//
//  Copyright (c) 2020-2021 MobileCoin. All rights reserved.
//

import Foundation

final class Account {
    let accountKey: AccountKey

    let fogView = FogView()

    var allTxOutTrackers: [TxOutTracker] = []

    init(accountKey: AccountKeyWithFog) {
        logger.info("")
        self.accountKey = accountKey.accountKey
    }

    var publicAddress: PublicAddress {
        accountKey.publicAddress
    }

    var unscannedMissedBlocksRanges: [Range<UInt64>] { fogView.unscannedMissedBlocksRanges }

    private var allTxOutsFoundBlockCount: UInt64 {
        var allTxOutsFoundBlockCount = fogView.allRngTxOutsFoundBlockCount
        for unscannedMissedBlocksRange in unscannedMissedBlocksRanges
            where unscannedMissedBlocksRange.lowerBound < allTxOutsFoundBlockCount
        {
            allTxOutsFoundBlockCount = unscannedMissedBlocksRange.lowerBound
        }
        return allTxOutsFoundBlockCount
    }

    /// The number of blocks for which we have complete knowledge of this Account's wallet.
    var knowableBlockCount: UInt64 {
        var knowableBlockCount = allTxOutsFoundBlockCount
        for txOut in allTxOutTrackers {
            if case .unspent(let knownToBeUnspentBlockCount) = txOut.spentStatus {
                knowableBlockCount = min(knowableBlockCount, knownToBeUnspentBlockCount)
            }
        }
        return knowableBlockCount
    }

    var cachedBalance: Balance {
        let blockCount = knowableBlockCount
        let txOutValues = allTxOutTrackers
            .filter { $0.receivedAndUnspent(asOfBlockCount: blockCount) }
            .map { $0.knownTxOut.value }
        return Balance(values: txOutValues, blockCount: blockCount)
    }

    func cachedBalance(atBlockCount blockCount: UInt64) -> Balance? {
        logger.info("atBlockCount: \(blockCount)")
        guard blockCount <= knowableBlockCount else {
            logger.info("""
                error - blockCount: \(blockCount) > \
                knowableBlockCount: \(knowableBlockCount)
                """)
            return nil
        }
        let txOutValues = allTxOutTrackers
            .filter { $0.receivedAndUnspent(asOfBlockCount: blockCount) }
            .map { $0.knownTxOut.value }
        return Balance(values: txOutValues, blockCount: blockCount)
    }

    var cachedAccountActivity: AccountActivity {
        let blockCount = knowableBlockCount
        let txOuts = allTxOutTrackers.compactMap { OwnedTxOut($0, atBlockCount: blockCount) }
        return AccountActivity(txOuts: txOuts, blockCount: blockCount)
    }

    func cachedAccountActivity(asOfBlockCount blockCount: UInt64) -> AccountActivity? {
        logger.info("asOfBlockCount: \(blockCount)")
        guard blockCount <= knowableBlockCount else {
            logger.info("""
                error - blockCount: \(blockCount) > \
                knowableBlockCount: \(knowableBlockCount)
                """)
            return nil
        }
        let txOuts = allTxOutTrackers.compactMap { OwnedTxOut($0, atBlockCount: blockCount) }
        return AccountActivity(txOuts: txOuts, blockCount: blockCount)
    }

    var ownedTxOuts: [KnownTxOut] {
        ownedTxOutsAndBlockCount.txOuts
    }

    var ownedTxOutsAndBlockCount: (txOuts: [KnownTxOut], blockCount: UInt64) {
        let knowableBlockCount = self.knowableBlockCount
        let txOuts = allTxOutTrackers
            .filter { $0.received(asOfBlockCount: knowableBlockCount) }
            .map { $0.knownTxOut }
        return (txOuts: txOuts, blockCount: knowableBlockCount)
    }

    var unspentTxOuts: [KnownTxOut] {
        unspentTxOutsAndBlockCount.txOuts
    }

    var unspentTxOutsAndBlockCount: (txOuts: [KnownTxOut], blockCount: UInt64) {
        let knowableBlockCount = self.knowableBlockCount
        let txOuts = allTxOutTrackers
            .filter { $0.receivedAndUnspent(asOfBlockCount: knowableBlockCount) }
            .map { $0.knownTxOut }
        return (txOuts: txOuts, blockCount: knowableBlockCount)
    }

    func receivedAndUnspentTxOuts(atBlockCount blockCount: UInt64) -> [KnownTxOut]? {
        logger.info("atBlockCount: \(blockCount)")
        guard blockCount <= knowableBlockCount else {
            logger.info("""
                error - blockCount: \(blockCount) > \
                knowableBlockCount: \(knowableBlockCount)
                """)
            return nil
        }
        return allTxOutTrackers
            .filter { $0.receivedAndUnspent(asOfBlockCount: blockCount) }
            .map { $0.knownTxOut }
    }

    func addTxOuts(_ txOuts: [KnownTxOut]) {
        logger.info("txOuts: \(redacting: txOuts)")
        allTxOutTrackers.append(contentsOf: txOuts.map { TxOutTracker($0) })
    }

    func addViewKeyScanResults(scannedBlockRanges: [Range<UInt64>], foundTxOuts: [KnownTxOut]) {
        addTxOuts(foundTxOuts)
        fogView.markBlocksAsScanned(blockRanges: scannedBlockRanges)
    }

    func cachedReceivedStatus(of receipt: Receipt)
        -> Result<Receipt.ReceivedStatus, InvalidInputError>
    {
        logger.info("receipt.txOutPublicKey: \(redacting: receipt.txOutPublicKey)")
        return ownedTxOut(for: receipt).map {
            if let ownedTxOut = $0 {
                logger.info("received - txOut.publicKey: \(redacting: ownedTxOut.publicKey)")
                return .received(block: ownedTxOut.block)
            } else {
                let knownToBeNotReceivedBlockCount = allTxOutsFoundBlockCount
                guard receipt.txTombstoneBlockIndex > knownToBeNotReceivedBlockCount else {
                    logger.info("""
                        tombstone exceeded - receipt.txTombstoneBlockIndex: \
                        \(receipt.txTombstoneBlockIndex) > \
                        knownToBeNotReceivedBlockCount: \(knownToBeNotReceivedBlockCount)
                        """)
                    return .tombstoneExceeded
                }
                logger.info("""
                    not received - \
                    knownToBeNotReceivedBlockCount: \(knownToBeNotReceivedBlockCount)
                    """)
                return .notReceived(knownToBeNotReceivedBlockCount: knownToBeNotReceivedBlockCount)
            }
        }
    }

    /// Retrieves the `KnownTxOut`'s corresponding to `receipt` and verifies `receipt` is valid.
    private func ownedTxOut(for receipt: Receipt) -> Result<KnownTxOut?, InvalidInputError> {
        logger.info("""
            receipt.txOutPublicKey: \(redacting: receipt.txOutPublicKey), \
            account: \(redacting: accountKey.publicAddress)
            """)
        if let lastTxOut = ownedTxOuts.last {
            logger.info("Last received TxOut: Tx pubkey: \(redacting: lastTxOut.publicKey)")
        }

        // First check if we've received the TxOut (either from Fog View or from view key scanning).
        // This has the benefit of providing a guarantee that the TxOut is owned by this account.
        guard let ownedTxOut =
                ownedTxOuts.first(where: { $0.publicKey == receipt.txOutPublicKeyTyped })
        else {
            logger.info("success - txOut owned by this account")
            return .success(nil)
        }

        // Make sure the Receipt data matches the TxOut found in the ledger. This verifies that the
        // public key, commitment, and masked value match.
        //
        // Note: This doesn't verify the confirmation number or tombstone block (since neither are
        // saved to the ledger).
        guard receipt.matchesTxOut(ownedTxOut) else {
            logger.info("""
                failure - Receipt data doesn't match \
                the corresponding TxOut found in the ledger
                """)
            return .failure(InvalidInputError(
                "Receipt data doesn't match the corresponding TxOut found in the ledger."))
        }

        // Verify that the confirmation number validates for this account key. This provides a
        // guarantee that the sender of the Receipt was the creator of the TxOut that we received.
        guard receipt.validateConfirmationNumber(accountKey: accountKey) else {
            logger.info("""
                failure - receipt confirmation \
                number: \(redacting: receipt.confirmationNumber) is invalid \
                for this account
                """)
            return .failure(InvalidInputError("Receipt confirmation number is invalid."))
        }

        logger.info("success - txOut owned by this account")
        return .success(ownedTxOut)
    }
}

extension Account {
    /// - Returns: `.failure` if `accountKey` doesn't use Fog.
    static func make(accountKey: AccountKey) -> Result<Account, InvalidInputError> {
        logger.info("")
        guard let accountKey = AccountKeyWithFog(accountKey: accountKey) else {
            logger.info("failure - accounts without fog URLs are not currently supported")
            return .failure(InvalidInputError(
                "Accounts without fog URLs are not currently supported."))
        }

        logger.info("success - accountKey uses Fog")
        return .success(Account(accountKey: accountKey))
    }
}

extension Account: CustomRedactingStringConvertible {
    var redactingDescription: String {
        publicAddress.redactingDescription
    }
}

final class TxOutTracker {
    let knownTxOut: KnownTxOut

    var keyImageTracker: KeyImageSpentTracker

    init(_ knownTxOut: KnownTxOut) {
        logger.info("knownTxOut.publicKey: \(redacting: knownTxOut.publicKey)")
        self.knownTxOut = knownTxOut
        self.keyImageTracker = KeyImageSpentTracker(knownTxOut.keyImage)
    }

    var spentStatus: KeyImage.SpentStatus {
        keyImageTracker.spentStatus
    }

    var isSpent: Bool {
        keyImageTracker.isSpent
    }

    func receivedAndUnspent(asOfBlockCount blockCount: UInt64) -> Bool {
        logger.info("asOfBlockCount: \(blockCount)")
        return received(asOfBlockCount: blockCount) && !spent(asOfBlockCount: blockCount)
    }

    func received(asOfBlockCount blockCount: UInt64) -> Bool {
        logger.info("asOfBlockCount: \(blockCount)")
        return knownTxOut.block.index < blockCount
    }

    func spent(asOfBlockCount blockCount: UInt64) -> Bool {
        logger.info("asOfBlockCount: \(blockCount)")
        if case .spent = keyImageTracker.spentStatus.status(atBlockCount: blockCount) {
            return true
        }
        return false
    }

    func netValue(atBlockCount blockCount: UInt64) -> UInt64 {
        logger.info("asOfBlockCount: \(blockCount)")
        if receivedAndUnspent(asOfBlockCount: blockCount) {
            return knownTxOut.value
        } else {
            return 0
        }
    }
}

extension OwnedTxOut {
    fileprivate init?(_ txOutTracker: TxOutTracker, atBlockCount blockCount: UInt64) {
        logger.info("""
            txOut.publicKey: \(redacting: txOutTracker.knownTxOut.publicKey), \
            atBlockCount: \(blockCount)
            """)
        guard txOutTracker.knownTxOut.block.index < blockCount else {
            logger.info("knownTxout block index < blockCount")
            return nil
        }
        let receivedBlock = txOutTracker.knownTxOut.block

        let spentBlock: BlockMetadata?
        if case .spent(let block) = txOutTracker.spentStatus, block.index < blockCount {
            spentBlock = block
        } else {
            spentBlock = nil
        }

        self.init(txOutTracker.knownTxOut, receivedBlock: receivedBlock, spentBlock: spentBlock)
    }
}