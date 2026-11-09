//! What the bytes are, decided here from their magic numbers rather than
//! guessed by the decoder, and a PNG without its text chunks.

use std::borrow::Cow;

use foamy_helper::Failure;

pub const PNG_MAGIC: &[u8] = b"\x89PNG\r\n\x1a\n";

/// The most byte ranges a PNG without its text may be put together from:
/// no cover interleaves text with that many other chunks (the shell
/// script's limit, kept so the same files pass).
pub const MAX_RUNS: usize = 64;

/// The raster formats every player's cover comes in, none of which reaches
/// an ImageMagick delegate or a vector coder.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Format {
    Jpeg,
    Png,
    Gif,
    Bmp,
    Webp,
}

impl Format {
    /// ImageMagick's coder name, given explicitly as `<CODER>:-[0]`.
    pub fn coder(self) -> &'static str {
        match self {
            Format::Jpeg => "JPEG",
            Format::Png => "PNG",
            Format::Gif => "GIF",
            Format::Bmp => "BMP",
            Format::Webp => "WEBP",
        }
    }
}

/// The format from the first bytes, as the script's `od | case` did:
/// `ff d8 ff`, the PNG signature, `GIF89a`/`GIF87a`, `BM`, `RIFF????WEBP`.
pub fn format(data: &[u8]) -> Option<Format> {
    if data.starts_with(b"\xff\xd8\xff") {
        Some(Format::Jpeg)
    } else if data.starts_with(PNG_MAGIC) {
        Some(Format::Png)
    } else if data.starts_with(b"GIF89a") || data.starts_with(b"GIF87a") {
        Some(Format::Gif)
    } else if data.starts_with(b"BM") {
        Some(Format::Bmp)
    } else if data.starts_with(b"RIFF") && data.get(8..12) == Some(b"WEBP") {
        Some(Format::Webp)
    } else {
        None
    }
}

fn be32(data: &[u8], at: usize) -> Option<u32> {
    Some(u32::from_be_bytes(
        data.get(at..at.checked_add(4)?)?.try_into().ok()?,
    ))
}

/// zlib's CRC-32 table (reflected polynomial 0xedb88320), as PNG uses.
const CRC_TABLE: [u32; 256] = {
    let mut table = [0u32; 256];
    let mut n = 0;
    while n < 256 {
        let mut crc = n as u32;
        let mut bit = 0;
        while bit < 8 {
            crc = if crc & 1 != 0 {
                (crc >> 1) ^ 0xedb8_8320
            } else {
                crc >> 1
            };
            bit += 1;
        }
        table[n] = crc;
        n += 1;
    }
    table
};

pub fn crc32(data: &[u8]) -> u32 {
    let mut crc = 0xffff_ffffu32;
    for &byte in data {
        crc = CRC_TABLE[((crc ^ byte as u32) & 0xff) as usize] ^ (crc >> 8);
    }
    !crc
}

fn invalid(why: &str) -> Failure {
    Failure::coded("INVALID_PNG", why)
}

