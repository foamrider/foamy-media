//! The cover's bytes: an HTTPS GET (what `curl -sf --proto =https
//! --max-redirs 0 --max-filesize 8000000 --max-time 8` did, with the size
//! checked on the bytes received rather than on disk afterwards) or a local
//! regular file. The deadline connector is foamy-zendesk's (foamy-train's),
//! which also bounds ureq's CONNECT-reply loop through a proxy.

use std::fs::File;
use std::io;
use std::path::Path;
use std::sync::{Arc, Mutex, OnceLock};
use std::time::{Duration, Instant};

use foamy_helper::{Failure, tls};
use rustix::fs::{FileType, Mode, OFlags};
use ureq::config::AutoHeaderValue;
use ureq::http::header::CONTENT_LENGTH;
use ureq::tls::{Certificate, RootCerts, TlsConfig, TlsProvider};
use ureq::unversioned::resolver::DefaultResolver;
use ureq::unversioned::transport::{
    Buffers, ConnectProxyConnector, ConnectionDetails, Connector, NextTimeout, RustlsConnector,
    TcpConnector, Transport,
};
use ureq::{Agent, Proxy, Timeout};

/// One deadline for the whole request (curl's `--max-time 8`).
pub const TIMEOUT: Duration = Duration::from_secs(8);
const USER_AGENT: &str = "foamy-media";

fn too_large() -> Failure {
    Failure::coded("TOO_LARGE", "the cover is larger than 8 MB")
}

fn unreadable(path: &Path, why: &str) -> Failure {
    Failure::coded("UNREADABLE", format!("{}: {why}", path.display()))
}

/// A local cover: a regular file (symlinks followed, as `[ -f ]` did) of at
/// most `max` bytes. `stat` decides before anything is opened, so a FIFO,
/// a device or a socket is never opened at all; the descriptor is opened
/// non-blocking and without becoming a controlling terminal, and `fstat`
/// must find the same regular file, so a swap in between is refused too.
/// The read stops after `max + 1` bytes whatever the file grew to.
pub fn local(path: &Path, max: u64) -> Result<Vec<u8>, Failure> {
    let regular =
        |stat: &rustix::fs::Stat| FileType::from_raw_mode(stat.st_mode) == FileType::RegularFile;
    let before = rustix::fs::stat(path).map_err(|error| unreadable(path, &error.to_string()))?;
    if !regular(&before) {
        return Err(unreadable(path, "not a regular file"));
    }
    let flags = OFlags::RDONLY | OFlags::NONBLOCK | OFlags::NOCTTY | OFlags::CLOEXEC;
    let fd = rustix::fs::open(path, flags, Mode::empty())
        .map_err(|error| unreadable(path, &error.to_string()))?;
    let stat = rustix::fs::fstat(&fd).map_err(|error| unreadable(path, &error.to_string()))?;
    if !regular(&stat) || stat.st_dev != before.st_dev || stat.st_ino != before.st_ino {
        return Err(unreadable(path, "not a regular file"));
    }
    if stat.st_size as u64 > max {
        return Err(too_large());
    }
    foamy_helper::io::read_limited(File::from(fd), max).map_err(|error| {
        if foamy_helper::io::is_over_limit(&error) {
            too_large()
        } else {
            unreadable(path, &error.to_string())
        }
    })
}

/// A remote cover over HTTPS, at most `max` bytes. The CPU check comes
/// first, so a handshake never aborts on missing instructions.
pub fn https(url: &str, max: u64) -> Result<Vec<u8>, Failure> {
    if !tls::cpu_supported() {
        return Err(Failure::coded("TLS_UNSUPPORTED", tls::UNSUPPORTED));
    }
    Client::new(true, Proxy::try_from_env()).get(url, TIMEOUT, max)
}

fn roots() -> Arc<Vec<Certificate<'static>>> {
    static ROOTS: OnceLock<Arc<Vec<Certificate<'static>>>> = OnceLock::new();
    ROOTS
        .get_or_init(|| {
            Arc::new(
                tls::system_roots_der()
                    .iter()
                    .map(|der| Certificate::from_der(der.as_ref()).to_owned())
                    .collect(),
            )
        })
        .clone()
}

