// Writes a valid 1x1 PNG whose text chunks are tiny on disk and enormous when
// inflated: the fixture the byte, pixel and memory limits cannot catch,
// because libpng keeps every zTXt it inflates outside ImageMagick's resource
// accounting.
//
//   node tests/make-text-bomb.js <path> [chunks] [KiB per chunk]
//
// Half the zTXt chunks sit before the image data and half after it (libpng
// reads both: png_read_info, then png_read_end), with one tEXt and one iTXt
// among them. Each chunk's text is a run of zeros deflated on its own, so
// nothing here ever holds more than one chunk's inflated text.

const { deflateSync } = require("node:zlib")
const { writeFileSync } = require("node:fs")

const output = process.argv[2]
const count = Number(process.argv[3] || 64)
const kib = Number(process.argv[4] || 1024)
if (!output) {
  console.error("usage: node tests/make-text-bomb.js <path> [chunks] [KiB per chunk]")
  process.exit(2)
}

const crcTable = (() => {
  const table = new Int32Array(256)
  for (let n = 0; n < 256; n++) {
    let c = n
    for (let k = 0; k < 8; k++) c = c & 1 ? 0xedb88320 ^ (c >>> 1) : c >>> 1
    table[n] = c
  }
  return table
})()

function crc32(buffer) {
  let c = 0xffffffff
  for (let i = 0; i < buffer.length; i++) c = crcTable[(c ^ buffer[i]) & 0xff] ^ (c >>> 8)
  return (c ^ 0xffffffff) >>> 0
}

function chunk(type, body) {
  const length = Buffer.alloc(4)
  length.writeUInt32BE(body.length, 0)
  const typed = Buffer.concat([Buffer.from(type, "ascii"), body])
  const crc = Buffer.alloc(4)
  crc.writeUInt32BE(crc32(typed), 0)
  return Buffer.concat([length, typed, crc])
}

// One inflated text, deflated once and reused: every chunk is still its own
// zlib stream, which is what makes libpng inflate and keep each one.
const text = deflateSync(Buffer.alloc(kib * 1024, 0x41), { level: 9 })
function zTXt(index) {
  return chunk("zTXt", Buffer.concat([Buffer.from("k" + index + "\0\0", "latin1"), text]))
}

const header = Buffer.alloc(13)
header.writeUInt32BE(1, 0)      // width
header.writeUInt32BE(1, 4)      // height
header[8] = 8                   // bit depth
header[9] = 2                   // truecolour

const parts = [Buffer.from([0x89, 0x50, 0x4e, 0x47, 0x0d, 0x0a, 0x1a, 0x0a]), chunk("IHDR", header)]
parts.push(chunk("tEXt", Buffer.from("Comment\0a cover", "latin1")))
parts.push(chunk("iTXt", Buffer.from("Title\0\0\0\0a cover", "latin1")))
const before = Math.ceil(count / 2)
for (let i = 0; i < before; i++) parts.push(zTXt(i))
// One filter byte and one green pixel.
parts.push(chunk("IDAT", deflateSync(Buffer.from([0, 0x1d, 0xb9, 0x54]))))
for (let i = before; i < count; i++) parts.push(zTXt(i))
parts.push(chunk("IEND", Buffer.alloc(0)))

writeFileSync(output, Buffer.concat(parts))
