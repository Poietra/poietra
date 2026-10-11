///|
/// A bounded decoder for the portable format. The schema strips unknown fields
/// before domain reference validation; caller-owned records are copied.
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
priv enum FileInputOwnership {
  Borrowed
  ParsedJson
}

///|
fn parse_file_field(
  value : @core.Any,
  field : FileField,
  validation? : AssetValidation = AssetValidation::new(),
  ownership? : FileInputOwnership = Borrowed,
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
        parse_file_field(value, child, validation~, ownership~)
      }
    Nullable(child) =>
      if @core.is_null(value) {
        value
      } else {
        parse_file_field(value, child, validation~, ownership~)
      }
    Record(fields) => {
      if !is_record(value) {
        raise InvalidFileField
      }
      let result = if ownership is ParsedJson {
        value
      } else {
        @core.new_object()
      }
      for key, child in fields {
        let item = parse_file_field(
          value._get(key),
          child,
          validation~,
          ownership~,
        )
        if ownership is Borrowed && !@core.is_undefined(item) {
          put_own(result, key, item)
        }
      }
      if ownership is ParsedJson {
        for key in @core.object_keys(value) {
          if !fields.contains(key) {
            erase_own(value, key)
          }
        }
      }
      result
    }
    Dictionary(child) => {
      if !is_record(value) {
        raise InvalidFileField
      }
      let result = if ownership is ParsedJson {
        value
      } else {
        @core.new_object()
      }
      for key in @core.object_keys(value) {
        if !@assets.document_id(key) {
          raise InvalidFileField
        }
        let item = parse_file_field(
          value._get(key),
          child,
          validation~,
          ownership~,
        )
        if ownership is Borrowed {
          put_own(result, key, item)
        }
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
      match ownership {
        ParsedJson => {
          for item in items {
            parse_file_field(item, child, validation~, ownership~) |> ignore
          }
          value
        }
        Borrowed =>
          @core.any(
            FixedArray::makei(items.length(), fn(i) raise InvalidFileField {
              parse_file_field(items[i], child, validation~, ownership~)
            }),
          )
      }
    }
    Easing => {
      if !is_valid_easing(value) {
        raise InvalidFileField
      }
      if @core.typeof_(value) == "string" || ownership is ParsedJson {
        value
      } else {
        merge_values(@core.new_object(), value)
      }
    }
    Image => {
      let parsed = parse_file_field(
        value,
        image_file_field,
        validation~,
        ownership~,
      )
      let asset = decode_ImageAsset(parsed)
      if !validation.image(asset) {
        raise InvalidFileField
      }
      parsed
    }
    Media => {
      let parsed = parse_file_field(
        value,
        media_file_field,
        validation~,
        ownership~,
      )
      if !validation.media(decode_MediaAsset(parsed)) {
        raise InvalidFileField
      }
      parsed
    }
    Playback =>
      parse_file_field(value, playback_file_field, validation~, ownership~)
    Audio => {
      let parsed = parse_file_field(
        value,
        audio_file_field,
        validation~,
        ownership~,
      )
      // Media was validated by the nested schema. Do not scan its source again.
      if !@assets.valid_audio_fields(decode_AudioTrack(parsed)) {
        raise InvalidFileField
      }
      parsed
    }
    CurveValue =>
      if @core.typeof_(value) == "number" {
        parse_file_field(value, file_number, validation~, ownership~)
      } else {
        parse_file_field(value, Color, validation~, ownership~)
      }
    Keyframe => {
      let parsed = parse_file_field(
        value,
        keyframe_file_field,
        validation~,
        ownership~,
      )
      if !@scene.valid_keyframe(decode_Keyframe(parsed)) {
        raise InvalidFileField
      }
      parsed
    }
    SceneObject => {
      let parsed = parse_file_field(
        value,
        object_file_field,
        validation~,
        ownership~,
      )
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
let audio_value_fields : Map[String, FileField] = {
  "id": Identifier,
  "name": Text(200),
  "volume": Numeric(0.0, 1.0, false),
  "muted": Boolean,
  "start": media_time,
  "offset": media_time,
  "duration": media_time,
}

///|
let audio_file_field : FileField = {
  let fields = audio_value_fields.copy()
  fields.set("asset", Media)
  Record(fields)
}

///|
let object_file_field : FileField = Record({
  "id": Identifier,
  "name": Text(200),
  "kind": Strings([
    "circle", "rectangle", "text", "equation", "path", "arrow", "numberline", "image",
    "video", "graph", "geometry", "network", "surface",
  ]),
  "order": file_number,
  "groupId": Nullable(Identifier),
  "parentId": Optional(Nullable(Identifier)),
  "clipChildren": Optional(Boolean),
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
let graph_file_field : FileField = Record({
  "syntaxVersion": Numeric(1.0, 2.0, true),
  "expression": Text(512),
  "xMin": Numeric(-100000.0, 100000.0, false),
  "xMax": Numeric(-100000.0, 100000.0, false),
  "yMin": Numeric(-100000.0, 100000.0, false),
  "yMax": Numeric(-100000.0, 100000.0, false),
  "a": Numeric(-100000.0, 100000.0, false),
  "b": Numeric(-100000.0, 100000.0, false),
  "c": Numeric(-100000.0, 100000.0, false),
  "axes": Boolean,
  "grid": Boolean,
  "filled": Optional(Boolean),
  "breaks": Sequence(Numeric(-100000.0, 100000.0, false), 0, 32),
})

///|
let geometry_file_field : FileField = Record({
  "version": Numeric(1.0, 1.0, true),
  "points": Dictionary(
    Record({
      "kind": Strings(["free", "midpoint"]),
      "x": Numeric(-100000.0, 100000.0, false),
      "y": Numeric(-100000.0, 100000.0, false),
      "from": Optional(Nullable(Identifier)),
      "to": Optional(Nullable(Identifier)),
      "label": Text(100),
      "deleted": Optional(Boolean),
    }),
  ),
  "vectors": Dictionary(
    Record({
      "from": Identifier,
      "to": Identifier,
      "label": Text(100),
      "deleted": Optional(Boolean),
    }),
  ),
  "angles": Dictionary(
    Record({
      "from": Identifier,
      "vertex": Identifier,
      "to": Identifier,
      "label": Text(100),
      "deleted": Optional(Boolean),
    }),
  ),
})

///|
let network_file_field : FileField = Record({
  "version": Numeric(1.0, 1.0, true),
  "nodes": Dictionary(
    Record({
      "x": Numeric(-100000.0, 100000.0, false),
      "y": Numeric(-100000.0, 100000.0, false),
      "label": Text(100),
      "deleted": Optional(Boolean),
    }),
  ),
  "edges": Dictionary(
    Record({
      "from": Identifier,
      "to": Identifier,
      "label": Text(100),
      "directed": Boolean,
      "weight": Optional(Nullable(Numeric(-100000.0, 100000.0, false))),
      "bend": Numeric(-10.0, 10.0, false),
      "deleted": Optional(Boolean),
    }),
  ),
})

///|
let surface_file_field : FileField = Record({
  "version": Numeric(1.0, 1.0, true),
  "kind": Strings(["heightfield", "parametric"]),
  "xExpression": Text(512),
  "yExpression": Text(512),
  "zExpression": Text(512),
  "uMin": Numeric(-100000.0, 100000.0, false),
  "uMax": Numeric(-100000.0, 100000.0, false),
  "vMin": Numeric(-100000.0, 100000.0, false),
  "vMax": Numeric(-100000.0, 100000.0, false),
  "a": Numeric(-100000.0, 100000.0, false),
  "b": Numeric(-100000.0, 100000.0, false),
  "c": Numeric(-100000.0, 100000.0, false),
  "yaw": Numeric(-100000.0, 100000.0, false),
  "pitch": Numeric(-89.0, 89.0, false),
  "zoom": Numeric(0.05, 10.0, false),
  "steps": Numeric(4.0, 48.0, true),
  "filled": Boolean,
  "wireframe": Boolean,
  "axes": Boolean,
})

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
  "graph": Optional(graph_file_field),
  "geometry": Optional(geometry_file_field),
  "network": Optional(network_file_field),
  "surface": Optional(surface_file_field),
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
  for channel in @scene.property_channels() {
    fields[@scene.property_channel_name(channel) + "Timing"] = Optional(
      Nullable(timing_file_field),
    )
  }
  Record(fields)
}

///|
let project_file_field : FileField = Record({
  "version": Numeric(1.0, 7.0, true),
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
pub fn read_network_definition(value : @core.Any) -> @scene.NetworkDefinition {
  let parsed = parse_file_field(value, network_file_field) catch {
    _ => {
      @core.throw_error("グラフ理論のデータ形式が不正です。")
      @core.undefined()
    }
  }
  let result = decode_NetworkDefinition(parsed)
  if @scene.network_validation_error(result) is Some(message) {
    @core.throw_error(message)
  }
  result
}

///|
pub fn read_surface_definition(value : @core.Any) -> @scene.SurfaceDefinition {
  let parsed = parse_file_field(value, surface_file_field) catch {
    _ => {
      @core.throw_error("3D曲面のデータ形式が不正です。")
      @core.undefined()
    }
  }
  let result = decode_SurfaceDefinition(parsed)
  if @scene.surface_validation_error(result) is Some(message) {
    @core.throw_error(message)
  }
  result
}

///|
pub fn read_geometry_definition(value : @core.Any) -> @scene.GeometryDefinition {
  let parsed = parse_file_field(value, geometry_file_field) catch {
    _ => {
      @core.throw_error("幾何のデータ形式が不正です。")
      @core.undefined()
    }
  }
  let definition = decode_GeometryDefinition(parsed)
  if @scene.geometry_validation_error(definition) is Some(message) {
    @core.throw_error(message)
  }
  definition
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

///|
pub fn read_image_asset(
  value : @core.Any,
  validation? : AssetValidation = AssetValidation::new(),
) -> @scene.ImageAsset raise {
  decode_ImageAsset(parse_file_field(value, Image, validation~))
}

///|
pub fn read_media_asset(
  value : @core.Any,
  validation? : AssetValidation = AssetValidation::new(),
) -> @scene.MediaAsset raise {
  let asset = decode_MediaAsset(
    parse_file_field(value, media_file_field, validation~),
  )
  if !validation.media(asset) {
    raise InvalidFileField
  }
  asset
}

///|
pub fn read_media_playback(value : @core.Any) -> @scene.MediaPlayback raise {
  decode_MediaPlayback(parse_file_field(value, Playback))
}

///|
/// A specialized reader can reuse a previously validated immutable media leaf.
/// The reader owns that provenance check; ordinary inputs validate afresh.
pub fn read_audio_track(
  value : @core.Any,
  media_reader? : (@core.Any) -> @scene.MediaAsset raise = fn(value) raise {
    read_media_asset(value)
  },
) -> @scene.AudioTrack raise {
  let parsed = parse_file_field(value, Record(audio_value_fields))
  let asset = media_reader(value._get("asset"))
  let track = decode_AudioTrack(parsed, asset_decoder=fn(_) { asset })
  if !@assets.valid_audio_fields(track) {
    raise InvalidFileField
  }
  track
}
