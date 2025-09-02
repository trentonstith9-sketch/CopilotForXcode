import AppKit
import XcodeInspector

extension WidgetWindowsController {
    @MainActor
    func hideFixErrorWindow() {
        windows.fixErrorPanelWindow.alphaValue = 0
        windows.fixErrorPanelWindow.setIsVisible(false)
    }
    
    @MainActor
    func displayFixErrorWindow() {
        windows.fixErrorPanelWindow.setIsVisible(true)
        windows.fixErrorPanelWindow.alphaValue = 1
        windows.fixErrorPanelWindow.orderFrontRegardless()
    }
    
    func setupFixErrorPanelObservers() {
        store.publisher
            .map(\.fixErrorPanelState.errorAnnotations)
            .removeDuplicates()
            .sink { [weak self] _ in 
                Task { @MainActor [weak self] in 
                    await self?.updateFixErrorPanelWindowLocation()
                }
            }.store(in: &cancellable)
        
        store.publisher
            .map(\.fixErrorPanelState.isPanelDisplayed)
            .removeDuplicates()
            .sink { [weak self ] _ in
                Task { @MainActor [weak self] in 
                    await self?.updateFixErrorPanelWindowLocation()
                }
            }.store(in: &cancellable)
    }
    
    @MainActor
    func updateFixErrorPanelWindowLocation() async {
        guard let activeApp = await XcodeInspector.shared.safe.activeApplication,
              activeApp.isXcode
        else {
            hideFixErrorWindow()
            return
        }
        
        let state = store.withState { $0.fixErrorPanelState }
        guard state.isPanelDisplayed,
              let focusedEditor = state.focusedEditor,
              let scrollViewRect = focusedEditor.element.parent?.rect
        else {
            hideFixErrorWindow()
            return
        }
        
        let annotations = state.errorAnnotationsAtCursorPosition
        
        guard !annotations.isEmpty,
              let annotationRect = annotations.first(where: { $0.rect != nil})?.rect,
              scrollViewRect.contains(annotationRect),
              let screen = NSScreen.screens.first(where: { $0.frame.origin == .zero })
        else {
            hideFixErrorWindow()
            return
        }
        
        var fixErrorPanelWindowFrame = windows.fixErrorPanelWindow.frame
        fixErrorPanelWindowFrame.origin.x = annotationRect.minX - fixErrorPanelWindowFrame.width - Style.fixPanelToAnnotationSpacing
        // Locate the window to the middle in Y
        fixErrorPanelWindowFrame.origin.y = screen.frame.maxY - annotationRect.minY - annotationRect.height / 2 - fixErrorPanelWindowFrame.height / 2 + screen.frame.minY
        
        windows.fixErrorPanelWindow.setFrame(fixErrorPanelWindowFrame, display: true, animate: true)
        displayFixErrorWindow()
    }
    
    @MainActor
    func handleFixErrorEditorNotification(notification: SourceEditor.AXNotification) async {
        switch notification.kind {
        case .scrollPositionChanged:
            store.send(.fixErrorPanel(.onScrollPositionChanged))
        case .valueChanged:
            store.send(.fixErrorPanel(.onEditorContentChanged))
        case .selectedTextChanged:
            store.send(.fixErrorPanel(.onCursorPositionChanged))
        default:
            break
        }
        
        await updateFixErrorPanelWindowLocation()
    }
}
