import GeckoView
import UIKit

@MainActor
final class GPTSelectionController: NSObject, SelectionActionDelegate {
    private weak var session: GeckoSession?
    private var actionID: String?
    private var actions: Set<String> = []
    private let host = GPTSelectionHostView(frame: .zero)

    override init() {
        super.init()
        host.owner = self
    }

    func onShowSelectionAction(session: GeckoSession, request: SelectionActionRequest) {
        guard !request.editable,
              !request.selection.isEmpty,
              let engineView = session.engineView else {
            hide()
            return
        }

        self.session = session
        actionID = request.actionId
        actions = Set(request.actions)
        if host.superview !== engineView {
            host.removeFromSuperview()
            engineView.addSubview(host)
        }

        let scale = engineView.window?.screen.scale ?? UIScreen.main.scale
        let rect = CGRect(
            x: request.screenRect.origin.x / scale,
            y: request.screenRect.origin.y / scale,
            width: max(1, request.screenRect.width / scale),
            height: max(1, request.screenRect.height / scale)
        )
        host.frame = rect.intersection(engineView.bounds)
        if host.frame.isNull || host.frame.isEmpty {
            host.frame = CGRect(x: engineView.bounds.midX, y: 60, width: 1, height: 1)
        }
        host.becomeFirstResponder()
        UIMenuController.shared.showMenu(from: host, rect: host.bounds)
    }

    func onHideSelectionAction(session: GeckoSession) {
        hide()
    }

    fileprivate func supports(_ command: String) -> Bool {
        actionID != nil && actions.contains(command)
    }

    fileprivate func execute(_ command: String) {
        guard let session, let actionID else { return }
        session.executeSelectionAction(actionId: actionID, commandId: command)
        hide()
    }

    private func hide() {
        UIMenuController.shared.hideMenu()
        host.resignFirstResponder()
        host.removeFromSuperview()
        session = nil
        actionID = nil
        actions.removeAll()
    }
}

@MainActor
private final class GPTSelectionHostView: UIView {
    weak var owner: GPTSelectionController?

    override var canBecomeFirstResponder: Bool { true }

    override func canPerformAction(_ action: Selector, withSender sender: Any?) -> Bool {
        if action == #selector(copy(_:)) {
            return owner?.supports(SelectionActionCommand.copy) == true
        }
        if action == #selector(selectAll(_:)) {
            return owner?.supports(SelectionActionCommand.selectAll) == true
        }
        return false
    }

    override func copy(_ sender: Any?) {
        owner?.execute(SelectionActionCommand.copy)
    }

    override func selectAll(_ sender: Any?) {
        owner?.execute(SelectionActionCommand.selectAll)
    }
}
