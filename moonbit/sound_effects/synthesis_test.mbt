///|
test "all voices produce bounded audible PCM with silent edges and measured cues" {
  for preset in presets() {
    for duration in [60.0, preset.duration, 3000.0] {
      for pitch in [-12.0, 0.0, 12.0] {
        guard synthesize(preset.voice, duration, pitch, 42) is Ok(sound) else {
          fail("valid synthesis")
        }
        assert_eq(sound.samples.length(), (duration * 48.0).round().to_int())
        assert_eq(sound.samples[0], 0.0)
        assert_eq(sound.samples[sound.samples.length() - 1], 0.0)
        let mut sum = 0.0
        let mut maximum = 0.0
        for sample in sound.samples {
          let value = sample.to_double()
          assert_true(!value.is_nan() && !value.is_inf())
          sum += value
          maximum = maximum.max(value.abs())
        }
        assert_true(maximum >= 0.499 && maximum <= 0.501)
        assert_true((sum / sound.samples.length().to_double()).abs() < 0.00001)
        assert_true(sound.onset >= 0.0 && sound.onset <= sound.peak)
        assert_true(sound.peak < sound.end && sound.end <= sound.duration)
        assert_eq(sound.waveform.length(), 128)
        for value in sound.waveform {
          assert_true(value >= 0.0 && value <= 0.501)
        }
      }
    }
  }
}

///|
test "a recipe is repeatable and WAV stores exactly the preview PCM" {
  for preset in presets() {
    guard synthesize(preset.voice, preset.duration, 0.0, 1) is Ok(a) else {
      fail("sound")
    }
    guard synthesize(preset.voice, preset.duration, 0.0, 1) is Ok(b) else {
      fail("sound")
    }
    assert_eq(a.wave(), b.wave())
    guard synthesize(preset.voice, preset.duration, 0.0, 2) is Ok(variant) else {
      fail("variant")
    }
    assert_true(a.wave() != variant.wave())
    let bytes = a.wave()
    assert_eq(bytes.length(), 44 + a.samples.length() * 2)
    assert_eq(bytes[:4].to_owned(), b"RIFF")
    assert_eq(bytes[8:16].to_owned(), b"WAVEfmt ")
    assert_eq(bytes[36:40].to_owned(), b"data")
    for index in 0..<a.samples.length() {
      let value = bytes[44 + index * 2].to_int() +
        (bytes[45 + index * 2].to_int() << 8)
      let signed = if value >= 32768 { value - 65536 } else { value }
      assert_eq(signed.to_double() / 32768.0, a.samples[index].to_double())
    }
  }
}

///|
test "invalid render inputs are rejected before allocation" {
  for duration in [-1.0, 0.0, 59.0, 3001.0, 1.0 / 0.0, 0.0 / 0.0] {
    assert_true(synthesize(Whoosh, duration, 0.0, 1) is Err(_))
  }
  for pitch in [-13.0, 13.0, 1.0 / 0.0, 0.0 / 0.0] {
    assert_true(synthesize(Whoosh, 500.0, pitch, 1) is Err(_))
  }
}
