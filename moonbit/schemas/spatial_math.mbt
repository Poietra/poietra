///|
fn network_element_schema() -> @zod.ZodSchema {
  let coordinate = @zod.number().finite().min(-100000).max(100000)
  let id = @zod.string().regex("^[a-zA-Z0-9_-]{1,80}$")
  let label = @zod.string().max(100)
  @zod.union([
    @zod.object({ "x": coordinate, "y": coordinate, "label": label }),
    @zod.object({
      "from": id,
      "to": id,
      "label": label,
      "directed": @zod.boolean(),
      "weight": coordinate.nullable().optional(),
      "bend": @zod.number().finite().min(-10).max(10),
    }),
  ])
}

///|
fn surface_definition_schema() -> @zod.ZodSchema {
  let coordinate = @zod.number().finite().min(-100000).max(100000)
  let expression = @zod.string().min(1).max(512)
  @zod.object({
    "version": @zod.literal(@core.any(1)),
    "kind": @zod.enum_(["heightfield", "parametric"]),
    "xExpression": expression,
    "yExpression": expression,
    "zExpression": expression,
    "uMin": coordinate,
    "uMax": coordinate,
    "vMin": coordinate,
    "vMax": coordinate,
    "a": coordinate,
    "b": coordinate,
    "c": coordinate,
    "yaw": coordinate,
    "pitch": @zod.number().finite().min(-89).max(89),
    "zoom": @zod.number().finite().min(0).max(10),
    "steps": @zod.number().int().min(4).max(48),
    "filled": @zod.boolean(),
    "wireframe": @zod.boolean(),
    "axes": @zod.boolean(),
  })
}
