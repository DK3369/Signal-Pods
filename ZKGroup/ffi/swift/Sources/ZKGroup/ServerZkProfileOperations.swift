//
// Copyright (C) 2020 Signal Messenger, LLC.
// All rights reserved.
//
// SPDX-License-Identifier: GPL-3.0-only
//
// Generated by zkgroup/codegen/codegen.py - do not edit

import Foundation
import libzkgroup

public class ServerZkProfileOperations {

  let serverSecretParams: ServerSecretParams

  public init(serverSecretParams: ServerSecretParams) {
    self.serverSecretParams = serverSecretParams
  }

  public func issueProfileKeyCredential(profileKeyCredentialRequest: ProfileKeyCredentialRequest, uuid: ZKGUuid, profileKeyCommitment: ProfileKeyCommitment) throws  -> ProfileKeyCredentialResponse {
    var randomness: [UInt8] = Array(repeating: 0, count: Int(32))
    let result = SecRandomCopyBytes(kSecRandomDefault, randomness.count, &randomness)
    guard result == errSecSuccess else {
      throw ZkGroupException.AssertionError
    }

    return try issueProfileKeyCredential(randomness: randomness, profileKeyCredentialRequest: profileKeyCredentialRequest, uuid: uuid, profileKeyCommitment: profileKeyCommitment)
  }

  public func issueProfileKeyCredential(randomness: [UInt8], profileKeyCredentialRequest: ProfileKeyCredentialRequest, uuid: ZKGUuid, profileKeyCommitment: ProfileKeyCommitment) throws  -> ProfileKeyCredentialResponse {
    var newContents: [UInt8] = Array(repeating: 0, count: ProfileKeyCredentialResponse.SIZE)

    let ffi_return = FFI_ServerSecretParams_issueProfileKeyCredentialDeterministic(serverSecretParams.getInternalContentsForFFI(), UInt32(serverSecretParams.getInternalContentsForFFI().count), randomness, UInt32(randomness.count), profileKeyCredentialRequest.getInternalContentsForFFI(), UInt32(profileKeyCredentialRequest.getInternalContentsForFFI().count), uuid.getInternalContentsForFFI(), UInt32(uuid.getInternalContentsForFFI().count), profileKeyCommitment.getInternalContentsForFFI(), UInt32(profileKeyCommitment.getInternalContentsForFFI().count), &newContents, UInt32(newContents.count))
    if (ffi_return == Native.FFI_RETURN_INPUT_ERROR) {
      throw ZkGroupException.VerificationFailed
    }

    if (ffi_return != Native.FFI_RETURN_OK) {
      throw ZkGroupException.ZkGroupError
    }

    do {
      return try ProfileKeyCredentialResponse(contents: newContents)
    } catch ZkGroupException.InvalidInput {
      throw ZkGroupException.AssertionError
    }

  }

  public func verifyProfileKeyCredentialPresentation(groupPublicParams: GroupPublicParams, profileKeyCredentialPresentation: ProfileKeyCredentialPresentation) throws {
    let ffi_return = FFI_ServerSecretParams_verifyProfileKeyCredentialPresentation(serverSecretParams.getInternalContentsForFFI(), UInt32(serverSecretParams.getInternalContentsForFFI().count), groupPublicParams.getInternalContentsForFFI(), UInt32(groupPublicParams.getInternalContentsForFFI().count), profileKeyCredentialPresentation.getInternalContentsForFFI(), UInt32(profileKeyCredentialPresentation.getInternalContentsForFFI().count))
    if (ffi_return == Native.FFI_RETURN_INPUT_ERROR) {
      throw ZkGroupException.VerificationFailed
    }

    if (ffi_return != Native.FFI_RETURN_OK) {
      throw ZkGroupException.ZkGroupError
    }
  }

}