#[derive(Debug, Clone, Default)]
struct Deadline(Arc<Mutex<Option<Instant>>>);

impl Deadline {
    fn set(&self, at: Instant) {
        *self.0.lock().unwrap_or_else(|e| e.into_inner()) = Some(at);
    }
    fn get(&self) -> Option<Instant> {
        *self.0.lock().unwrap_or_else(|e| e.into_inner())
    }
}

#[derive(Debug)]
struct DeadlineConnector(Deadline);

impl<In: Transport> Connector<In> for DeadlineConnector {
    type Out = DeadlineTransport<In>;

    fn connect(
        &self,
        _details: &ConnectionDetails,
        chained: Option<In>,
    ) -> Result<Option<Self::Out>, ureq::Error> {
        Ok(chained.map(|inner| DeadlineTransport {
            inner,
            deadline: self.0.clone(),
        }))
    }
}

/// Every read and write capped at the time left before the request's deadline.
#[derive(Debug)]
struct DeadlineTransport<T> {
    inner: T,
    deadline: Deadline,
}

impl<T> DeadlineTransport<T> {
    fn cap(&self, timeout: NextTimeout) -> Result<NextTimeout, ureq::Error> {
        let Some(at) = self.deadline.get() else {
            return Ok(timeout);
        };
        let left = at.saturating_duration_since(Instant::now());
        if left.is_zero() {
            return Err(ureq::Error::Timeout(Timeout::Global));
        }
        let left = left.into();
        Ok(if left < timeout.after {
            NextTimeout {
                after: left,
                reason: Timeout::Global,
                ..timeout
            }
        } else {
            timeout
        })
    }
}

impl<T: Transport> Transport for DeadlineTransport<T> {
    fn buffers(&mut self) -> &mut dyn Buffers {
        self.inner.buffers()
    }
    fn transmit_output(&mut self, amount: usize, timeout: NextTimeout) -> Result<(), ureq::Error> {
        let timeout = self.cap(timeout)?;
        self.inner.transmit_output(amount, timeout)
    }
    fn await_input(&mut self, timeout: NextTimeout) -> Result<bool, ureq::Error> {
        let timeout = self.cap(timeout)?;
        self.inner.await_input(timeout)
    }
    fn is_open(&mut self) -> bool {
        self.inner.is_open()
    }
    fn is_tls(&self) -> bool {
        self.inner.is_tls()
    }
}

struct Client {
    agent: Agent,
    deadline: Deadline,
}

impl Client {
    /// `https_only` is false only in tests, which talk to a loopback
    /// `http://` server; [`https`] always sets it.
    fn new(https_only: bool, proxy: Option<Proxy>) -> Client {
        let deadline = Deadline::default();
        let config = Agent::config_builder()
            .https_only(https_only)
            // A redirect would move the fetch off the host that was checked,
            // so none is followed: the 3xx comes back and is refused below.
            .max_redirects(0)
            .max_redirects_will_error(false)
            .http_status_as_error(false)
            .user_agent(USER_AGENT)
            // No compression: the bytes counted are the bytes decoded.
            .accept_encoding(AutoHeaderValue::None)
            .proxy(proxy)
            .tls_config(
                TlsConfig::builder()
                    .provider(TlsProvider::Rustls)
                    .root_certs(RootCerts::Specific(roots()))
                    .unversioned_rustls_crypto_provider(tls::provider())
                    .build(),
            );
        let connector =
            ().chain(ConnectProxyConnector::default())
                .chain(TcpConnector::default())
                .chain(DeadlineConnector(deadline.clone()))
                .chain(RustlsConnector::default());
        Client {
            agent: Agent::with_parts(config.build(), connector, DefaultResolver::default()),
            deadline,
        }
    }

