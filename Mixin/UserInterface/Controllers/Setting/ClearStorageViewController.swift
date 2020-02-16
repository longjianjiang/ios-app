import UIKit
import MixinServices

class ClearStorageViewController: UITableViewController {

    @IBOutlet weak var photoCell: ModernSelectedBackgroundCell!
    @IBOutlet weak var videoCell: ModernSelectedBackgroundCell!
    @IBOutlet weak var audioCell: ModernSelectedBackgroundCell!
    @IBOutlet weak var fileCell: ModernSelectedBackgroundCell!
    @IBOutlet weak var photoCheckmark: CheckmarkView!
    @IBOutlet weak var videoCheckmark: CheckmarkView!
    @IBOutlet weak var audioCheckmark: CheckmarkView!
    @IBOutlet weak var fileCheckmark: CheckmarkView!
    @IBOutlet weak var photosLabel: UILabel!
    @IBOutlet weak var videosLabel: UILabel!
    @IBOutlet weak var audiosLabel: UILabel!
    @IBOutlet weak var filesLabel: UILabel!

    private var conversation: ConversationStorageUsage!
    private var isClearPhotos = true
    private var isClearVideos = true
    private var isClearAudios = true
    private var isClearFiles = true
    private var categorys = [String: ConversationCategoryStorage]()

    override func viewDidLoad() {
        super.viewDidLoad()

        tableView.tableFooterView = UIView()
        let conversationId = conversation.conversationId
        DispatchQueue.global().async { [weak self] in
            let categoryStorages = ConversationDAO.shared.getCategoryStorages(conversationId: conversationId)
            DispatchQueue.main.async {
                for categoryStorage in categoryStorages {
                    let mediaSize = categoryStorage.mediaSize
                    if categoryStorage.category.hasSuffix("_IMAGE") {
                        self?.categorys["_IMAGE"] = categoryStorage
                        self?.photosLabel.text = VideoMessageViewModel.byteCountFormatter.string(fromByteCount: mediaSize)
                    } else if categoryStorage.category.hasSuffix("_VIDEO") {
                        self?.categorys["_VIDEO"] = categoryStorage
                        self?.videosLabel.text = VideoMessageViewModel.byteCountFormatter.string(fromByteCount: mediaSize)
                    } else if categoryStorage.category.hasSuffix("_AUDIO") {
                        self?.categorys["_AUDIO"] = categoryStorage
                        self?.audiosLabel.text = VideoMessageViewModel.byteCountFormatter.string(fromByteCount: mediaSize)
                    } else if categoryStorage.category.hasSuffix("_DATA") {
                        self?.categorys["_DATA"] = categoryStorage
                        self?.filesLabel.text = VideoMessageViewModel.byteCountFormatter.string(fromByteCount: mediaSize)
                    }
                }

                self?.tableView.reloadData()
            }
        }
    }

    class func instance(conversation: ConversationStorageUsage) -> UIViewController {
        let vc = R.storyboard.setting.clear_storage()!
        vc.conversation = conversation
        let container = ContainerViewController.instance(viewController: vc, title: conversation.getConversationName())
        return container
    }

}

extension ClearStorageViewController: ContainerViewControllerDelegate {

    func prepareBar(rightButton: StateResponsiveButton) {
        rightButton.isEnabled = true
        rightButton.setTitleColor(.systemTint, for: .normal)
    }

    func barRightButtonTappedAction() {
        guard let rightButton = container?.rightButton, !rightButton.isBusy else {
            return
        }

        var messageCount = 0
        var size: Int64 = 0
        if isClearPhotos, let category = categorys["_IMAGE"] {
            messageCount += category.messageCount
            size += category.mediaSize
        }
        if isClearVideos, let category = categorys["_VIDEO"] {
            messageCount += category.messageCount
            size += category.mediaSize
        }
        if isClearAudios, let category = categorys["_AUDIO"] {
            messageCount += category.messageCount
            size += category.mediaSize
        }
        if isClearFiles, let category = categorys["_DATA"] {
            messageCount += category.messageCount
            size += category.mediaSize
        }

        let alc = UIAlertController(title: Localized.SETTING_STORAGE_USAGE_CLEAR(messageCount: messageCount, size: VideoMessageViewModel.byteCountFormatter.string(fromByteCount: size)), message: nil, preferredStyle: .actionSheet)
        alc.addAction(UIAlertAction(title: Localized.ACTION_CLEAR, style: .destructive, handler: { [weak self](_) in
            self?.clearAction()
        }))
        alc.addAction(UIAlertAction(title: Localized.DIALOG_BUTTON_CANCEL, style: .cancel, handler: nil))
        self.present(alc, animated: true, completion: nil)
    }

    private func clearAction() {
        let clearPhotos = isClearPhotos && categorys["_IMAGE"]?.messageCount ?? 0 > 0
        let clearVideos = isClearVideos && categorys["_VIDEO"]?.messageCount ?? 0 > 0
        let clearAudios = isClearAudios && categorys["_AUDIO"]?.messageCount ?? 0 > 0
        let clearFiles = isClearFiles && categorys["_DATA"]?.messageCount ?? 0 > 0
        container?.rightButton.isBusy = true
        DispatchQueue.global().async { [weak self] in
            var categories = [AttachmentContainer.Category]()
            if clearPhotos {
                categories.append(.photos)
            }
            if clearVideos {
                categories.append(.videos)
            }
            if clearAudios {
                categories.append(.audios)
            }
            if clearFiles {
                categories.append(.files)
            }
            self?.cleanUp(categories: categories)
            DispatchQueue.main.async {
                guard let weakSelf = self else {
                    return
                }
                NotificationCenter.default.post(name: .StorageUsageDidChange, object: nil)
                weakSelf.navigationController?.popViewController(animated: true)
            }
        }
    }
    
    private func cleanUp(categories: [AttachmentContainer.Category]) {
        let messageCategories = AttachmentContainer.getMessageCategories(categories: categories)
        AttachmentContainer.cleanUp(conversationId: conversation.conversationId, categories: messageCategories)
        MessageDAO.shared.deleteMessages(conversationId: conversation.conversationId, categories: messageCategories)
    }
    
    func textBarRightButton() -> String? {
        return Localized.ACTION_CLEAR
    }

}

extension ClearStorageViewController {

    override func tableView(_ tableView: UITableView, cellForRowAt indexPath: IndexPath) -> UITableViewCell {
        switch indexPath.row {
        case 0:
            photoCheckmark.status = isClearPhotos ? .selected : .unselected
            return photoCell
        case 1:
            videoCheckmark.status = isClearVideos ? .selected : .unselected
            return videoCell
        case 2:
            audioCheckmark.status = isClearAudios ? .selected : .unselected
            return audioCell
        case 3:
            fileCheckmark.status = isClearFiles ? .selected : .unselected
            return fileCell
        default:
            return UITableViewCell()
        }
    }

    override func tableView(_ tableView: UITableView, didSelectRowAt indexPath: IndexPath) {
        tableView.deselectRow(at: indexPath, animated: true)

        switch indexPath.row {
        case 0:
            isClearPhotos = !isClearPhotos
        case 1:
            isClearVideos = !isClearVideos
        case 2:
            isClearAudios = !isClearAudios
        case 3:
            isClearFiles = !isClearFiles
        default:
            break
        }
        tableView.reloadRows(at: [indexPath], with: .none)
        container?.rightButton.isEnabled = isClearPhotos || isClearVideos || isClearAudios || isClearFiles
    }

}
