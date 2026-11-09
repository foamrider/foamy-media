//! ImageMagick, as the script ran it, minus the shell: the cleaned bytes on
//! standard input under an explicit coder, the same resource limits, and
//! the kit's `Bounded` around each run.

use std::ffi::OsString;
use std::os::unix::fs::PermissionsExt;
use std::path::PathBuf;
use std::time::Duration;

use foamy_helper::Failure;
use foamy_helper::child::{Bounded, Output};
use foamy_helper::process::Resource;

use crate::image::{Format, PNG_MAGIC};

/// Bounds for the decode itself, because a small file can still declare an
/// enormous image. The width and height limits are the ones that refuse:
/// libpng checks them while reading IHDR, so an oversized cover is
/// rejected before a pixel is allocated. The rest only bound the cost of
/// what gets past them; the area limit in particular chooses where the
/// pixel cache lives rather than refusing anything. No real cover comes
/// close to 8000 px; Spotify publishes 640.
pub const LIMITS: [(&str, &str); 7] = [
    ("MAGICK_WIDTH_LIMIT", "8KP"),
    ("MAGICK_HEIGHT_LIMIT", "8KP"),
    ("MAGICK_AREA_LIMIT", "128MP"),
    ("MAGICK_MEMORY_LIMIT", "256MiB"),
    ("MAGICK_MAP_LIMIT", "512MiB"),
    ("MAGICK_TIME_LIMIT", "10"),
    ("MAGICK_THREAD_LIMIT", "2"),
];

/// Each run's wall clock: ImageMagick's own 10 s and room to exit.
const DEADLINE: Duration = Duration::from_secs(15);
const CPU_SECONDS: u64 = 20;
/// "687547" and a newline, with room to spare.
const MEAN_OUTPUT: usize = 4096;
/// A 640x640 PNG: 16-bit RGBA is 3.3 MB before deflate, which noise can't
/// shrink.
const COVER_OUTPUT: usize = 8 << 20;
const HISTOGRAM_OUTPUT: usize = 64 << 10;
/// `-colors 8` gives at most eight lines; anything past that is not ours.
const MAX_SWATCHES: usize = 16;

fn failed(output: &Output, what: &str) -> Failure {
    let why = if output.timed_out {
        "took too long"
    } else if output.overflowed {
        "wrote too much"
    } else {
        "failed"
    };
    Failure::coded("DECODE_FAILED", format!("ImageMagick's {what} {why}"))
}

/// An executable `name` in `path_var` (`PATH`'s format), as the shell's
/// lookup found `magick`.
pub fn which(name: &str, path_var: Option<OsString>) -> Option<PathBuf> {
    let path_var = path_var?;
    std::env::split_paths(&path_var)
        .filter(|dir| dir.is_absolute())
        .map(|dir| dir.join(name))
        .find(|candidate| {
            std::fs::metadata(candidate)
                .is_ok_and(|meta| meta.is_file() && meta.permissions().mode() & 0o111 != 0)
        })
}

pub struct Magick {
    program: PathBuf,
}

impl Magick {
    /// `magick` from `PATH`, else `MAGICK_MISSING`.
    pub fn find() -> Result<Magick, Failure> {
        which("magick", std::env::var_os("PATH"))
            .map(|program| Magick { program })
            .ok_or_else(|| {
                Failure::coded("MAGICK_MISSING", "ImageMagick (magick) is not installed")
            })
    }

    #[cfg(test)]
    pub fn at(program: &std::path::Path) -> Magick {
        Magick {
            program: program.to_owned(),
        }
    }

    /// One bounded run: `<CODER>:-[0]` (the first frame of the bytes on
    /// stdin, decoded by that coder only), then `args`.
    fn run(
        &self,
        format: Format,
        data: &[u8],
        args: &[&str],
        max_output: usize,
    ) -> std::io::Result<Output> {
        let mut command = Bounded::new(&self.program)
            .arg(format!("{}:-[0]", format.coder()))
            .args(args)
            .keep_env(&["PATH", "HOME", "TMPDIR"])
            .env("LC_ALL", "C");
        for (name, value) in LIMITS {
            command = command.env(name, value);
        }
        command
            .stdin(data.to_vec())
            .timeout(DEADLINE)
            .max_output(max_output)
            .rlimit(Resource::Core, 0)
            .rlimit(Resource::Cpu, CPU_SECONDS)
            .run()
    }

