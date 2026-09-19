///|
let image_sources : @collection.JsMap[String, String] = @collection.JsMap::new()

///|
let image_requests : @collection.JsMap[String, @core.Promise[Unit]] = @collection.JsMap::new()

///|
// Inline pixels are immutable but can be megabytes long. Bound this validation
// memo separately from prepared room assets; evicting it only repeats validation.
let inline_images : @collection.JsMap[String, Unit] = @collection.JsMap::new()

///|
pub fn prepared_image(source : @core.Any) -> @core.Any {
  if @core.is_nullish(source) || @core.equal(source, @core.any("")) {
    return @core.null()
  }
  let source : String = source.cast()
  if inline_images.has(source) {
    return @core.any(source)
  }
  if @assets.data_source(source, @assets.Image) {
    if inline_images.size() >= 64 {
      if inline_images.keys().next() is Some(oldest) {
        inline_images.delete(oldest) |> ignore
      }
    }
    inline_images.set(source, ()) |> ignore
    @core.any(source)
  } else {
    match image_sources.get(source) {
      Some(value) => @core.any(value)
      None => @core.null()
    }
  }
}

///|
pub fn prepare_images(scene : @core.Any) -> @core.Promise[Unit] {
  @core.from_async(async fn() {
    let objects = scene._get("objects")
    let compositions = scene._get("compositions")
    for id in @core.object_keys(objects) {
      let object = objects._get(id)
      if !@core.equal(object._get("kind"), @core.any("image")) {
        continue
      }
      let visible = @core.object_keys(compositions).any(fn(key) {
        let state = compositions._get(key)._get("states")._get(id)
        !@core.is_nullish(state) &&
        @core.equal(state._get("visible"), @core.any(true))
      })
      if !visible {
        continue
      }
      let asset = object._get("image")
      let valid = !@core.is_nullish(asset) &&
        @core.typeof_(asset._get("src")) == "string" &&
        @core.typeof_(asset._get("width")) == "number" &&
        @core.typeof_(asset._get("height")) == "number" &&
        @assets.valid_image(
          asset._get("src").cast(),
          asset._get("width").cast(),
          asset._get("height").cast(),
        )
      if !valid {
        let name : String = object._get("name").cast()
        raise MediaFailure(
          "「\{name}」の画像がありません。画像を追加し直してください。",
        )
      }
      let source : String = asset._get("src").cast()
      if !@core.is_nullish(prepared_image(@core.any(source))) {
        continue
      }
      let pending = match image_requests.get(source) {
        Some(pending) => pending
        None => {
          let pending = @core.from_async(async fn() {
              // Publish the shared request before calling any synchronously failing host API.
              @core.Promise::resolve(()).wait()
              defer image_requests.delete(source) |> ignore
              let blob = image_blob(source, @core.undefined()).wait()
              let image = blob_data_url(blob).wait()
              image_sources.set(source, image) |> ignore
            })
            |> native_errors
          image_requests.set(source, pending) |> ignore
          pending
        }
      }
      pending.wait()
    }
  })
  |> native_errors
}