    /// A 2xx body of at most `max` bytes, all within `timeout`.
    fn get(&self, url: &str, timeout: Duration, max: u64) -> Result<Vec<u8>, Failure> {
        self.deadline.set(Instant::now() + timeout);
        let mut response = self
            .agent
            .get(url)
            .config()
            .timeout_global(Some(timeout))
            .build()
            .call()
            .map_err(classify)?;
        let status = response.status();
        if !status.is_success() {
            return Err(Failure::coded(
                "HTTP",
                format!("the server answered {}", status.as_u16()),
            ));
        }
        // A declared size over the cap ends it before the body is read...
        let declared = response
            .headers()
            .get(CONTENT_LENGTH)
            .and_then(|value| value.to_str().ok())
            .and_then(|value| value.trim().parse::<u64>().ok());
        if declared.is_some_and(|length| length > max) {
            return Err(too_large());
        }
        // ...and the bytes that actually arrive are capped whatever was
        // declared (chunked, or a lying Content-Length). ureq's limit fails a
        // read that reaches it even at the end of the body, so allow one
        // byte more and check the length here.
        let data = response
            .body_mut()
            .with_config()
            .limit(max + 1)
            .read_to_vec()
            .map_err(classify)?;
        if data.len() as u64 > max {
            return Err(too_large());
        }
        Ok(data)
    }
}

fn timed_out() -> Failure {
    Failure::coded("TIMEOUT", "the cover took longer than 8 s")
}

