///|
fn proposal_result(status : Int, body : @core.Any) -> @core.Any {
  @core.from_entries([("status", @core.any(status)), ("body", body)])
}

///|
fn proposal_error(status : Int, message : String) -> @core.Any {
  proposal_result(status, @core.from_entries([("error", @core.any(message))]))
}

///|
async fn Room::propose(self : Room, input : @core.Any) -> @core.Any {
  self.flush_inbound()
  guard @http.optional_string(self.env._get("OPENAI_API_KEY")) is Some(api_key) &&
    !api_key.is_empty() else {
    return proposal_error(503, "AI はまだ接続されていません。")
  }
  let now = now()
  let locks = self.sql
    .exec_raw("SELECT until_ms FROM ai_lock WHERE id = 1")
    .to_array()
  if !locks.is_empty() && (locks[0]._get("until_ms").cast() : Double) > now {
    return proposal_error(
      429, "前の依頼を処理しています。少し待ってからお試しください。",
    )
  }
  let request_id = @core.global_this()._get("crypto")._call("randomUUID", [])
  self.sql.exec2(
    "INSERT OR REPLACE INTO ai_lock (id, request_id, until_ms) VALUES (1, ?, ?)",
    request_id,
    @core.any(now + 180000.0),
  )
  |> ignore
  defer self.sql.exec1(
      "DELETE FROM ai_lock WHERE id = 1 AND request_id = ?", request_id,
    )
    |> ignore
  try {
    let image_model = @http.optional_string(self.env._get("OPENAI_IMAGE_MODEL")).unwrap_or(
      "gpt-image-1",
    )
    let proposal = @http.call_promise(self.runtime, "createEditProposal", [
      self.doc,
      input,
      @core.any(api_key),
      self.env._get("OPENAI_MODEL"),
      @core.from_entries([
        (
          "images",
          @core.from_entries([
            (
              "model",
              @core.any(
                if image_model.is_empty() {
                  "gpt-image-1"
                } else {
                  image_model
                },
              ),
            ),
            (
              "quality",
              @core.any(
                @ai.image_quality(self.env._get("OPENAI_IMAGE_QUALITY")),
              ),
            ),
            (
              "store",
              @core.any(fn(bytes, mime) {
                @core.from_async(async fn() {
                  self.save_image(string(input, "roomId"), bytes, mime)
                })
                |> @http.native_errors
              }),
            ),
          ]),
        ),
        ("tuning", @ai.response_tuning(self.env)),
      ]),
    ]).wait()
    proposal_result(200, proposal)
  } catch {
    error =>
      proposal_error(
        400,
        @ai.ai_error_message(@http.native_error(error), self.runtime._get("ai")),
      )
  }
}