    fn checked(
        &self,
        format: Format,
        data: &[u8],
        args: &[&str],
        max: usize,
        what: &str,
    ) -> Result<Vec<u8>, Failure> {
        let output = self.run(format, data, args, max).map_err(|error| {
            Failure::coded("DECODE_FAILED", format!("can't run ImageMagick: {error}"))
        })?;
        if !output.success() {
            return Err(failed(&output, what));
        }
        Ok(output.stdout)
    }

    /// The mean colour, `#rrggbb`: the cover resized to one pixel.
    pub fn mean(&self, format: Format, data: &[u8]) -> Result<String, Failure> {
        let args = [
            "-resize",
            "1x1!",
            "-depth",
            "8",
            "-format",
            "%[hex:p{0,0}]",
            "info:",
        ];
        let out = self.checked(format, data, &args, MEAN_OUTPUT, "mean colour")?;
        parse_mean(&String::from_utf8_lossy(&out)).ok_or_else(|| {
            Failure::coded("DECODE_FAILED", "ImageMagick's mean colour is unreadable")
        })
    }

    /// The cover the panel displays: re-encoded from bytes that passed
    /// every check, at most 640 px a side, without metadata.
    pub fn cover(&self, format: Format, data: &[u8]) -> Result<Vec<u8>, Failure> {
        let args = ["-resize", "640x640>", "-strip", "PNG:-"];
        let png = self.checked(format, data, &args, COVER_OUTPUT, "cover")?;
        if !png.starts_with(PNG_MAGIC) {
            return Err(Failure::coded(
                "DECODE_FAILED",
                "ImageMagick's cover is not a PNG",
            ));
        }
        Ok(png)
    }

    /// Up to eight `(pixel count, #rrggbb)` swatches; empty when the
    /// decode fails (the colour then falls back to the mean, as when the
    /// script's last command failed after printing the rest).
    pub fn histogram(&self, format: Format, data: &[u8]) -> Vec<(u64, String)> {
        let args = [
            "-resize",
            "80x80",
            "-depth",
            "8",
            "-colors",
            "8",
            "-format",
            "%c",
            "histogram:info:",
        ];
        self.checked(format, data, &args, HISTOGRAM_OUTPUT, "histogram")
            .map(|out| parse_histogram(&String::from_utf8_lossy(&out)))
            .unwrap_or_default()
    }
}

fn hex6(text: &str) -> Option<String> {
    let hex = text.get(..6)?;
    hex.bytes()
        .all(|byte| byte.is_ascii_hexdigit())
        .then(|| format!("#{}", hex.to_ascii_lowercase()))
}

/// `%[hex:p{0,0}]`'s output: `RRGGBB` (or `RRGGBBAA`), the first six digits.
pub fn parse_mean(text: &str) -> Option<String> {
    hex6(text.trim_start())
}

