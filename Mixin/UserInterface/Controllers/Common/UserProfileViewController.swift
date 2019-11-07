import UIKit

final class UserProfileViewController: ProfileViewController {
    
    override var conversationId: String {
        return ConversationDAO.shared.makeConversationId(userId: AccountAPI.shared.accountUserId, ownerUserId: user.userId)
    }
    
    override var isMuted: Bool {
        return user.isMuted
    }
    
    private lazy var imagePicker = ImagePickerController(initialCameraPosition: .front, cropImageAfterPicked: true, parent: self, delegate: self)
    
    private var isMe = false
    private var relationship = Relationship.ME
    private var developer: UserItem?
    private var user: UserItem! {
        didSet {
            isMe = user.userId == AccountAPI.shared.accountUserId
            relationship = Relationship(rawValue: user.relationship) ?? .ME
            updateDeveloper()
        }
    }
    
    init(user: UserItem) {
        super.init(nibName: R.nib.profileView.name, bundle: R.nib.profileView.bundle)
        modalPresentationStyle = .custom
        transitioningDelegate = PopupPresentationManager.shared
        defer {
            // Defer closure escapes from subclass init
            // Make sure user's didSet is called
            self.user = user
        }
    }
    
    required init?(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    override func viewDidLoad() {
        size = isMe ? .unavailable : .compressed
        super.viewDidLoad()
        reloadData()
    }
    
    override func updateMuteInterval(inSeconds interval: Int64) {
        let userId = user.userId
        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.window)
        ConversationAPI.shared.mute(userId: userId, duration: interval) { [weak self] (result) in
            switch result {
            case let .success(response):
                self?.user.muteUntil = response.muteUntil
                self?.reloadData()
                UserDAO.shared.updateNotificationEnabled(userId: userId, muteUntil: response.muteUntil)
                let toastMessage: String
                if interval == MuteInterval.none {
                    toastMessage = Localized.PROFILE_TOAST_UNMUTED
                } else {
                    let dateRepresentation = DateFormatter.dateSimple.string(from: response.muteUntil.toUTCDate())
                    toastMessage = Localized.PROFILE_TOAST_MUTED(muteUntil: dateRepresentation)
                }
                hud.set(style: .notification, text: toastMessage)
            case let .failure(error):
                hud.set(style: .error, text: error.localizedDescription)
            }
            hud.scheduleAutoHidden()
        }
    }
    
}

// MARK: - Actions
extension UserProfileViewController {
    
    @objc func addContact() {
        relationshipView.isBusy = true
        UserAPI.shared.addFriend(userId: user.userId, full_name: user.fullName) { [weak self] (result) in
            switch result {
            case let .success(response):
                self?.handle(userResponse: response, postContactDidChangeNotificationOnSuccess: true)
            case let .failure(error):
                showAutoHiddenHud(style: .error, text: error.localizedDescription)
            }
            self?.relationshipView.isBusy = false
        }
    }
    
    @objc func sendMessage() {
        guard let navigationController = UIApplication.homeNavigationController else {
            return
        }
        if let vc = navigationController.viewControllers.last as? ConversationViewController, vc.dataSource?.category == .contact && vc.dataSource?.conversation.ownerId == user.userId {
            dismiss(animated: true, completion: nil)
            return
        }
        let vc = ConversationViewController.instance(ownerUser: user)
        dismissAndPush(vc)
    }
    
    @objc func showMyQrCode() {
        guard let account = AccountAPI.shared.account else {
            return
        }
        dismiss(animated: true) {
            let window = QrcodeWindow.instance()
            window.render(title: Localized.CONTACT_MY_QR_CODE,
                          description: Localized.MYQRCODE_PROMPT,
                          account: account)
            window.presentView()
        }
    }
    
    @objc func showMyMoneyReceivingCode() {
        guard let account = AccountAPI.shared.account else {
            return
        }
        dismiss(animated: true) {
            let window = QrcodeWindow.instance()
            window.renderMoneyReceivingCode(account: account)
            window.presentView()
        }
    }
    
    @objc func changeAvatarWithCamera() {
        imagePicker.presentCamera()
    }
    
    @objc func changeAvatarWithLibrary() {
        imagePicker.presentPhoto()
    }
    
