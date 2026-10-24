//! Owner-configured plugin HTTP. No cookies, proxy, credential store or application state.
use base64::{engine::general_purpose::STANDARD, Engine};
use reqwest::{header::HeaderMap, Method, Url};
use serde::{Deserialize, Serialize};
use std::{
    collections::BTreeMap,
    future::Future,
    net::{IpAddr, SocketAddr},
    time::Duration,
};

pub(crate) const MAX_BYTES: usize = 8 * 1024 * 1024;
const MAX_REDIRECTS: usize = 10;
const DEFAULT_UA: &str = "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/130.0.0.0 Safari/537.36";

#[derive(Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
pub(crate) struct Request {
    pub url: String,
    #[serde(default)]
    pub method: Option<String>,
    #[serde(default)]
    pub headers: BTreeMap<String, String>,
    #[serde(default)]
    pub body_base64: Option<String>,
    #[serde(default)]
    pub timeout_ms: Option<u64>,
    #[serde(default)]
    pub follow_redirects: Option<bool>,
    #[serde(default)]
    pub max_response_bytes: Option<usize>,
    #[serde(default)]
    pub strict_limit: bool,
    #[serde(default)]
    pub public_network_only: bool,
    #[serde(default)]
    pub allow_local_network: bool,
    #[serde(default)]
    pub allow_referer: Option<String>,
    #[serde(default)]
    pub allow_cookie: Option<String>,
    #[serde(default)]
    pub open_headers: bool,
    #[serde(default)]
    pub blocked_hosts: Vec<String>,
}

#[derive(Serialize)]
#[serde(rename_all = "camelCase")]
pub(crate) struct Response {
    pub status: u16,
    pub ok: bool,
    pub headers: BTreeMap<String, String>,
    pub body_base64: String,
    pub url: String,
    pub protocol_version: String,
}

pub(crate) async fn execute(request: Request) -> Result<Response, &'static str> {
    let timeout = Duration::from_millis(
        request
            .timeout_ms
            .filter(|value| *value != 0)
            .unwrap_or(20_000)
            .clamp(1_000, 45_000),
    );
    let allow_local = request.allow_local_network && !request.public_network_only;
    tokio::time::timeout(
        timeout,
        execute_with_resolver(request, move |url, public| {
            resolve_target(url, public, allow_local)
        }),
    )
    .await
    .map_err(|_| "plugin-network-timeout")?
}

