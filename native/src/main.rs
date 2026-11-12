//! `foamy-media-helper`: the album-art probe of the foamy-media plugin. It
//! replaces the `/bin/sh` script (curl, od, awk, dd, ImageMagick) the plugin
//! ran for every cover, with the same bounds.
//!
//! ```text
//! foamy-media-helper art-probe <target>
//! ```
//!
//! `<target>` is what `Model.artProbeTarget` returns: an `https://` URL on
//! one of the cover hosts (`scdn.co`, `ytimg.com` and their subdomains; no
//! credentials, no port, no space or control character), or an absolute
//! local path (no control character). Both are checked again here.
//!
//! # Reply
//!
//! Exactly one compact JSON line on stdout, also on failure:
//!
//! - `{"ok":true,"mean":"#rrggbb","file":<path>,"swatches":[{"count":n,"hex":"#rrggbb"},…]}`
//!   (exit 0): the cover's mean colour, the normalised copy the panel may
//!   display, and ImageMagick's eight-colour histogram of it (empty when
//!   that last decode failed; the colour then falls back to the mean).
//! - `{"ok":false,"code":…,"error":…}`: exit 2 for `INVALID_ARGUMENT`, 101
//!   for `INTERNAL` (a helper bug), otherwise 1, with code
//!   `TLS_UNSUPPORTED` (`foamy_helper::tls::UNSUPPORTED`; don't retry),
//!   `TIMEOUT`, `NETWORK`, `HTTP` (not a 2xx, a redirect included),
//!   `TOO_LARGE`, `UNREADABLE` (no such file, or not a regular file),
//!   `EMPTY`, `UNSUPPORTED_FORMAT`, `INVALID_PNG`, `MAGICK_MISSING`,
//!   `DECODE_FAILED` or `CACHE_FAILED`.
//!
//! stderr stays empty: ImageMagick's diagnostics are captured and dropped.
//!
//! # Steps
//!
//! 1. The bytes, at most 8,000,000 of them (`fetch`): an HTTPS GET with no
//!    redirects followed, one 8 s deadline for DNS, connect, proxy, TLS,
//!    head and body, a declared `Content-Length` over the cap refused before
//!    the body is read and the cap enforced again on the bytes received;
//!    or a local file that `stat` (following symlinks, as `[ -f ]` did)
//!    and `fstat` of the opened descriptor both call a regular file, opened
//!    `O_NONBLOCK | O_NOCTTY` so a FIFO or a terminal can't stall or adopt
//!    the helper. An empty result is refused.
//! 2. The format, from the magic bytes only (`image::format`): JPEG, PNG,
//!    GIF, BMP or WebP, named to ImageMagick as `<CODER>:-[0]`, so its own
//!    content sniffing (and every delegate and vector coder behind it) never
//!    decides. Anything else is `UNSUPPORTED_FORMAT`.
//! 3. A PNG loses its `tEXt`, `zTXt` and `iTXt` chunks (`image::strip_text`)
//!    before ImageMagick reads a byte: libpng inflates and keeps them outside
//!    every ImageMagick limit. The walk reads chunk headers only, checks
//!    each length, type and (for critical chunks) CRC, needs `IHDR` first
//!    and `IEND` last, drops what follows `IEND`, and allows at most 64
//!    kept ranges; anything else is `INVALID_PNG`.
//! 4. ImageMagick (`magick` from `PATH`, as before; `MAGICK_MISSING` without
//!    it) decodes three times, each a bounded child with the cleaned bytes
//!    on stdin: the 1x1 mean, the cover written for the panel
//!    (`-resize 640x640> -strip`, PNG on stdout) and the histogram
//!    (`-resize 80x80 -colors 8`). Each run gets the old limits
//!    (`MAGICK_WIDTH_LIMIT=8KP`, `MAGICK_HEIGHT_LIMIT=8KP`,
//!    `MAGICK_AREA_LIMIT=128MP`, `MAGICK_MEMORY_LIMIT=256MiB`,
//!    `MAGICK_MAP_LIMIT=512MiB`, `MAGICK_TIME_LIMIT=10`,
//!    `MAGICK_THREAD_LIMIT=2`), an environment of `PATH`, `HOME`, `TMPDIR`
//!    and `LC_ALL=C` only, a 15 s deadline, 20 s of CPU, no core dumps, a cap
//!    on its output, its own process group (killed as a whole) and
//!    `SIGKILL` if the helper dies.
//! 5. The cover goes to `${XDG_CACHE_HOME:-$HOME/.cache}/foamy-media/covers`
//!    (created 0700, tightened to 0700 if wider, then checked to be this
//!    user's private directory) as `<first 32 hex of sha256(cleaned bytes)>.png`,
//!    written atomically, mode 0600, unless that file is already there (then
//!    only its modification time is refreshed). The newest eight covers are
//!    kept, the current one always; other names are never touched.
//!
//! # Deadline
//!
//! The panel runs the helper under `timeout --kill-after=2s 60s`
//! (`MediaService.qml`), which signals the helper alone, not the
//! ImageMagick runs in their own process groups. The whole run therefore
//! has a 55 s budget (`foamy_helper::process::set_run_budget`): every
//! decode ends by then, and one that would start later doesn't start and
//! fails as a timeout, so the panel always gets the reply. The steps'
//! own deadlines add up to 53 s (8 s fetch, three 15 s decodes).

