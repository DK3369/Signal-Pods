//
//  Copyright (c) 2020 MobileCoin. All rights reserved.
//

import Foundation
import LibMobileCoin

struct TxOutMembershipProof {
    let serializedData: Data

    /// - Returns: `nil` when the input is not deserializable.
    init?(serializedData: Data) {
        self.serializedData = serializedData
    }
}

extension TxOutMembershipProof: Equatable {}
extension TxOutMembershipProof: Hashable {}

extension TxOutMembershipProof {
    init?(_ txOutMembershipProof: External_TxOutMembershipProof) {
        let serializedData: Data
        do {
            serializedData = try txOutMembershipProof.serializedData()
        } catch {
            // Safety: Protobuf binary serialization is no fail when not using proto2 or `Any`
            fatalError("Error: \(Self.self).\(#function): Protobuf serialization failed: \(error)")
        }
        self.init(serializedData: serializedData)
    }
}
