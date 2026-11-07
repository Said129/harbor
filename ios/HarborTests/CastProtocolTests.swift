import XCTest
@testable import Harbor

/// Desktop's Roku ECP (`roku.rs`) and DLNA/UPnP (`dlna.rs`) requests and parsers, driven by canned XML. No network.
final class CastProtocolTests: XCTestCase {
    /// Answers each request from a closure, so tests see exactly what would be sent.
    private struct FakeCastTransport: CastTransport {
        let handler: @Sendable (URLRequest) -> CastReply

        func send(_ request: URLRequest) async throws -> CastReply {
            handler(request)
        }
    }

    private func body(_ request: URLRequest?) -> String {
        String(decoding: request?.httpBody ?? Data(), as: UTF8.self)
    }

    private let deviceXML = """
    <?xml version="1.0"?>
    <root xmlns="urn:schemas-upnp-org:device-1-0">
      <device>
        <friendlyName>Living Room TV</friendlyName>
        <manufacturer>Sony Corporation</manufacturer>
        <modelName>KD-55X80J</modelName>
        <serviceList>
          <service>
            <serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType>
            <serviceId>urn:upnp-org:serviceId:RenderingControl</serviceId>
            <controlURL>/upnp/control/RenderingControl1</controlURL>
          </service>
          <service>
            <serviceType>urn:schemas-upnp-org:service:AVTransport:1</serviceType>
            <serviceId>urn:upnp-org:serviceId:AVTransport</serviceId>
            <controlURL>/upnp/control/AVTransport1</controlURL>
          </service>
        </serviceList>
      </device>
    </root>
    """

    // MARK: Roku ECP

    func testRokuDeviceInfoPrefersFriendlyNameThenUserNameThenModel() {
        let full = "<device-info><friendly-device-name>Living Room</friendly-device-name><user-device-name>Ignored</user-device-name><model-name>Roku Ultra</model-name></device-info>"
        XCTAssertEqual(CastRoku.parseDeviceInfo(full), CastRoku.DeviceInfo(name: "Living Room", model: "Roku Ultra"))

        let userOnly = "<device-info><user-device-name>Bedroom</user-device-name><model-name>Roku Express</model-name></device-info>"
        XCTAssertEqual(CastRoku.parseDeviceInfo(userOnly), CastRoku.DeviceInfo(name: "Bedroom", model: "Roku Express"))

        let modelOnly = "<device-info><model-name>Roku Stick</model-name></device-info>"
        XCTAssertEqual(CastRoku.parseDeviceInfo(modelOnly), CastRoku.DeviceInfo(name: "Roku Stick", model: "Roku Stick"))
    }

    func testEcpBaseKeepsTrailingSlashAndOnlyAcceptsPort8060() {
        XCTAssertEqual(CastRoku.normalizedEcpBase("192.168.1.20"), "http://192.168.1.20:8060/")
        XCTAssertEqual(CastRoku.normalizedEcpBase("http://192.168.1.20:8060"), "http://192.168.1.20:8060/")
        XCTAssertNil(CastRoku.normalizedEcpBase("192.168.1.20:9000"))
        XCTAssertNil(CastRoku.normalizedEcpBase("   "))
    }

    func testDeviceInfoRequestIsAGetOnTheEcpPath() {
        let request = CastRoku.deviceInfoRequest(base: "http://192.168.1.20:8060/")
        XCTAssertEqual(request?.url?.absoluteString, "http://192.168.1.20:8060/query/device-info")
        XCTAssertEqual(request?.httpMethod, "GET")
    }

    func testAppsParseAndMediaAssistantIsFoundByNameOrId() {
        let xml = "<apps><app id=\"12\" type=\"appl\">Netflix</app><app id=\"782875\" version=\"1.0\">Media Assistant</app><app id=\"\">Empty</app></apps>"
        let apps = CastRoku.parseApps(xml)
        XCTAssertEqual(apps, [CastRoku.App(id: "12", name: "Netflix"), CastRoku.App(id: "782875", name: "Media Assistant")])
        XCTAssertEqual(CastRoku.mediaAssistantChannel(in: apps), "782875")
        XCTAssertNil(CastRoku.mediaAssistantChannel(in: [CastRoku.App(id: "12", name: "Netflix")]))
        XCTAssertEqual(CastRoku.mediaAssistantChannel(in: [CastRoku.App(id: "9", name: "media assistant pro")]), "9")
    }

