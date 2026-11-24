@testable import AgentChatKit
import CoreGraphics
import Testing

/// A viewer over all of a message's attachments (Jai, Agent Pager, 2026-11-24: "If I have multiple image attachments,
/// I can't swipe between them"): where it stands, what it says, and what a drag across it does.
struct ChatMediaPagingTests {
    @Test func itOpensOnTheAttachmentTappedAndSaysWhichOfHowMany() {
        let paging = ChatMediaPaging(count: 4, index: 1)
        #expect(paging.index == 1)
        #expect(paging.position == "2 of 4")
        #expect(paging.hasPrevious)
        #expect(paging.hasNext)
    }

    @Test func oneAttachmentSaysNoPlaceAndHasNowhereToGo() {
        var paging = ChatMediaPaging(count: 1, index: 0)
        #expect(paging.position == nil)
        #expect(!paging.hasPrevious)
        #expect(!paging.hasNext)
        #expect(paging.settle(CGSize(width: -300, height: 4)) == .stays)
        #expect(paging.index == 0)
        #expect(paging.travel(CGSize(width: -80, height: 0)) == 0, "one picture does not follow the finger sideways")
    }

    @Test func aStartOutsideTheAttachmentsIsHeldInside() {
        #expect(ChatMediaPaging(count: 3, index: 9).index == 2)
        #expect(ChatMediaPaging(count: 3, index: -1).index == 0)
        #expect(ChatMediaPaging(count: 0, index: 2).index == 0)
    }

    @Test func aSwipeAcrossGoesToTheNextAndBackAndStopsAtEitherEnd() {
        var paging = ChatMediaPaging(count: 3, index: 0)
        #expect(paging.settle(CGSize(width: 200, height: 0)) == .stays, "nothing before the first")
        #expect(paging.settle(CGSize(width: -200, height: 10)) == .paged)
        #expect(paging.position == "2 of 3")
        #expect(paging.settle(CGSize(width: -200, height: -10)) == .paged)
        #expect(paging.position == "3 of 3")
        #expect(paging.settle(CGSize(width: -200, height: 0)) == .stays, "nothing after the last")
        #expect(paging.settle(CGSize(width: 200, height: 0)) == .paged)
        #expect(paging.position == "2 of 3")
    }

    @Test func aShortDragStaysAndASwipeDownStillCloses() {
        var paging = ChatMediaPaging(count: 3, index: 1)
        #expect(paging.settle(CGSize(width: -ChatStyle.viewerPageDrag + 1, height: 0)) == .stays)
        #expect(paging.settle(CGSize(width: 0, height: ChatStyle.viewerDismissDrag)) == .stays)
        #expect(paging.settle(CGSize(width: 30, height: ChatStyle.viewerDismissDrag + 1)) == .closes)
        #expect(paging.index == 1)
        // Mostly sideways, though far enough down: it pages, it does not close.
        #expect(paging.settle(CGSize(width: -400, height: ChatStyle.viewerDismissDrag + 1)) == .paged)
        #expect(paging.index == 2)
    }

    @Test func theButtonsStepOneAtATimeAndStopAtTheEnds() {
        var paging = ChatMediaPaging(count: 2, index: 0)
        paging.previous()
        #expect(paging.index == 0)
        paging.next()
        #expect(paging.index == 1)
        paging.next()
        #expect(paging.index == 1)
    }

    @Test func thePagesFollowAFingerBetweenPagesAndDragStifflyPastAnEnd() {
        let first = ChatMediaPaging(count: 2, index: 0)
        #expect(first.travel(CGSize(width: -90, height: 5)) == -90)
        #expect(first.travel(CGSize(width: 90, height: 5)) == 30)
        #expect(first.travel(CGSize(width: 10, height: 90)) == 0, "a drag down moves no page")
    }
}
