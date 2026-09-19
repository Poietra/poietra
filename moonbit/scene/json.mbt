///| The JS document uses explicit null for cleared groups, paths and overrides.

///|
/// MoonBit derives Option fields from missing keys; normalize only those fields.
pub fn normalize_nullable_fields(value : Json) -> Json {
  match value {
    Object(fields) => {
      let result : Map[String, Json] = Map([])
      for key, value in fields {
        if value is Null &&
          (
            key == "groupId" ||
            key == "parentId" ||
            key == "path" ||
            key == "positionTiming" ||
            key == "opacityTiming" ||
            key == "sizeTiming" ||
            key == "rotationTiming" ||
            key == "fillTiming" ||
            key == "strokeTiming" ||
            key == "strokeWidthTiming" ||
            key == "fontSizeTiming" ||
            key == "cornerRadiusTiming" ||
            key == "pathTiming" ||
            key == "revealTiming"
          ) {
          continue
        }
        result[key] = normalize_nullable_fields(value)
      }
      result.to_json()
    }
    Array(values) => values.map(normalize_nullable_fields).to_json()
    _ => value
  }
}