/// `data` without its PNG text chunks (`tEXt`, `zTXt`, `iTXt`), before
/// ImageMagick reads a byte; other formats pass unchanged.
///
/// libpng inflates every `zTXt` chunk and keeps it, with every `tEXt`,
/// until the read is over, outside every ImageMagick limit (they count
/// pixels): a megabyte of crafted chunks can hold a gigabyte of text on a
/// 1x1 image. ImageMagick only turns that text into properties, which
/// `-strip` drops from the cover it writes, so the image decodes to the
/// same pixels without it.
///
/// Only chunk headers (and, for critical chunks, the CRC over type and
/// data) are read; nothing is inflated, and the copy is at most the input's
/// size. The PNG must be a chain of chunks starting with a 13-byte `IHDR`,
/// each with a length under 2^31, wholly inside the data, a type of four
/// ASCII letters and, for a critical chunk (upper-case first letter), a
/// matching CRC (libpng refuses those anyway; an ancillary chunk with a bad
/// CRC is one libpng skips, so it passes), ending with `IEND`. What follows
/// `IEND` is dropped. Putting it together from more than [`MAX_RUNS`]
/// ranges is refused too. Anything else is `INVALID_PNG`.
pub fn strip_text(format: Format, data: &[u8]) -> Result<Cow<'_, [u8]>, Failure> {
    if format != Format::Png {
        return Ok(Cow::Borrowed(data));
    }
    if !data.starts_with(PNG_MAGIC) {
        return Err(invalid("no PNG signature"));
    }
    // The byte ranges kept, and where the current one started.
    let mut kept: Vec<(usize, usize)> = Vec::new();
    let mut start = 0;
    let mut at = PNG_MAGIC.len();
    let mut first = true;
    loop {
        let length = be32(data, at).ok_or_else(|| invalid("no IEND chunk"))?;
        if length > 0x7fff_ffff {
            return Err(invalid("a chunk length is over 2^31 - 1"));
        }
        let kind = data
            .get(at + 4..at + 8)
            .ok_or_else(|| invalid("a chunk header is cut short"))?;
        if !kind.iter().all(u8::is_ascii_alphabetic) {
            return Err(invalid("a chunk type is not four letters"));
        }
        let end = (at + 12)
            .checked_add(length as usize)
            .filter(|&end| end <= data.len())
            .ok_or_else(|| invalid("a chunk runs past the end of the file"))?;
        if first && (kind != b"IHDR" || length != 13) {
            return Err(invalid("the first chunk is not IHDR"));
        }
        first = false;
        if kind[0].is_ascii_uppercase() {
            let stored = be32(data, end - 4).unwrap_or(0);
            if crc32(&data[at + 4..end - 4]) != stored {
                return Err(invalid("a critical chunk's CRC does not match"));
            }
        }
        if matches!(kind, b"tEXt" | b"zTXt" | b"iTXt") {
            if at > start {
                kept.push((start, at));
                if kept.len() > MAX_RUNS {
                    return Err(invalid("text between too many chunks"));
                }
            }
            start = end;
        }
        let last = kind == b"IEND";
        at = end;
        if last {
            break;
        }
    }
    if start == 0 && at == data.len() {
        return Ok(Cow::Borrowed(data));
    }
    if at > start {
        kept.push((start, at));
    }
    if kept.len() > MAX_RUNS {
        return Err(invalid("text between too many chunks"));
    }
    let mut out = Vec::with_capacity(kept.iter().map(|(from, to)| to - from).sum());
    for (from, to) in kept {
        out.extend_from_slice(&data[from..to]);
    }
    Ok(Cow::Owned(out))
}

/// Test PNGs, built from chunks.
#[cfg(test)]
pub mod testing {
    use super::{PNG_MAGIC, crc32};

    pub fn chunk(out: &mut Vec<u8>, kind: &[u8; 4], data: &[u8]) {
        out.extend_from_slice(&(data.len() as u32).to_be_bytes());
        out.extend_from_slice(kind);
        out.extend_from_slice(data);
        let mut typed = kind.to_vec();
        typed.extend_from_slice(data);
        out.extend_from_slice(&crc32(&typed).to_be_bytes());
    }

    fn adler32(data: &[u8]) -> u32 {
        let (mut a, mut b) = (1u32, 0u32);
        for &byte in data {
            a = (a + byte as u32) % 65521;
            b = (b + a) % 65521;
        }
        (b << 16) | a
    }

    /// A zlib stream of one stored deflate block (`data` under 64 KiB).
    pub fn zlib_stored(data: &[u8]) -> Vec<u8> {
        let mut out = vec![0x78, 0x01, 1];
        let length = data.len() as u16;
        out.extend_from_slice(&length.to_le_bytes());
        out.extend_from_slice(&(!length).to_le_bytes());
        out.extend_from_slice(data);
        out.extend_from_slice(&adler32(data).to_be_bytes());
        out
    }

