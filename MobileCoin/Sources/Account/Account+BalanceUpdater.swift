//
//  Copyright (c) 2020-2021 MobileCoin. All rights reserved.
//

import Foundation
import LibMobileCoin

extension Account {
    struct BalanceUpdater {
        private let account: ReadWriteDispatchLock<Account>
        private let txOutFetcher: FogView.TxOutFetcher
        private let viewKeyScanner: FogViewKeyScanner
        private let fogKeyImageChecker: FogKeyImageChecker

        init(
            account: ReadWriteDispatchLock<Account>,
            fogViewService: FogViewService,
            fogKeyImageService: FogKeyImageService,
            fogBlockService: FogBlockService,
            fogQueryScalingStrategy: FogQueryScalingStrategy,
            targetQueue: DispatchQueue?
        ) {
            logger.info("")
            self.account = account
            self.txOutFetcher = FogView.TxOutFetcher(
                fogView: account.mapLockWithoutLocking { $0.fogView },
                accountKey: account.accessWithoutLocking.accountKey,
                fogViewService: fogViewService,
                fogQueryScalingStrategy: fogQueryScalingStrategy,
                targetQueue: targetQueue)
            self.viewKeyScanner = FogViewKeyScanner(
                accountKey: account.accessWithoutLocking.accountKey,
                fogBlockService: fogBlockService)
            self.fogKeyImageChecker = FogKeyImageChecker(
                fogKeyImageService: fogKeyImageService,
                targetQueue: targetQueue)
        }

        func updateBalance(completion: @escaping (Result<Balance, ConnectionError>) -> Void) {
            logger.info("")
            checkForNewTxOuts {
                guard $0.successOr(completion: completion) != nil else {
                    logger.info("failure")
                    return
                }

                self.viewKeyScanUnscannedMissedBlocks {
                    guard $0.successOr(completion: completion) != nil else {
                        logger.info("failure")
                        return
                    }

                    logger.info("checking for spent txOuts")
                    self.checkForSpentTxOuts {
                        completion($0.map {
                            self.account.readSync { $0.cachedBalance }
                        })
                    }
                }
            }
        }

        func checkForNewTxOuts(completion: @escaping (Result<(), ConnectionError>) -> Void) {
            logger.info("")
            txOutFetcher.fetchTxOuts(partialResultsWithWriteLock: { newTxOuts in
                let account = self.account.accessWithoutLocking
                account.addTxOuts(newTxOuts)
            }, completion: completion)
        }

        func viewKeyScanUnscannedMissedBlocks(
            completion: @escaping (Result<(), ConnectionError>) -> Void
        ) {
            logger.info("")
            let unscannedBlockRanges = account.readSync { $0.unscannedMissedBlocksRanges }
            viewKeyScanner.viewKeyScanBlocks(blockRanges: unscannedBlockRanges) {
                completion($0.map { foundTxOuts in
                    self.account.writeSync {
                        $0.addViewKeyScanResults(
                            scannedBlockRanges: unscannedBlockRanges,
                            foundTxOuts: foundTxOuts)
                    }
                })
            }
        }

        func checkForSpentTxOuts(completion: @escaping (Result<(), ConnectionError>) -> Void) {
            logger.info("")
            let keyImageTrackers = account.mapLock { account in
                account.allTxOutTrackers.filter { !$0.isSpent }.map { $0.keyImageTracker }
            }
            let queries = keyImageTrackers.readSync {
                $0.map { ($0.keyImage, $0.nextKeyImageQueryBlockIndex) }
            }
            fogKeyImageChecker.checkKeyImages(keyImageQueries: queries) {
                completion($0.map { statuses in
                    keyImageTrackers.writeSync { keyImageTrackers in
                        for (tracker, status) in zip(keyImageTrackers, statuses) {
                            tracker.spentStatus = status
                        }
                    }
                })
            }
        }
    }
}