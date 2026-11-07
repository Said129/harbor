import Foundation

/// Desktop's vendor buckets (`dlna.rs`, `DlnaVendor`). They pick the MIME type, the DIDL profile and the Sony/Panasonic pauses.
enum DLNAVendor: String, Equatable, Sendable {
    case samsung
    case lgWebos
    case sonyBravia
    case panasonic
    case hisenseVidaa
    case other
}

/// A renderer's device description after parsing (`dlna.rs`, `fetch_device`), with the control URLs resolved against the description URL.
struct CastDLNADescription: Equatable, Sendable {
    let name: String
    let model: String?
    let manufacturer: String?
    let vendor: DLNAVendor
    let avTransportURL: String
    let renderingControlURL: String?
}

/// One SOAP call of a load or a transport command. `CastController` sends it and applies the Desktop pauses around it.
struct CastSOAPCall: Equatable, Sendable {
    let service: String
    let action: String
    let controlURL: String
    let body: String
    /// Desktop ignores the result of Stop before a Sony load.
    var ignoresFailure = false
    var pauseAfterMilliseconds = 0
    /// Desktop retries a failed Seek once after this pause and ignores the second result.
    var retryAfterMilliseconds: Int?

    var request: URLRequest? {
        CastDLNA.soapRequest(controlURL: controlURL, service: service, action: action, body: body)
    }
}

enum CastDLNA {
    static let avTransport = "AVTransport"
    static let renderingControl = "RenderingControl"

    /// Desktop's `classify_vendor`, the same substring rules in the same order.
    static func classifyVendor(name: String, model: String, manufacturer: String) -> DLNAVendor {
        let n = name.lowercased()
        let mo = model.lowercased()
        let mf = manufacturer.lowercased()
        if mf.contains("samsung") || n.contains("samsung") || mo.contains("samsung") { return .samsung }
        if mf.contains("lg") || mo.contains("webos") || n.contains("[lg]") || n.hasPrefix("lg ") || mo.hasPrefix("lg ") { return .lgWebos }
        if mf.contains("sony") || n.contains("bravia") || mo.contains("bravia") || mo.hasPrefix("kdl-") || mo.hasPrefix("kd-") || mo.hasPrefix("xbr-") { return .sonyBravia }
        if mf.contains("panasonic") || n.contains("viera") || mo.contains("viera") { return .panasonic }
        if mf.contains("hisense") || mo.contains("vidaa") || n.contains("vidaa") || n.contains("hisense") { return .hisenseVidaa }
        return .other
    }

    /// Desktop's `fetch_device` on an already-downloaded description. Throws when there is no AVTransport service.
    static func parseDescription(_ xml: String, location: String) throws -> CastDLNADescription {
        guard let avControl = serviceControl(xml, service: avTransport) else { throw CastProtocolError.noAVTransport }
        let name = CastXML.tag(xml, "friendlyName") ?? CastXML.tag(xml, "roomName") ?? "Media Renderer"
        let model = CastXML.tag(xml, "modelName")
        let manufacturer = CastXML.tag(xml, "manufacturer")
        let vendor = classifyVendor(name: name, model: model ?? "", manufacturer: manufacturer ?? "")
        let rendering = serviceControl(xml, service: renderingControl).map { CastNet.resolve(location, $0) }
        return CastDLNADescription(
            name: name,
            model: model,
            manufacturer: manufacturer,
            vendor: vendor,
            avTransportURL: CastNet.resolve(location, avControl),
            renderingControlURL: rendering
        )
    }

    /// Desktop's `extract_service_control`: the controlURL of the first `<service>` block whose type names the service.
    static func serviceControl(_ xml: String, service: String) -> String? {
        var rest = Substring(xml)
        while let start = rest.range(of: "<service>") {
            guard let end = rest[start.upperBound...].range(of: "</service>") else { return nil }
            let block = String(rest[start.lowerBound..<end.lowerBound])
            if block.contains(":\(service):"), let url = CastXML.tag(block, "controlURL") {
                return url
            }
            rest = rest[end.upperBound...]
        }
        return nil
    }