    func testGuessFormatReadsContentTypeThenPath() {
        XCTAssertEqual(CastRoku.guessFormat(url: "http://x/a", contentType: "application/dash+xml"), "dash")
        XCTAssertEqual(CastRoku.guessFormat(url: "http://x/a", contentType: "video/quicktime"), "mp4")
        XCTAssertEqual(CastRoku.guessFormat(url: "http://x/a.m3u8", contentType: nil), "hls")
        XCTAssertEqual(CastRoku.guessFormat(url: "http://x/a.mpd?token=1", contentType: nil), "dash")
        XCTAssertEqual(CastRoku.guessFormat(url: "http://x/a.mkv", contentType: nil), "mkv")
        XCTAssertEqual(CastRoku.guessFormat(url: "http://x/live/manifest", contentType: nil), "ism")
        XCTAssertEqual(CastRoku.guessFormat(url: "http://x/live.ts?x=1", contentType: nil), "mp4")
    }

    func testLaunchRequestMatchesDesktopUrlAndStartTime() {
        let request = CastRoku.launchRequest(
            base: "http://192.168.1.20:8060/",
            channel: "782875",
            url: "https://cdn.example.com/movie.mkv?token=a b",
            title: "Night Movie",
            contentType: nil,
            startSeconds: 125.5
        )
        XCTAssertEqual(request?.httpMethod, "POST")
        XCTAssertEqual(request?.value(forHTTPHeaderField: "Content-Length"), "0")
        XCTAssertEqual(
            request?.url?.absoluteString,
            "http://192.168.1.20:8060/launch/782875?u=https%3A%2F%2Fcdn.example.com%2Fmovie.mkv%3Ftoken%3Da%20b&t=v&k=(null)&videoName=Night%20Movie&videoFormat=mkv&streamformat=mkv&startMS=125500"
        )
    }

    func testLaunchRequestOmitsStartTimeUpToOneSecondAndDefaultsTitle() {
        let request = CastRoku.launchRequest(base: "http://192.168.1.20:8060/", channel: "782875", url: "http://x/a.mp4", title: nil, contentType: nil, startSeconds: 1)
        XCTAssertEqual(
            request?.url?.absoluteString,
            "http://192.168.1.20:8060/launch/782875?u=http%3A%2F%2Fx%2Fa.mp4&t=v&k=(null)&videoName=Harbor&videoFormat=mp4&streamformat=mp4"
        )
    }

    func testKeypressUsesPlayForPauseAndHomeForStop() {
        let play = CastRoku.keypressRequest(base: "http://192.168.1.20:8060/", key: CastRoku.Key.play)
        XCTAssertEqual(play?.url?.absoluteString, "http://192.168.1.20:8060/keypress/Play")
        XCTAssertEqual(play?.httpMethod, "POST")
        let home = CastRoku.keypressRequest(base: "http://192.168.1.20:8060/", key: CastRoku.Key.home)
        XCTAssertEqual(home?.url?.absoluteString, "http://192.168.1.20:8060/keypress/Home")
    }

    func testMediaPlayerParsesStateErrorPositionAndDuration() {
        let xml = "<player state=\"playing\" error=\"false\"><position>12345 ms</position><duration>3600000 ms</duration></player>"
        let status = CastRoku.parseMediaPlayer(xml)
        XCTAssertEqual(status.playerState, "PLAYING")
        XCTAssertFalse(status.error)
        XCTAssertEqual(status.positionSec, 12.345, accuracy: 0.0001)
        XCTAssertEqual(status.durationSec ?? -1, 3600, accuracy: 0.0001)

        let empty = CastRoku.parseMediaPlayer("<player state=\"close\" error=\"true\"></player>")
        XCTAssertEqual(empty.playerState, "CLOSE")
        XCTAssertTrue(empty.error)
        XCTAssertEqual(empty.positionSec, 0)
        XCTAssertNil(empty.durationSec)
    }

