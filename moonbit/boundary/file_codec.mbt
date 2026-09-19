///|
/// A bounded decoder for the portable format. The schema constructs fresh
/// records and strips unknown fields before domain reference validation.
priv enum FileField {
  Numeric(Double, Double, Bool)
  Text(Int)
  Identifier
  Color
  Boolean
  Strings(Array[String])
  Record(Map[String, FileField])
  Dictionary(FileField)
  Sequence(FileField, Int, Int)
  Optional(FileField)
  Nullable(FileField)
  Easing
  Image
  Media
  Playback
  Audio
  SceneObject
  Keyframe
  CurveValue
}

///|
priv suberror InvalidFileField

///|
fn parse_file_field(
  value : @core.Any,
  field : FileField,
) -> @core.Any raise InvalidFileField {
  match field {
    Numeric(minimum, maximum, integer) => {
      guard @core.typeof_(value) == "number" else { raise InvalidFileField }
      let number : Double = value.cast()
      if !@assets.bounded_number(number, minimum, maximum) ||
        (integer && number.trunc() != number) {
        raise InvalidFileField
      }
      value
    }
    Text(maximum) => {
      if @core.typeof_(value) != "string" ||
        (value.cast() : String).length() > maximum {
        raise InvalidFileField
      }
      value
    }
    Identifier => {
      if @core.typeof_(value) != "string" || !@assets.document_id(value.cast()) {
        raise InvalidFileField
      }
      value
    }
    Color => {
      if @core.typeof_(value) != "string" ||
        !@assets.document_color(value.cast()) {
        raise InvalidFileField
      }
      value
    }
    Boolean => {
      if @core.typeof_(value) != "boolean" {
        raise InvalidFileField
      }
      value
    }
    Strings(choices) => {
      if @core.typeof_(value) != "string" || !choices.contains(value.cast()) {
        raise InvalidFileField
      }
      value
    }
    Optional(child) =>
      if @core.is_undefined(value) {
        value
      } else {
        parse_file_field(value, child)
      }
    Nullable(child) =>
      if @core.is_null(value) {
        value
      } else {
        parse_file_field(value, child)
      }
    Record(fields) => {
      if !chat_object(value) {
        raise InvalidFileField
      }
      let result = @core.new_object()
      for key, child in fields {
        let item = parse_file_field(value._get(key), child)
        if !@core.is_undefined(item) {
          put_own(result, key, item)
        }
      }
      result
    }
    Dictionary(child) => {
      if !chat_object(value) {
        raise InvalidFileField
      }
      let result = @core.new_object()
      for key in @core.object_keys(value) {
        if !@assets.document_id(key) {
          raise InvalidFileField
        }
        put_own(result, key, parse_file_field(value._get(key), child))
      }
      result
    }
    Sequence(child, minimum, maximum) => {
      if !is_array(value) {
        raise InvalidFileField
      }
      let items : FixedArray[@core.Any] = value.cast()
      if items.length() < minimum || items.length() > maximum {
        raise InvalidFileField
      }
      @core.any(
        FixedArray::makei(items.length(), fn(i) raise InvalidFileField {
          parse_file_field(items[i], child)
        }),
      )
    }
    Easing => {
      if !is_valid_easing(value) {
        raise InvalidFileField
      }
      if @core.typeof_(value) == "string" {
        value
      } else {
        merge_values(@core.new_object(), value)
      }
    }
    Image => {
      let parsed = parse_file_field(value, image_file_field)
      let asset = decode_ImageAsset(parsed)
      if !@assets.valid_image(asset.src, asset.width, asset.height) {
        raise InvalidFileField
      }
      parsed
    }
    Media => {
      let parsed = parse_file_field(value, media_file_field)
      if !@assets.valid_media(decode_MediaAsset(parsed)) {
        raise InvalidFileField
      }
      parsed
    }
    Playback => parse_file_field(value, playback_file_field)
    Audio => {
      let parsed = parse_file_field(value, audio_file_field)
      if !@assets.valid_audio(decode_AudioTrack(parsed)) {
        raise InvalidFileField
      }
      parsed
    }
    CurveValue =>
      if @core.typeof_(value) == "number" {
        parse_file_field(value, file_number)
      } else {
        parse_file_field(value, Color)
      }
    Keyframe => {
      let parsed = parse_file_field(value, keyframe_file_field)
      if !@scene.valid_keyframe(decode_Keyframe(parsed)) {
        raise InvalidFileField
      }
      parsed
    }
    SceneObject => {
      let parsed = parse_file_field(value, object_file_field)
      let object = decode_SceneObject(parsed)
      if object.kind == @scene.Image && object.image is None {
        raise InvalidFileField
      }
      if object.kind == @scene.Video {
        guard object.media is Some(asset) && object.playback is Some(playback) else {
          raise InvalidFileField
        }
        if !asset.mime.has_prefix("video/") ||
          playback.offset + playback.duration > asset.duration + 1.0 {
          raise InvalidFileField
        }
      }
      parsed
    }
  }
}

///|
let file_number : FileField = Numeric(-100000.0, 100000.0, false)

///|
let file_duration : FileField = Numeric(0.0, 600000.0, false)

///|
let media_time : FileField = Numeric(0.0, 86400000.0, false)

///|
let image_file_field : FileField = Record({
  "src": Text(1398166),
  "width": Numeric(1.0, 2048.0, true),
  "height": Numeric(1.0, 2048.0, true),
})

