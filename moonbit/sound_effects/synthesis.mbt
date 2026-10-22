///|
pub let sample_rate : Int = 48000

///|
pub(all) struct Sound {
  samples : FixedArray[Float]
  waveform : Array[Double]
  duration : Double
  onset : Double
  peak : Double
  end : Double
}

///|
pub fn Sound::cue(self : Sound, point : SyncPoint) -> Double {
  match point {
    Onset => self.onset
    Peak => self.peak
    End => self.end
  }
}

///|
priv struct Resonator {
  start : Int
  coefficient : Double
  damping : Double
  mut previous : Double
  mut current : Double
}

///|
/// Damped modal synthesis needs no per-sample trigonometry for stationary tones.
fn mode(
  frequency : Double,
  decay : Double,
  gain : Double,
  start : Int,
) -> Resonator {
  let angle = 2.0 * @math.PI * frequency.min(18000.0) / sample_rate.to_double()
  let damping = @math.exp(-1.0 / (decay * sample_rate.to_double()))
  {
    start,
    coefficient: 2.0 * damping * @math.cos(angle),
    damping: damping * damping,
    previous: 0.0,
    current: gain * @math.sin(angle),
  }
}

///|
fn Resonator::next(self : Resonator, index : Int) -> Double {
  if index < self.start {
    return 0.0
  }
  let value = self.current
  self.current = self.coefficient * value - self.damping * self.previous
  self.previous = value
  value
}

///|
fn edge(index : Int, length : Int, fade : Int) -> Double {
  let x = (index.min(length - 1 - index).to_double() / fade.to_double()).min(
    1.0,
  )
  x * x * (3.0 - 2.0 * x)
}

