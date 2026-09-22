///|
#external
pub type Encoder

///|
#external
pub type Decoder

///|
#module("lib0/encoding")
pub extern "js" fn encoder() -> Encoder = "createEncoder"

///|
#module("lib0/encoding")
pub extern "js" fn write_uint(output : Encoder, value : Double) -> Unit = "writeVarUint"

///|
#module("lib0/encoding")
pub extern "js" fn write_string(output : Encoder, value : String) -> Unit = "writeVarString"

///|
#module("lib0/encoding")
pub extern "js" fn write_bytes(output : Encoder, value : @core.Any) -> Unit = "writeVarUint8Array"

///|
#module("lib0/encoding")
pub extern "js" fn write_raw_bytes(output : Encoder, value : @core.Any) -> Unit = "writeUint8Array"

///|
#module("lib0/encoding")
pub extern "js" fn to_bytes(output : Encoder) -> @core.Any = "toUint8Array"

///|
#module("lib0/encoding")
pub extern "js" fn length(output : Encoder) -> Int = "length"

///|
#module("lib0/decoding")
pub extern "js" fn decoder(bytes : @core.Any) -> Decoder = "createDecoder"

///|
#module("lib0/decoding")
pub extern "js" fn read_uint(input : Decoder) -> Double = "readVarUint"

///|
pub fn read_string(input : Decoder) -> String {
  decode_utf8(read_bytes(input))
}

///|
pub fn read_bytes(input : Decoder) -> @core.Any {
  let length = read_uint(input)
  let value = @core.any(input)
  let size : Double = value._get("arr")._get("byteLength").cast()
  let position : Double = value._get("pos").cast()
  // lib0's native decoder constructs a view of the backing ArrayBuffer. Bound
  // reads by the supplied view, which may be only a slice of that buffer.
  if length > size - position {
    @core.throw_error("Unexpected end of message")
  }
  read_fixed_bytes(input, length)
}

///|
#module("lib0/decoding")
extern "js" fn read_fixed_bytes(input : Decoder, length : Double) -> @core.Any = "readUint8Array"

///|
#module("lib0/string")
extern "js" fn decode_utf8(bytes : @core.Any) -> String = "decodeUtf8"