    @objc func editMyName() {
        presentEditNameController(title: R.string.localizable.profile_edit_name(), text: user.fullName, placeholder: R.string.localizable.profile_full_name()) { [weak self] (name) in
            let hud = Hud()
            hud.show(style: .busy, text: "", on: AppDelegate.current.window)
            AccountAPI.shared.update(fullName: name) { (result) in
                switch result {
                case let .success(account):
                    AccountAPI.shared.updateAccount(account: account)
                    if let self = self {
                        self.user = UserItem.createUser(from: account)
                        self.reloadData()
                    }
                    hud.set(style: .notification, text: Localized.TOAST_CHANGED)
                case let .failure(error):
                    hud.set(style: .error, text: error.localizedDescription)
                }
                hud.scheduleAutoHidden()
            }
        }
    }
    
    @objc func editMyBiography() {
        let vc = BiographyViewController.instance(user: user)
        dismissAndPush(vc)
    }
    
    @objc func changeNumber() {
        if AccountAPI.shared.account?.has_pin ?? false {
            let vc = VerifyPinNavigationController(rootViewController: ChangeNumberVerifyPinViewController())
            dismissAndPresent(vc)
        } else {
            let vc = WalletPasswordViewController.instance(dismissTarget: .changePhone)
            dismissAndPush(vc)
        }
    }
    
    @objc func openApp() {
        let userId = user.userId
        dismiss(animated: true) {
            guard let parent = UIApplication.homeNavigationController?.visibleViewController else {
                return
            }
            let conversationId: String
            if let vc = UIApplication.homeNavigationController?.viewControllers.last as? ConversationViewController {
                conversationId = vc.conversationId
            } else {
                conversationId = self.conversationId
            }
            DispatchQueue.global().async {
                guard let app = AppDAO.shared.getApp(ofUserId: userId) else {
                    return
                }
                DispatchQueue.main.async {
                    WebViewController.presentInstance(with: .init(conversationId: conversationId, app: app), asChildOf: parent)
                }
                UIApplication.logEvent(eventName: "open_app", parameters: ["source": "UserWindow", "identityNumber": app.appNumber])
            }
        }
    }
    
    @objc func transfer() {
        let viewController: UIViewController
        if AccountAPI.shared.account?.has_pin ?? false {
            viewController = TransferOutViewController.instance(asset: nil, type: .contact(user))
        } else {
            viewController = WalletPasswordViewController.instance(dismissTarget: .transfer(user: user))
        }
        dismissAndPush(viewController)
    }
    
    @objc func editAlias() {
        let userId = user.userId
        presentEditNameController(title: R.string.localizable.profile_edit_name(), text: user.fullName, placeholder: R.string.localizable.profile_full_name()) { [weak self] (name) in
            let hud = Hud()
            hud.show(style: .busy, text: "", on: AppDelegate.current.window)
            UserAPI.shared.remarkFriend(userId: userId, full_name: name) { [weak self] (result) in
                switch result {
                case let .success(response):
                    self?.handle(userResponse: response, postContactDidChangeNotificationOnSuccess: false)
                    hud.set(style: .notification, text: Localized.TOAST_CHANGED)
                case let .failure(error):
                    hud.set(style: .error, text: error.localizedDescription)
                }
                hud.scheduleAutoHidden()
            }
        }
    }
    
    @objc func showDeveloper() {
        guard let developer = developer else {
            return
        }
        let vc = UserProfileViewController(user: user)
        if user.appCreatorId == AccountAPI.shared.accountUserId, let account = AccountAPI.shared.account {
            vc.user = UserItem.createUser(from: account)
        } else {
            vc.user = developer
        }
        dismissAndPresent(vc)
    }
    
    @objc func shareUser() {
        let vc = MessageReceiverViewController.instance(content: .contact(user.userId))
        dismissAndPush(vc)
    }
    
    @objc func searchConversation() {
        let vc = InConversationSearchViewController()
        vc.load(user: user, conversationId: conversationId)
        let container = ContainerViewController.instance(viewController: vc, title: user.fullName)
        dismissAndPush(container)
    }
    
    @objc func showSharedMedia() {
        let vc = R.storyboard.chat.shared_media()!
        vc.conversationId = conversationId
        let container = ContainerViewController.instance(viewController: vc, title: R.string.localizable.chat_shared_media())
        dismissAndPush(container)
    }
    
    @objc func showTransactions() {
        let vc = PeerTransactionsViewController.instance(opponentId: user.userId)
        dismissAndPush(vc)
    }
    
