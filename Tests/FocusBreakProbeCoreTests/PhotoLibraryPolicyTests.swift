import Testing
@testable import FocusBreakProbeCore

@Suite("Photo library policies")
struct PhotoLibraryPolicyTests {
    @Test("Every round covers the library and never repeats at a boundary")
    func rotation() {
        var rotation = PhotoRotation()
        let photos = ["a", "b", "c", "d"]
        var previous: String?
        for _ in 0..<20 {
            var seen = Set<String>()
            for _ in photos {
                let next = rotation.next(in: photos)!
                #expect(next != previous)
                #expect(seen.insert(next).inserted)
                rotation.didShow(next)
                previous = next
            }
            #expect(seen == Set(photos))
        }
        #expect(rotation.next(in: []) == nil)
        #expect(rotation.next(in: ["only"]) == "only")
        #expect(rotation.next(in: ["new"]) == "new")
    }

    @Test("Automatic mode retains a portrait completely and fills similar landscape ratios")
    func photoFit() {
        let portrait = ResponsiveLayoutPolicy.photoDestination(sourceWidth: 2400, sourceHeight: 3600,
            targetWidth: 1600, targetHeight: 800)
        #expect(abs(portrait.width / portrait.height - 2.0 / 3) < 0.0001)
        #expect(portrait.height == 800 && portrait.x > 0 && portrait.y == 0)
        let landscape = ResponsiveLayoutPolicy.photoDestination(sourceWidth: 1800, sourceHeight: 1000,
            targetWidth: 1600, targetHeight: 800)
        #expect(landscape.width == 1600 && landscape.height == 800 && landscape.x == 0)
        let wideOnPortrait = ResponsiveLayoutPolicy.photoDestination(sourceWidth: 1800, sourceHeight: 1000,
            targetWidth: 800, targetHeight: 1200)
        #expect(wideOnPortrait.width == 800 && wideOnPortrait.y > 0)
    }
}
