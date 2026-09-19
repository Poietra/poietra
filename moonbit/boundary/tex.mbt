///|
extern "js" fn tex_completion_value(
  label : String,
  insert : String,
  caret : Int,
  keys : FixedArray[String],
  hint : @core.Any,
) -> @core.Any =
  #|(label, insert, caret, keys, hint) => ({label, insert, caret, keys, hint})

///|
fn encode_tex_completion(item : @editor.TexCompletion) -> @core.Any {
  tex_completion_value(
    item.label,
    item.insert,
    item.caret,
    FixedArray::makei(item.keys.length(), fn(i) { item.keys[i] }),
    item.hint.map(@core.any).unwrap_or(@core.undefined()),
  )
}

///|
pub fn tex_completions() -> FixedArray[@core.Any] {
  let items = @editor.tex_completions()
  FixedArray::makei(items.length(), fn(i) { encode_tex_completion(items[i]) })
}

///|
extern "js" fn tex_context_value(start : Int, query : String) -> @core.Any =
  #|(start, query) => ({start, query})

///|
pub fn tex_completion_context(text : String, caret : Int) -> @core.Any {
  @editor.tex_context(text, caret)
  .map(fn(value) { tex_context_value(value.start, value.query) })
  .unwrap_or(@core.null())
}

///|
pub fn match_tex_completions(
  query : String,
  limit : @core.Any,
) -> FixedArray[@core.Any] {
  let items = @editor.match_tex_completions(
    query,
    if @core.is_undefined(limit) {
      8
    } else {
      limit.cast()
    },
  )
  FixedArray::makei(items.length(), fn(i) { encode_tex_completion(items[i]) })
}

///|
extern "js" fn tex_insertion_value(text : String, caret : Int) -> @core.Any =
  #|(text, caret) => ({text, caret})

///|
pub fn apply_tex_completion(
  text : String,
  start : Int,
  caret : Int,
  input : @core.Any,
) -> @core.Any {
  let next = @editor.apply_tex_completion(text, start, caret, {
    label: "",
    insert: input._get("insert").cast(),
    caret: input._get("caret").cast(),
    keys: [],
    hint: None,
  })
  tex_insertion_value(next.text, next.caret)
}