    func testRokuStatusCodesMapToDesktopErrors() {
        XCTAssertEqual(CastRoku.error(forStatus: 403), .rokuBlocked)
        XCTAssertEqual(CastRoku.error(forStatus: 401), .rokuBlocked)
        XCTAssertEqual(CastRoku.error(forStatus: 404), .rokuNotFound)
        XCTAssertEqual(CastRoku.error(forStatus: 500), .rokuHTTP(500))
    }

    func testPlayerStatesNormalizeAsDesktop() {
        XCTAssertEqual(CastPlayerState.normalize("play"), "PLAYING")
        XCTAssertEqual(CastPlayerState.normalize("PAUSED_PLAYBACK"), "PAUSED")
        XCTAssertEqual(CastPlayerState.normalize("buffer"), "BUFFERING")
        XCTAssertEqual(CastPlayerState.normalize("NO_MEDIA_PRESENT"), "IDLE")
        XCTAssertEqual(CastPlayerState.normalize("weird"), "WEIRD")
    }

    // MARK: Shared helpers

    func testHMSFormattingAndParsing() {
        XCTAssertEqual(CastNet.formatHMS(3725), "01:02:05")
        XCTAssertEqual(CastNet.formatHMS(-4), "00:00:00")
        XCTAssertEqual(CastNet.formatHMS(61.9), "00:01:01")
        XCTAssertEqual(CastNet.parseHMS("01:02:05"), 3725)
        XCTAssertEqual(CastNet.parseHMS("NOT_IMPLEMENTED"), 0)
        XCTAssertEqual(CastNet.parseHMS("0:02:03.500"), 123.5, accuracy: 0.0001)
    }

    func testPercentEncodeAndXMLEscapeMatchDesktop() {
        XCTAssertEqual(CastNet.percentEncode("a b/\u{E9}"), "a%20b%2F%C3%A9")
        XCTAssertEqual(CastNet.percentEncode("A-z_0.~"), "A-z_0.~")
        XCTAssertEqual(CastNet.xmlEscape("<a & 'b'>"), "&lt;a &amp; &apos;b&apos;&gt;")
        XCTAssertEqual(CastNet.xmlUnescape("x&amp;y&lt;z"), "x&y<z")
    }

    func testResolveJoinsRelativeControlUrls() {
        XCTAssertEqual(CastNet.resolve("http://h:1/a/b.xml", "/ctl"), "http://h:1/ctl")
        XCTAssertEqual(CastNet.resolve("http://h:1/a/b.xml", "ctl"), "http://h:1/ctl")
        XCTAssertEqual(CastNet.resolve("http://h:1/a/b.xml", "https://other/ctl"), "https://other/ctl")
    }

    func testSubnetHostsCoverTheSlash24WithoutTheDevice() {
        let hosts = CastDiscovery.subnetHosts(localIPv4: "192.168.1.20")
        XCTAssertEqual(hosts.count, 253)
        XCTAssertEqual(hosts.first, "192.168.1.1")
        XCTAssertEqual(hosts.last, "192.168.1.254")
        XCTAssertFalse(hosts.contains("192.168.1.20"))
        XCTAssertEqual(CastDiscovery.subnetHosts(localIPv4: "10.0.0"), [])
        XCTAssertEqual(CastDiscovery.subnetHosts(localIPv4: "10.0.0.300"), [])
    }

    func testProbeAcceptsOnlyDeviceInfoDocumentsOnPort8060() async {
        let transport = FakeCastTransport { request in
            if request.url?.host == "192.168.1.20", request.url?.path == "/query/device-info" {
                return CastReply(status: 200, body: "<device-info><friendly-device-name>Den</friendly-device-name></device-info>")
            }
            if request.url?.host == "192.168.1.21" {
                return CastReply(status: 200, body: "<html>not a roku</html>")
            }
            return CastReply(status: 404, body: "")
        }
        let targets = await CastDiscovery.probe(hosts: ["192.168.1.21", "192.168.1.20", "192.168.1.22"], transport: transport)
        XCTAssertEqual(targets.count, 1)
        XCTAssertEqual(targets.first?.name, "Den")
        XCTAssertEqual(targets.first?.kind, .roku)
        XCTAssertEqual(targets.first?.endpoint, "http://192.168.1.20:8060/")
    }

