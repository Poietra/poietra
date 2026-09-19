///|
pub(all) struct ClockState {
  client_id : Double
  clock : Double
  live : Bool
}

///|
pub(all) struct Cursor {
  x : Double
  y : Double
}

///|
pub(all) struct State {
  name : String
  color : String
  scene_id : String?
  composition_id : String?
  selected_ids : Array[String]
  cursor : Cursor?
}

///|
pub fn accepts(
  previous : ClockState?,
  client_id : Double,
  clock : Double,
  live : Bool,
) -> Bool {
  match previous {
    None => live
    Some(old) =>
      old.client_id == client_id &&
      (clock > old.clock || (clock == old.clock && !live && old.live))
  }
}

///|
fn short_text(value : String, limit : Int) -> String {
  value[:value.length().min(limit)].to_owned()
}

///|
fn hex_color(value : String) -> Bool {
  if value.length() != 7 || !value.has_prefix("#") {
    return false
  }
  for index = 1; index < 7; index = index + 1 {
    let code = value.code_unit_at(index).to_int()
    if !((code >= 48 && code <= 57) ||
      (code >= 65 && code <= 70) ||
      (code >= 97 && code <= 102)) {
      return false
    }
  }
  true
}

///|
pub fn clean_state(
  name : String?,
  color : String?,
  scene_id : String?,
  composition_id : String?,
  selected_ids : Array[String],
  cursor : Cursor?,
) -> State {
  let name = short_text(name.unwrap_or(""), 40)
  let color = color.unwrap_or("")
  {
    name: if name.is_empty() {
      "Guest"
    } else {
      name
    },
    color: if hex_color(color) {
      color
    } else {
      "#7874dc"
    },
    scene_id: scene_id.map(fn(value) { short_text(value, 80) }),
    composition_id: composition_id.map(fn(value) { short_text(value, 80) }),
    selected_ids: selected_ids[:selected_ids.length().min(12)]
    .to_owned()
    .map(fn(value) { short_text(value, 80) }),
    cursor: cursor.bind(fn(point) {
      if point.x.is_nan() ||
        point.x.is_inf() ||
        point.y.is_nan() ||
        point.y.is_inf() {
        None
      } else {
        Some({
          x: point.x.max(-10000.0).min(10000.0),
          y: point.y.max(-10000.0).min(10000.0),
        })
      }
    }),
  }
}
