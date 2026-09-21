///|
#external
priv type NativeHost

///|
#external
priv type NativeEncoder

///|
#external
priv type NativePacket

///|
#external
priv type NativeMetrics

///|
extern "js" fn checked_host(value : @core.Any) -> NativeHost =
  #|value => {
  #|  for (const name of ['loadMathRuntime','prepare','measureLine','fontStyles','svgBytes','png','rgba','readAudio','createEncoder','progress']) {
  #|    if (typeof value?.[name] !== 'function') throw new TypeError('Missing render host method: ' + name);
  #|  }
  #|  return value;
  #|}

///|
extern "js" fn host_prepare(
  host : NativeHost,
  sources : FixedArray[String],
  images : FixedArray[String],
) -> @core.Promise[Unit] =
  #|(host, sources, images) => Promise.resolve(host.prepare(sources, images))

///|
extern "js" fn host_load_math(host : NativeHost) -> @core.Promise[@core.Any] =
  #|host => Promise.resolve(host.loadMathRuntime())

///|
extern "js" fn host_rgba(
  host : NativeHost,
  svg : String,
) -> @core.Promise[Bytes] =
  #|(host, svg) => Promise.resolve(host.rgba(svg)).then(value => {
  #|  if (!(value instanceof Uint8Array)) throw new TypeError('Rasterizer must return Uint8Array.');
  #|  return value;
  #|})

///|
extern "js" fn host_png(
  host : NativeHost,
  svg : String,
) -> @core.Promise[Bytes] =
  #|(host, svg) => Promise.resolve(host.png(svg)).then(value => {
  #|  if (!(value instanceof Uint8Array)) throw new TypeError('PNG output must be Uint8Array.');
  #|  return value;
  #|})

///|
extern "js" fn host_svg(
  host : NativeHost,
  svg : String,
) -> @core.Promise[Bytes] =
  #|(host, svg) => Promise.resolve(host.svgBytes(svg)).then(value => {
  #|  if (!(value instanceof Uint8Array)) throw new TypeError('SVG output must be Uint8Array.');
  #|  return value;
  #|})

///|
extern "js" fn host_measure(
  host : NativeHost,
  text : String,
  size : Double,
) -> NativeMetrics =
  #|(host, text, size) => {
  #|  const value = host.measureLine(text, size);
  #|  for (const name of ['left','right','ascent','descent']) {
  #|    if (!Number.isFinite(value?.[name])) throw new TypeError('Invalid text measurement: ' + name);
  #|  }
  #|  return value;
  #|}

///|
extern "js" fn NativeMetrics::left(self : NativeMetrics) -> Double =
  #|value => value.left

///|
extern "js" fn NativeMetrics::right(self : NativeMetrics) -> Double =
  #|value => value.right

///|
extern "js" fn NativeMetrics::ascent(self : NativeMetrics) -> Double =
  #|value => value.ascent

///|
extern "js" fn NativeMetrics::descent(self : NativeMetrics) -> Double =
  #|value => value.descent

///|
extern "js" fn host_font_styles(host : NativeHost) -> String =
  #|host => {
  #|  const value = host.fontStyles();
  #|  if (typeof value !== 'string') throw new TypeError('Font styles must be a string.');
  #|  return value;
  #|}

///|
extern "js" fn host_audio(
  host : NativeHost,
  source : String,
  start : Double,
  end : Double,
) -> @core.Promise[FixedArray[NativePacket]] =
  #|(host, source, start, end) => Promise.resolve(host.readAudio(source, start, end)).then(packets => {
  #|  if (!Array.isArray(packets)) throw new TypeError('Audio source must return an array.');
  #|  for (const value of packets) {
  #|    if (!Number.isFinite(value?.timestamp) || !Number.isSafeInteger(value.sampleRate) ||
  #|        value.sampleRate < 1 || value.sampleRate > 2147483647 ||
  #|        !(value.left instanceof Float32Array) || !(value.right instanceof Float32Array)) {
  #|      throw new TypeError('Invalid PCM packet from audio source.');
  #|    }
  #|  }
  #|  return packets;
  #|})

///|
extern "js" fn NativePacket::timestamp(self : NativePacket) -> Double =
  #|value => value.timestamp

///|
extern "js" fn NativePacket::sample_rate(self : NativePacket) -> Int =
  #|value => value.sampleRate

///|
extern "js" fn NativePacket::left(self : NativePacket) -> FixedArray[Float] =
  #|value => value.left

///|
extern "js" fn NativePacket::right(self : NativePacket) -> FixedArray[Float] =
  #|value => value.right

///|
extern "js" fn host_create_encoder(
  host : NativeHost,
  width : Int,
  height : Int,
  fps : Double,
  duration_ms : Double,
  audio : Bool,
) -> @core.Promise[NativeEncoder] =
  #|(host, width, height, fps, durationMs, audio) => Promise.resolve(host.createEncoder({width, height, fps, durationMs, audio}))

///|
extern "js" fn checked_encoder(value : NativeEncoder) -> Unit =
  #|value => {
  #|  for (const name of ['addVideo','addAudio','finish','dispose']) {
  #|    if (typeof value?.[name] !== 'function') throw new TypeError('Missing encoder method: ' + name);
  #|  }
  #|}

///|
extern "js" fn encoder_video(
  encoder : NativeEncoder,
  pixels : Bytes,
) -> @core.Promise[Unit] =
  #|(encoder, pixels) => Promise.resolve(encoder.addVideo(pixels))

///|
extern "js" fn encoder_audio(
  encoder : NativeEncoder,
  left : FixedArray[Float],
  right : FixedArray[Float],
  timestamp : Double,
) -> @core.Promise[Unit] =
  #|(encoder, left, right, timestamp) => Promise.resolve(encoder.addAudio(left, right, timestamp))

///|
extern "js" fn encoder_finish(encoder : NativeEncoder) -> @core.Promise[Bytes] =
  #|encoder => Promise.resolve(encoder.finish()).then(value => {
  #|  if (!(value instanceof Uint8Array)) throw new TypeError('Encoder output must be Uint8Array.');
  #|  return value;
  #|})

///|
extern "js" fn encoder_dispose(encoder : NativeEncoder) -> @core.Promise[Unit] =
  #|encoder => Promise.resolve(encoder.dispose())

///|
extern "js" fn host_progress(
  host : NativeHost,
  value : Double,
) -> @core.Promise[Unit] =
  #|(host, value) => Promise.resolve(host.progress(value))

///|
extern "js" fn check_signal(signal : @core.Any) -> Unit =
  #|signal => { signal?.throwIfAborted(); }

///|
extern "js" fn compare_ids(a : String, b : String) -> Int =
  #|(a, b) => a.localeCompare(b)

///|
extern "js" fn native_throw(value : @core.Any) -> Unit =
  #|value => { throw value; }
