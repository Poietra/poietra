///|
priv enum Role {
  Developer
  User
  Assistant
}

///|
priv struct Message {
  role : Role
  content : String
}

///|
priv struct EditRequest {
  scene_id : String
  composition_id : String?
  transition_id : String?
  selected_ids : Array[String]
  prompt : String
  history : Array[Message]
  supports_append : Bool
}

///|
priv struct Usage {
  mut input : Double
  mut cached : Double
  mut output : Double
}

///|
priv struct Tuning {
  effort : String?
  tier : String?
}

///|
priv struct ImageGeneration {
  model : String
  quality : String
  store : @core.Any
}

///|
priv struct RequestScope {
  started : Double
  controller : @core.Any
  timeout_error : @core.Any
  deadline : @core.Promise[@core.Any]
  timer : @core.Any
}

///|
priv struct Generation {
  scope : RequestScope
  client : @core.Any
  runtime : @core.Any
  model : String
  messages : Array[Message]
  tuning : Tuning?
  usage : Usage
  mut attempts : Int
}

///|
fn string(value : @core.Any, key : String) -> String {
  value._get(key).cast()
}

///|
fn array(value : @core.Any) -> Array[@core.Any] {
  if @core.is_nullish(value) {
    []
  } else {
    let entries : FixedArray[@core.Any] = value.cast()
    entries.iter().to_array()
  }
}

///|
fn encode_message(value : Message) -> @core.Any {
  @core.from_entries([
    (
      "role",
      @core.any(
        match value.role {
          Developer => "developer"
          User => "user"
          Assistant => "assistant"
        },
      ),
    ),
    ("content", @core.any(value.content)),
  ])
}

///|
fn read_request(value : @core.Any) -> EditRequest {
  {
    scene_id: string(value, "sceneId"),
    composition_id: @http.optional_string(value._get("compositionId")),
    transition_id: @http.optional_string(value._get("transitionId")),
    selected_ids: array(value._get("selectedIds")).map(fn(id) { id.cast() }),
    prompt: string(value, "prompt"),
    history: array(value._get("history")).map(fn(turn) {
      let assistant = string(turn, "role") == "assistant"
      {
        role: if assistant {
          Assistant
        } else {
          User
        },
        content: if assistant {
          json(
            @core.from_entries([
              ("message", turn._get("content")),
              (
                "proposalStatus",
                if @core.is_nullish(turn._get("proposalStatus")) {
                  @core.null()
                } else {
                  turn._get("proposalStatus")
                },
              ),
            ]),
          )
        } else {
          string(turn, "content")
        },
      }
    }),
    supports_append: @core.equal(
      value._get("supportsCompositionAppends"),
      @core.any(true),
    ),
  }
}

///|
pub fn image_quality(value : @core.Any) -> String {
  match @http.optional_string(value) {
    Some("low") => "low"
    Some("high") => "high"
    _ => "medium"
  }
}

///|
fn read_tuning(value : @core.Any) -> Tuning? {
  if @core.is_nullish(value) {
    None
  } else {
    Some({
      effort: @http.optional_string(value._get("reasoningEffort")),
      tier: @http.optional_string(value._get("serviceTier")),
    })
  }
}

///|
fn encode_tuning(tuning : Tuning?) -> @core.Any {
  match tuning {
    None => @core.null()
    Some(tuning) => {
      let result = @core.new_object()
      if tuning.effort is Some(effort) {
        result._set("reasoningEffort", @core.any(effort))
      }
      if tuning.tier is Some(tier) {
        result._set("serviceTier", @core.any(tier))
      }
      result
    }
  }
}

///|
pub fn response_tuning(env : @core.Any) -> @core.Any {
  let effort = @http.optional_string(env._get("OPENAI_REASONING_EFFORT")).unwrap_or(
    "medium",
  )
  let tier = @http.optional_string(env._get("OPENAI_SERVICE_TIER")).unwrap_or(
    "fast",
  )
  encode_tuning(
    Some({
      effort: if ["none", "minimal", "low", "medium", "high", "xhigh", "max"].contains(
          effort,
        ) {
        Some(effort)
      } else {
        None
      },
      tier: if ["flex", "scale", "priority", "fast", "ultrafast"].contains(tier) {
        Some(tier)
      } else {
        None
      },
    }),
  )
}

///|
fn images_config(options : @core.Any) -> ImageGeneration? {
  let value = options._get("images")
  if @core.is_nullish(value) {
    None
  } else {
    Some({
      model: string(value, "model"),
      quality: string(value, "quality"),
      store: value,
    })
  }
}