/// `histogram:info:` lines, e.g. `   2581: (214,212,206) #D6D4CE srgb(214,212,206)`.
pub fn parse_histogram(text: &str) -> Vec<(u64, String)> {
    let line = |line: &str| -> Option<(u64, String)> {
        let (count, rest) = line.trim_start().split_once(':')?;
        if count.is_empty() || !count.bytes().all(|byte| byte.is_ascii_digit()) {
            return None;
        }
        let rest = rest.trim_start().strip_prefix('(')?;
        let (_, rest) = rest.split_once(')')?;
        let hex = hex6(rest.trim_start().strip_prefix('#')?)?;
        Some((count.parse().ok()?, hex))
    };
    text.lines().filter_map(line).take(MAX_SWATCHES).collect()
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::image::testing::{plain, text_bomb};
    use crate::image::{format, strip_text};

    #[test]
    fn the_mean_is_the_first_six_hex_digits() {
        assert_eq!(parse_mean("D2CFC8").as_deref(), Some("#d2cfc8"));
        assert_eq!(parse_mean("d2cfc8ff\n").as_deref(), Some("#d2cfc8"));
        assert_eq!(parse_mean(""), None);
        assert_eq!(parse_mean("D2CF"), None);
        assert_eq!(parse_mean("magick: unable to open image"), None);
        assert_eq!(parse_mean("ééééééé"), None);
    }

    #[test]
    fn histogram_lines_become_swatches() {
        let text = "          2581: (214,212,206) #D6D4CE srgb(214,212,206)\n\
                    \x20         1485: (45.7895,169.684,81) #2EAA51 srgb(17.9567%,66.5428%,31.7647%)\n\
                    \x20           12: (1,2,3,4) #01020304 srgba(1,2,3,0.0157)\n\
                    garbage: (1,2,3) #zzzzzz\n\
                    x1: (1,2,3) #010203\n\
                    \n";
        assert_eq!(
            parse_histogram(text),
            [
                (2581, "#d6d4ce".to_owned()),
                (1485, "#2eaa51".to_owned()),
                (12, "#010203".to_owned())
            ]
        );
        let many = "1: (1,1,1) #010101\n".repeat(100);
        assert_eq!(parse_histogram(&many).len(), MAX_SWATCHES);
    }

    #[test]
    fn which_finds_only_executable_files() {
        let path = std::env::join_paths(["relative", "/nonexistent", "/usr/bin"]).unwrap();
        assert_eq!(
            which("sh", Some(path.clone())),
            Some(PathBuf::from("/usr/bin/sh"))
        );
        assert_eq!(which("foamy-media-no-such-program", Some(path)), None);
        assert_eq!(which("sh", None), None);
    }

    fn installed() -> Option<Magick> {
        let magick = Magick::find().ok();
        if magick.is_none() {
            eprintln!("skip: ImageMagick not installed");
        }
        magick
    }

    #[test]
    fn a_plain_cover_decodes_to_its_colour() {
        let Some(magick) = installed() else { return };
        let png = plain([0x1d, 0xb9, 0x54]);
        assert_eq!(magick.mean(Format::Png, &png).unwrap(), "#1db954");
        let cover = magick.cover(Format::Png, &png).unwrap();
        assert!(cover.starts_with(PNG_MAGIC));
        // -resize 80x80 enlarges the one pixel to 6400 of them.
        assert_eq!(
            magick.histogram(Format::Png, &png),
            [(6400, "#1db954".to_owned())]
        );
    }

    #[test]
    fn the_coder_is_ours_not_imagemagicks() {
        let Some(magick) = installed() else { return };
        // A PNG named as JPEG is not sniffed back into a PNG.
        let png = plain([1, 2, 3]);
        assert_eq!(
            magick.mean(Format::Jpeg, &png).unwrap_err().code,
            "DECODE_FAILED"
        );
        // Nor is an SVG named as anything.
        let svg = b"<svg xmlns=\"http://www.w3.org/2000/svg\" width=\"4\" height=\"4\"/>";
        assert_eq!(
            magick.mean(Format::Png, svg).unwrap_err().code,
            "DECODE_FAILED"
        );
        assert!(magick.histogram(Format::Png, svg).is_empty());
    }

    #[test]
    fn an_oversized_image_is_refused_by_the_width_limit() {
        let Some(magick) = installed() else { return };
        // 9000 x 1: past MAGICK_WIDTH_LIMIT before a pixel row is read.
        let mut png = crate::image::testing::head(9000);
        png.extend_from_slice(&crate::image::testing::tail(9000, [0, 0, 0]));
        assert!(magick.mean(Format::Png, &png).is_err());
        let mut fine = crate::image::testing::head(4000);
        fine.extend_from_slice(&crate::image::testing::tail(4000, [0, 0, 0]));
        assert_eq!(magick.mean(Format::Png, &fine).unwrap(), "#000000");
    }

    #[test]
    fn a_stripped_text_bomb_reads_as_the_plain_cover() {
        let Some(magick) = installed() else { return };
        let bomb = text_bomb([0xb2, 0x31, 0x3a], 16, 4096);
        let format = format(&bomb).unwrap();
        let stripped = strip_text(format, &bomb).unwrap();
        assert_eq!(magick.mean(format, &stripped).unwrap(), "#b2313a");
    }

    #[test]
    fn a_missing_program_is_a_decode_failure() {
        let magick = Magick::at(std::path::Path::new("/nonexistent/magick"));
        let failure = magick.mean(Format::Png, &plain([0, 0, 0])).unwrap_err();
        assert_eq!(failure.code, "DECODE_FAILED");
    }
}