    // MARK: DLNA / UPnP

    func testDescriptionResolvesAVTransportAndRenderingControlAgainstLocation() throws {
        let parsed = try CastDLNA.parseDescription(deviceXML, location: "http://192.168.1.50:49152/description.xml")
        XCTAssertEqual(parsed.name, "Living Room TV")
        XCTAssertEqual(parsed.model, "KD-55X80J")
        XCTAssertEqual(parsed.vendor, .sonyBravia)
        XCTAssertEqual(parsed.avTransportURL, "http://192.168.1.50:49152/upnp/control/AVTransport1")
        XCTAssertEqual(parsed.renderingControlURL, "http://192.168.1.50:49152/upnp/control/RenderingControl1")
    }

    func testDescriptionWithoutAVTransportThrows() {
        let xml = "<root><device><friendlyName>Speaker</friendlyName><serviceList><service><serviceType>urn:schemas-upnp-org:service:RenderingControl:1</serviceType><controlURL>/rc</controlURL></service></serviceList></device></root>"
        XCTAssertThrowsError(try CastDLNA.parseDescription(xml, location: "http://h/d.xml")) { error in
            XCTAssertEqual(error as? CastProtocolError, .noAVTransport)
        }
    }

    func testVendorClassificationFollowsDesktopOrder() {
        XCTAssertEqual(CastDLNA.classifyVendor(name: "", model: "KD-55X80J", manufacturer: ""), .sonyBravia)
        XCTAssertEqual(CastDLNA.classifyVendor(name: "Samsung TV", model: "", manufacturer: ""), .samsung)
        XCTAssertEqual(CastDLNA.classifyVendor(name: "", model: "", manufacturer: "LG Electronics"), .lgWebos)
        XCTAssertEqual(CastDLNA.classifyVendor(name: "Viera", model: "", manufacturer: ""), .panasonic)
        XCTAssertEqual(CastDLNA.classifyVendor(name: "Kitchen", model: "", manufacturer: "Acme"), .other)
    }

