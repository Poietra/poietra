///|
pub fn valid_room_id(value : String) -> Bool {
  value.length() >= 16 &&
  value.length() <= 80 &&
  value
  .iter()
  .all(fn(c) {
    (c >= 'a' && c <= 'z') ||
    (c >= 'A' && c <= 'Z') ||
    (c >= '0' && c <= '9') ||
    c == '_' ||
    c == '-'
  })
}
