///|
pub fn valid_canvas_dimension(value : Double) -> Bool {
  !value.is_nan() &&
  !value.is_inf() &&
  value >= 1.0 &&
  value <= 8192.0 &&
  value.floor() == value
}