    func testSetAVTransportURIRequestCarriesEscapedUrlAndMetadata() throws {
        let plan = CastDLNA.loadPlan(
            controlURL: "http://192.168.1.50:49152/upnp/control/AVTransport1",
            mediaURL: "http://192.168.1.20:8080/video.mp4?x=1&y=2",
            title: "Movie & Co",
            contentType: nil,
            startSeconds: nil,
            vendor: .other
        )
        XCTAssertEqual(plan.map(\.action), ["SetAVTransportURI", "Play"])
        let call = try XCTUnwrap(plan.first)
        XCTAssertTrue(call.body.hasPrefix("<InstanceID>0</InstanceID><CurrentURI>http://192.168.1.20:8080/video.mp4?x=1&amp;y=2</CurrentURI><CurrentURIMetaData>&lt;DIDL-Lite "))
        XCTAssertTrue(call.body.contains("Movie &amp;amp; Co"))
        XCTAssertTrue(call.body.contains("http-get:*:video/mp4:DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"))

        let request = try XCTUnwrap(call.request)
        XCTAssertEqual(request.httpMethod, "POST")
        XCTAssertEqual(request.url?.absoluteString, "http://192.168.1.50:49152/upnp/control/AVTransport1")
        XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "text/xml; charset=\"utf-8\"")
        XCTAssertEqual(request.value(forHTTPHeaderField: "SOAPAction"), "\"urn:schemas-upnp-org:service:AVTransport:1#SetAVTransportURI\"")
        let sent = body(request)
        XCTAssertTrue(sent.hasPrefix("<?xml version=\"1.0\" encoding=\"utf-8\"?><s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\""))
        XCTAssertTrue(sent.contains("<s:Body><u:SetAVTransportURI xmlns:u=\"urn:schemas-upnp-org:service:AVTransport:1\">"))
        XCTAssertTrue(sent.hasSuffix("</u:SetAVTransportURI></s:Body></s:Envelope>"))
    }

    func testDIDLAddsVendorProfileAndNamespaceForVideoAndMusicClass() {
        let video = CastDLNA.buildDIDL(url: "http://h/m.mp4", title: "Movie", mime: "video/mp4", isLive: false, vendor: .sonyBravia)
        XCTAssertTrue(video.contains("xmlns:av=\"urn:schemas-sony-com:av\""))
        XCTAssertTrue(video.contains("<upnp:class>object.item.videoItem</upnp:class>"))
        XCTAssertTrue(video.contains("protocolInfo=\"http-get:*:video/mp4:DLNA.ORG_PN=AVC_MP4_MP_HD_AC3;DLNA.ORG_OP=01;DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000\""))

        let audio = CastDLNA.buildDIDL(url: "http://h/s.flac", title: "Song", mime: "audio/flac", isLive: false, vendor: .sonyBravia)
        XCTAssertTrue(audio.contains("<upnp:class>object.item.audioItem.musicTrack</upnp:class>"))
        XCTAssertTrue(audio.contains("protocolInfo=\"http-get:*:audio/flac:DLNA.ORG_OP=01;"))
        XCTAssertFalse(audio.contains("DLNA.ORG_PN"))
    }

    func testSonyLoadStopsFirstSettlesAndSeeksWithRetry() {
        let plan = CastDLNA.loadPlan(
            controlURL: "http://192.168.1.50/ctl",
            mediaURL: "http://h/m.mp4",
            title: nil,
            contentType: "video/mp4",
            startSeconds: 3725,
            vendor: .sonyBravia
        )
        XCTAssertEqual(plan.map(\.action), ["Stop", "SetAVTransportURI", "Play", "Seek"])
        XCTAssertEqual(plan.map(\.pauseAfterMilliseconds), [200, 400, 1200, 0])
        XCTAssertTrue(plan[0].ignoresFailure)
        XCTAssertNil(plan[1].retryAfterMilliseconds)
        XCTAssertEqual(plan[3].retryAfterMilliseconds, 700)
        XCTAssertEqual(plan[3].body, "<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>01:02:05</Target>")
        XCTAssertEqual(plan[3].request?.value(forHTTPHeaderField: "SOAPAction"), "\"urn:schemas-upnp-org:service:AVTransport:1#Seek\"")
    }

    func testPanasonicLoadSettlesAfterSetURIAndSkipsSeekAtStart() {
        let plan = CastDLNA.loadPlan(controlURL: "http://h/ctl", mediaURL: "http://h/m.mp4", title: nil, contentType: nil, startSeconds: 1, vendor: .panasonic)
        XCTAssertEqual(plan.map(\.action), ["SetAVTransportURI", "Play"])
        XCTAssertEqual(plan.map(\.pauseAfterMilliseconds), [400, 0])
        XCTAssertTrue(plan[0].body.contains("http-get:*:video/mp4:DLNA.ORG_OP=01;"))
    }

    func testTransportCallsBuildExactBodiesAndActions() {
        XCTAssertEqual(CastDLNA.pauseCall(controlURL: "http://h/c").body, "<InstanceID>0</InstanceID>")
        XCTAssertEqual(CastDLNA.pauseCall(controlURL: "http://h/c").action, "Pause")
        XCTAssertEqual(CastDLNA.playCall(controlURL: "http://h/c").body, "<InstanceID>0</InstanceID><Speed>1</Speed>")
        XCTAssertEqual(CastDLNA.stopCall(controlURL: "http://h/c").action, "Stop")
        XCTAssertEqual(CastDLNA.seekCall(controlURL: "http://h/c", seconds: 61.9).body, "<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>00:01:01</Target>")
    }

    func testVolumeCallUsesRenderingControlAndClampsToRange() throws {
        let call = CastDLNA.volumeCall(volumeControlURL: "http://h/rc", percent: 140)
        XCTAssertEqual(call.service, "RenderingControl")
        XCTAssertTrue(call.body.contains("<Channel>Master</Channel><DesiredVolume>100</DesiredVolume>"))
        let request = try XCTUnwrap(call.request)
        XCTAssertEqual(request.value(forHTTPHeaderField: "SOAPAction"), "\"urn:schemas-upnp-org:service:RenderingControl:1#SetVolume\"")
        XCTAssertTrue(body(request).contains("<u:SetVolume xmlns:u=\"urn:schemas-upnp-org:service:RenderingControl:1\">"))
        XCTAssertTrue(CastDLNA.volumeCall(volumeControlURL: "http://h/rc", percent: -3).body.contains("<DesiredVolume>0</DesiredVolume>"))
    }

    func testPositionAndTransportInfoParseWithDesktopDefaults() {
        XCTAssertEqual(CastDLNA.parsePositionInfo("<RelTime>0:12:34</RelTime>"), 754)
        XCTAssertEqual(CastDLNA.parsePositionInfo("<RelTime>NOT_IMPLEMENTED</RelTime>"), 0)
        XCTAssertEqual(CastDLNA.parseTransportState("<CurrentTransportState>PAUSED_PLAYBACK</CurrentTransportState>"), "PAUSED_PLAYBACK")
        XCTAssertEqual(CastDLNA.parseTransportState("<x/>"), "UNKNOWN")
        XCTAssertEqual(CastDLNA.upnpErrorCode("<errorCode>714</errorCode>"), "714")
    }

    // MARK: Controller

    @MainActor
    func testStopHandsBackTheLastPositionForLocalResume() async {
        let transport = FakeCastTransport { request in
            let action = request.value(forHTTPHeaderField: "SOAPAction") ?? ""
            if action.contains("GetPositionInfo") { return CastReply(status: 200, body: "<RelTime>0:01:30</RelTime>") }
            if action.contains("GetTransportInfo") { return CastReply(status: 200, body: "<CurrentTransportState>PLAYING</CurrentTransportState>") }
            return CastReply(status: 200, body: "")
        }
        let controller = CastController(transport: transport, pollInterval: .seconds(3600))
        let target = CastTarget(id: "dlna-a", kind: .dlna, name: "TV", model: nil, host: "192.168.1.50", endpoint: "http://192.168.1.50/ctl", vendor: .other)
        await controller.cast(to: target, mediaURL: "http://h/m.mp4", contentType: nil, title: "A", startSeconds: 0)
        XCTAssertEqual(controller.phase, .playing)
        await controller.refresh()
        XCTAssertEqual(controller.positionSec, 90)
        await controller.stop()
        XCTAssertNil(controller.selected)
        XCTAssertEqual(controller.takeResumePosition(), 90)
        XCTAssertNil(controller.takeResumePosition())
    }

    @MainActor
    func testRejectedLoadClearsSelectionAndKeepsTheFailure() async {
        let transport = FakeCastTransport { request in
            let action = request.value(forHTTPHeaderField: "SOAPAction") ?? ""
            if action.contains("SetAVTransportURI") { return CastReply(status: 500, body: "<errorCode>714</errorCode>") }
            return CastReply(status: 200, body: "")
        }
        let controller = CastController(transport: transport, pollInterval: .seconds(3600))
        let target = CastTarget(id: "dlna-b", kind: .dlna, name: "Speaker", model: nil, host: "192.168.1.51", endpoint: "http://192.168.1.51/ctl", vendor: .other)
        await controller.cast(to: target, mediaURL: "http://h/m.mp4", contentType: nil, title: nil, startSeconds: 0)
        XCTAssertNil(controller.selected)
        XCTAssertEqual(controller.phase, .idle)
        XCTAssertNotNil(controller.failure)
        XCTAssertNil(controller.takeResumePosition())
    }

    @MainActor
    func testRokuLaunchFailsWithInstallStepsWhenMediaAssistantIsMissing() async {
        let transport = FakeCastTransport { request in
            if request.url?.path == "/query/apps" {
                return CastReply(status: 200, body: "<apps><app id=\"12\">Netflix</app></apps>")
            }
            return CastReply(status: 404, body: "")
        }
        let controller = CastController(transport: transport, pollInterval: .seconds(3600))
        let target = CastTarget(id: "roku-192.168.1.20", kind: .roku, name: "Roku", model: nil, host: "192.168.1.20", endpoint: "http://192.168.1.20:8060/")
        await controller.cast(to: target, mediaURL: "http://h/m.mkv", contentType: nil, title: nil, startSeconds: 0)
        XCTAssertNil(controller.selected)
        XCTAssertEqual(controller.failure?.steps.count, 4)
    }
}
