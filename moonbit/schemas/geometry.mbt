///|
fn geometry_element_schema() -> @zod.ZodSchema {
  let coordinate = @zod.number().finite().min(-100000).max(100000)
  let reference = @zod.string().regex("^[a-zA-Z0-9_-]{1,80}$")
  let label = @zod.string().max(100)
  @zod.union([
    @zod.object({
      "kind": @zod.enum_(["free", "midpoint"]),
      "x": coordinate,
      "y": coordinate,
      "from": reference.nullable().optional(),
      "to": reference.nullable().optional(),
      "label": label,
    }),
    @zod.object({
      "from": reference,
      "vertex": reference,
      "to": reference,
      "label": label,
    }),
    @zod.object({ "from": reference, "to": reference, "label": label }),
  ])
}
