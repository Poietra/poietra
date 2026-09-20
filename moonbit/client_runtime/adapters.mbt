///|
// Preserve the pinned compiler's foreign optional-Bool ABI: -1 selects the
// default, while explicit false/true (and JS undefined) pass through unchanged.
fn prepared_stage_frame(
  source : @core.Any,
  renderer : @core.Any,
  scope : String,
  enabled : @core.Any,
) -> @core.Any {
  @ui.use_prepared_stage_frame(
    source,
    renderer,
    scope,
    enabled=if @core.equal(enabled, @core.any(-1)) {
      true
    } else {
      enabled.cast()
    },
  )
}