    /// A zlib stream that inflates to `1 + 258 * matches` zero bytes:
    /// fixed Huffman codes, a literal then matches of 258 at distance 1.
    pub fn zlib_zeros(matches: usize) -> Vec<u8> {
        let mut out = vec![0x78, 0x01];
        let mut used = 0u32;
        let mut put = |out: &mut Vec<u8>, value: u32, count: u32, msb_first: bool| {
            for i in 0..count {
                let bit = if msb_first { count - 1 - i } else { i };
                if used.is_multiple_of(8) {
                    out.push(0);
                }
                if value >> bit & 1 == 1 {
                    *out.last_mut().unwrap() |= 1 << (used % 8);
                }
                used += 1;
            }
        };
        put(&mut out, 1, 1, false); // BFINAL
        put(&mut out, 1, 2, false); // BTYPE 01: fixed codes
        put(&mut out, 0x30, 8, true); // literal 0
        for _ in 0..matches {
            put(&mut out, 0b1100_0101, 8, true); // length 258 (code 285)
            put(&mut out, 0, 5, true); // distance 1 (code 0)
        }
        put(&mut out, 0, 7, true); // end of block (256)
        let size = (1 + 258 * matches) as u32;
        out.extend_from_slice(&((size % 65521) << 16 | 1).to_be_bytes());
        out
    }

    /// The signature and a `width` x 1 RGB8 IHDR.
    pub fn head(width: u32) -> Vec<u8> {
        let mut out = PNG_MAGIC.to_vec();
        let mut header = width.to_be_bytes().to_vec();
        header.extend_from_slice(&1u32.to_be_bytes());
        header.extend_from_slice(&[8, 2, 0, 0, 0]);
        chunk(&mut out, b"IHDR", &header);
        out
    }

    /// IDAT and IEND of a `width` x 1 RGB8 image of one colour.
    pub fn tail(width: u32, rgb: [u8; 3]) -> Vec<u8> {
        let mut row = vec![0u8];
        for _ in 0..width {
            row.extend_from_slice(&rgb);
        }
        let mut out = Vec::new();
        chunk(&mut out, b"IDAT", &zlib_stored(&row));
        chunk(&mut out, b"IEND", &[]);
        out
    }

    /// A plain 1x1 PNG of one colour.
    pub fn plain(rgb: [u8; 3]) -> Vec<u8> {
        let mut out = head(1);
        out.extend_from_slice(&tail(1, rgb));
        out
    }

    /// The same image with `count` zTXt chunks, each inflating to about
    /// 258 * `matches` bytes, half before the image data and half after
    /// it (libpng reads both), plus one tEXt and one iTXt.
    pub fn text_bomb(rgb: [u8; 3], count: usize, matches: usize) -> Vec<u8> {
        let mut text = b"Comment\0\0".to_vec();
        text.extend_from_slice(&zlib_zeros(matches));
        let mut out = head(1);
        chunk(&mut out, b"tEXt", b"Comment\0a cover");
        chunk(&mut out, b"iTXt", b"Title\0\0\0\0a cover");
        for _ in 0..count / 2 {
            chunk(&mut out, b"zTXt", &text);
        }
        let tail = tail(1, rgb);
        // IDAT, then the rest of the text, then IEND (12 bytes).
        out.extend_from_slice(&tail[..tail.len() - 12]);
        for _ in count / 2..count {
            chunk(&mut out, b"zTXt", &text);
        }
        out.extend_from_slice(&tail[tail.len() - 12..]);
        out
    }
}

#[cfg(test)]
mod tests {
    use super::testing::*;
    use super::*;

    fn strip(data: &[u8]) -> Result<Vec<u8>, String> {
        strip_text(Format::Png, data)
            .map(|data| data.into_owned())
            .map_err(|failure| {
                assert_eq!(failure.code, "INVALID_PNG");
                failure.message
            })
    }

    /// The chunk types of a PNG, in order.
    fn kinds(data: &[u8]) -> Vec<String> {
        let mut out = Vec::new();
        let mut at = 8;
        while at + 8 <= data.len() {
            let length = be32(data, at).unwrap() as usize;
            out.push(String::from_utf8_lossy(&data[at + 4..at + 8]).into_owned());
            at += 12 + length;
        }
        out
    }