///|
let media_file_field : FileField = Record({
  "src": Text(44739307),
  "mime": Strings([
    "video/mp4", "video/webm", "audio/mpeg", "audio/wav", "audio/ogg", "audio/flac",
    "audio/mp4", "audio/webm",
  ]),
  "duration": media_time,
  "width": Optional(Numeric(1.0, 8192.0, true)),
  "height": Optional(Numeric(1.0, 8192.0, true)),
  "hasAudio": Boolean,
  "waveform": Optional(Sequence(Numeric(0.0, 1.0, false), 0, 160)),
})

///|
let playback_file_field : FileField = Record({
  "start": media_time,
  "offset": media_time,
  "duration": media_time,
})

///|
let audio_file_field : FileField = Record({
  "id": Identifier,
  "name": Text(200),
  "asset": Media,
  "volume": Numeric(0.0, 1.0, false),
  "muted": Boolean,
  "start": media_time,
  "offset": media_time,
  "duration": media_time,
})

///|
let object_file_field : FileField = Record({
  "id": Identifier,
  "name": Text(200),
  "kind": Strings([
    "circle", "rectangle", "text", "equation", "path", "arrow", "numberline", "image",
    "video",
  ]),
  "order": file_number,
  "groupId": Nullable(Identifier),
  "parentId": Optional(Nullable(Identifier)),
  "locked": Boolean,
  "image": Optional(Image),
  "media": Optional(Media),
  "playback": Optional(Playback),
})

///|
let file_point : FileField = Record({ "x": file_number, "y": file_number })

///|
let file_bezier : FileField = Record({ "c1": file_point, "c2": file_point })

///|
let state_file_field : FileField = Record({
  "x": file_number,
  "y": file_number,
  "width": file_number,
  "height": file_number,
  "rotation": file_number,
  "anchorX": Optional(file_number),
  "anchorY": Optional(file_number),
  "scaleX": Optional(file_number),
  "scaleY": Optional(file_number),
  "shear": Optional(file_number),
  "opacity": Numeric(0.0, 1.0, false),
  "visible": Boolean,
  "fill": Color,
  "stroke": Color,
  "strokeWidth": Numeric(0.0, 10000.0, false),
  "text": Text(10000),
  "fontSize": Numeric(0.0, 10000.0, false),
  "cornerRadius": Numeric(0.0, 10000.0, false),
  "effect": Strings(["none", "glow"]),
  "path": file_bezier,
})

///|
let timing_file_field : FileField = Record({
  "start": file_duration,
  "duration": file_duration,
  "easing": Easing,
})

///|
let keyframe_file_field : FileField = Record({
  "property": Strings(
    {
      let names = []
      for c in @scene.property_channels() {
        names.append(@scene.curve_properties(c).map(@scene.curve_property_name))
      }
      names
    },
  ),
  "at": Numeric(0.0, 1.0, false),
  "value": CurveValue,
  "easing": Easing,
  "deleted": Optional(Boolean),
})

///|
fn track_file_fields() -> FileField {
  let fields = {
    "implicit": Optional(Boolean),
    "keyframes": Optional(Dictionary(Keyframe)),
    "objectId": Identifier,
    "type": Strings(["move", "write", "fade", "grow", "none"]),
    "start": file_duration,
    "duration": file_duration,
    "easing": Easing,
    "order": Strings(["together", "sequential"]),
    "path": Nullable(file_bezier),
  }
  for
    key in [
      "position", "opacity", "size", "rotation", "fill", "stroke", "strokeWidth",
      "fontSize", "cornerRadius", "path", "reveal",
    ] {
    fields[key + "Timing"] = Optional(Nullable(timing_file_field))
  }
  Record(fields)
}

///|
let project_file_field : FileField = Record({
  "version": Numeric(1.0, 2.0, true),
  "name": Text(100),
  "sceneOrder": Sequence(Identifier, 1, 100),
  "scenes": Dictionary(
    Record({
      "id": Identifier,
      "name": Text(200),
      "width": Numeric(1.0, 8192.0, true),
      "height": Numeric(1.0, 8192.0, true),
      "background": Color,
      "objects": Dictionary(SceneObject),
      "audioTracks": Optional(Dictionary(Audio)),
      "compositionOrder": Sequence(Identifier, 1, 100),
      "compositions": Dictionary(
        Record({
          "id": Identifier,
          "name": Text(200),
          "duration": file_duration,
          "accent": Color,
          "states": Dictionary(state_file_field),
        }),
      ),
      "transitions": Dictionary(
        Record({
          "id": Identifier,
          "fromId": Identifier,
          "toId": Identifier,
          "duration": file_duration,
          "tracks": Dictionary(track_file_fields()),
        }),
      ),
    }),
  ),
})

///|
pub fn read_keyframe(value : @core.Any) -> @scene.Keyframe {
  decode_Keyframe(value)
}

///|
pub fn write_keyframe(value : @scene.Keyframe) -> @core.Any {
  encode_Keyframe(value)
}

///|
pub fn validate_keyframe(value : @core.Any) -> Unit {
  (parse_file_field(value, Keyframe) |> ignore) catch {
    _ =>
      @core.throw_error(
        "キーフレームの時刻・値・イージングが無効です。時刻は区間の 0〜100% の間に指定してください。",
      )
  }
}

///|
pub fn valid_document_id(value : String) -> Bool {
  @assets.document_id(value)
}
