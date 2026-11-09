//! The covers the panel may display: `${XDG_CACHE_HOME:-$HOME/.cache}/
//! foamy-media/covers/<stamp>.png`, named for the cleaned bytes (not the
//! URL: a player that rewrites one `file://` path for every track still
//! gets a new cover, and a new cover is a new path, which is what lets the
//! panel cross-fade rather than reload in place).

use std::cmp::Reverse;
use std::fs::{self, DirBuilder, File};
use std::os::unix::fs::{DirBuilderExt, MetadataExt, PermissionsExt};
use std::path::{Path, PathBuf};
use std::time::SystemTime;

use foamy_helper::Failure;
use foamy_helper::hash::sha256_hex;
use rustix::fs::{Mode, OFlags};

/// How many covers stay on disk.
pub const KEEP: usize = 8;

fn failed(what: &str, path: &Path, error: impl std::fmt::Display) -> Failure {
    Failure::coded(
        "CACHE_FAILED",
        format!("{what} {}: {error}", path.display()),
    )
}

fn absolute(value: Option<std::ffi::OsString>) -> Option<PathBuf> {
    value.map(PathBuf::from).filter(|path| path.is_absolute())
}

/// The covers directory for these `XDG_CACHE_HOME` and `HOME` values.
pub fn dir_for(
    cache_home: Option<std::ffi::OsString>,
    home: Option<std::ffi::OsString>,
) -> Option<PathBuf> {
    absolute(cache_home)
        .or_else(|| absolute(home).map(|home| home.join(".cache")))
        .map(|base| base.join("foamy-media").join("covers"))
}

/// The covers directory, created 0700 (what `mkdir -p` and `chmod 700`
/// did), then checked to be this user's own, private, not a symlink.
pub fn dir() -> Result<PathBuf, Failure> {
    let dir =
        dir_for(std::env::var_os("XDG_CACHE_HOME"), std::env::var_os("HOME")).ok_or_else(|| {
            Failure::coded(
                "CACHE_FAILED",
                "neither XDG_CACHE_HOME nor HOME is an absolute path",
            )
        })?;
    prepare(&dir)?;
    Ok(dir)
}

fn prepare(dir: &Path) -> Result<(), Failure> {
    DirBuilder::new()
        .recursive(true)
        .mode(0o700)
        .create(dir)
        .map_err(|error| failed("can't create", dir, error))?;
    let meta = fs::symlink_metadata(dir).map_err(|error| failed("can't read", dir, error))?;
    // An older directory with a wider mode is tightened, as `chmod 700` did,
    // but only a real directory of this user's.
    if meta.is_dir() && meta.uid() == rustix::process::getuid().as_raw() && meta.mode() & 0o077 != 0
    {
        fs::set_permissions(dir, fs::Permissions::from_mode(0o700))
            .map_err(|error| failed("can't restrict", dir, error))?;
    }
    foamy_helper::fs::ensure_private_dir(dir).map_err(|error| failed("can't use", dir, error))
}

/// `<first 32 hex digits of sha256(data)>.png`.
pub fn name(data: &[u8]) -> String {
    format!("{}.png", &sha256_hex(data)[..32])
}

fn is_cover_name(name: &str) -> bool {
    name.len() == 36
        && name.ends_with(".png")
        && name[..32]
            .bytes()
            .all(|byte| matches!(byte, b'0'..=b'9' | b'a'..=b'f'))
}

/// The cover for `data` in `dir`: `encode()` written atomically (mode 0600)
/// unless a regular file of that name is already there, which then only
/// gets a new modification time so pruning counts it as the newest.
pub fn store(
    dir: &Path,
    data: &[u8],
    encode: impl FnOnce() -> Result<Vec<u8>, Failure>,
) -> Result<PathBuf, Failure> {
    let path = dir.join(name(data));
    if fs::symlink_metadata(&path).is_ok_and(|meta| meta.is_file()) {
        let flags = OFlags::RDONLY | OFlags::NOFOLLOW | OFlags::NONBLOCK | OFlags::CLOEXEC;
        if let Ok(fd) = rustix::fs::open(&path, flags, Mode::empty()) {
            let _ = File::from(fd).set_modified(SystemTime::now());
        }
        return Ok(path);
    }
    let png = encode()?;
    foamy_helper::fs::write_atomic(&path, &png, 0o600)
        .map_err(|error| failed("can't write", &path, error))?;
    Ok(path)
}

