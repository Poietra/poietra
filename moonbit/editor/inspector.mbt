///|
pub fn object_label(kind : @scene.ObjectKind) -> String {
  match kind {
    Circle => "Circle"
    Rectangle => "Rectangle"
    Text => "Text"
    Equation => "Equation"
    Path => "Path"
    Arrow => "Arrow"
    NumberLine => "Number line"
    Image => "Image"
    Video => "Video"
  }
}

///|
pub fn color_code(text : String) -> String? {
  let start = if text.has_prefix("#") { 1 } else { 0 }
  if text.length() - start != 6 {
    return None
  }
  for index = start; index < text.length(); index = index + 1 {
    let unit = text.code_unit_at(index).to_int()
    if !((unit >= 48 && unit <= 57) ||
      (unit >= 65 && unit <= 70) ||
      (unit >= 97 && unit <= 102)) {
      return None
    }
  }
  Some("#" + text[start:].to_owned())
}

///|
pub(all) enum Alignment {
  AlignStart
  AlignCenter
  AlignEnd
}

///|
pub(all) struct AlignmentItem {
  id : String
  position : Double
  low : Double
  extent : Double
}

///|
pub fn alignment_plan(
  items : Array[AlignmentItem],
  extent : Double,
  alignment : Alignment,
) -> Array[(String, Double)] {
  if items.is_empty() {
    return []
  }
  let mut low = 0.0
  let mut high = extent
  if items.length() > 1 {
    low = items[0].low
    high = items[0].low + items[0].extent
    for item in items {
      low = @scene.minimum(low, item.low)
      high = @scene.maximum(high, item.low + item.extent)
    }
  }
  let target = match alignment {
    AlignStart => low
    AlignCenter => (low + high) / 2.0
    AlignEnd => high
  }
  items.map(fn(item) {
    let anchor = match alignment {
      AlignStart => item.low
      AlignCenter => item.low + item.extent / 2.0
      AlignEnd => item.low + item.extent
    }
    (item.id, item.position + target - anchor)
  })
}
