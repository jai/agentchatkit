import AgentChatCore
import Testing

struct ScreenshotLineTests {
    @Test func aBubbleSaysHowManyScreenshotsWent() {
        #expect(ScreenshotLine.bubbleText("Look", screenshots: 0) == "Look")
        #expect(ScreenshotLine.bubbleText("", screenshots: 1) == "Screenshot attached")
        #expect(ScreenshotLine.bubbleText("Look ", screenshots: 2) == "Look\n\n2 screenshots attached")
    }
}
