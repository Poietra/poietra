///|
pub(all) struct TexCompletion {
  label : String
  insert : String
  caret : Int
  keys : Array[String]
  hint : String?
}

///|
pub(all) struct TexContext {
  start : Int
  query : String
}

///|
pub(all) struct TexInsertion {
  text : String
  caret : Int
}

///|
fn tex_slice_index(value : Int, length : Int) -> Int {
  if value < 0 {
    (length + value).max(0)
  } else {
    value.min(length)
  }
}

///|
/// Scan only the unfinished command, in UTF-16 units shared with DOM selectionStart.
pub fn tex_context(text : String, caret : Int) -> TexContext? {
  let end = tex_slice_index(caret, text.length())
  let mut index = end - 1
  while index >= 0 {
    let unit = text.code_unit_at(index).to_int()
    if !((unit >= 65 && unit <= 90) || (unit >= 97 && unit <= 122)) {
      break
    }
    index -= 1
  }
  if index < 0 || text.code_unit_at(index).to_int() != 92 {
    return None
  }
  let mut preceding = index
  while preceding >= 0 && text.code_unit_at(preceding).to_int() == 92 {
    preceding -= 1
  }
  if (index - preceding) % 2 == 0 {
    return None
  }
  Some({ start: index, query: text[index + 1:end].to_owned(), })
}

///|
pub fn match_tex_completions(
  query : String,
  limit : Int,
) -> Array[TexCompletion] {
  let selected : Array[Int] = []
  for folded in [false, true] {
    let prefix = if folded { query.to_lower() } else { query }
    let matched : Array[(Int, Int)] = []
    for index, item in tex_catalog {
      if selected.contains(index) {
        continue
      }
      let mut rank : Int? = None
      for key in item.keys {
        let candidate = if folded { key.to_lower() } else { key }
        if candidate.has_prefix(prefix) {
          rank = Some(rank.unwrap_or(key.length()).min(key.length()))
        }
      }
      if rank is Some(rank) {
        matched.push((index, rank))
      }
    }
    if !query.is_empty() {
      matched.sort_by(fn(a, b) {
        if a.1 == b.1 {
          a.0 - b.0
        } else {
          a.1 - b.1
        }
      })
    }
    for (index, _) in matched {
      selected.push(index)
    }
  }
  // Array.slice(0, limit) also admits a negative limit at the host boundary.
  let count = tex_slice_index(limit, selected.length())
  Array::makei(count, fn(index) { tex_catalog[selected[index]] })
}

///|
pub fn apply_tex_completion(
  text : String,
  start : Int,
  caret : Int,
  item : TexCompletion,
) -> TexInsertion {
  let first = tex_slice_index(start, text.length())
  let last = tex_slice_index(caret, text.length())
  {
    text: text[:first].to_owned() + item.insert + text[last:].to_owned(),
    caret: start + item.caret,
  }
}
