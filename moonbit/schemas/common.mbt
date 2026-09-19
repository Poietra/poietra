///|
pub fn parse(schema : @zod.ZodSchema, input : @core.Any) -> @core.Any {
  match schema.safeParse(input) {
    Ok(value) => value
    Err(error) => {
      // Preserve native ZodError identity for API error reporting and repair.
      @core.throw_(error.as_any())
      panic()
    }
  }
}

///|
let cubic_easing : @zod.ZodSchema = {
  let coordinate = @zod.number().finite().min(0).max(1)
  @zod.object({
    "type": @zod.literal(@core.any("cubicBezier")),
    "x1": coordinate,
    "y1": coordinate,
    "x2": coordinate,
    "y2": coordinate,
  }).strict()
}

///|
let easing : @zod.ZodSchema = @zod.union([
  @zod.enum_(["linear", "easeInOut", "easeIn", "easeOut"]),
  cubic_easing,
])

///|
pub fn easing_schema() -> @core.Any {
  easing.as_any()
}

///|
pub fn cubic_easing_schema() -> @core.Any {
  cubic_easing.as_any()
}

///|
let image_source : @zod.ZodSchema = @zod.string()
  .max(1398166)
  .refine(fn(value) { @assets.valid_source(value.cast(), Image) })

///|
let image_asset : @zod.ZodSchema = @zod.object({
  "src": image_source,
  "width": @zod.number().int().min(1).max(2048),
  "height": @zod.number().int().min(1).max(2048),
})

///|
pub fn image_source_schema() -> @core.Any {
  image_source.as_any()
}

///|
pub fn image_asset_schema() -> @core.Any {
  image_asset.as_any()
}

///|
let media_time : @zod.ZodSchema = @zod.number().finite().min(0).max(86400000)

///|
let media_asset : @zod.ZodSchema = @zod.object({
    "src": @zod.string()
    .max(44739307)
    .refine(fn(value) { @assets.valid_source(value.cast(), Media) }),
    "mime": @zod.enum_([
      "video/mp4", "video/webm", "audio/mpeg", "audio/wav", "audio/ogg", "audio/flac",
      "audio/mp4", "audio/webm",
    ]),
    "duration": media_time.refine(fn(value) { (value.cast() : Double) > 0.0 }),
    "width": @zod.number().int().min(1).max(8192).optional(),
    "height": @zod.number().int().min(1).max(8192).optional(),
    "hasAudio": @zod.boolean(),
    "waveform": @zod.array(@zod.number().finite().min(0).max(1))
    .max(160)
    .optional(),
  })
  .refine(fn(value) {
    let mime : String = value._get("mime").cast()
    !mime.has_prefix("video/") ||
    (
      !@core.is_undefined(value._get("width")) &&
      !@core.is_undefined(value._get("height"))
    )
  })
  .refine(fn(value) {
    let src : String = value._get("src").cast()
    !src.has_prefix("data:") ||
    src.has_prefix("data:" + (value._get("mime").cast() : String) + ";")
  })

///|
let media_playback : @zod.ZodSchema = @zod.object({
  "start": media_time,
  "offset": media_time,
  "duration": media_time,
})

///|
let audio_track : @zod.ZodSchema = @zod.object({
  "start": media_time,
  "offset": media_time,
  "duration": media_time,
  "id": @zod.string()
  .regex("^[a-zA-Z0-9_-]{1,80}$")
  .refine(fn(value) { @assets.document_id(value.cast()) }),
  "name": @zod.string().max(200),
  "asset": media_asset,
  "volume": @zod.number().finite().min(0).max(1),
  "muted": @zod.boolean(),
}).refine(fn(value) {
  let asset = value._get("asset")
  (asset._get("hasAudio").cast() : Bool) &&
  (value._get("offset").cast() : Double) +
  (value._get("duration").cast() : Double) <=
  (asset._get("duration").cast() : Double) + 1.0
})

///|
pub fn media_asset_schema() -> @core.Any {
  media_asset.as_any()
}

///|
pub fn media_playback_schema() -> @core.Any {
  media_playback.as_any()
}

///|
pub fn audio_track_schema() -> @core.Any {
  audio_track.as_any()
}

///|
let ai_history : @zod.ZodSchema = {
  let content = @zod.string().max(3000)
  let turn = @zod.discriminated_union("role", [
    @zod.object({ "role": @zod.literal(@core.any("user")), "content": content }).strict(),
    @zod.object({
      "role": @zod.literal(@core.any("assistant")),
      "content": content,
      "proposalStatus": @zod.enum_(["proposed", "applied", "discarded"]).optional(),
    }).strict(),
  ])
  @zod.array(turn)
  .max(24)
  .refine(
    fn(history) {
      let entries : FixedArray[@core.Any] = history.cast()
      let mut total = 0
      for entry in entries {
        total += (entry._get("content").cast() : String).length()
      }
      total <= 24000
    },
    message="会話履歴は合計 24000 文字以内にしてください。",
  )
}

///|
pub fn ai_history_schema() -> @core.Any {
  ai_history.as_any()
}
