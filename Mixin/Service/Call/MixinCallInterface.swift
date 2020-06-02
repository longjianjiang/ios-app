import UIKit
import AVFoundation
import UserNotifications
import CallKit
import WebRTC
import MixinServices

class MixinCallInterface {
    
    private let callObserver = CXCallObserver()
    
    private lazy var vibrator = Vibrator()
    private unowned var service: CallService!
    
    private var pendingIncomingUuid: UUID?
    
    private var isLineIdle: Bool {
        service.activeCall == nil && callObserver.calls.isEmpty
    }
    
    required init(manager: CallService) {
        self.service = manager
    }
    
    private func requestRecordPermission(completion: @escaping (Bool) -> Void) {
        let session = AVAudioSession.sharedInstance()
        switch session.recordPermission {
        case .undetermined:
            session.requestRecordPermission { (granted) in
                completion(granted)
            }
        case .denied:
            completion(false)
        case .granted:
            completion(true)
        @unknown default:
            completion(false)
        }
    }
    
}

extension MixinCallInterface: CallInterface {
    
    func requestStartCall(uuid: UUID, handle: CallHandle, completion: @escaping CallInterfaceCompletion) {
        guard WebSocketService.shared.isConnected else {
            completion(CallError.networkFailure)
            return
        }
        guard isLineIdle else {
            completion(CallError.busy)
            return
        }
        requestRecordPermission { (granted) in
            if granted {
                self.service.startCall(uuid: uuid, handle: handle, completion: { success in
                    guard success else {
                        return
                    }
                    RTCDispatcher.dispatchAsync(on: .typeAudioSession) {
                        try? RTCAudioSession.sharedInstance().setActive(true)
                        self.service.ringtonePlayer.play(ringtone: .outgoing)
                    }
                })
                completion(nil)
            } else {
                completion(CallError.microphonePermissionDenied)
            }
        }
    }
    
    func requestAnswerCall(uuid: UUID) {
        vibrator.stop()
        service.answerCall(uuid: uuid, completion: nil)
    }
    
    func requestEndCall(uuid: UUID, completion: @escaping CallInterfaceCompletion) {
        vibrator.stop()
        if uuid == pendingIncomingUuid {
            pendingIncomingUuid = nil
        }
        UNUserNotificationCenter.current().removeNotifications(withIdentifiers: [uuid.uuidString])
        service.endCall(uuid: uuid)
        completion(nil)
    }
    
    func requestSetMute(uuid: UUID, muted: Bool, completion: @escaping CallInterfaceCompletion) {
        service.isMuted = muted
        completion(nil)
    }
    
    func reportIncomingCall(_ call: Call, completion: @escaping CallInterfaceCompletion) {
        guard isLineIdle else {
            completion(CallError.busy)
            return
        }
        requestRecordPermission { (granted) in
            guard granted else {
                completion(CallError.microphonePermissionDenied)
                return
            }
            if self.pendingIncomingUuid == nil {
                DispatchQueue.main.sync {
                    if UIApplication.shared.applicationState == .active {
                        self.service.ringtonePlayer.play(ringtone: .incoming)
                    } else {
                        NotificationManager.shared.requestCallNotification(messageId: call.uuidString, callerName: call.opponentUsername)
                    }
                    self.vibrator.start()
                    if let user = call.opponentUser {
                        self.service.showCallingInterface(user: user,
                                                          style: .incoming)
                    } else {
                        self.service.showCallingInterface(userId: call.opponentUserId,
                                                          username: call.opponentUsername,
                                                          style: .incoming)
                    }
                }
                self.pendingIncomingUuid = call.uuid
                completion(nil)
            } else {
                completion(CallError.busy)
            }
        }
    }
    
    func reportCall(uuid: UUID, endedByReason reason: CXCallEndedReason) {
        vibrator.stop()
        if uuid == pendingIncomingUuid {
            pendingIncomingUuid = nil
        }
        UNUserNotificationCenter.current().removeNotifications(withIdentifiers: [uuid.uuidString])
    }
    
    func reportOutgoingCallStartedConnecting(uuid: UUID) {
        if uuid == pendingIncomingUuid {
            pendingIncomingUuid = nil
        }
    }
    
    func reportOutgoingCall(uuid: UUID, connectedAtDate date: Date) {
        
    }
    
    func reportIncomingCall(uuid: UUID, connectedAtDate date: Date) {
        
    }
    
}
