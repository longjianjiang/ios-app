import UIKit

class RecentKeywordCell: UICollectionViewCell {
    
    @IBOutlet weak var label: InsetLabel!
    
    @IBOutlet weak var labelLeadingConstraint: NSLayoutConstraint!
    @IBOutlet weak var labelTrailingConstraint: NSLayoutConstraint!
    @IBOutlet weak var labelBottomConstraint: NSLayoutConstraint!
    @IBOutlet weak var labelTopConstraint: NSLayoutConstraint!
    
    override func awakeFromNib() {
        super.awakeFromNib()
        label.contentInset = UIEdgeInsets(top: 8, left: 14, bottom: 8, right: 14)
    }
    
    override func layoutSubviews() {
        super.layoutSubviews()
        label.layer.cornerRadius = label.frame.height / 2
    }
    
    override func sizeThatFits(_ size: CGSize) -> CGSize {
        let string = NSString(string: label.text ?? "")
        var contentSize = ceil(string.size(withAttributes: [.font: label.font!]))
        contentSize.width += (labelLeadingConstraint.constant + labelTrailingConstraint.constant)
        contentSize.width += label.contentInset.horizontal
        contentSize.height += (labelTopConstraint.constant + labelBottomConstraint.constant)
        contentSize.height += label.contentInset.vertical
        let width = min(size.width, contentSize.width)
        let height = min(size.height, contentSize.height)
        return CGSize(width: width, height: height)
    }
    
}