mod cache;
mod fetch;
mod image;
mod magick;

use std::path::PathBuf;
use std::process::ExitCode;
use std::time::Duration;

use foamy_helper::{Failure, json, process};
use serde_json::{Value, json};

/// The most bytes a cover may have. A cover is a few hundred kilobytes;
/// anything far past that is not one.
pub const MAX_BYTES: u64 = 8_000_000;

/// The whole run's deadline, under the panel's 60 s `timeout` (module doc,
/// "Deadline").
const RUN_BUDGET: Duration = Duration::from_secs(55);

/// The only hosts whose images are fetched, matched on a label boundary
/// (Model.js `artHosts`, kept in step).
const HOSTS: [&str; 2] = ["scdn.co", "ytimg.com"];

fn invalid(message: &str) -> Failure {
    Failure::coded("INVALID_ARGUMENT", message).with_exit_code(2)
}

fn args() -> Result<Vec<String>, Failure> {
    std::env::args_os()
        .map(|arg| {
            arg.into_string()
                .map_err(|_| invalid("arguments must be UTF-8"))
        })
        .collect()
}

/// Where a cover comes from.
#[derive(Debug, PartialEq, Eq)]
enum Source {
    Remote(String),
    Local(PathBuf),
}

fn host_allowed(host: &str) -> bool {
    HOSTS.iter().any(|allowed| {
        host == *allowed
            || host
                .strip_suffix(allowed)
                .is_some_and(|label| label.len() > 1 && label.ends_with('.'))
    })
}

/// `Model.artProbeTarget`'s rules, again: the helper is the boundary.
fn source(target: &str) -> Result<Source, Failure> {
    if target.chars().any(|c| c < ' ' || c == '\u{7f}') {
        return Err(invalid("the target has a control character"));
    }
    if let Some(rest) = target.strip_prefix("https://") {
        if target.contains(' ') {
            return Err(invalid("the URL has a space"));
        }
        let authority = rest.split(['/', '?', '#']).next().unwrap_or("");
        // Credentials and ports are never part of an album-art URL.
        if authority.is_empty() || authority.contains(['@', ':']) {
            return Err(invalid("the URL's host is not a plain host name"));
        }
        if !host_allowed(&authority.to_ascii_lowercase()) {
            return Err(invalid("the URL is not on a cover host"));
        }
        return Ok(Source::Remote(target.to_owned()));
    }
    if target.starts_with('/') {
        return Ok(Source::Local(PathBuf::from(target)));
    }
    Err(invalid(
        "the target is neither an https URL nor an absolute path",
    ))
}

fn art_probe(target: &str) -> Result<Value, Failure> {
    let data = match source(target)? {
        Source::Remote(url) => fetch::https(&url, MAX_BYTES)?,
        Source::Local(path) => fetch::local(&path, MAX_BYTES)?,
    };
    if data.is_empty() {
        return Err(Failure::coded("EMPTY", "the cover is empty"));
    }
    let format = image::format(&data)
        .ok_or_else(|| Failure::coded("UNSUPPORTED_FORMAT", "not a JPEG, PNG, GIF, BMP or WebP"))?;
    let data = image::strip_text(format, &data)?;

    let magick = magick::Magick::find()?;
    let mean = magick.mean(format, &data)?;
    let dir = cache::dir()?;
    let file = cache::store(&dir, &data, || magick.cover(format, &data))?;
    cache::prune(&dir, &file, cache::KEEP);
    let swatches = magick.histogram(format, &data);

    let file = file
        .to_str()
        .ok_or_else(|| Failure::coded("CACHE_FAILED", "the cache path is not UTF-8"))?;
    Ok(json!({
        "ok": true,
        "mean": mean,
        "file": file,
        "swatches": swatches
            .iter()
            .map(|(count, hex)| json!({"count": count, "hex": hex}))
            .collect::<Vec<_>>(),
    }))
}

fn main_json(args: &[String]) -> Result<Value, Failure> {
    match &args[1.min(args.len())..] {
        [command, target] if command == "art-probe" => art_probe(target),
        _ => Err(invalid("usage: foamy-media-helper art-probe <target>")),
    }
}

/// `main_json` with every child bounded by `budget` from now.
fn run_within(budget: Duration, args: &[String]) -> Result<Value, Failure> {
    process::set_run_budget(budget);
    main_json(args)
}