    #[test]
    fn formats_come_from_the_magic_bytes() {
        assert_eq!(format(b"\xff\xd8\xff\xe0rest"), Some(Format::Jpeg));
        assert_eq!(format(&plain([1, 2, 3])), Some(Format::Png));
        assert_eq!(format(b"GIF89a..."), Some(Format::Gif));
        assert_eq!(format(b"GIF87a..."), Some(Format::Gif));
        assert_eq!(format(b"BM\0\0"), Some(Format::Bmp));
        assert_eq!(format(b"RIFF\x10\0\0\0WEBPVP8 "), Some(Format::Webp));
        for bad in [
            &b""[..],
            b"\xff\xd8",
            b"\x89PNG\r\n\x1a",
            b"GIF88a",
            b"B",
            b"RIFF\x10\0\0\0WAVE",
            b"RIFF\x10\0\0",
            b"<svg xmlns=\"http://www.w3.org/2000/svg\"/>",
            b"push graphic-context",
            b"%PDF-1.7",
            b"not an image at all\n",
        ] {
            assert_eq!(format(bad), None, "{:?}", String::from_utf8_lossy(bad));
        }
        assert_eq!(Format::Webp.coder(), "WEBP");
        assert_eq!(Format::Jpeg.coder(), "JPEG");
    }

    #[test]
    fn crc_matches_zlib() {
        assert_eq!(crc32(b""), 0);
        assert_eq!(crc32(b"123456789"), 0xcbf4_3926);
        assert_eq!(crc32(b"IEND"), 0xae42_6082);
    }

    #[test]
    fn other_formats_pass_unchanged() {
        let jpeg = b"\xff\xd8\xff not checked here";
        assert!(matches!(
            strip_text(Format::Jpeg, jpeg).unwrap(),
            Cow::Borrowed(_)
        ));
    }

    #[test]
    fn a_png_without_text_is_not_copied() {
        let png = plain([10, 20, 30]);
        assert!(matches!(
            strip_text(Format::Png, &png).unwrap(),
            Cow::Borrowed(_)
        ));
    }

    #[test]
    fn text_chunks_go_and_everything_else_stays_in_order() {
        let plain = plain([200, 30, 60]);
        let bomb = text_bomb([200, 30, 60], 8, 4096);
        assert!(bomb.len() > plain.len());
        let stripped = strip(&bomb).unwrap();
        assert_eq!(stripped, plain);
        assert_eq!(kinds(&stripped), ["IHDR", "IDAT", "IEND"]);
    }

    #[test]
    fn a_zlib_bomb_is_dropped_without_being_inflated() {
        // 64 chunks of ~1 MiB of text each (13 bits per 258 bytes) in
        // ~430 KB of file: stripped by reading headers alone, so it costs
        // what the file costs.
        let bomb = text_bomb([1, 2, 3], 64, 4096);
        assert!(bomb.len() < 500_000, "{}", bomb.len());
        assert_eq!(strip(&bomb).unwrap(), plain([1, 2, 3]));
    }

    #[test]
    fn ancillary_chunks_between_text_are_kept() {
        let mut png = head(1);
        chunk(&mut png, b"tEXt", b"a\0b");
        chunk(&mut png, b"gAMA", &[0, 0, 0xb1, 0x8f]);
        chunk(&mut png, b"zTXt", b"a\0\0x");
        png.extend_from_slice(&tail(1, [9, 9, 9]));
        assert_eq!(
            kinds(&strip(&png).unwrap()),
            ["IHDR", "gAMA", "IDAT", "IEND"]
        );
    }

    #[test]
    fn text_between_too_many_chunks_is_refused() {
        let build = |pairs: usize| {
            let mut png = head(1);
            for _ in 0..pairs {
                chunk(&mut png, b"tEXt", b"k\0v");
                chunk(&mut png, b"gAMA", &[0, 0, 0xb1, 0x8f]);
            }
            png.extend_from_slice(&tail(1, [9, 9, 9]));
            png
        };
        // n pairs keep n + 1 ranges: the head, then each gAMA (the last one
        // running on through IDAT and IEND).
        assert!(strip(&build(MAX_RUNS - 1)).is_ok());
        assert!(strip(&build(MAX_RUNS)).is_err());
        assert!(strip(&build(80)).is_err());
    }