///|
pub fn synthesize(
  voice : Voice,
  duration : Double,
  semitones : Double,
  seed : UInt,
) -> Result[Sound, String] {
  if duration.is_nan() ||
    duration.is_inf() ||
    duration < 60.0 ||
    duration > 3000.0 {
    return Err("効果音の長さは 60〜3,000 ms にしてください。")
  }
  if semitones.is_nan() || semitones.is_inf() || semitones.abs() > 12.0 {
    return Err(
      "効果音の高さは −12〜12 半音にしてください。",
    )
  }
  let rate = sample_rate.to_double()
  let length = (duration * rate / 1000.0).round().to_int()
  let seconds = length.to_double() / rate
  let decay = seconds *
    (0.85 + ((seed * 2654435761) >> 24).to_double() / 255.0 * 0.3)
  let pitch = @math.pow(2.0, semitones / 12.0)
  let modes : Array[Resonator] = []
  match voice {
    Click => {
      modes.push(mode(2400.0 * pitch, decay * 0.12, 0.5, 0))
      modes.push(mode(3710.0 * pitch, decay * 0.07, 0.22, 0))
      modes.push(mode(5230.0 * pitch, decay * 0.04, 0.1, 0))
    }
    Tap => {
      modes.push(mode(170.0 * pitch, decay * 0.16, 0.8, 0))
      modes.push(mode(380.0 * pitch, decay * 0.08, 0.25, 0))
      modes.push(mode(920.0 * pitch, decay * 0.04, 0.12, 0))
    }
    Impact => {
      modes.push(mode(62.0 * pitch, decay * 0.22, 0.7, 0))
      modes.push(mode(103.0 * pitch, decay * 0.13, 0.3, 0))
      modes.push(mode(191.0 * pitch, decay * 0.08, 0.12, 0))
    }
    Chime =>
      for
        (ratio, gain, damping) in [
          (1.0, 0.65, 0.23),
          (2.01, 0.23, 0.17),
          (2.76, 0.12, 0.1),
          (4.07, 0.05, 0.06),
        ] {
        modes.push(mode(880.0 * pitch * ratio, decay * damping, gain, 0))
      }
    Success =>
      for (ratio, delay) in [(1.0, 0.0), (1.25, 0.16), (1.5, 0.32)] {
        let start = (delay * length.to_double()).to_int()
        modes.push(mode(660.0 * pitch * ratio, decay * 0.18, 0.5, start))
        modes.push(mode(1324.0 * pitch * ratio, decay * 0.09, 0.12, start))
      }
    _ => ()
  }
  let samples : FixedArray[Float] = FixedArray::make(length, 0.0)
  // Small fixed delay lines give tonal effects a diffuse tail without convolution.
  let delay = FixedArray::make((rate * 0.031).to_int(), 0.0)
  let mut random = seed ^ 0x9e3779b9
  let mut low = 0.0
  let mut body = 0.0
  let mut phase = 0.0
  let mut sum = 0.0
  let mut weights = 0.0
  let fade = (length / 8).min(240)
  for index in 0..<length {
    random = random * 1664525 + 1013904223
    let noise = (random >> 8).to_double() / 8388608.0 - 1.0
    let x = index.to_double() / (length - 1).to_double()
    let t = index.to_double() / rate
    let band = match voice {
      Whoosh => (600.0 + 4300.0 * @math.sin(@math.PI * x)) * pitch
      Swish => (2200.0 + 4200.0 * x) * pitch
      Riser => (300.0 + 6000.0 * x * x) * pitch
      _ => 5500.0 * pitch
    }
    let alpha = 2.0 * @math.PI * band / (rate + 2.0 * @math.PI * band)
    low += alpha * (noise - low)
    body += 0.035 * (low - body)
    let band_noise = low - body
    let mut value = 0.0
    for resonator in modes {
      value += resonator.next(index)
    }
    match voice {
      Click => value += band_noise * @math.exp(-t / (seconds * 0.025)) * 0.45
      Tap => value += band_noise * @math.exp(-t / (seconds * 0.035)) * 0.2
      Pop => {
        let frequency = (320.0 + 1100.0 * @math.exp(-t / (seconds * 0.065))) *
          pitch
        phase += 2.0 * @math.PI * frequency / rate
        value = (@math.sin(phase) * 0.9 + band_noise * 0.15) *
          @math.exp(-t / (seconds * 0.14))
      }
      Whoosh | Swish => {
        let envelope = @math.sin(@math.PI * x)
        value = band_noise *
          envelope *
          envelope *
          (1.0 + 0.12 * @math.sin(t * 93.0))
      }
      Impact =>
        value += (body * 0.5 + band_noise * 0.25) *
          @math.exp(-t / (seconds * 0.07))
      Riser => {
        phase += 2.0 * @math.PI * (180.0 + 600.0 * x * x) * pitch / rate
        value = (band_noise * 0.8 + @math.sin(phase) * 0.12) * x * x
      }
      Glitch => {
        let pulse = @math.sin(@math.PI * (x * 7.0 % 1.0))
        phase += 2.0 *
          @math.PI *
          (650.0 + (x * 5.0).floor() * 230.0) *
          pitch /
          rate
        value = (band_noise * 0.7 + @math.sin(phase) * 0.3) *
          pulse *
          pulse *
          (1.0 - x)
      }
      _ => ()
    }
    if voice is Chime || voice is Success || voice is Impact {
      let slot = index % delay.length()
      let reflection = delay[slot]
      delay[slot] = value + reflection * 0.27
      value += reflection * 0.18
    }
    let weight = edge(index, length, fade)
    value *= weight
    samples[index] = Float::from_double(value)
    sum += samples[index].to_double()
    weights += weight
  }
  // Remove DC without introducing nonzero file edges; leave 6 dB of mix headroom.
  let correction = sum / weights
  let mut maximum = 0.0
  for index in 0..<length {
    let value = samples[index].to_double() -
      correction * edge(index, length, fade)
    samples[index] = Float::from_double(value)
    maximum = maximum.max(value.abs())
  }
  let gain = 0.5 / maximum.max(0.0000001)
  for index in 0..<length {
    samples[index] = Float::from_double(
      (samples[index].to_double() * gain * 32768.0).round() / 32768.0,
    )
  }
  let waveform = Array::make(128, 0.0)
  let energies : Array[Double] = []
  let window = sample_rate / 200
  let hop = sample_rate / 1000
  let mut energy = 0.0
  for index in 0..<length {
    let value = samples[index].to_double()
    let bin = (index * waveform.length() / length).min(waveform.length() - 1)
    waveform[bin] = waveform[bin].max(value.abs())
    energy += value * value
    if index >= window {
      let previous = samples[index - window].to_double()
      energy -= previous * previous
    }
    if index >= window - 1 && (index + 1 - window) % hop == 0 {
      energies.push(energy.max(0.0))
    }
  }
  let mut peak_index = 0
  for index in 0..<energies.length() {
    if energies[index] > energies[peak_index] {
      peak_index = index
    }
  }
  let maximum = energies[peak_index]
  let mut first = 0
  let mut last = energies.length() - 1
  while first < peak_index && energies[first] < maximum * 0.001 {
    first += 1
  }
  while last > peak_index && energies[last] < maximum * 0.00001 {
    last -= 1
  }
  Ok({
    samples,
    waveform,
    duration: length.to_double() * 1000.0 / rate,
    onset: (first * hop).to_double() * 1000.0 / rate,
    peak: (peak_index * hop + window / 2).to_double() * 1000.0 / rate,
    end: (last * hop + window).min(length).to_double() * 1000.0 / rate,
  })
}
