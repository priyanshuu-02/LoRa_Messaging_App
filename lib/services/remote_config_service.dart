import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

class RemoteConfigService {
  // IMPORTANT: Replace this with the raw URL of the file in your Git repository.
  // For example, on GitHub, click the file, then click the "Raw" button.
  static const String _configUrl =
      'https://gist.githubusercontent.com/git-theresa/2f2318a7c115e8c15c545f49557a2753/raw/app_enabled.txt';

  /// Checks if the app is remotely enabled.
  ///
  /// Defaults to `false` (blocked) if the check fails, for security.
  Future<bool> isAppEnabled() async {
    try {
      final response = await http.get(Uri.parse(_configUrl));

      if (response.statusCode == 200) {
        // The file content should be exactly "true" or "false".
        final content = response.body.trim().toLowerCase();
        debugPrint("Remote config fetched: '$content'");
        return content == 'true';
      } else {
        debugPrint(
            'Failed to fetch remote config. Status: ${response.statusCode}');
        return false; // Fails closed
      }
    } catch (e) {
      debugPrint('Error fetching remote config: $e');
      return false; // Fails closed
    }
  }
}