fn main() -> ExitCode {
    json::run(|| run_within(RUN_BUDGET, &args()?), json::error_reply)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn cover_hosts_match_on_a_label_boundary() {
        for host in [
            "scdn.co",
            "i.scdn.co",
            "ytimg.com",
            "i.ytimg.com",
            "a.b.scdn.co",
        ] {
            assert!(host_allowed(host), "{host}");
        }
        for host in [
            "evilscdn.co",
            "evilytimg.com",
            "scdn.co.evil.test",
            ".scdn.co",
            "co",
            "",
        ] {
            assert!(!host_allowed(host), "{host}");
        }
    }

    #[test]
    fn targets_are_checked_again() {
        let url = "https://i.scdn.co/image/ab67616d0000b273";
        assert_eq!(source(url).unwrap(), Source::Remote(url.into()));
        assert_eq!(
            source("https://I.SCDN.CO/x").unwrap(),
            Source::Remote("https://I.SCDN.CO/x".into())
        );
        assert_eq!(
            source("/home/me/My Cover.png").unwrap(),
            Source::Local("/home/me/My Cover.png".into())
        );
        for bad in [
            "http://i.scdn.co/x",
            "https://i.scdn.co.evil.test/x",
            "https://user@i.scdn.co/x",
            "https://i.scdn.co:8443/x",
            "https://evil.test/i.scdn.co",
            "https://evil.test?i.scdn.co",
            "https://i.scdn.co/a b",
            "https:///x",
            "https://i.scdn.co/\nx",
            "/home/me/a\u{7f}b",
            "/tmp/\tx",
            "file:///home/me/x.png",
            "relative/x.png",
            "-x",
            "",
        ] {
            let failure = source(bad).unwrap_err();
            assert_eq!(failure.code, "INVALID_ARGUMENT", "{bad:?}");
            assert_eq!(failure.exit_code, 2);
        }
    }

    #[test]
    fn arguments_other_than_one_target_are_refused() {
        let call = |rest: &[&str]| {
            let mut args = vec!["foamy-media-helper".to_owned()];
            args.extend(rest.iter().map(|arg| arg.to_string()));
            main_json(&args).unwrap_err().code
        };
        assert_eq!(call(&[]), "INVALID_ARGUMENT");
        assert_eq!(call(&["art-probe"]), "INVALID_ARGUMENT");
        assert_eq!(call(&["art-probe", "/a", "/b"]), "INVALID_ARGUMENT");
        assert_eq!(call(&["probe", "/a"]), "INVALID_ARGUMENT");
    }

    /// [`the_run_budget_ends_the_decodes`]'s child: a local cover and a
    /// `magick` on `PATH` that takes 10 s per run (inside each run's own
    /// 15 s deadline), under a 1 s budget. Prints the reply and how long it
    /// took; run normally it does nothing.
    #[test]
    fn run_budget_child() {
        let Some(cover) = std::env::var_os("FOAMY_MEDIA_BUDGET_TEST") else {
            return;
        };
        let started = std::time::Instant::now();
        let args = [
            "foamy-media-helper".to_owned(),
            "art-probe".to_owned(),
            cover.into_string().unwrap(),
        ];
        let reply = run_within(Duration::from_secs(1), &args);
        println!("elapsed_ms={}", started.elapsed().as_millis());
        match reply {
            Ok(value) => println!("ok {value}"),
            Err(failure) => println!("failure {} {}", failure.code, failure.message),
        }
    }

    #[test]
    fn the_run_budget_ends_the_decodes() {
        // ImageMagick runs in its own process group, out of the wrapper's
        // reach, so the budget is what ends it in time.
        let dir = std::env::temp_dir().join(format!("foamy-media-budget-{}", std::process::id()));
        std::fs::create_dir_all(&dir).unwrap();
        let magick = dir.join("magick");
        std::fs::write(&magick, "#!/bin/sh\nexec sleep 10\n").unwrap();
        std::fs::set_permissions(&magick, std::os::unix::fs::PermissionsExt::from_mode(0o755))
            .unwrap();
        let cover = dir.join("cover.png");
        std::fs::write(&cover, crate::image::testing::plain([1, 2, 3])).unwrap();
        let output = foamy_helper::child::Bounded::new(std::env::current_exe().unwrap())
            .args([
                "--exact",
                "tests::run_budget_child",
                "--nocapture",
                "--test-threads=1",
                "-q",
            ])
            .env("FOAMY_MEDIA_BUDGET_TEST", &cover)
            .env(
                "PATH",
                std::env::join_paths([dir.as_path(), "/usr/bin".as_ref(), "/bin".as_ref()])
                    .unwrap(),
            )
            .env("XDG_CACHE_HOME", dir.join("cache"))
            .timeout(Duration::from_secs(60))
            .run()
            .unwrap();
        let _ = std::fs::remove_dir_all(&dir);
        let text = output.stdout_lossy();
        assert!(output.success(), "{output:?}");
        assert!(
            text.contains("failure DECODE_FAILED ImageMagick's mean colour took too long"),
            "{text}"
        );
        let elapsed: u64 = text
            .lines()
            .find_map(|line| line.strip_prefix("elapsed_ms="))
            .unwrap()
            .parse()
            .unwrap();
        assert!(elapsed < 5000, "within the 1 s budget: {elapsed} ms");
    }

    #[test]
    fn a_missing_local_cover_is_unreadable() {
        let failure = art_probe("/nonexistent/foamy-media/cover.png").unwrap_err();
        assert_eq!(failure.code, "UNREADABLE");
    }
}
