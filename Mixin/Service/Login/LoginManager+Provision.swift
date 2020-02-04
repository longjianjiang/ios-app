import Foundation
import MixinServices

extension LoginManager {
    
    func updateProvision(id: String, base64EncodedPublicKey: String, completion: @escaping (Bool) -> Void) {
        
        func alert(_ str: String) {
            AppDelegate.current.window.rootViewController?.alert(str)
        }
        
        guard let identityKeyPair = try? PreKeyUtil.getIdentityKeyPair() else {
            return
        }
        ProvisioningAPI.shared.code { (response) in
            switch response {
            case .success(let response):
                guard let account = LoginManager.shared.account else {
                    return
                }
                let cryptor = MXNProvisionCryptor(signalContext: globalSignalContext,
                                                  base64EncodedPublicKey: base64EncodedPublicKey)
                let message = ProvisionMessage(identityKeyPublic: identityKeyPair.publicKey,
                                               identityKeyPrivate: identityKeyPair.privateKey,
                                               userId: account.user_id,
                                               sessionId: account.session_id,
                                               provisioningCode: response.code)
                guard let secretData = cryptor.encryptedData(from: message) else {
                    completion(false)
                    return
                }
                let secret = secretData.base64EncodedString()
                ProvisioningAPI.shared.update(id: id, secret: secret, completion: { (result) in
                    switch result {
                    case .success:
                        completion(true)
                    case .failure(let error):
                        alert(error.localizedDescription)
                        completion(false)
                    }
                })
            case .failure(let error):
                alert(error.localizedDescription)
                completion(false)
            }
        }
    }
    
}