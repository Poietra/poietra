///|
fn Generation::tuning(self : Generation) -> Tuning? {
  if (self.runtime._get("tuningState")._get("disabled").cast() : Bool) {
    None
  } else {
    self.tuning
  }
}

///|
async fn Generation::request(
  self : Generation,
  extra : Array[Message],
  tuning : Tuning?,
) -> @core.Any {
  self.scope.check()
  let body = @core.from_entries([
    ("model", @core.any(self.model)),
    ("store", @core.any(false)),
    ("max_output_tokens", @core.any(6000)),
    (
      "input",
      @core.any(
        FixedArray::from_array((self.messages + extra).map(encode_message)[:]),
      ),
    ),
    (
      "text",
      @core.from_entries([
        (
          "format",
          self.runtime._call("zodTextFormat", [
            @schemas.edit_proposal_schema(),
            @core.any("poietra_edit"),
          ]),
        ),
      ]),
    ),
  ])
  if tuning is Some(tuning) {
    if tuning.effort is Some(effort) {
      body._set(
        "reasoning",
        @core.from_entries([("effort", @core.any(effort))]),
      )
    }
    if tuning.tier is Some(tier) {
      body._set("service_tier", @core.any(tier))
    }
  }
  self.scope.wait(
    @http.call_promise(self.client._get("responses"), "parse", [
      body,
      @core.from_entries([("signal", self.scope.controller._get("signal"))]),
    ]),
  )
}

///|
fn token_count(value : @core.Any, key : String) -> Double {
  if @core.is_nullish(value) || @core.is_nullish(value._get(key)) {
    0.0
  } else {
    value._get(key).cast()
  }
}

///|
async fn Generation::generate(
  self : Generation,
  extra : Array[Message],
) -> @core.Any {
  self.attempts += 1
  let tuning = self.tuning()
  let result = self.request(extra, tuning) catch {
    error => {
      let value = native_error(error)
      guard tuning is Some(config) &&
        (config.effort is Some(_) || config.tier is Some(_)) &&
        instance_of(value, self.runtime._get("OpenAI")._get("APIError")) &&
        @core.equal(value._get("status"), @core.any(400)) else {
        raise error
      }
      self.runtime._get("tuningState")._set("disabled", @core.any(true))
      log("warn", "ai_tuning_unsupported", [
        ("tuning", encode_tuning(tuning)),
        ("message", value._get("message")),
      ])
      self.request(extra, None)
    }
  }
  let usage = result._get("usage")
  self.usage.input += token_count(usage, "input_tokens")
  self.usage.cached += if @core.is_nullish(usage) {
    0.0
  } else {
    token_count(usage._get("input_tokens_details"), "cached_tokens")
  }
  self.usage.output += token_count(usage, "output_tokens")
  if @core.equal(result._get("status"), @core.any("incomplete")) {
    fail(
      "編集案をまとめきれませんでした。依頼を小さく分けてお試しください。",
    )
  }
  let parsed = result._get("output_parsed")
  if @core.is_nullish(parsed) {
    fail(
      "この依頼の編集案を作れませんでした。依頼を言い換えてお試しください。",
    )
  }
  parsed
}

///|
async fn Generation::image(
  self : Generation,
  images : ImageGeneration,
  operation : @core.Any,
) -> @core.Any {
  let size = string(operation, "size")
  let (width, height) = match size {
    "landscape" => (1536, 1024)
    "portrait" => (1024, 1536)
    _ => (1024, 1024)
  }
  for compression in [80, 40] {
    self.scope.check()
    let response = self.scope.wait(
      @http.call_promise(self.client._get("images"), "generate", [
        @core.from_entries([
          ("model", @core.any(images.model)),
          ("prompt", operation._get("prompt")),
          ("n", @core.any(1)),
          ("size", @core.any("\{width}x\{height}")),
          ("quality", @core.any(images.quality)),
          (
            "background",
            @core.any(
              if (operation._get("transparent").cast() : Bool) {
                "transparent"
              } else {
                "auto"
              },
            ),
          ),
          ("output_format", @core.any("webp")),
          ("output_compression", @core.any(compression)),
        ]),
        @core.from_entries([("signal", self.scope.controller._get("signal"))]),
      ]),
    )
    let data = array(response._get("data"))
    let encoded = if data.is_empty() {
      None
    } else {
      @http.optional_string(data[0]._get("b64_json"))
    }
    guard encoded is Some(encoded) && !encoded.is_empty() else {
      fail(
        "画像を生成できませんでした。内容を変えてお試しください。",
      )
      panic()
    }
    // Decode directly into one typed buffer; no intermediary JS character array.
    let decoded : String = @core.throwable(fn() {
      @core.global_this()._call("atob", [@core.any(encoded)]).cast()
    })
    let bytes = @buffer.Uint8Array::from_size(decoded.length())
    for i = 0; i < decoded.length(); i = i + 1 {
      bytes.set_at(i, decoded.code_unit_at(i).to_int())
    }
    guard @assets.image_mime(@http.byte_header(bytes)[:]) is Some(mime) else {
      fail("生成した画像を読み取れませんでした。")
      panic()
    }
    if bytes.length() > @assets.image_limit {
      continue
    }
    // Storage shares the deadline too; a stalled upload cannot hold the room lock.
    let src = self.scope.wait(
      @http.call_promise(images.store, "store", [
        bytes.as_any(),
        @core.any(mime),
      ]),
    )
    return @core.from_entries([
      ("src", src),
      ("width", @core.any(width)),
      ("height", @core.any(height)),
    ])
  }
  fail(
    "生成した画像が 1 MB を超えました。単純な内容か小さいサイズでお試しください。",
  )
  @core.undefined()
}
