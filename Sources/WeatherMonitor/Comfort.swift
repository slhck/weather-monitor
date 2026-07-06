import Foundation

/// "Feels like" apparent temperature in °C, using the Steadman / Australian
/// Bureau of Meteorology formula, which blends temperature, humidity and wind
/// into one number across the whole range (no switching between a hot-weather
/// and a cold-weather formula):
///
///     AT = T + 0.33·e − 0.70·ws − 4.00
///     e  = (RH / 100) · 6.105 · exp(17.27·T / (237.7 + T))
///
/// where `T` is the dry-bulb temperature (°C), `RH` the relative humidity (%),
/// `ws` the 10 m wind speed (m/s) and `e` the water-vapour pressure (hPa).
///
/// Humidity is required (it drives the vapour pressure); wind is treated as
/// calm (0 m/s) when a station isn't reporting it.
func apparentTemperature(temperature: Double, humidity: Double?, windSpeed: Double?) -> Double? {
    guard let humidity else { return nil }
    let vapourPressure = (humidity / 100) * 6.105 * exp(17.27 * temperature / (237.7 + temperature))
    let wind = windSpeed ?? 0
    return temperature + 0.33 * vapourPressure - 0.70 * wind - 4.00
}

/// A short, plain-English descriptor for how an apparent temperature feels,
/// used to annotate the "feels like" reading (the misery index).
func comfortLabel(apparent: Double) -> String {
    switch apparent {
    case 40...: return "dangerous heat"
    case 35..<40: return "sweltering"
    case 30..<35: return "very hot"
    case 26..<30: return "hot"
    case 20..<26: return "pleasant"
    case 12..<20: return "mild"
    case 5..<12: return "cool"
    case 0..<5: return "cold"
    case -10..<0: return "freezing"
    default: return "frigid"
    }
}
