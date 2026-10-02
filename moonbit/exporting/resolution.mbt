///|
/// A single requested edge retains the source aspect ratio, including when
/// another collaborator changes the source before export is captured.
pub(all) enum Resolution {
  Source
  ShortEdge(Double)
  Width(Double)
  Height(Double)
} derive(Eq, Debug)

///|
pub fn dimensions(
  source : Size,
  resolution : Resolution,
  container : Container,
) -> Size {
  let scale = match resolution {
    Source => 1.0
    ShortEdge(pixels) => pixels / source.width.min(source.height)
    Width(pixels) => pixels / source.width
    Height(pixels) => pixels / source.height
  }
  let unit = if container == Mp4 { 2.0 } else { 1.0 }
  let rounded = fn(value : Double) {
    ((value * scale / unit + 0.5).floor() * unit).max(unit)
  }
  { width: rounded(source.width), height: rounded(source.height), }
}
