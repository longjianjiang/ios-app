import UIKit

protocol RecentSearchHeaderViewDelegate: class {
    
    func recentSearchHeaderViewDidSelectClear(_ view: RecentSearchHeaderView)
    
}

class RecentSearchHeaderView: UICollectionReusableView {
    
    @IBOutlet weak var label: UILabel!
    
    weak var delegate: RecentSearchHeaderViewDelegate?
    
    var indexPath: IndexPath?
    
    @IBAction func clearAction(_ sender: Any) {
        delegate?.recentSearchHeaderViewDidSelectClear(self)
    }
    
}