fn classify(error: ureq::Error) -> Failure {
    match error {
        ureq::Error::Timeout(_) => timed_out(),
        ureq::Error::Io(ref io) if foamy_helper::net::is_deadline(io) => timed_out(),
        ureq::Error::Io(ref io) if io.kind() == io::ErrorKind::TimedOut => timed_out(),
        ureq::Error::BodyExceedsLimit(_) => too_large(),
        ureq::Error::StatusCode(code) => {
            Failure::coded("HTTP", format!("the server answered {code}"))
        }
        ureq::Error::TooManyRedirects | ureq::Error::RedirectFailed => {
            Failure::coded("HTTP", "the server redirected")
        }
        error => Failure::coded("NETWORK", error.to_string()),
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::{Read, Write};
    use std::net::{TcpListener, TcpStream};
    use std::os::unix::fs::symlink;
    use std::path::PathBuf;
    use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
    use std::thread;

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> TempDir {
            static N: AtomicU64 = AtomicU64::new(0);
            let path = std::env::temp_dir().join(format!(
                "foamy-media-fetch-{}-{}",
                std::process::id(),
                N.fetch_add(1, Ordering::Relaxed)
            ));
            std::fs::create_dir(&path).unwrap();
            TempDir(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = std::fs::remove_dir_all(&self.0);
        }
    }

    #[test]
    fn a_local_cover_is_read_up_to_the_cap() {
        let dir = TempDir::new();
        let path = dir.0.join("cover.jpg");
        std::fs::write(&path, b"0123456789").unwrap();
        assert_eq!(local(&path, 10).unwrap(), b"0123456789");
        assert_eq!(local(&path, 9).unwrap_err().code, "TOO_LARGE");
        // A symlink to a regular file is followed, as `[ -f ]` did.
        let link = dir.0.join("link.jpg");
        symlink(&path, &link).unwrap();
        assert_eq!(local(&link, 10).unwrap(), b"0123456789");
    }

    #[test]
    fn special_files_are_never_read() {
        let dir = TempDir::new();
        let fifo = dir.0.join("fifo");
        rustix::fs::mknodat(
            rustix::fs::CWD,
            &fifo,
            FileType::Fifo,
            Mode::from_raw_mode(0o600),
            0,
        )
        .unwrap();
        let started = Instant::now();
        assert_eq!(local(&fifo, 10).unwrap_err().code, "UNREADABLE");
        assert!(
            started.elapsed() < Duration::from_secs(1),
            "a FIFO blocked the read"
        );
        // A symlink to one is refused just the same.
        let link = dir.0.join("link");
        symlink(&fifo, &link).unwrap();
        assert_eq!(local(&link, 10).unwrap_err().code, "UNREADABLE");
        for path in ["/dev/zero", "/dev/null", "/proc/self", "/nonexistent/x"] {
            assert_eq!(
                local(Path::new(path), 10).unwrap_err().code,
                "UNREADABLE",
                "{path}"
            );
        }
        assert_eq!(local(&dir.0, 10).unwrap_err().code, "UNREADABLE");
    }

    /// A one-request HTTP server on loopback: `reply` gets the stream after
    /// the request head has been read.
    fn serve(reply: impl FnOnce(&mut TcpStream) + Send + 'static) -> String {
        let listener = TcpListener::bind("127.0.0.1:0").unwrap();
        let port = listener.local_addr().unwrap().port();
        thread::spawn(move || {
            let (mut stream, _) = listener.accept().unwrap();
            let mut head = Vec::new();
            let mut byte = [0u8; 1];
            while !head.ends_with(b"\r\n\r\n") && stream.read(&mut byte).unwrap_or(0) == 1 {
                head.push(byte[0]);
            }
            reply(&mut stream);
        });
        format!("http://127.0.0.1:{port}/cover")
    }

    fn get(url: &str, max: u64) -> Result<Vec<u8>, Failure> {
        Client::new(false, None).get(url, Duration::from_millis(1500), max)
    }

    #[test]
    fn a_body_within_the_cap_arrives_whole() {
        let url = serve(|stream| {
            let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 10\r\n\r\n0123456789");
        });
        assert_eq!(get(&url, 10).unwrap(), b"0123456789");
    }

    #[test]
    fn a_declared_size_over_the_cap_is_refused() {
        let url = serve(|stream| {
            let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 11\r\n\r\n01234567890");
        });
        assert_eq!(get(&url, 10).unwrap_err().code, "TOO_LARGE");
    }

    #[test]
    fn the_cap_holds_without_a_content_length() {
        // Chunked: nothing declared, so only the bytes received can decide.
        let url = serve(|stream| {
            let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n");
            for _ in 0..64 {
                if stream.write_all(b"400\r\n").is_err()
                    || stream.write_all(&[b'x'; 0x400]).is_err()
                    || stream.write_all(b"\r\n").is_err()
                {
                    return;
                }
            }
            let _ = stream.write_all(b"0\r\n\r\n");
        });
        assert_eq!(get(&url, 4096).unwrap_err().code, "TOO_LARGE");
    }

    #[test]
    fn the_cap_holds_when_the_server_closes_without_any_length() {
        let url = serve(|stream| {
            let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nConnection: close\r\n\r\n");
            let _ = stream.write_all(&[b'x'; 5000]);
        });
        assert_eq!(get(&url, 4096).unwrap_err().code, "TOO_LARGE");
    }

    #[test]
    fn a_redirect_is_not_followed() {
        let followed = Arc::new(AtomicBool::new(false));
        let elsewhere = {
            let followed = followed.clone();
            serve(move |stream| {
                followed.store(true, Ordering::SeqCst);
                let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nx");
            })
        };
        let url = serve(move |stream| {
            let reply =
                format!("HTTP/1.1 302 Found\r\nLocation: {elsewhere}\r\nContent-Length: 0\r\n\r\n");
            let _ = stream.write_all(reply.as_bytes());
        });
        let failure = get(&url, 10).unwrap_err();
        assert_eq!(failure.code, "HTTP");
        thread::sleep(Duration::from_millis(100));
        assert!(
            !followed.load(Ordering::SeqCst),
            "the redirect was followed"
        );
    }

    #[test]
    fn an_error_status_is_refused() {
        let url = serve(|stream| {
            let _ = stream.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 3\r\n\r\nnop");
        });
        assert_eq!(get(&url, 10).unwrap_err().code, "HTTP");
    }

    #[test]
    fn a_trickling_server_cannot_outlast_the_deadline() {
        let url = serve(|stream| {
            let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 100000\r\n\r\n");
            for _ in 0..100 {
                if stream.write_all(b" ").is_err() {
                    break;
                }
                thread::sleep(Duration::from_millis(100));
            }
        });
        let started = Instant::now();
        let failure = Client::new(false, None)
            .get(&url, Duration::from_millis(600), 1 << 20)
            .unwrap_err();
        assert_eq!(failure.code, "TIMEOUT");
        assert!(
            started.elapsed() < Duration::from_secs(3),
            "{:?}",
            started.elapsed()
        );
    }

    #[test]
    fn plain_http_is_refused_by_the_real_client() {
        let url = serve(|stream| {
            let _ = stream.write_all(b"HTTP/1.1 200 OK\r\nContent-Length: 1\r\n\r\nx");
        });
        let failure = Client::new(true, None)
            .get(&url, Duration::from_millis(500), 10)
            .unwrap_err();
        assert_eq!(failure.code, "NETWORK");
    }
}
