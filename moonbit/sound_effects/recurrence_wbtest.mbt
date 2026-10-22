///|
test "stationary modal recurrence retains the analytic damped tone" {
  for frequency in [62.0, 170.0, 880.0, 5230.0, 10460.0] {
    let decay = 0.4
    let gain = 0.65
    let voice = mode(frequency, decay, gain, 0)
    let angle = 2.0 * @math.PI * frequency / sample_rate.to_double()
    let mut error = 0.0
    for index in 0..<(sample_rate * 3) {
      let reference = gain *
        @math.exp(-index.to_double() / (decay * sample_rate.to_double())) *
        @math.sin(angle * (index + 1).to_double())
      error = error.max((voice.next(index) - reference).abs())
    }
    assert_true(error < 0.00000001)
  }
}