    @objc func removeFriend() {
        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.window)
        UserAPI.shared.removeFriend(userId: user.userId, completion: { [weak self] (result) in
            switch result {
            case let .success(response):
                self?.handle(userResponse: response, postContactDidChangeNotificationOnSuccess: true)
                hud.set(style: .notification, text: Localized.TOAST_CHANGED)
            case let .failure(error):
                hud.set(style: .error, text: error.localizedDescription)
            }
            hud.scheduleAutoHidden()
        })
    }
    
    @objc func blockUser() {
        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.window)
        UserAPI.shared.blockUser(userId: user.userId) { [weak self] (result) in
            switch result {
            case let .success(response):
                self?.handle(userResponse: response, postContactDidChangeNotificationOnSuccess: false)
                hud.set(style: .notification, text: Localized.TOAST_CHANGED)
            case let .failure(error):
                hud.set(style: .error, text: error.localizedDescription)
            }
            hud.scheduleAutoHidden()
        }
    }
    
    @objc func unblockUser() {
        let hud = Hud()
        hud.show(style: .busy, text: "", on: AppDelegate.current.window)
        UserAPI.shared.unblockUser(userId: user.userId) { [weak self] (result) in
            switch result {
            case let .success(response):
                self?.handle(userResponse: response, postContactDidChangeNotificationOnSuccess: false)
                hud.set(style: .notification, text: Localized.TOAST_CHANGED)
            case let .failure(error):
                hud.set(style: .error, text: error.localizedDescription)
            }
            hud.scheduleAutoHidden()
        }
        
    }
    
    @objc func reportUser() {
        let userId = user.userId
        let conversationId = self.conversationId
        let alert = UIAlertController(title: R.string.localizable.profile_report_tips(), message: nil, preferredStyle: .alert)
        alert.addAction(UIAlertAction(title: Localized.DIALOG_BUTTON_CANCEL, style: .cancel, handler: nil))
        alert.addAction(UIAlertAction(title: R.string.localizable.profile_report(), style: .destructive, handler: { (_) in
            let hud = Hud()
            hud.show(style: .busy, text: "", on: AppDelegate.current.window)
            DispatchQueue.global().async {
                switch UserAPI.shared.reportUser(userId: userId) {
                case let .success(user):
                    UserDAO.shared.updateUsers(users: [user], sendNotificationAfterFinished: false)
                case let .failure(error):
                    showAutoHiddenHud(style: .error, text: error.localizedDescription)
                }
                ConversationDAO.shared.deleteConversationAndMessages(conversationId: conversationId)
                MixinFile.cleanAllChatDirectories()
                NotificationCenter.default.afterPostOnMain(name: .ConversationDidChange, object: nil)
                DispatchQueue.main.async {
                    UIApplication.homeNavigationController?.backToHome()
                }
            }
        }))
        present(alert, animated: true, completion: nil)
    }
    
}

extension UserProfileViewController: ImagePickerControllerDelegate {
    
    func imagePickerController(_ controller: ImagePickerController, didPickImage image: UIImage) {
        guard let avatarBase64 = image.scaledToSize(newSize: CGSize(width: 1024, height: 1024)).base64 else {
            alert(Localized.CONTACT_ERROR_COMPOSE_AVATAR)
            return
        }
        let hud = Hud()
        hud.show(style: .busy, text: "", on: view)
        AccountAPI.shared.update(fullName: nil, avatarBase64: avatarBase64, completion: { (result) in
            switch result {
            case let .success(account):
                AccountAPI.shared.updateAccount(account: account)
                hud.set(style: .notification, text: Localized.TOAST_CHANGED)
            case let .failure(error):
                hud.set(style: .error, text: error.localizedDescription)
            }
            hud.scheduleAutoHidden()
        })
    }
    
}

// MARK: - Private works
extension UserProfileViewController {
    