    #[test]
    fn a_chunk_past_the_end_is_refused() {
        let plain = plain([1, 1, 1]);
        let mut png = plain[..33].to_vec();
        let mut overrun = Vec::new();
        chunk(&mut overrun, b"zTXt", b"k\0\0x");
        overrun[..4].copy_from_slice(&0x0010_0000u32.to_be_bytes());
        png.extend_from_slice(&overrun);
        png.extend_from_slice(&plain[33..]);
        assert!(strip(&png).unwrap_err().contains("past the end"));
    }

    #[test]
    fn a_length_over_two_gigabytes_is_refused() {
        let plain = plain([1, 1, 1]);
        let mut png = plain[..33].to_vec();
        png.extend_from_slice(&0x8000_0000u32.to_be_bytes());
        png.extend_from_slice(b"zTXt");
        png.extend_from_slice(&plain[33..]);
        assert!(strip(&png).unwrap_err().contains("2^31"));
        // On 64-bit `at + 12 + length` cannot wrap, but the largest legal
        // length must still fail as past the end rather than overflow.
        let mut png = plain[..33].to_vec();
        png.extend_from_slice(&0x7fff_ffffu32.to_be_bytes());
        png.extend_from_slice(b"zTXt");
        assert!(strip(&png).unwrap_err().contains("past the end"));
    }

    #[test]
    fn truncated_files_are_refused() {
        let png = text_bomb([5, 5, 5], 2, 16);
        // Every cut, mid-header, mid-data, before IEND, is refused (the
        // signature alone included); only the whole file passes.
        for cut in 8..png.len() {
            assert!(strip(&png[..cut]).is_err(), "cut at {cut}");
        }
        assert!(strip(&png).is_ok());
        assert!(strip(&png[..8]).unwrap_err().contains("IEND"));
    }

    #[test]
    fn a_chunk_type_must_be_four_letters() {
        let plain = plain([1, 1, 1]);
        let mut png = plain[..33].to_vec();
        chunk(&mut png, b"t3Xt", b"k\0v");
        png.extend_from_slice(&plain[33..]);
        assert!(strip(&png).unwrap_err().contains("four letters"));
    }

    #[test]
    fn the_first_chunk_must_be_ihdr() {
        let plain = plain([1, 1, 1]);
        let mut png = PNG_MAGIC.to_vec();
        chunk(&mut png, b"tEXt", b"k\0v");
        png.extend_from_slice(&plain[8..]);
        assert!(strip(&png).unwrap_err().contains("IHDR"));
        let mut png = PNG_MAGIC.to_vec();
        chunk(&mut png, b"IHDR", &[0; 12]);
        png.extend_from_slice(&plain[33..]);
        assert!(strip(&png).unwrap_err().contains("IHDR"));
    }

    #[test]
    fn a_critical_chunk_with_a_bad_crc_is_refused() {
        let mut png = plain([1, 1, 1]);
        // The IDAT's last CRC byte (IEND is the final 12 bytes).
        let at = png.len() - 13;
        png[at] ^= 1;
        assert!(strip(&png).unwrap_err().contains("CRC"));
        // A text chunk with a bad CRC is dropped like any other.
        let plain = plain([1, 1, 1]);
        let mut png = plain[..33].to_vec();
        chunk(&mut png, b"zTXt", b"k\0\0x");
        let last = png.len() - 1;
        png[last] ^= 1;
        png.extend_from_slice(&plain[33..]);
        assert_eq!(strip(&png).unwrap(), plain);
    }

    #[test]
    fn what_follows_iend_is_dropped() {
        let mut png = plain([3, 4, 5]);
        png.extend_from_slice(b"trailing bytes, a zip, anything");
        assert_eq!(strip(&png).unwrap(), plain([3, 4, 5]));
    }

    #[test]
    fn the_signature_is_required_for_a_png() {
        assert!(strip(b"\x89PNX\r\n\x1a\n").is_err());
    }
}
