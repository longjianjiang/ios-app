import Foundation
import CommonCrypto

enum MessageCryptor {
    
    enum Error: Swift.Error {
        case keyGeneration
        case ivGeneration
        case agreementCalculation
        case invalidAgreement
        case badCipher
    }
    
    private static let version = Data([0x01])
    private static let sessionSize = Data([0x01, 0x00])
    
    static func encrypt(_ message: Data, with privateKey: Ed25519PrivateKey, remotePublicKey: Data, remoteSessionID: UUID) throws -> Data {
        guard let key = Data(withNumberOfSecuredRandomBytes: kCCKeySizeAES128) else {
            throw Error.keyGeneration
        }
        guard let messageIV = Data(withNumberOfSecuredRandomBytes: 12) else {
            throw Error.ivGeneration
        }
        guard let messageKeyIV = Data(withNumberOfSecuredRandomBytes: 16) else {
            throw Error.ivGeneration
        }
        guard let sharedSecret = AgreementCalculator.agreement(fromPublicKeyData: remotePublicKey, privateKeyData: privateKey.x25519Representation) else {
            throw Error.agreementCalculation
        }
        let x25519PublicKey = privateKey.publicKey.x25519Representation
        let encryptedMessageKey = try AESCryptor.encrypt(key, with: sharedSecret, iv: messageKeyIV, padding: .pkcs7)
        let encryptedMessage = try AESGCMCryptor.encrypt(message, with: key, iv: messageIV)
        let cipher = version
            + sessionSize
            + x25519PublicKey
            + remoteSessionID.data
            + messageKeyIV
            + encryptedMessageKey
            + messageIV
            + encryptedMessage
        return cipher
    }
    
    static func decrypt(cipher: Data, with privateKey: Ed25519PrivateKey) throws -> Data {
        guard cipher.count > 111 else {
            throw Error.badCipher
        }
        
        let senderPublicKey = cipher[cipher.startIndex.advanced(by: 3)...cipher.startIndex.advanced(by: 34)]
        let sessionID = cipher[cipher.startIndex.advanced(by: 35)...cipher.startIndex.advanced(by: 50)]
        let messageKeyIV = cipher[cipher.startIndex.advanced(by: 51)...cipher.startIndex.advanced(by: 66)]
        let encryptedMessageKey = cipher[cipher.startIndex.advanced(by: 67)...cipher.startIndex.advanced(by: 98)]
        let messageIV = cipher[cipher.startIndex.advanced(by: 99)...cipher.startIndex.advanced(by: 110)]
        let encryptedMessage = cipher[cipher.startIndex.advanced(by: 111)...]
        
        guard let sharedSecret = AgreementCalculator.agreement(fromPublicKeyData: senderPublicKey, privateKeyData: privateKey.x25519Representation) else {
            throw Error.invalidAgreement
        }
        let key = try AESCryptor.decrypt(encryptedMessageKey, with: sharedSecret, iv: messageKeyIV)
        
        let decryptedMessage = try AESGCMCryptor.decrypt(encryptedMessage, with: key, iv: messageIV)
        return decryptedMessage
    }
    
}
