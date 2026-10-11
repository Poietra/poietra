///|
priv struct PickerColor {
  hue : Double
  saturation : Double
  brightness : Double
}

///|
fn picker_rgb(value : String) -> Array[Int] {
  let hex = @editor.color_code(value).unwrap_or("#000000").to_lower()
  let digit = fn(index : Int) {
    let code = hex.code_unit_at(index).to_int()
    if code <= 57 {
      code - 48
    } else {
      code - 87
    }
  }
  [1, 3, 5].map(fn(index) { digit(index) * 16 + digit(index + 1) })
}

///|
fn picker_hex(rgb : Array[Int]) -> String {
  let hex = ((rgb[0] << 16) | (rgb[1] << 8) | rgb[2]).to_string(radix=16)
  "#" + "000000"[0:6 - hex.length()].to_owned() + hex
}

///|
fn picker_color(value : String) -> PickerColor {
  let rgb = picker_rgb(value).map(fn(channel) { channel.to_double() / 255.0 })
  let high = rgb[0].max(rgb[1]).max(rgb[2])
  let low = rgb[0].min(rgb[1]).min(rgb[2])
  let delta = high - low
  let hue = if delta == 0.0 {
    0.0
  } else if high == rgb[0] {
    60.0 * ((rgb[1] - rgb[2]) / delta)
  } else if high == rgb[1] {
    60.0 * (2.0 + (rgb[2] - rgb[0]) / delta)
  } else {
    60.0 * (4.0 + (rgb[0] - rgb[1]) / delta)
  }
  {
    hue: if hue < 0.0 {
      hue + 360.0
    } else {
      hue
    },
    saturation: if high == 0.0 {
      0.0
    } else {
      delta / high
    },
    brightness: high,
  }
}

///|
fn PickerColor::hex(self : PickerColor) -> String {
  let hue = self.hue / 60.0
  let sector = hue.to_int() % 6
  let fraction = hue - hue.to_int().to_double()
  let v = self.brightness
  let p = v * (1.0 - self.saturation)
  let q = v * (1.0 - self.saturation * fraction)
  let t = v * (1.0 - self.saturation * (1.0 - fraction))
  let rgb = match sector {
    0 => [v, t, p]
    1 => [q, v, p]
    2 => [p, v, t]
    3 => [p, q, v]
    4 => [t, p, v]
    _ => [v, p, q]
  }
  picker_hex(rgb.map(fn(channel) { (channel * 255.0 + 0.5).to_int() }))
}
