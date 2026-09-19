///|
fn messages(
  input : EditRequest,
  scene : @core.Any,
  images : Bool,
) -> Array[Message] raise {
  let content = json(
    @core.from_entries([
      ("request", @core.any(input.prompt)),
      (
        "selection",
        @core.from_entries([
          (
            "compositionId",
            match input.composition_id {
              Some(id) => @core.any(id)
              None => @core.null()
            },
          ),
          (
            "transitionId",
            match input.transition_id {
              Some(id) => @core.any(id)
              None => @core.null()
            },
          ),
          (
            "objectIds",
            @core.any(FixedArray::from_array(input.selected_ids[:])),
          ),
        ]),
      ),
      ("scene", scene),
    ]),
  )
  if content.length() > 200000 {
    fail(
      "この Scene は大きすぎます。Scene を分けてからお試しください。",
    )
  }
  let developer = instructions +
    (if images { image_instructions } else { no_image_instructions }) +
    (if input.supports_append {
      ""
    } else {
      "\nThis client cannot apply appendComposition. Do not use appendComposition for this request. If adding a Composition is necessary, ask the user to reload the page to use the updated editor, and return no operations. Existing-object and existing-timeline editing remains available."
    })
  [{ role: Developer, content: developer, }] +
  input.history +
  [{ role: User, content, }]
}

///|
fn validate_selection(
  input : EditRequest,
  project : @core.Any,
) -> @core.Any raise {
  if @core.is_nullish(project) || !owns(project._get("scenes"), input.scene_id) {
    fail("Scene が見つかりません。")
  }
  let scene = project._get("scenes")._get(input.scene_id)
  if input.composition_id is Some(id) &&
    !id.is_empty() &&
    !owns(scene._get("compositions"), id) {
    fail("選択中の Composition が見つかりません。")
  }
  if input.transition_id is Some(id) &&
    !id.is_empty() &&
    !owns(scene._get("transitions"), id) {
    fail("選択中の Transition が見つかりません。")
  }
  if input.selected_ids.any(fn(id) { !owns(scene._get("objects"), id) }) {
    fail(
      "選択中のオブジェクトが変更されました。選び直してお試しください。",
    )
  }
  scene
}

///|
pub fn create_edit_proposal(
  doc : @core.Any,
  value : @core.Any,
  api_key : String,
  model : String,
  options : @core.Any,
  runtime : @core.Any,
) -> @core.Promise[@core.Any] {
  @core.from_async(async fn() {
    let input = read_request(
      @core.throwable(fn() { @schemas.parse_ai_request(value) }),
    )
    let scope = open_scope()
    defer scope.close()
    errdefer scope.controller._call("abort", []) |> ignore
    let yjs = runtime._get("Y")
    // Snapshot before the first await; later collaborator writes cannot change preconditions.
    let snapshot = @core.new(yjs._get("Doc"), [])
    defer snapshot._call("destroy", []) |> ignore
    try {
      @core.throwable(fn() {
        yjs._call("applyUpdate", [
          snapshot,
          yjs._call("encodeStateAsUpdate", [doc]),
        ])
      })
      |> ignore
      let project = @boundary.read_project(snapshot, yjs)
      let scene = validate_selection(input, project)
      let images = images_config(options)
      let generation : Generation = {
        scope,
        runtime,
        model,
        messages: messages(input, scene, images is Some(_)),
        client: @core.new(runtime._get("OpenAI"), [
          @core.from_entries([
            ("apiKey", @core.any(api_key)),
            ("timeout", @core.any(60000)),
            ("maxRetries", @core.any(1)),
          ]),
        ]),
        tuning: read_tuning(options._get("tuning")),
        usage: { input: 0.0, cached: 0.0, output: 0.0, },
        attempts: 0,
      }
      let compile = fn(
        parsed : @core.Any,
        asset : (@core.Any) -> @core.Any,
      ) raise {
        let operations = array(parsed._get("operations"))
        if !input.supports_append &&
          operations.any(fn(op) { string(op, "action") == "appendComposition" }) {
          fail(
            "場面の追加を使うには、ページを再読み込みしてから依頼してください。",
          )
        }
        if images is None &&
          operations.any(fn(op) { string(op, "action") == "generateImage" }) {
          fail(
            "画像の生成はこのサーバーでは使えません。Add image で画像を追加してください。",
          )
        }
        @core.throwable(fn() {
          @proposals.compile_proposal(
            snapshot,
            project,
            input.scene_id,
            @proposals.with_generated_images(parsed, asset),
            yjs,
          )
        })
      }
      let placeholder = fn(operation) {
        @proposals.placeholder_image(string(operation, "size"))
      }
      // Refusals, incomplete responses and API errors occur outside the repair catch.
      let mut parsed = generation.generate([])
      let mut proposal = compile(parsed, placeholder) catch {
        error => {
          if scope.elapsed() > 50000.0 {
            raise error
          }
          let reason = rejection_reason(error, runtime)
          log("warn", "ai_proposal_rejected", [
            ("ms", @core.any(scope.elapsed())),
            ("reason", @core.any(reason)),
          ])
          parsed = generation.generate([
            { role: Assistant, content: json(parsed), },
            {
              role: User,
              content: "The previous proposal was rejected before it reached the editor. Validation error: " +
              reason +
              "\nReturn a corrected proposal for the same request. Use only object, composition and transition IDs that exist in the current Scene, or refs declared in this proposal; keep every track within its Transition duration; never edit locked objects. If the request cannot be satisfied with the available operations, explain why and return no operations.",
            },
          ])
          compile(parsed, placeholder)
        }
      }
      let requests = array(parsed._get("operations")).filter(fn(op) {
        string(op, "action") == "generateImage"
      })
      if !requests.is_empty() {
        if scope.elapsed() > 60000.0 {
          fail(
            "時間内に画像を生成できませんでした。もう一度依頼してください。",
          )
        }
        guard images is Some(images) else {
          fail("画像の生成はこのサーバーでは使えません。")
          panic()
        }
        let assets = @core.Promise::all(
          requests.map(fn(operation) {
            @core.from_async(async fn() {
              let began = now()
              let asset = generation.image(images, operation)
              log("log", "ai_image_generated", [
                ("ms", @core.any(now() - began)),
                ("size", operation._get("size")),
                ("transparent", operation._get("transparent")),
              ])
              asset
            })
          }),
        ).wait()
        proposal = compile(parsed, fn(operation) {
          for index, request in requests {
            if @core.equal(operation, request) {
              return assets[index]
            }
          }
          @core.undefined()
        })
      }
      log("log", "ai_proposal", [
        ("ms", @core.any(scope.elapsed())),
        ("attempts", @core.any(generation.attempts)),
        ("operations", parsed._get("operations")._get("length")),
        ("changes", proposal._get("changes")._get("length")),
        ("images", @core.any(requests.length())),
        (
          "usage",
          @core.from_entries([
            ("input", @core.any(generation.usage.input)),
            ("cached", @core.any(generation.usage.cached)),
            ("output", @core.any(generation.usage.output)),
          ]),
        ),
        ("tuning", encode_tuning(generation.tuning())),
      ])
      proposal
    } catch {
      error => {
        if (scope.controller._get("signal")._get("aborted").cast() : Bool) {
          log("warn", "ai_request_timeout", [("ms", @core.any(scope.elapsed()))])
          raise AiFailure(scope.timeout_error)
        }
        raise AiFailure(native_error(error))
      }
    }
  })
  |> native_errors
}
