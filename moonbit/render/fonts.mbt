///|
pub(all) struct FontAsset {
  family : String
  url : String
  unicode_range : String?
  ranges : Array[(Int, Int)]?
}

///|
pub(all) struct FontCatalog {
  faces : Array[FontAsset]
}

///|
pub fn font_catalog(
  inter_url : String,
  css : String,
  files : Map[String, String],
) -> FontCatalog {
  let urls : Map[String, String] = Map([])
  for path, url in files {
    urls[path.split("/").last().unwrap().to_owned()] = url
  }
  let faces : Array[FontAsset] = [
    {
      family: "Poietra Inter",
      url: inter_url,
      unicode_range: None,
      ranges: None,
    },
  ]
  for section in css.split("@font-face").drop(1) {
    guard section.split_once("{") is Some((_, body)) else { continue }
    guard body.split_once("}") is Some((declaration, _)) else { continue }
    guard declaration.split_once("url(./files/") is Some((_, path)) else {
      continue
    }
    guard path.split_once(")") is Some((name, _)) else { continue }
    guard urls.get(name.to_owned()) is Some(url) else { continue }
    guard declaration.split_once("unicode-range:") is Some((_, rest)) else {
      continue
    }
    guard rest.split_once(";") is Some((range, _)) else { continue }
    let range = @editor.trim_text(range.to_owned()).to_owned()
    let ranges : Array[(Int, Int)] = []
    let mut valid = true
    for part in range.split(",") {
      let part = @editor.trim_text(part.to_owned())
      if !part.has_prefix("U+") {
        valid = false
        break
      }
      let pair = part[2:].split_once("-")
      let (start, end) = pair.unwrap_or((part[2:], part[2:]))
      ranges.push(
        (@string.parse_int(start, base=16), @string.parse_int(end, base=16)),
      ) catch {
        _ => {
          valid = false
          break
        }
      }
    }
    if valid {
      faces.push({
        family: "Poietra Noto Sans JP",
        url,
        unicode_range: Some(range),
        ranges: Some(ranges),
      })
    }
  }
  { faces, }
}

///|
pub fn required_faces(
  catalog : FontCatalog,
  sources : Array[String],
) -> Array[FontAsset] {
  let points : Map[Int, Unit] = Map([])
  for source in sources {
    for character in source {
      points[character.to_int()] = ()
    }
  }
  if points.is_empty() {
    return []
  }
  catalog.faces.filter(fn(face) {
    match face.ranges {
      None => true
      Some(ranges) =>
        ranges.any(fn(range) {
          points
          .keys()
          .any(fn(point) { point > 255 && point >= range.0 && point <= range.1 })
        })
    }
  })
}

///|
pub(all) struct LineMetrics {
  advance : Double
  left : Double
  right : Double
  ascent : Double
  descent : Double
}

///|
pub fn text_metrics(
  text : String,
  size : Double,
  measure : ((String) -> LineMetrics)?,
) -> TextMetrics {
  if size <= 0.0 {
    return { width: 0.0, height: 0.0, line_height: 0.0, baseline: 0.0, }
  }
  let lines = text.split("\n").to_array()
  let line_height = size * 1.25
  match measure {
    None => {
      let mut width = 0.0
      for line in lines {
        let mut advance = 0.0
        for character in line {
          advance += if character.to_int() > 255 { 1.0 } else { 0.62 }
        }
        width = @scene.maximum(width, advance)
      }
      {
        width: width * size,
        height: size + (lines.length() - 1).to_double() * line_height,
        line_height,
        baseline: size * 0.3,
      }
    }
    Some(measure) => {
      let mut ascent = size * 0.8
      let mut descent = size * 0.2
      let mut width = 0.0
      for line in lines {
        let m = measure(line.to_owned())
        ascent = @scene.maximum(ascent, m.ascent)
        descent = @scene.maximum(descent, m.descent)
        width = @scene.maximum(
          width,
          2.0 *
          @scene.maximum(
            @scene.maximum(m.advance / 2.0, m.advance / 2.0 + m.left),
            m.right - m.advance / 2.0,
          ),
        )
      }
      {
        width,
        height: ascent +
        descent +
        (lines.length() - 1).to_double() * line_height,
        line_height,
        baseline: (ascent - descent) / 2.0,
      }
    }
  }
}
