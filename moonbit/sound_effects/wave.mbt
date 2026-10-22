///|
fn little_endian(
  bytes : FixedArray[Byte],
  offset : Int,
  value : Int,
  count : Int,
) -> Unit {
  for index in 0..<count {
    bytes[offset + index] = ((value >> (index * 8)) & 255).to_byte()
  }
}

///|
/// PCM16 WAV is portable across the browser and Node renderers; preview uses
/// these same quantized samples, without a codec or a second synthesis path.
pub fn Sound::wave(self : Sound) -> Bytes {
  let size = self.samples.length() * 2
  let bytes = FixedArray::make(size + 44, b'\x00')
  let header = b"RIFF\x00\x00\x00\x00WAVEfmt \x10\x00\x00\x00\x01\x00\x01\x00\x80\xbb\x00\x00\x00\x77\x01\x00\x02\x00\x10\x00data"
  bytes.blit_from_bytes(0, header, 0, header.length())
  little_endian(bytes, 4, size + 36, 4)
  little_endian(bytes, 40, size, 4)
  for index in 0..<self.samples.length() {
    let pcm = (self.samples[index].to_double() * 32768.0).round().to_int()
    little_endian(bytes, 44 + index * 2, pcm, 2)
  }
  Bytes::makei(bytes.length(), fn(index) { bytes[index] })
}