async fn execute_with_resolver<F, Fut>(
    request: Request,
    resolve: F,
) -> Result<Response, &'static str>
where
    F: Fn(Url, bool) -> Fut,
    Fut: Future<Output = Result<Vec<SocketAddr>, &'static str>>,
{
    let mut target = Url::parse(&request.url).map_err(|_| "plugin-network-url")?;
    validate_request_url(&target, &request)?;
    let mut method = Method::from_bytes(
        request
            .method
            .as_deref()
            .unwrap_or("GET")
            .to_uppercase()
            .as_bytes(),
    )
    .map_err(|_| "plugin-network-method")?;
    let mut headers = filter_headers(&request, &target)?;
    let mut body = request
        .body_base64
        .as_ref()
        .map(|value| STANDARD.decode(value).map_err(|_| "plugin-network-body"))
        .transpose()?;
    if body
        .as_ref()
        .is_some_and(|bytes| bytes.len() > MAX_BYTES + 5)
    {
        return Err("plugin-network-body-size");
    }
    if method == Method::GET || method == Method::HEAD {
        body = None;
    }
    let limit = request
        .max_response_bytes
        .unwrap_or(MAX_BYTES)
        .min(MAX_BYTES);
    let mut redirects = 0;
    let mut response = loop {
        validate_request_url(&target, &request)?;
        let addresses = resolve(target.clone(), request.public_network_only).await?;
        if addresses.is_empty() {
            return Err("plugin-network-dns");
        }
        let host = target.host_str().ok_or("plugin-network-url")?;
        let client = reqwest::Client::builder()
            .no_proxy()
            .redirect(reqwest::redirect::Policy::none())
            .connect_timeout(Duration::from_secs(10))
            .pool_max_idle_per_host(0)
            .resolve_to_addrs(host, &addresses)
            .build()
            .map_err(|_| "plugin-network-client")?;
        let mut operation = client.request(method.clone(), target.clone());
        for (name, value) in &headers {
            operation = operation.header(name.as_str(), value.as_str());
        }
        if let Some(body) = &body {
            operation = operation.body(body.clone());
        }
        let response = operation.send().await.map_err(|error| {
            if error.is_timeout() {
                "plugin-network-timeout"
            } else {
                "plugin-network-request"
            }
        })?;
        let status = response.status().as_u16();
        if !request.follow_redirects.unwrap_or(true)
            || !matches!(status, 301 | 302 | 303 | 307 | 308)
        {
            break response;
        }
        let Some(location) = response.headers().get(reqwest::header::LOCATION) else {
            break response;
        };
        let location = location.to_str().map_err(|_| "plugin-network-redirect")?;
        let next = target
            .join(location)
            .map_err(|_| "plugin-network-redirect")?;
        redirects += 1;
        if redirects > MAX_REDIRECTS {
            return Err("plugin-network-redirect-limit");
        }
        if target.scheme() == "https" && next.scheme() == "http" {
            return Err("plugin-network-downgrade");
        }
        validate_request_url(&next, &request)?;
        let cross_origin = !same_origin(&target, &next);
        let had_body = body.is_some();
        apply_redirect_method(&mut method, &mut body, status);
        if cross_origin && body.is_some() {
            return Err("plugin-network-cross-origin-body");
        }
        if cross_origin {
            headers.retain(|name, _| {
                matches!(
                    name.as_str(),
                    "accept" | "accept-language" | "accept-encoding" | "user-agent" | "range"
                )
            });
        }
        if had_body && body.is_none() {
            headers.retain(|name, _| {
                !matches!(
                    name.as_str(),
                    "content-type" | "content-length" | "content-encoding" | "transfer-encoding"
                )
            });
        }
        target = next;
    };
    if request.strict_limit
        && response
            .content_length()
            .is_some_and(|length| length > limit as u64)
    {
        return Err("plugin-network-response-size");
    }
    let status = response.status().as_u16();
    let headers = response_headers(response.headers());
    let url = response.url().to_string();
    let protocol_version = match response.version() {
        reqwest::Version::HTTP_2 => "HTTP/2",
        reqwest::Version::HTTP_10 => "HTTP/1.0",
        _ => "HTTP/1.1",
    }
    .to_owned();
    let mut bytes = Vec::new();
    while let Some(chunk) = response
        .chunk()
        .await
        .map_err(|_| "plugin-network-response")?
    {
        let remaining = limit.saturating_sub(bytes.len());
        if chunk.len() > remaining {
            if request.strict_limit {
                return Err("plugin-network-response-size");
            }
            bytes.extend_from_slice(&chunk[..remaining]);
            break;
        }
        bytes.extend_from_slice(&chunk);
    }
    Ok(Response {
        status,
        ok: (200..300).contains(&status),
        headers,
        body_base64: STANDARD.encode(bytes),
        url,
        protocol_version,
    })
}

fn host_of(value: &str) -> Option<String> {
    let value = value.trim();
    if value.is_empty() {
        return None;
    }
    let url = if value.contains("://") {
        value.to_owned()
    } else {
        "https://".to_owned() + value
    };
    Url::parse(&url)
        .ok()?
        .host_str()
        .map(|host| host.trim_matches(['[', ']']).to_lowercase())
}

fn same_site(left: &str, right: &str) -> bool {
    let left = left.to_lowercase();
    let right = right.to_lowercase();
    let left = left.strip_suffix('.').unwrap_or(&left);
    let right = right.strip_suffix('.').unwrap_or(&right);
    if left == right {
        return true;
    }
    match (psl::domain(left.as_bytes()), psl::domain(right.as_bytes())) {
        (Some(first), Some(second)) => {
            first.suffix().is_known()
                && second.suffix().is_known()
                && first.as_bytes() == second.as_bytes()
        }
        _ => false,
    }
}

