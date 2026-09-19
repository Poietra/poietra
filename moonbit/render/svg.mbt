///|
pub fn finite(value : Double, fallback? : Double = 0.0) -> Double {
  if value.is_nan() || value.is_inf() {
    fallback
  } else {
    value
  }
}

///|
pub fn unit(value : Double) -> Double {
  finite(value).max(0.0).min(1.0)
}

///|
pub fn number(value : Double) -> String {
  let safe = finite(value)
  (if safe.abs() < 1.0e15 {
    (safe * 1000000.0).round() / 1000000.0
  } else {
    safe
  }).to_string()
}

///|
/// Read UTF-16 explicitly: isolated surrogates are invalid XML, pairs are not.
pub fn escape_xml(value : String) -> String {
  let output = StringBuilder()
  let mut i = 0
  while i < value.length() {
    let code = value.code_unit_at(i).to_int()
    if code >= 0xd800 && code <= 0xdbff && i + 1 < value.length() {
      let next = value.code_unit_at(i + 1).to_int()
      if next >= 0xdc00 && next <= 0xdfff {
        output.write_substring(value, i, 2)
        i += 2
        continue
      }
    }
    if code >= 0xd800 && code <= 0xdfff {
      output.write_string("�")
    } else if code <= 8 ||
      code == 11 ||
      code == 12 ||
      (code >= 14 && code <= 31) ||
      code == 0xfffe ||
      code == 0xffff {
      ()
    } else {
      match code {
        38 => output.write_string("&amp;")
        60 => output.write_string("&lt;")
        62 => output.write_string("&gt;")
        34 => output.write_string("&quot;")
        39 => output.write_string("&apos;")
        _ => output.write_substring(value, i, 1)
      }
    }
    i += 1
  }
  output.to_string()
}

///|
pub fn safe_id(value : String) -> String {
  if value.is_empty() {
    return "empty"
  }
  let output = StringBuilder()
  let mut i = 0
  while i < value.length() {
    if i > 0 {
      output.write_string("-")
    }
    let mut code = value.code_unit_at(i).to_int()
    if code >= 0xd800 && code <= 0xdbff && i + 1 < value.length() {
      let next = value.code_unit_at(i + 1).to_int()
      if next >= 0xdc00 && next <= 0xdfff {
        code = 0x10000 + (code - 0xd800) * 0x400 + next - 0xdc00
        i += 1
      }
    }
    output.write_string(code.to_string(radix=16))
    i += 1
  }
  output.to_string()
}

///|
fn letter(code : Int) -> Bool {
  (code >= 65 && code <= 90) || (code >= 97 && code <= 122)
}

///|
/// This recognizes literal CSS paint only. URL, variable and inherited resources
/// never enter the self-contained SVG generated for preview or export.
pub fn color(value : String, fallback? : String = "none") -> String {
  let value = @editor.trim_text(value).to_owned()
  if value.is_empty() {
    return fallback
  }
  if value.has_prefix("#") {
    if ![4, 5, 7, 9].contains(value.length()) {
      return fallback
    }
    for i = 1; i < value.length(); i = i + 1 {
      let c = value.code_unit_at(i).to_int()
      if !((c >= 48 && c <= 57) || (c >= 65 && c <= 70) || (c >= 97 && c <= 102)) {
        return fallback
      }
    }
    return value
  }
  let mut prefix = 0
  while prefix < value.length() && letter(value.code_unit_at(prefix).to_int()) {
    prefix += 1
  }
  let name = value[:prefix].to_owned().to_lower()
  if prefix == value.length() {
    return if ["inherit", "initial", "unset", "revert", "currentcolor"].contains(
        name,
      ) {
      fallback
    } else {
      value
    }
  }
  if !["rgb", "rgba", "hsl", "hsla"].contains(name) ||
    value.length() < prefix + 3 ||
    value.code_unit_at(prefix).to_int() != 40 ||
    value.code_unit_at(value.length() - 1).to_int() != 41 {
    return fallback
  }
  for i = prefix + 1; i < value.length() - 1; i = i + 1 {
    let c = value.code_unit_at(i).to_int()
    if (c >= 48 && c <= 57) || [46, 44, 37, 43, 45, 47].contains(c) {
      continue
    }
    if !@editor.trim_text(value[i:i + 1].to_owned()).is_empty() {
      return fallback
    }
  }
  value
}
