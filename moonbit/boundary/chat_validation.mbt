///|
fn chat_object(value : @core.Any) -> Bool {
  !@core.is_nullish(value) &&
  @core.typeof_(value) == "object" &&
  !is_array(value)
}

///|
fn chat_text(value : @core.Any, maximum : Int) -> Bool {
  @core.typeof_(value) == "string" &&
  (value.cast() : String).length() <= maximum
}

///|
pub fn valid_chat_proposal(value : @core.Any) -> Bool {
  if !chat_object(value) ||
    @core.typeof_(value._get("id")) != "string" ||
    @core.typeof_(value._get("message")) != "string" ||
    @core.typeof_(value._get("count")) != "number" ||
    (
      (value._get("count").cast() : Double).is_nan() ||
      (value._get("count").cast() : Double).is_inf()
    ) ||
    !is_array(value._get("changes")) {
    return false
  }
  let changes : FixedArray[@core.Any] = value._get("changes").cast()
  for change in changes {
    if !chat_object(change) || !is_array(change._get("path")) {
      return false
    }
    let path : FixedArray[@core.Any] = change._get("path").cast()
    for key in path {
      if @core.typeof_(key) != "string" {
        return false
      }
    }
  }
  true
}

///|
pub fn valid_chat_message(value : @core.Any) -> Bool {
  if !chat_object(value) {
    return false
  }
  for
    (key, maximum) in [
      ("id", 100),
      ("content", 24000),
      ("authorId", 100),
      ("authorName", 40),
      ("color", 7),
    ] {
    if !chat_text(value._get(key), maximum) {
      return false
    }
  }
  let color : String = value._get("color").cast()
  if color.length() != 7 || color[0] != '#' {
    return false
  }
  for character in color[1:].iter() {
    if !(character >= '0' && character <= '9') &&
      !(character >= 'a' && character <= 'f') &&
      !(character >= 'A' && character <= 'F') {
      return false
    }
  }
  let role : String = if @core.typeof_(value._get("role")) == "string" {
    value._get("role").cast()
  } else {
    ""
  }
  if role != "user" && role != "assistant" {
    return false
  }
  if @core.typeof_(value._get("createdAt")) != "number" {
    return false
  }
  let created : Double = value._get("createdAt").cast()
  if (created.is_nan() || created.is_inf()) ||
    created < 0.0 ||
    created > 8640000000000000.0 {
    return false
  }
  let scope = value._get("scope")
  if !chat_object(scope) ||
    !chat_text(scope._get("sceneId"), 100) ||
    !chat_text(scope._get("label"), 2000) ||
    !is_array(scope._get("selectedIds")) {
    return false
  }
  let ids : FixedArray[@core.Any] = scope._get("selectedIds").cast()
  if ids.length() > 100 {
    return false
  }
  for id in ids {
    if @core.typeof_(id) != "string" {
      return false
    }
  }
  let selection = scope._get("selection")
  if !chat_object(selection) || !chat_text(selection._get("id"), 100) {
    return false
  }
  if !strict_equal(selection._get("kind"), @core.any("composition")) &&
    !strict_equal(selection._get("kind"), @core.any("transition")) {
    return false
  }
  for key in ["mentionsCodex", "applied", "dismissed"] {
    let field = value._get(key)
    if !@core.is_undefined(field) && @core.typeof_(field) != "boolean" {
      return false
    }
  }
  let reply = value._get("replyTo")
  if !@core.is_undefined(reply) && !chat_text(reply, 100) {
    return false
  }
  let status = value._get("status")
  if !@core.is_undefined(status) &&
    (
      @core.typeof_(status) != "string" ||
      @editor.chat_status(status.cast()) is None
    ) {
    return false
  }
  let client = value._get("requestClientId")
  if !@core.is_undefined(client) {
    if @core.typeof_(client) != "number" {
      return false
    }
    let number : Double = client.cast()
    if (number.is_nan() || number.is_inf()) ||
      number < 0.0 ||
      number > 9007199254740991.0 ||
      number % 1.0 != 0.0 {
      return false
    }
  }
  let proposal = value._get("proposal")
  @core.is_undefined(proposal) || valid_chat_proposal(proposal)
}
