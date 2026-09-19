///|
extern "js" fn round(value : Double) -> Double = "Math.round"

///|
pub fn placeholder_image(size : String) -> @core.Any {
  let (width, height) = match size {
    "landscape" => (1536, 1024)
    "portrait" => (1024, 1536)
    _ => (1024, 1024)
  }
  @core.from_entries([
    (
      "src",
      @core.any(
        "data:image/png;base64,iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNkYPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==",
      ),
    ),
    ("width", @core.any(width)),
    ("height", @core.any(height)),
  ])
}

///|
pub fn with_generated_images(
  raw : @core.Any,
  asset : (@core.Any) -> @core.Any,
) -> @core.Any {
  let operations : FixedArray[@core.Any] = raw._get("operations").cast()
  let is_image = fn(operation : @core.Any) {
    same_identity(operation._get("action"), @core.any("generateImage"))
  }
  if operations.iter().filter(is_image).count() > 2 {
    return fail("一度に生成できる画像は 2 枚までです。")
  }
  let resolved = FixedArray::makei(operations.length(), fn(index) {
    let operation = operations[index]
    if !is_image(operation) {
      return operation
    }
    let image = asset(operation)
    if !truthy(image) {
      return fail("画像の生成が完了していません。")
    }
    let width : Double = operation._get("width").cast()
    let height = round(
        width *
        (image._get("height").cast() : Double) /
        (image._get("width").cast() : Double) *
        100.0,
      ) /
      100.0
    let output = @core.from_entries([
      ("action", @core.any("createImage")),
      (
        "height",
        @core.any(if height.is_nan() || height.is_inf() { 0.0 } else { height }),
      ),
      ("image", image),
    ])
    for key in ["ref", "compositionId", "name", "x", "y", "width"] {
      output._set(key, operation._get(key))
    }
    output
  })
  @core.from_entries([
    ("message", raw._get("message")),
    ("operations", @core.any(resolved)),
  ])
}