    private func reloadData() {
        for view in centerStackView.subviews {
            view.removeFromSuperview()
        }
        for view in menuStackView.subviews {
            view.removeFromSuperview()
        }
        
        avatarImageView.setImage(with: user)
        titleLabel.text = user.fullName
        subtitleLabel.identityNumber = user.identityNumber
        
        if user.isVerified {
            badgeImageView.image = R.image.ic_user_verified()
            badgeImageView.isHidden = false
        } else if user.isBot {
            badgeImageView.image = R.image.ic_user_bot()
            badgeImageView.isHidden = false
        } else {
            badgeImageView.isHidden = true
        }
        
        switch relationship {
        case .ME, .FRIEND:
            break
        case .STRANGER:
            relationshipView.style = .addContact
            relationshipView.button.removeTarget(nil, action: nil, for: .allEvents)
            relationshipView.button.addTarget(self, action: #selector(addContact), for: .touchUpInside)
            centerStackView.addArrangedSubview(relationshipView)
        case .BLOCKING:
            relationshipView.style = .unblock
            relationshipView.button.removeTarget(nil, action: nil, for: .allEvents)
            relationshipView.button.addTarget(self, action: #selector(unblockUser), for: .touchUpInside)
            centerStackView.addArrangedSubview(relationshipView)
        }
        
        if !user.biography.isEmpty {
            descriptionView.label.text = user.biography
            centerStackView.addArrangedSubview(descriptionView)
        }
        
        if !isMe {
            if user.isBot {
                shortcutView.leftShortcutButton.setImage(R.image.ic_open_app(), for: .normal)
                shortcutView.leftShortcutButton.removeTarget(nil, action: nil, for: .allEvents)
                shortcutView.leftShortcutButton.addTarget(self, action: #selector(openApp), for: .touchUpInside)
            } else {
                shortcutView.leftShortcutButton.setImage(R.image.ic_transfer(), for: .normal)
                shortcutView.leftShortcutButton.removeTarget(nil, action: nil, for: .allEvents)
                shortcutView.leftShortcutButton.addTarget(self, action: #selector(transfer), for: .touchUpInside)
            }
            shortcutView.sendMessageButton.removeTarget(nil, action: nil, for: .allEvents)
            shortcutView.sendMessageButton.addTarget(self, action: #selector(sendMessage), for: .touchUpInside)
            shortcutView.toggleSizeButton.removeTarget(nil, action: nil, for: .allEvents)
            shortcutView.toggleSizeButton.addTarget(self, action: #selector(toggleSize), for: .touchUpInside)
            centerStackView.addArrangedSubview(shortcutView)
        }
        
        if centerStackView.arrangedSubviews.isEmpty {
            menuStackViewTopConstraint.constant = 24
        } else {
            menuStackViewTopConstraint.constant = 0
        }
        
        if isMe {
            menuItemGroups = [
                [ProfileMenuItem(title: R.string.localizable.profile_my_qrcode(),
                                 subtitle: nil,
                                 style: [],
                                 action: #selector(showMyQrCode)),
                 ProfileMenuItem(title: R.string.localizable.contact_receive_money(),
                                 subtitle: nil,
                                 style: [.accessoryDisclosure],
                                 action: #selector(showMyMoneyReceivingCode))],
                [ProfileMenuItem(title: R.string.localizable.profile_edit_name(),
                                 subtitle: nil,
                                 style: [],
                                 action: #selector(editMyName)),
                 ProfileMenuItem(title: R.string.localizable.profile_edit_biography(),
                                 subtitle: nil,
                                 style: [.accessoryDisclosure],
                                 action: #selector(editMyBiography))],
                [ProfileMenuItem(title: R.string.localizable.profile_change_avatar_camera(),
                                 subtitle: nil,
                                 style: [.accessoryDisclosure],
                                 action: #selector(changeAvatarWithCamera)),
                 ProfileMenuItem(title: R.string.localizable.profile_change_avatar_library(),
                                 subtitle: nil,
                                 style: [.accessoryDisclosure],
                                 action: #selector(changeAvatarWithLibrary))],
                [ProfileMenuItem(title: R.string.localizable.profile_change_number(),
                                 subtitle: nil,
                                 style: [],
                                 action: #selector(changeNumber))]
            ]
        } else {
            var groups = [[ProfileMenuItem]]()
            
            let shareUserItem = ProfileMenuItem(title: R.string.localizable.profile_share_card(),
                                                subtitle: nil,
                                                style: [.accessoryDisclosure],
                                                action: #selector(shareUser))
            groups.append([shareUserItem])
            
            let sharedMediaAndSearchGroup = [
                ProfileMenuItem(title: R.string.localizable.chat_shared_media(),
                                subtitle: nil,
                                style: [.accessoryDisclosure],
                                action: #selector(showSharedMedia)),
                ProfileMenuItem(title: R.string.localizable.profile_search_conversation(),
                                subtitle: nil,
                                style: [.accessoryDisclosure],
                                action: #selector(searchConversation))
            ]
            groups.append(sharedMediaAndSearchGroup)
            
            let muteAndTransactionGroup: [ProfileMenuItem] = {
                var group: [ProfileMenuItem]
                if user.isMuted {
                    let subtitle: String?
                    if let date = user.muteUntil?.toUTCDate() {
                        let rep = DateFormatter.log.string(from: date)
                        subtitle = R.string.localizable.profile_mute_ends_at(rep)
                    } else {
                        subtitle = nil
                    }
                    group = [ProfileMenuItem(title: R.string.localizable.profile_muted(),
                                             subtitle: subtitle,
                                             style: [],
                                             action: #selector(mute))]
                } else {
                    group = [ProfileMenuItem(title: R.string.localizable.profile_mute(),
                                             subtitle: nil,
                                             style: [],
                                             action: #selector(mute))]
                }
                group.append(ProfileMenuItem(title: R.string.localizable.profile_transactions(),
                                             subtitle: nil,
                                             style: [.accessoryDisclosure],
                                             action: #selector(showTransactions)))
                return group
            }()
            groups.append(muteAndTransactionGroup)
            
            let editAliasAndBotRelatedGroup: [ProfileMenuItem] = {
                var group = [ProfileMenuItem]()
                if relationship == .FRIEND {
                    group.append(ProfileMenuItem(title: R.string.localizable.profile_edit_name(),
                                                 subtitle: nil,
                                                 style: [],
                                                 action: #selector(editAlias)))
                }
                if user.isBot {
                    if user.isSelfBot {
                        group.append(ProfileMenuItem(title: R.string.localizable.chat_menu_transfer(),
                                                     subtitle: nil,
                                                     style: [],
                                                     action: #selector(transfer)))
                    } else {
                        group.append(ProfileMenuItem(title: R.string.localizable.chat_menu_developer(),
                                                     subtitle: nil,
                                                     style: [],
                                                     action: #selector(showDeveloper)))
                    }
                }
                return group
            }()
            if !editAliasAndBotRelatedGroup.isEmpty {
                groups.append(editAliasAndBotRelatedGroup)
            }
            
            let contactRelationshipGroup: [ProfileMenuItem] = {
                var group: [ProfileMenuItem]
                switch relationship {
                case .ME:
                    group = []
                case .FRIEND:
                    group = [ProfileMenuItem(title: R.string.localizable.profile_remove(),
                                             subtitle: nil,
                                             style: [.destructive],
                                             action: #selector(removeFriend))]
                case .STRANGER:
                    group = [ProfileMenuItem(title: R.string.localizable.profile_block(),
                                             subtitle: nil,
                                             style: [.destructive],
                                             action: #selector(blockUser))]
                case .BLOCKING:
                    group = [ProfileMenuItem(title: R.string.localizable.profile_unblock(),
                                             subtitle: nil,
                                             style: [],
                                             action: #selector(unblockUser))]
                }
                group.append(ProfileMenuItem(title: R.string.localizable.group_menu_clear(),
                                             subtitle: nil,
                                             style: [.destructive],
                                             action: #selector(clearChat)))
                return group
            }()
            groups.append(contactRelationshipGroup)
            
            let reportItem = ProfileMenuItem(title: R.string.localizable.profile_report(),
                                             subtitle: nil,
                                             style: [.destructive],
                                             action: #selector(reportUser))
            groups.append([reportItem])
            
            menuItemGroups = groups
        }
        
        updatePreferredContentSizeHeight()
    }
    
    private func handle(userResponse: UserResponse, postContactDidChangeNotificationOnSuccess: Bool) {
        user = UserItem.createUser(from: userResponse)
        reloadData()
        UserDAO.shared.updateUsers(users: [userResponse], notifyContact: postContactDidChangeNotificationOnSuccess)
    }
    
    private func updateDeveloper() {
        guard let creatorId = user.appCreatorId else {
            developer = nil
            return
        }
        DispatchQueue.global().async { [weak self] in
            var developer = UserDAO.shared.getUser(userId: creatorId)
            if developer == nil {
                switch UserAPI.shared.showUser(userId: creatorId) {
                case let .success(user):
                    UserDAO.shared.updateUsers(users: [user], sendNotificationAfterFinished: false)
                    developer = UserItem.createUser(from: user)
                case let .failure(error):
                    showAutoHiddenHud(style: .error, text: error.localizedDescription)
                }
            }
            self?.developer = developer
        }
    }
    
}