/// Keeps the newest `keep` covers in `dir`, `current` always among them,
/// and removes the rest. Only names this module writes are ever touched;
/// a failure here leaves a cover more on disk, nothing worse.
pub fn prune(dir: &Path, current: &Path, keep: usize) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    let mut covers: Vec<(SystemTime, PathBuf)> = entries
        .filter_map(Result::ok)
        .filter(|entry| entry.file_name().to_str().is_some_and(is_cover_name))
        .filter_map(|entry| {
            let meta = entry.metadata().ok()?;
            let modified = meta.modified().ok()?;
            meta.is_file().then(|| (modified, entry.path()))
        })
        .filter(|(_, path)| path != current)
        .collect();
    covers.sort_by_key(|(modified, _)| Reverse(*modified));
    for (_, stale) in covers.into_iter().skip(keep.saturating_sub(1)) {
        let _ = fs::remove_file(stale);
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::sync::atomic::{AtomicU64, Ordering};
    use std::time::Duration;

    struct TempDir(PathBuf);

    impl TempDir {
        fn new() -> TempDir {
            static N: AtomicU64 = AtomicU64::new(0);
            let path = std::env::temp_dir().join(format!(
                "foamy-media-cache-{}-{}",
                std::process::id(),
                N.fetch_add(1, Ordering::Relaxed)
            ));
            fs::create_dir(&path).unwrap();
            TempDir(path)
        }
    }

    impl Drop for TempDir {
        fn drop(&mut self) {
            let _ = fs::remove_dir_all(&self.0);
        }
    }

    fn mode(path: &Path) -> u32 {
        fs::symlink_metadata(path).unwrap().mode() & 0o777
    }

    #[test]
    fn the_directory_follows_xdg() {
        let os = |s: &str| Some(std::ffi::OsString::from(s));
        assert_eq!(
            dir_for(os("/c"), os("/h")).unwrap(),
            PathBuf::from("/c/foamy-media/covers")
        );
        assert_eq!(
            dir_for(None, os("/h")).unwrap(),
            PathBuf::from("/h/.cache/foamy-media/covers")
        );
        // Empty or relative values are not a cache directory.
        assert_eq!(
            dir_for(os(""), os("/h")).unwrap(),
            PathBuf::from("/h/.cache/foamy-media/covers")
        );
        assert_eq!(
            dir_for(os("rel"), os("/h")).unwrap(),
            PathBuf::from("/h/.cache/foamy-media/covers")
        );
        assert_eq!(dir_for(None, os("rel")), None);
        assert_eq!(dir_for(None, None), None);
    }

    #[test]
    fn the_directory_is_private_and_a_wider_one_is_tightened() {
        let temp = TempDir::new();
        let dir = temp.0.join("foamy-media/covers");
        prepare(&dir).unwrap();
        assert_eq!(mode(&dir), 0o700);
        fs::set_permissions(&dir, fs::Permissions::from_mode(0o755)).unwrap();
        prepare(&dir).unwrap();
        assert_eq!(mode(&dir), 0o700);
        // A symlink in its place is refused, not followed.
        let link = temp.0.join("link");
        std::os::unix::fs::symlink(&dir, &link).unwrap();
        assert_eq!(prepare(&link).unwrap_err().code, "CACHE_FAILED");
    }

    #[test]
    fn covers_are_named_for_their_bytes() {
        // sha256("abc") = ba7816bf8f01cfea414140de5dae2223b00361a3...
        assert_eq!(name(b"abc"), "ba7816bf8f01cfea414140de5dae2223.png");
        assert!(is_cover_name(&name(b"abc")));
        for bad in [
            "ba7816bf8f01cfea414140de5dae2223.jpg",
            "BA7816BF8F01CFEA414140DE5DAE2223.png",
            "ba7816bf8f01cfea414140de5dae222.png",
            "ba7816bf8f01cfea414140de5dae2223.png.new",
            "notes.png",
        ] {
            assert!(!is_cover_name(bad), "{bad}");
        }
    }

    #[test]
    fn a_stored_cover_is_reused_not_reencoded() {
        let temp = TempDir::new();
        let first = store(&temp.0, b"cover", || Ok(b"png".to_vec())).unwrap();
        assert_eq!(fs::read(&first).unwrap(), b"png");
        assert_eq!(mode(&first), 0o600);
        let old = SystemTime::now() - Duration::from_secs(3600);
        File::open(&first).unwrap().set_modified(old).unwrap();
        let again = store(&temp.0, b"cover", || panic!("encoded twice")).unwrap();
        assert_eq!(again, first);
        assert!(fs::metadata(&first).unwrap().modified().unwrap() > old);
        // Other bytes, another cover; a failed encode writes nothing.
        let failure = store(&temp.0, b"other", || {
            Err(Failure::coded("DECODE_FAILED", "x"))
        });
        assert_eq!(failure.unwrap_err().code, "DECODE_FAILED");
        assert_eq!(fs::read_dir(&temp.0).unwrap().count(), 1);
    }

    #[test]
    fn pruning_keeps_the_newest_and_the_current_cover() {
        let temp = TempDir::new();
        let now = SystemTime::now();
        let mut paths = Vec::new();
        for index in 0..12u64 {
            let path = temp.0.join(name(&index.to_be_bytes()));
            fs::write(&path, b"x").unwrap();
            // Index 0 is the newest.
            File::options()
                .write(true)
                .open(&path)
                .unwrap()
                .set_modified(now - Duration::from_secs(60 * index))
                .unwrap();
            paths.push(path);
        }
        let foreign = temp.0.join("keep-me.png");
        fs::write(&foreign, b"x").unwrap();
        // The current cover is the oldest one (a reuse whose touch failed).
        let current = paths[11].clone();
        prune(&temp.0, &current, KEEP);
        let left: Vec<bool> = paths.iter().map(|path| path.exists()).collect();
        let expected: Vec<bool> = (0..12)
            .map(|index| index < KEEP - 1 || index == 11)
            .collect();
        assert_eq!(left, expected);
        assert!(
            foreign.exists(),
            "a name the probe doesn't write was removed"
        );
    }
}
