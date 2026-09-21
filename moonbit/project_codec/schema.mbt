///|
fn field_schema(field : FileField, prefix : String) -> Json {
  let reference = fn(name : String) -> Json { { "$ref": Json(prefix + name) } }
  match field {
    Numeric(minimum, maximum, integer) =>
      {
        "type": Json(if integer { "integer" } else { "number" }),
        "minimum": Json(minimum),
        "maximum": Json(maximum),
      }
    Text(maximum) => { "type": "string", "maxLength": Json(maximum) }
    Identifier =>
      {
        "type": "string",
        "pattern": "^[A-Za-z0-9_-]{1,80}$",
        "not": { "enum": ["__proto__", "constructor", "prototype"] },
      }
    Color =>
      {
        "type": "string",
        "pattern": "^(none|transparent|#[0-9a-fA-F]{3}|#[0-9a-fA-F]{6}|#[0-9a-fA-F]{8})$",
      }
    Boolean => { "type": "boolean" }
    Strings(choices) => { "type": "string", "enum": Json(choices) }
    Optional(child) => field_schema(child, prefix)
    Nullable(child) =>
      { "anyOf": [field_schema(child, prefix), { "type": "null" }] }
    Record(fields) => {
      let properties : Map[String, Json] = Map([])
      let required : Array[String] = []
      let keys = fields.keys().to_array()
      keys.sort()
      for key in keys {
        let child = fields[key]
        properties[key] = field_schema(child, prefix)
        if !(child is Optional(_)) {
          required.push(key)
        }
      }
      {
        "type": "object",
        "properties": Json(properties),
        "required": Json(required),
        "propertyNames": {
          "not": { "enum": ["__proto__", "constructor", "prototype"] },
        },
      }
    }
    Dictionary(child) =>
      {
        "type": "object",
        "propertyNames": field_schema(Identifier, prefix),
        "additionalProperties": field_schema(child, prefix),
      }
    Sequence(child, minimum, maximum) =>
      {
        "type": "array",
        "items": field_schema(child, prefix),
        "minItems": Json(minimum),
        "maxItems": Json(maximum),
      }
    Easing => reference("Easing")
    Image => reference("ImageAsset")
    Media => reference("MediaAsset")
    Playback => reference("MediaPlayback")
    Audio => reference("AudioTrack")
    SceneObject => reference("SceneObject")
    Keyframe => reference("Keyframe")
    CurveValue =>
      {
        "anyOf": [
          field_schema(file_number, prefix),
          field_schema(Color, prefix),
        ],
      }
  }
}

///|
/// Structural schema from the same field definitions as the portable decoder.
/// Reference, timing, source-codec and UTF-16 length checks still run at ingestion.
pub fn project_schema(reference_prefix? : String = "#/$defs/") -> Json {
  let easing : Json = {
    "anyOf": [
      { "enum": ["linear", "easeInOut", "easeIn", "easeOut"] },
      {
        "type": "object",
        "required": ["type", "x1", "y1", "x2", "y2"],
        "additionalProperties": false,
        "properties": {
          "type": { "const": "cubicBezier" },
          "x1": { "type": "number", "minimum": 0, "maximum": 1 },
          "y1": { "type": "number", "minimum": 0, "maximum": 1 },
          "x2": { "type": "number", "minimum": 0, "maximum": 1 },
          "y2": { "type": "number", "minimum": 0, "maximum": 1 },
        },
      },
    ],
  }
  let definitions : Map[String, Json] = { "Easing": easing }
  for
    (name, field) in [
      ("ImageAsset", image_file_field),
      ("MediaAsset", media_file_field),
      ("MediaPlayback", playback_file_field),
      ("AudioTrack", audio_file_field),
      ("SceneObject", object_file_field),
      ("Keyframe", keyframe_file_field),
    ] {
    definitions[name] = field_schema(field, reference_prefix)
  }
  guard field_schema(project_file_field, reference_prefix) is Object(root) else {
    return Json::null()
  }
  root["$schema"] = "https://json-schema.org/draft/2020-12/schema"
  root["title"] = "Poietra portable project"
  root["description"] = "Version 1 and 2 portable documents. Structural constraints are generated from the decoder. Ingestion also validates UTF-16 string lengths, references, timing, asset contents and rendering compatibility. Use POST /inspect before rendering; successful inspection does not guarantee codec decoding."
  root["$defs"] = Json(definitions)
  Json::object(root)
}