fn filter_headers(
    request: &Request,
    target: &Url,
) -> Result<BTreeMap<String, String>, &'static str> {
    let host = target
        .host_str()
        .ok_or("plugin-network-url")?
        .trim_matches(['[', ']']);
    let referer = request.allow_referer.as_deref().and_then(host_of);
    let cookie = request.allow_cookie.as_deref().and_then(host_of);
    let mut output = BTreeMap::new();
    for (name, value) in &request.headers {
        let name = name.to_ascii_lowercase();
        if name == "accept-encoding" || name.starts_with("x-harbor") {
            continue;
        }
        let keep = if name == "referer" || name == "origin" {
            request.open_headers
                || referer.as_deref().is_some_and(|allowed| {
                    host_of(value).is_some_and(|actual| {
                        same_site(&actual, host)
                            && same_site(&actual, allowed)
                            && same_site(host, allowed)
                    })
                })
        } else if name == "cookie" {
            request.open_headers
                || cookie
                    .as_deref()
                    .is_some_and(|allowed| same_site(host, allowed))
        } else if request.open_headers && (name == "authorization" || name.starts_with("sec-")) {
            true
        } else {
            !matches!(
                name.as_str(),
                "host"
                    | "cookie"
                    | "set-cookie"
                    | "authorization"
                    | "content-length"
                    | "connection"
                    | "origin"
                    | "referer"
            ) && !name.starts_with("sec-")
        };
        if keep {
            reqwest::header::HeaderName::from_bytes(name.as_bytes())
                .map_err(|_| "plugin-network-header")?;
            reqwest::header::HeaderValue::from_bytes(value.as_bytes())
                .map_err(|_| "plugin-network-header")?;
            output.insert(name, value.clone());
        }
    }
    output
        .entry("user-agent".to_owned())
        .or_insert_with(|| DEFAULT_UA.to_owned());
    output
        .entry("accept".to_owned())
        .or_insert_with(|| "application/json, text/plain, */*".to_owned());
    output
        .entry("accept-language".to_owned())
        .or_insert_with(|| "en-US,en;q=0.9".to_owned());
    Ok(output)
}

fn response_headers(headers: &HeaderMap) -> BTreeMap<String, String> {
    let mut output = BTreeMap::new();
    for (name, value) in headers {
        if matches!(
            name.as_str(),
            "content-type"
                | "content-length"
                | "last-modified"
                | "etag"
                | "date"
                | "cache-control"
                | "expires"
                | "content-language"
                | "content-encoding"
                | "content-disposition"
                | "content-range"
                | "accept-ranges"
                | "retry-after"
                | "link"
                | "location"
                | "vary"
                | "age"
                | "server"
                | "grpc-status"
                | "grpc-message"
                | "grpc-encoding"
                | "grpc-accept-encoding"
        ) {
            if let Ok(value) = value.to_str() {
                output.insert(name.to_string(), value.to_owned());
            }
        }
    }
    output
}

fn validate_url(url: &Url, blocked: &[String]) -> Result<(), &'static str> {
    validate_url_with_local(url, blocked, false)
}

fn validate_request_url(url: &Url, request: &Request) -> Result<(), &'static str> {
    if request.allow_local_network && !request.public_network_only {
        validate_url_with_local(url, &request.blocked_hosts, true)
    } else {
        validate_url(url, &request.blocked_hosts)
    }
}

fn validate_url_with_local(
    url: &Url,
    blocked: &[String],
    allow_local: bool,
) -> Result<(), &'static str> {
    if !matches!(url.scheme(), "http" | "https") {
        return Err("plugin-network-scheme");
    }
    let host = url
        .host_str()
        .ok_or("plugin-network-url")?
        .trim_matches(['[', ']'])
        .to_lowercase();
    if !allow_local
        && (host == "localhost"
            || host.ends_with(".localhost")
            || host.ends_with(".local")
            || host.ends_with(".internal")
            || host.starts_with("fc")
            || host.starts_with("fd")
            || host.starts_with("fe80:")
            || host.starts_with("64:ff9b:")
            || host.parse::<IpAddr>().is_ok_and(is_private_ip))
    {
        return Err("plugin-network-private");
    }
    if blocked.iter().any(|blocked| {
        let blocked = blocked.to_lowercase();
        host == blocked || host.ends_with(&(".".to_owned() + &blocked))
    }) {
        return Err("plugin-network-blocked");
    }
    Ok(())
}

