///|
/// Yjs clocks are JavaScript safe integers, not signed 32-bit positions.
pub(all) struct ClockSpan {
  clock : Double
  length : Double
} derive(Eq, Debug)

///|
fn merged_clock_spans(source : Array[ClockSpan]) -> Array[ClockSpan] {
  let source = source.copy()
  source.sort_by(fn(a, b) { a.clock.compare(b.clock) })
  let merged : Array[ClockSpan] = []
  for span in source {
    if span.length <= 0.0 {
      continue
    }
    if merged.last() is Some(previous) &&
      span.clock <= previous.clock + previous.length {
      let end = (previous.clock + previous.length).max(span.clock + span.length)
      merged[merged.length() - 1] = {
        ..previous,
        length: end - previous.clock,
      }
    } else {
      merged.push(span)
    }
  }
  merged
}

///|
/// Normalize once, then walk ordered intervals. No per-item flatMap copies.
pub fn omit_clock_spans(
  source : Array[ClockSpan],
  omitted : Array[ClockSpan],
) -> Array[ClockSpan] {
  let source = merged_clock_spans(source)
  let omitted = merged_clock_spans(omitted)
  let result = []
  let mut index = 0
  for span in source {
    let mut cursor = span.clock
    let end = span.clock + span.length
    while index < omitted.length() &&
          omitted[index].clock + omitted[index].length <= cursor {
      index += 1
    }
    while index < omitted.length() && omitted[index].clock < end {
      let cut = omitted[index]
      if cut.clock > cursor {
        result.push({ clock: cursor, length: cut.clock - cursor, })
      }
      cursor = cursor.max(cut.clock + cut.length)
      if cursor >= end {
        break
      }
      index += 1
    }
    if cursor < end {
      result.push({ clock: cursor, length: end - cursor, })
    }
  }
  result
}
