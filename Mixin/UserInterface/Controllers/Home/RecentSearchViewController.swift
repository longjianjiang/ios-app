import UIKit
import MixinServices
import AlignedCollectionViewFlowLayout

class RecentSearchViewController: UIViewController {
    
    @IBOutlet weak var collectionView: UICollectionView!
    @IBOutlet weak var collectionLayout: AlignedCollectionViewFlowLayout!
    
    private let cellCountPerRow = 4
    private let maxRowCount = 2
    private let cellMinWidth: CGFloat = 60
    private let queue = OperationQueue()
    
    private lazy var templateKeywordCell = R.nib.recentKeywordCell(owner: nil)!
    
    private var users = [UserItem]()
    private var needsReload = true
    private var keywordItemSizes = [Int: CGSize]()
    private var appItemSize = CGSize.zero
    
    private var recentSearchKeywords: [String] {
        AppGroupUserDefaults.User.recentSearchKeywords
    }
    
    deinit {
        NotificationCenter.default.removeObserver(self)
    }
    
    override func viewDidLoad() {
        super.viewDidLoad()
        queue.maxConcurrentOperationCount = 1
        collectionLayout.horizontalAlignment = .left
        collectionView.register(R.nib.recentKeywordCell)
        collectionView.dataSource = self
        collectionView.delegate = self
        
        let tapRecognizer = UITapGestureRecognizer(target: self, action: #selector(dismissIfTappingBelowCells(recognizer:)))
        collectionView.addGestureRecognizer(tapRecognizer)
        let swipeRecognizer = UISwipeGestureRecognizer(target: self, action: #selector(hideSearchAction))
        swipeRecognizer.direction = .up
        swipeRecognizer.delegate = self
        collectionView.addGestureRecognizer(swipeRecognizer)
        
        let center = NotificationCenter.default
        center.addObserver(self,
                           selector: #selector(setNeedsReload),
                           name: AppGroupUserDefaults.User.didChangeRecentlyUsedAppIdsNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(setNeedsReload),
                           name: AppGroupUserDefaults.User.didChangeRecentSearchKeywordsNotification,
                           object: nil)
        center.addObserver(self,
                           selector: #selector(userDidChange(_:)),
                           name: .UserDidChange,
                           object: nil)
        
        reloadIfNeeded()
    }
    
    override func viewWillLayoutSubviews() {
        super.viewWillLayoutSubviews()
        let cellsWidth = cellMinWidth * CGFloat(cellCountPerRow)
        let totalSpacing = view.bounds.width - cellsWidth
        let spacing = floor(totalSpacing / CGFloat(cellCountPerRow + 1))
        appItemSize = CGSize(width: cellMinWidth + spacing, height: 109)
        collectionLayout.sectionInset = UIEdgeInsets(top: 0, left: spacing / 2, bottom: 0, right: spacing / 2)
    }
    
    @IBAction func hideSearchAction() {
        let top = UIApplication.homeNavigationController?.topViewController
        (top as? HomeViewController)?.hideSearch()
    }
    
    @objc func setNeedsReload() {
        needsReload = true
    }
    
    @objc func userDidChange(_ sender: Notification) {
        let userId: String
        if let response = sender.object as? UserResponse {
            userId = response.userId
        } else if let user = sender.object as? UserItem {
            userId = user.userId
        } else {
            return
        }
        if users.contains(where: { $0.userId == userId }) {
            needsReload = true
        }
    }
    
    @objc func dismissIfTappingBelowCells(recognizer: UITapGestureRecognizer) {
        let location = recognizer.location(in: collectionView)
        if location.y > collectionView.contentSize.height {
            hideSearchAction()
        }
    }
    
    func reloadIfNeeded() {
        guard needsReload else {
            return
        }
        needsReload = false
        queue.cancelAllOperations()
        let maxIdCount = maxRowCount * cellCountPerRow
        let op = BlockOperation()
        op.addExecutionBlock { [unowned op, weak self] in
            guard self != nil, !op.isCancelled, LoginManager.shared.isLoggedIn else {
                return
            }
            let ids = AppGroupUserDefaults.User.recentlyUsedAppIds.prefix(maxIdCount)
            let users = UserDAO.shared.getUsers(ofAppIds: Array(ids))
            DispatchQueue.main.sync {
                guard let weakSelf = self, !op.isCancelled else {
                    return
                }
                weakSelf.reload(users: users)
            }
        }
        queue.addOperation(op)
    }
    
    private func reload(users: [UserItem]) {
        self.users = users
        self.keywordItemSizes = [:]
        collectionView.reloadData()
        collectionLayout.invalidateLayout()
    }
    
}

extension RecentSearchViewController: UICollectionViewDataSource {
    
    func collectionView(_ collectionView: UICollectionView, numberOfItemsInSection section: Int) -> Int {
        if section == 0 {
            return recentSearchKeywords.count
        } else {
            return users.count
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, cellForItemAt indexPath: IndexPath) -> UICollectionViewCell {
        if indexPath.section == 0 {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: R.reuseIdentifier.recent_keyword, for: indexPath)!
            cell.label.text = recentSearchKeywords[indexPath.row]
            return cell
        } else {
            let cell = collectionView.dequeueReusableCell(withReuseIdentifier: R.reuseIdentifier.recent_app, for: indexPath)!
            cell.render(user: users[indexPath.row])
            return cell
        }
    }
    
    func numberOfSections(in collectionView: UICollectionView) -> Int {
        2
    }
    
    func collectionView(_ collectionView: UICollectionView, viewForSupplementaryElementOfKind kind: String, at indexPath: IndexPath) -> UICollectionReusableView {
        let view = collectionView.dequeueReusableSupplementaryView(ofKind: kind, withReuseIdentifier: R.reuseIdentifier.recent_search_header, for: indexPath)!
        if indexPath.section == 0 {
            view.label.text = R.string.localizable.search_title_keyword()
        } else {
            view.label.text = R.string.localizable.search_title_app()
        }
        view.indexPath = indexPath
        view.delegate = self
        return view
    }
    
}

extension RecentSearchViewController: UICollectionViewDelegate {
    
    func collectionView(_ collectionView: UICollectionView, didSelectItemAt indexPath: IndexPath) {
        guard let parent = parent as? SearchViewController else {
            return
        }
        if indexPath.section == 0 {
            let keyword = recentSearchKeywords[indexPath.item]
            parent.searchTextField.text = keyword
            parent.searchAction(collectionView)
        } else {
            let user = users[indexPath.row]
            let vc = ConversationViewController.instance(ownerUser: user)
            parent.searchTextField.resignFirstResponder()
            parent.homeNavigationController?.pushViewController(vc, animated: true)
            vc.transitionCoordinator?.animate(alongsideTransition: nil, completion: { (_) in
                parent.homeViewController?.hideSearch()
            })
        }
    }
    
}

extension RecentSearchViewController: UICollectionViewDelegateFlowLayout {
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, sizeForItemAt indexPath: IndexPath) -> CGSize {
        if indexPath.section == 0 {
            if let size = keywordItemSizes[indexPath.row] {
                return size
            } else {
                templateKeywordCell.label.text = recentSearchKeywords[indexPath.row]
                let widthToFit = collectionView.bounds.width - collectionView.contentInset.horizontal
                let sizeToFit = CGSize(width: widthToFit, height: UIView.layoutFittingExpandedSize.height)
                let size = templateKeywordCell.sizeThatFits(sizeToFit)
                keywordItemSizes[indexPath.row] = size
                return size
            }
        } else {
            return appItemSize
        }
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, minimumLineSpacingForSectionAt section: Int) -> CGFloat {
        section == 0 ? 0 : 10
    }
    
    func collectionView(_ collectionView: UICollectionView, layout collectionViewLayout: UICollectionViewLayout, referenceSizeForHeaderInSection section: Int) -> CGSize {
        let hasContent = (section == 1 && !users.isEmpty)
            || (section == 0 && !recentSearchKeywords.isEmpty)
        if hasContent {
            if section == 0 {
                return CGSize(width: collectionView.bounds.width, height: 37)
            } else {
                return CGSize(width: collectionView.bounds.width, height: 57)
            }
        } else {
            return .zero
        }
    }
    
}

extension RecentSearchViewController: RecentSearchHeaderViewDelegate {
    
    func recentSearchHeaderViewDidSelectClear(_ view: RecentSearchHeaderView) {
        guard let section = view.indexPath?.section else {
            return
        }
        if section == 0 {
            AppGroupUserDefaults.User.removeAllRecentSearchKeyword()
        } else {
            AppGroupUserDefaults.User.removeAllRecentlyUsedAppId()
        }
        reloadIfNeeded()
    }
    
}

extension RecentSearchViewController: UIGestureRecognizerDelegate {
    
    func gestureRecognizer(_ gestureRecognizer: UIGestureRecognizer, shouldRecognizeSimultaneouslyWith otherGestureRecognizer: UIGestureRecognizer) -> Bool {
        true
    }
    
}