fn unmap(ip: IpAddr) -> IpAddr {
    match ip {
        IpAddr::V6(value) => {
            if let Some(v4) = value.to_ipv4_mapped() {
                return IpAddr::V4(v4);
            }
            // iOS DNS64 can synthesize this /96 prefix on IPv6-only mobile networks.
            // Validate its embedded IPv4 while retaining the actual IPv6 socket address.
            let segments = value.segments();
            if segments[..6] == [0x64, 0xff9b, 0, 0, 0, 0] {
                let bytes = value.octets();
                return IpAddr::V4(std::net::Ipv4Addr::new(
                    bytes[12], bytes[13], bytes[14], bytes[15],
                ));
            }
            ip
        }
        _ => ip,
    }
}

fn is_private_ip(ip: IpAddr) -> bool {
    match unmap(ip) {
        IpAddr::V4(ip) => {
            let [a, b, _, _] = ip.octets();
            ip.is_broadcast()
                || a == 0
                || a == 10
                || a == 127
                || (a == 169 && b == 254)
                || (a == 172 && (16..=31).contains(&b))
                || (a == 192 && b == 168)
                || (a == 100 && (64..=127).contains(&b))
        }
        IpAddr::V6(ip) => {
            ip.is_loopback()
                || ip.is_unspecified()
                || (ip.segments()[0] & 0xfe00) == 0xfc00
                || (ip.segments()[0] & 0xffc0) == 0xfe80
                || (ip.segments()[0] == 0x64 && ip.segments()[1] == 0xff9b)
        }
    }
}

fn is_public_ip(ip: IpAddr) -> bool {
    match unmap(ip) {
        IpAddr::V4(ip) => {
            let [a, b, c, _] = ip.octets();
            !is_private_ip(IpAddr::V4(ip))
                && !(a >= 224
                    || (a == 192 && b == 0 && (c == 0 || c == 2))
                    || (a == 192 && b == 88 && c == 99)
                    || (a == 198 && (b == 18 || b == 19))
                    || (a == 198 && b == 51 && c == 100)
                    || (a == 203 && b == 0 && c == 113))
        }
        IpAddr::V6(ip) => {
            let s = ip.segments();
            (s[0] & 0xe000) == 0x2000
                && s[0] != 0x2002
                && !(s[0] == 0x2001 && s[1] == 0x0db8)
                && !(s[0] == 0x2001 && s[1] < 0x0200)
        }
    }
}

fn checked_addresses(
    mut values: Vec<SocketAddr>,
    public_only: bool,
) -> Result<Vec<SocketAddr>, &'static str> {
    if values.is_empty()
        || values.iter().any(|value| {
            if public_only {
                !is_public_ip(value.ip())
            } else {
                is_private_ip(value.ip())
            }
        })
    {
        return Err("plugin-network-private");
    }
    values.sort_unstable();
    values.dedup();
    Ok(values)
}

async fn resolve_target(
    url: Url,
    public_only: bool,
    allow_local: bool,
) -> Result<Vec<SocketAddr>, &'static str> {
    let host = url
        .host_str()
        .ok_or("plugin-network-url")?
        .trim_matches(['[', ']']);
    let port = url.port_or_known_default().ok_or("plugin-network-url")?;
    let values: Vec<SocketAddr> = if let Ok(ip) = host.parse::<IpAddr>() {
        vec![SocketAddr::new(ip, port)]
    } else {
        tokio::net::lookup_host((host, port))
            .await
            .map_err(|_| "plugin-network-dns")?
            .collect()
    };
    if allow_local && !public_only {
        if values.is_empty()
            || values.iter().any(|value| {
                value.ip().is_unspecified()
                    || value.ip().is_multicast()
                    || value.ip() == IpAddr::V4(std::net::Ipv4Addr::BROADCAST)
            })
        {
            return Err("plugin-network-private");
        }
        Ok(values)
    } else {
        checked_addresses(values, public_only)
    }
}

fn same_origin(left: &Url, right: &Url) -> bool {
    left.scheme() == right.scheme()
        && left.host_str() == right.host_str()
        && left.port_or_known_default() == right.port_or_known_default()
}

