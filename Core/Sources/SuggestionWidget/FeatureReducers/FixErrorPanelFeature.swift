import ComposableArchitecture
import Foundation
import SuggestionBasic
import XcodeInspector
import ChatTab
import ConversationTab

@Reducer
public struct FixErrorPanelFeature {
    @ObservableState
    public struct State: Equatable {
        public var focusedEditor: SourceEditor? = nil 
        public var editorContent: EditorInformation.SourceEditorContent? = nil
        public var fixId: String? = nil
        public var fixFailure: FixEditorErrorIssueFailure? = nil
        public var cursorPosition: CursorPosition? {
            editorContent?.cursorPosition
        }
        public var isPanelDisplayed: Bool = false
        
        public var errorAnnotations: [EditorInformation.LineAnnotation] {
            editorContent?.lineAnnotations.filter { $0.isError } ?? []
        }
        
        public var editorContentLines: [String] {
            editorContent?.lines ?? []
        }
        
        public var errorAnnotationsAtCursorPosition: [EditorInformation.LineAnnotation] {
            let errorAnnotations = errorAnnotations
            guard !errorAnnotations.isEmpty, let cursorPosition = cursorPosition else {
                return []
            }
            
            return errorAnnotations.filter { $0.line == cursorPosition.line + 1 }
        }
        
        public mutating func resetFailure() {
            fixFailure = nil
            fixId = nil
        }
    }
    
    public enum Action: Equatable {
        case onFocusedEditorChanged(SourceEditor?)
        case onEditorContentChanged
        case onScrollPositionChanged
        case onCursorPositionChanged
        
        case fixErrorIssue([EditorInformation.LineAnnotation])
        case scheduleFixFailureReset
        
        case appear
        case onFailure(FixEditorErrorIssueFailure)
        case checkDisplay
        case resetFixFailure
        
        // Annotation checking
        case startAnnotationCheck
        case onAnnotationCheckTimerFired
    }
    
    let id = UUID()
    
    enum CancelID: Hashable {
        case observeErrorNotification(UUID)
        case annotationCheck(UUID)
        case scheduleFixFailureReset(UUID)
    }
    
    public init() {}
    
    @Dependency(\.suggestionWidgetControllerDependency) var suggestionWidgetControllerDependency
    
    public var body: some ReducerOf<Self> {
        Reduce { state, action in
            switch action {
            case .appear:
                return .run { send in 
                    let stream = AsyncStream<Void> { continuation in
                        let observer = NotificationCenter.default.addObserver(
                            forName: .fixEditorErrorIssueError, 
                            object: nil, 
                            queue: .main
                        ) { notification in 
                            guard let error = notification.userInfo?["error"] as? FixEditorErrorIssueFailure
                            else {
                                return
                            }
                            
                            Task {
                                await send(.onFailure(error))
                            }
                        }
                        
                        continuation.onTermination = { _ in
                            NotificationCenter.default.removeObserver(observer)
                        }
                    }
                    
                    for await _ in stream {
                        // Stream continues until cancelled
                    }
                }.cancellable(
                    id: CancelID.observeErrorNotification(id), 
                    cancelInFlight: true
                )
                
            case .onFocusedEditorChanged(let editor):
                state.focusedEditor = editor
                return .merge(
                    .send(.startAnnotationCheck),
                    .send(.resetFixFailure)
                )
                
            case .onEditorContentChanged:
                return .merge(
                    .send(.startAnnotationCheck),
                    .send(.resetFixFailure)
                )
                
            case .onScrollPositionChanged:
                return .merge(
                    .send(.resetFixFailure),
                    // Force checking the annotation
                    .send(.onAnnotationCheckTimerFired),
                    .send(.checkDisplay)
                )
                
            case .onCursorPositionChanged:
                return .merge(
                    .send(.resetFixFailure),
                    // Force checking the annotation
                    .send(.onAnnotationCheckTimerFired),
                    .send(.checkDisplay)
                )
                
            case .fixErrorIssue(let annotations):
                guard let fileURL = state.focusedEditor?.realtimeDocumentURL ?? nil,
                      let workspaceURL = state.focusedEditor?.realtimeWorkspaceURL ?? nil
                else {
                    return .none
                }
                
                let fixId = UUID().uuidString
                state.fixId = fixId
                state.fixFailure = nil
                
                let editorErrorIssue: EditorErrorIssue = .init(
                    lineAnnotations: annotations,
                    fileURL: fileURL,
                    workspaceURL: workspaceURL,
                    id: fixId
                )
                
                let userInfo = [
                    "editorErrorIssue": editorErrorIssue
                ]
                
                return .run { _ in 
                    await MainActor.run {
                        suggestionWidgetControllerDependency.onOpenChatClicked()
                         
                        NotificationCenter.default.post(
                            name: .fixEditorErrorIssue,
                            object: nil,
                            userInfo: userInfo
                        )
                    }
                }
                
            case .scheduleFixFailureReset:
                return .run { send in 
                    try await Task.sleep(nanoseconds: 3_000_000_000) // 3 seconds
                    await send(.resetFixFailure)
                }
                .cancellable(id: CancelID.scheduleFixFailureReset(id), cancelInFlight: true)
                
            case .resetFixFailure:
                state.resetFailure()
                return .cancel(id: CancelID.scheduleFixFailureReset(id))
                
            case .onFailure(let failure):
                guard case let .isReceivingMessage(fixId) = failure,
                      fixId == state.fixId
                else {
                    return .none
                }
                
                state.fixFailure = failure
                
                return .run { send in await send(.scheduleFixFailureReset)}
                
            case .checkDisplay:
                state.isPanelDisplayed = !state.editorContentLines.isEmpty
                    && !state.errorAnnotationsAtCursorPosition.isEmpty
                return .none
                
            // MARK: - Annotation Check
                
            case .startAnnotationCheck:
                return .run { send in 
                    let startTime = Date()
                    let maxDuration: TimeInterval = 60 * 5
                    let interval: TimeInterval = 1
                    
                    while Date().timeIntervalSince(startTime) < maxDuration {
                        try await Task.sleep(nanoseconds: UInt64(interval) * 1_000_000_000)
                        
                        await send(.onAnnotationCheckTimerFired)
                    }
                }.cancellable(id: CancelID.annotationCheck(id), cancelInFlight: true)
                
            case .onAnnotationCheckTimerFired:
                guard let editor = state.focusedEditor else {
                    return .cancel(id: CancelID.annotationCheck(id))
                }
                
                let newEditorContent = editor.getContent()
                let newLineAnnotations = newEditorContent.lineAnnotations
                let newErrorLineAnnotations = newLineAnnotations.filter { $0.isError }
                let errorAnnotations = state.errorAnnotations
                
                if state.editorContent != newEditorContent {
                    state.editorContent = newEditorContent
                }
                
                if errorAnnotations != newErrorLineAnnotations {
                    return .merge(
                        .send(.checkDisplay),
                        .cancel(id: CancelID.annotationCheck(id))
                    )
                } else {
                    return .none
                }
            }
        }
    }
}
