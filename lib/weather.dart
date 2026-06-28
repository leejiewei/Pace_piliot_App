import 'dart:convert';

import 'package:http/http.dart' as http;

import 'models.dart';

// FUNCTION 2 - Live weather for your location.
// Uses the free Open-Meteo API (no API key needed).
class WeatherService {
  Future<WeatherData> fetch(double latitude, double longitude) async {
    final url = Uri.parse('https://api.open-meteo.com/v1/forecast').replace(
      queryParameters: {
        'latitude': latitude.toString(),
        'longitude': longitude.toString(),
        'current':
            'temperature_2m,relative_humidity_2m,wind_speed_10m,precipitation',
        'wind_speed_unit': 'ms',
      },
    );

    final response = await http.get(url);
    if (response.statusCode != 200) {
      throw Exception('Weather request failed: ${response.statusCode}');
    }
    final json = jsonDecode(response.body) as Map<String, Object?>;
    return WeatherData.fromOpenMeteo(json);
  }
}