    static func envelope(service: String, action: String, body: String) -> String {
        "<?xml version=\"1.0\" encoding=\"utf-8\"?>"
            + "<s:Envelope xmlns:s=\"http://schemas.xmlsoap.org/soap/envelope/\" s:encodingStyle=\"http://schemas.xmlsoap.org/soap/encoding/\">"
            + "<s:Body><u:\(action) xmlns:u=\"urn:schemas-upnp-org:service:\(service):1\">\(body)</u:\(action)></s:Body>"
            + "</s:Envelope>"
    }

    static func soapRequest(controlURL: String, service: String, action: String, body: String) -> URLRequest? {
        CastNet.request(
            controlURL,
            method: "POST",
            timeout: 6,
            headers: [
                "Content-Type": "text/xml; charset=\"utf-8\"",
                "SOAPAction": "\"urn:schemas-upnp-org:service:\(service):1#\(action)\"",
            ],
            body: envelope(service: service, action: action, body: body)
        )
    }

    /// Desktop's `pick_vendor_mime`: the MIME type when the content type is unknown.
    static func pickVendorMime(vendor: DLNAVendor, isLive: Bool) -> String {
        switch (vendor, isLive) {
        case (.sonyBravia, true), (.panasonic, true), (.lgWebos, true), (.hisenseVidaa, true):
            return "video/mpeg"
        case (_, true):
            return "video/mp2t"
        case (_, false):
            return "video/mp4"
        }
    }

    /// Desktop's `build_didl`: the DIDL-Lite item with the vendor's profile and namespace additions.
    static func buildDIDL(url: String, title: String, mime: String, isLive: Bool, vendor: DLNAVendor) -> String {
        let audio = mime.trimmingCharacters(in: .whitespacesAndNewlines).lowercased().hasPrefix("audio/")
        let itemClass: String
        if audio {
            itemClass = "object.item.audioItem.musicTrack"
        } else if isLive {
            itemClass = "object.item.videoItem.videoBroadcast"
        } else {
            itemClass = "object.item.videoItem"
        }
        let profile: String
        if audio {
            profile = ""
        } else {
            switch (vendor, isLive) {
            case (.sonyBravia, true): profile = "DLNA.ORG_PN=AVC_TS_HD_60_AC3_ISO;"
            case (.sonyBravia, false): profile = "DLNA.ORG_PN=AVC_MP4_MP_HD_AC3;"
            case (.panasonic, true): profile = "DLNA.ORG_PN=MPEG_TS_SD_NA;"
            case (_, true): profile = "DLNA.ORG_PN=MPEG_TS;"
            default: profile = ""
            }
        }
        let operations = isLive ? "00" : "01"
        let protocolTail = ":" + profile + "DLNA.ORG_OP=" + operations + ";DLNA.ORG_CI=0;DLNA.ORG_FLAGS=01700000000000000000000000000000"
        let vendorNamespace: String
        switch vendor {
        case .sonyBravia: vendorNamespace = " xmlns:av=\"urn:schemas-sony-com:av\""
        case .panasonic: vendorNamespace = " xmlns:pv=\"http://www.pv.com/pvns/\""
        default: vendorNamespace = ""
        }
        return "<DIDL-Lite xmlns=\"urn:schemas-upnp-org:metadata-1-0/DIDL-Lite/\" xmlns:dc=\"http://purl.org/dc/elements/1.1/\" xmlns:upnp=\"urn:schemas-upnp-org:metadata-1-0/upnp/\" xmlns:sec=\"http://www.sec.co.kr/\"\(vendorNamespace)>"
            + "<item id=\"0\" parentID=\"-1\" restricted=\"1\">"
            + "<dc:title>\(CastNet.xmlEscape(title))</dc:title>"
            + "<upnp:class>\(itemClass)</upnp:class>"
            + "<res protocolInfo=\"http-get:*:\(CastNet.xmlEscape(mime))\(protocolTail)\">\(CastNet.xmlEscape(url))</res>"
            + "</item></DIDL-Lite>"
    }