fn apply_redirect_method(method: &mut Method, body: &mut Option<Vec<u8>>, status: u16) {
    if status == 303 {
        if *method != Method::HEAD {
            *method = Method::GET;
        }
        *body = None;
    } else if (status == 301 || status == 302) && *method == Method::POST {
        *method = Method::GET;
        *body = None;
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;
    use std::{
        io::{Read, Write},
        net::TcpListener,
        sync::mpsc,
        thread,
        time::Instant,
    };

    fn request(url: &str) -> Request {
        serde_json::from_value(json!({"url":url})).unwrap()
    }
    fn run<F: Future>(future: F) -> F::Output {
        tokio::runtime::Builder::new_current_thread()
            .enable_all()
            .build()
            .unwrap()
            .block_on(future)
    }

    fn server(
        status: &str,
        headers: &str,
        body: &[u8],
    ) -> (u16, mpsc::Receiver<Vec<u8>>, thread::JoinHandle<()>) {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        listener.set_nonblocking(true).unwrap();
        let port = listener.local_addr().unwrap().port();
        let response = [
            format!(
                "HTTP/1.1 {status}\r\nContent-Length: {}\r\nConnection: close\r\n{headers}\r\n",
                body.len()
            )
            .into_bytes(),
            body.to_vec(),
        ]
        .concat();
        let (sender, receiver) = mpsc::channel();
        let task = thread::spawn(move || {
            let deadline = Instant::now() + Duration::from_secs(5);
            let mut stream = loop {
                match listener.accept() {
                    Ok((stream, _)) => break stream,
                    Err(error)
                        if error.kind() == std::io::ErrorKind::WouldBlock
                            && Instant::now() < deadline =>
                    {
                        thread::sleep(Duration::from_millis(5))
                    }
                    Err(error) => panic!("owned fixture accept: {error}"),
                }
            };
            stream
                .set_read_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            stream
                .set_write_timeout(Some(Duration::from_secs(5)))
                .unwrap();
            let mut bytes = Vec::new();
            loop {
                let mut buffer = [0; 1024];
                let count = stream.read(&mut buffer).unwrap();
                if count == 0 {
                    break;
                }
                bytes.extend_from_slice(&buffer[..count]);
                assert!(bytes.len() < 16 * 1024);
                if let Some(header_end) = bytes.windows(4).position(|value| value == b"\r\n\r\n") {
                    let text = String::from_utf8_lossy(&bytes[..header_end]).to_lowercase();
                    let length = text
                        .lines()
                        .find_map(|line| {
                            line.strip_prefix("content-length:")
                                .and_then(|value| value.trim().parse::<usize>().ok())
                        })
                        .unwrap_or(0);
                    if bytes.len() >= header_end + 4 + length {
                        break;
                    }
                }
            }
            sender.send(bytes).unwrap();
            stream.write_all(&response).unwrap();
        });
        (port, receiver, task)
    }

    async fn owned_resolver(url: Url, _: bool) -> Result<Vec<SocketAddr>, &'static str> {
        Ok(vec![SocketAddr::from((
            [127, 0, 0, 1],
            url.port().unwrap(),
        ))])
    }

    #[test]
    fn plugin_http_private_mixed_dns_reserved_and_dns64_addresses() {
        for value in [
            "127.0.0.1",
            "10.0.0.1",
            "172.16.0.1",
            "192.168.1.1",
            "100.64.0.1",
            "169.254.1.1",
            "::1",
            "fd00::1",
            "fe80::1",
            "::ffff:127.0.0.1",
            "64:ff9b::a00:1",
        ] {
            assert!(is_private_ip(value.parse().unwrap()), "{value}");
        }
        for value in [
            "192.0.0.1",
            "192.0.0.255",
            "192.0.2.1",
            "192.0.2.254",
            "198.51.100.1",
            "203.0.113.1",
            "224.0.0.1",
            "2001:db8::1",
            "2002::1",
        ] {
            assert!(!is_public_ip(value.parse().unwrap()), "{value}");
        }
        for value in [
            "8.8.8.8",
            "192.0.1.1",
            "192.0.66.69",
            "192.0.78.1",
            "172.15.1.1",
            "2606:4700:4700::1111",
            "64:ff9b::808:808",
        ] {
            assert!(is_public_ip(value.parse().unwrap()), "{value}");
        }
        assert!(checked_addresses(
            vec![
                "8.8.8.8:443".parse().unwrap(),
                "127.0.0.1:443".parse().unwrap()
            ],
            false
        )
        .is_err());
        assert!(checked_addresses(vec!["8.8.8.8:443".parse().unwrap()], true).is_ok());
        assert!(checked_addresses(vec!["192.0.66.69:443".parse().unwrap()], true).is_ok());
        assert!(checked_addresses(
            vec![
                "192.0.66.69:443".parse().unwrap(),
                "192.0.2.1:443".parse().unwrap()
            ],
            true
        )
        .is_err());
    }

    #[test]
    fn plugin_http_header_gates_use_private_suffixes_and_owned_permissions() {
        assert!(same_site(
            "cdn.reader.example.co.uk",
            "reader.example.co.uk."
        ));
        assert!(!same_site("alice.github.io", "bob.github.io"));
        assert!(!same_site("first.blogspot.com", "second.blogspot.com"));
        assert!(!same_site("first.owned-invalid", "second.owned-invalid"));
        let mut request = request("https://cdn.reader.example.co.uk/path");
        request.allow_referer = Some("https://reader.example.co.uk".to_owned());
        request.allow_cookie = Some(request.url.clone());
        request.headers = [
            ("Referer", "https://reader.example.co.uk/one"),
            ("Cookie", "owned=cookie"),
            ("Authorization", "Bearer owned"),
            ("X-Owned", "owned"),
            ("Accept-Encoding", "gzip"),
            ("X-Harbor-Test", "never"),
        ]
        .into_iter()
        .map(|(key, value)| (key.to_owned(), value.to_owned()))
        .collect();
        let filtered = filter_headers(&request, &Url::parse(&request.url).unwrap()).unwrap();
        assert_eq!(
            filtered.get("referer").map(String::as_str),
            Some("https://reader.example.co.uk/one")
        );
        assert!(filtered.contains_key("cookie") && filtered.contains_key("x-owned"));
        assert!(
            !filtered.contains_key("authorization")
                && !filtered.contains_key("accept-encoding")
                && !filtered.contains_key("x-harbor-test")
        );
        request.allow_referer = Some("https://unrelated.example.org".to_owned());
        request.allow_cookie = None;
        assert!(
            !filter_headers(&request, &Url::parse(&request.url).unwrap())
                .unwrap()
                .contains_key("referer")
        );
        request.open_headers = true;
        let open = filter_headers(&request, &Url::parse(&request.url).unwrap()).unwrap();
        assert!(
            open.contains_key("authorization")
                && open.contains_key("referer")
                && open.contains_key("cookie")
        );
        assert!(!open.contains_key("accept-encoding") && !open.contains_key("x-harbor-test"));
    }

    #[test]
    fn plugin_http_rejects_schemes_private_hosts_and_blocked_hops() {
        for value in [
            "file:///owned",
            "https://localhost/a",
            "http://127.1/a",
            "https://[::1]/",
            "https://server.local/a",
            "https://[64:ff9b::808:808]/",
        ] {
            assert!(validate_url(&Url::parse(value).unwrap(), &[]).is_err());
        }
        assert!(validate_url(
            &Url::parse("https://cdn.tracker.example.org/path").unwrap(),
            &["tracker.example.org".to_owned()]
        )
        .is_err());
        assert!(validate_url(&Url::parse("https://public.example.org/path").unwrap(), &[]).is_ok());
    }

    #[test]
    fn plugin_http_configured_reading_can_use_an_actual_loopback_source() {
        let (port, received, task) = server(
            "200 OK",
            "Content-Type: text/plain\r\n",
            b"owned local source",
        );
        let mut request = request(&format!("http://127.0.0.1:{port}/reading"));
        request.allow_local_network = true;
        let response = run(execute(request)).unwrap();
        assert_eq!(
            STANDARD.decode(response.body_base64).unwrap(),
            b"owned local source"
        );
        assert!(received
            .recv()
            .unwrap()
            .starts_with(b"GET /reading HTTP/1.1"));
        task.join().unwrap();
    }

    #[test]
    fn plugin_http_reading_permission_cannot_override_public_policy_blocked_hosts_or_schemes() {
        let target = Url::parse("http://127.0.0.1:18734/page").unwrap();
        let mut reading = request(target.as_str());
        assert!(validate_request_url(&target, &reading).is_err());
        reading.allow_local_network = true;
        assert!(validate_request_url(&target, &reading).is_ok());
        reading.public_network_only = true;
        assert!(validate_request_url(&target, &reading).is_err());
        reading.public_network_only = false;
        reading.blocked_hosts.push("127.0.0.1".to_owned());
        assert!(validate_request_url(&target, &reading).is_err());
        assert!(validate_request_url(&Url::parse("file:///owned").unwrap(), &reading).is_err());
    }

    #[test]
    fn plugin_http_actual_owned_socket_preserves_binary_and_filters_response_headers() {
        let (port, received, task) = server("200 OK", "ETag: owned-tag\r\nSet-Cookie: hidden=owned\r\nContent-Type: application/octet-stream\r\n", &[0, 1, 255, 2]);
        let request = request(&format!("http://owned.example.invalid:{port}/bytes"));
        let response = run(execute_with_resolver(request, owned_resolver)).unwrap();
        assert_eq!(
            STANDARD.decode(response.body_base64).unwrap(),
            [0, 1, 255, 2]
        );
        assert_eq!(
            response.headers.get("etag").map(String::as_str),
            Some("owned-tag")
        );
        assert!(!response.headers.contains_key("set-cookie"));
        let original =
            String::from_utf8(received.recv_timeout(Duration::from_secs(5)).unwrap()).unwrap();
        assert!(original.contains(&format!("host: owned.example.invalid:{port}")));
        task.join().unwrap();
    }

    #[test]
    fn plugin_http_actual_redirect_drops_custom_credentials_and_post_body() {
        let (final_port, final_request, final_task) = server("200 OK", "", b"owned");
        let location = format!("Location: http://other.example.invalid:{final_port}/final\r\n");
        let (first_port, first_request, first_task) = server("302 Found", &location, b"");
        let mut request = request(&format!(
            "http://first.example.invalid:{first_port}/redirect"
        ));
        request.method = Some("POST".to_owned());
        request.body_base64 = Some(STANDARD.encode(b"owned-body"));
        request.open_headers = true;
        request
            .headers
            .insert("Authorization".to_owned(), "Bearer owned".to_owned());
        request
            .headers
            .insert("X-Owned-Secret".to_owned(), "owned-private".to_owned());
        let response = run(execute_with_resolver(request, owned_resolver)).unwrap();
        assert_eq!(response.status, 200);
        let first = String::from_utf8(first_request.recv_timeout(Duration::from_secs(5)).unwrap())
            .unwrap()
            .to_lowercase();
        let second = String::from_utf8(final_request.recv_timeout(Duration::from_secs(5)).unwrap())
            .unwrap()
            .to_lowercase();
        assert!(
            first.starts_with("post ")
                && first.contains("bearer owned")
                && first.ends_with("owned-body")
        );
        assert!(
            second.starts_with("get ")
                && !second.contains("bearer owned")
                && !second.contains("owned-private")
                && !second.contains("owned-body")
        );
        first_task.join().unwrap();
        final_task.join().unwrap();
    }

    #[test]
    fn plugin_http_actual_limits_and_non_replayable_redirect_body() {
        for strict in [true, false] {
            let (port, received, task) = server("200 OK", "", b"12345678");
            let mut request = request(&format!("http://owned.example.invalid:{port}/bounded"));
            request.max_response_bytes = Some(3);
            request.strict_limit = strict;
            let response = run(execute_with_resolver(request, owned_resolver));
            if strict {
                assert_eq!(response.err(), Some("plugin-network-response-size"));
            } else {
                assert_eq!(
                    STANDARD.decode(response.unwrap().body_base64).unwrap(),
                    b"123"
                );
            }
            received.recv_timeout(Duration::from_secs(5)).unwrap();
            task.join().unwrap();
        }
        let (port, received, task) = server(
            "307 Temporary Redirect",
            "Location: http://other.example.invalid:9/never\r\n",
            b"",
        );
        let mut request = request(&format!("http://owned.example.invalid:{port}/no-replay"));
        request.method = Some("POST".to_owned());
        request.body_base64 = Some(STANDARD.encode(b"owned-body"));
        assert_eq!(
            run(execute_with_resolver(request, owned_resolver)).err(),
            Some("plugin-network-cross-origin-body")
        );
        received.recv_timeout(Duration::from_secs(5)).unwrap();
        task.join().unwrap();
    }
}