    /// Desktop's `load` as an ordered plan: Sony stops first, SetAVTransportURI, Play, then Seek to the resume point.
    static func loadPlan(controlURL: String, mediaURL: String, title: String?, contentType: String?, startSeconds: Double?, vendor: DLNAVendor, isLive: Bool = false) -> [CastSOAPCall] {
        let mime = contentType ?? pickVendorMime(vendor: vendor, isLive: isLive)
        let metadata = buildDIDL(url: mediaURL, title: title ?? "Harbor", mime: mime, isLive: isLive, vendor: vendor)
        let seeks = (startSeconds ?? 0) > 1
        var plan: [CastSOAPCall] = []
        if vendor == .sonyBravia {
            plan.append(CastSOAPCall(service: avTransport, action: "Stop", controlURL: controlURL, body: instance, ignoresFailure: true, pauseAfterMilliseconds: 200))
        }
        let setURI = "<InstanceID>0</InstanceID><CurrentURI>\(CastNet.xmlEscape(mediaURL))</CurrentURI><CurrentURIMetaData>\(CastNet.xmlEscape(metadata))</CurrentURIMetaData>"
        let settle = (vendor == .sonyBravia || vendor == .panasonic) ? 400 : 0
        plan.append(CastSOAPCall(service: avTransport, action: "SetAVTransportURI", controlURL: controlURL, body: setURI, pauseAfterMilliseconds: settle))
        plan.append(CastSOAPCall(service: avTransport, action: "Play", controlURL: controlURL, body: playBody, pauseAfterMilliseconds: seeks ? 1200 : 0))
        if let startSeconds, seeks {
            plan.append(CastSOAPCall(service: avTransport, action: "Seek", controlURL: controlURL, body: seekBody(startSeconds), retryAfterMilliseconds: 700))
        }
        return plan
    }

    static let instance = "<InstanceID>0</InstanceID>"
    static let playBody = "<InstanceID>0</InstanceID><Speed>1</Speed>"

    static func playCall(controlURL: String) -> CastSOAPCall {
        CastSOAPCall(service: avTransport, action: "Play", controlURL: controlURL, body: playBody)
    }

    static func pauseCall(controlURL: String) -> CastSOAPCall {
        CastSOAPCall(service: avTransport, action: "Pause", controlURL: controlURL, body: instance)
    }

    static func stopCall(controlURL: String) -> CastSOAPCall {
        CastSOAPCall(service: avTransport, action: "Stop", controlURL: controlURL, body: instance)
    }

    static func seekCall(controlURL: String, seconds: Double) -> CastSOAPCall {
        CastSOAPCall(service: avTransport, action: "Seek", controlURL: controlURL, body: seekBody(seconds))
    }

    /// REL_TIME seek body (`dlna.rs`, `seek`).
    static func seekBody(_ seconds: Double) -> String {
        "<InstanceID>0</InstanceID><Unit>REL_TIME</Unit><Target>\(CastNet.formatHMS(seconds))</Target>"
    }

    /// RenderingControl SetVolume on the master channel. Desktop 0.9.132 has no volume call; this is added for iOS. The value is clamped to 0...100.
    static func volumeCall(volumeControlURL: String, percent: Int) -> CastSOAPCall {
        let level = min(max(percent, 0), 100)
        return CastSOAPCall(
            service: renderingControl,
            action: "SetVolume",
            controlURL: volumeControlURL,
            body: "<InstanceID>0</InstanceID><Channel>Master</Channel><DesiredVolume>\(level)</DesiredVolume>"
        )
    }

    static func positionInfoCall(controlURL: String) -> CastSOAPCall {
        CastSOAPCall(service: avTransport, action: "GetPositionInfo", controlURL: controlURL, body: instance)
    }

    static func transportInfoCall(controlURL: String) -> CastSOAPCall {
        CastSOAPCall(service: avTransport, action: "GetTransportInfo", controlURL: controlURL, body: instance)
    }

    /// Desktop's `status`: `RelTime` from GetPositionInfo, zero when missing.
    static func parsePositionInfo(_ xml: String) -> Double {
        CastNet.parseHMS(CastXML.tag(xml, "RelTime") ?? "0:00:00")
    }

    /// Desktop's `status`: `CurrentTransportState`, `UNKNOWN` when missing.
    static func parseTransportState(_ xml: String) -> String {
        CastXML.tag(xml, "CurrentTransportState") ?? "UNKNOWN"
    }

    /// The `errorCode` of a SOAP fault, which Desktop puts in its error text.
    static func upnpErrorCode(_ xml: String) -> String? {
        CastXML.tag(xml, "errorCode")
    }
}
