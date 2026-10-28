import 'dart:convert';

import 'package:bugaoshan/providers/app_config_provider.dart';
import 'package:bugaoshan/services/github_resource_service.dart';
import 'package:bugaoshan/services/update_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

Map<String, dynamic> release(String tag, {bool preview = true}) => {
  'tag_name': tag,
  'prerelease': preview,
  'body': 'Notes for $tag',
  'assets': [
    for (final suffix in [
      'windows_x64.zip',
      'linux_x64.tar.gz',
      'universal.apk',
    ])
      {
        'name': 'bugaoshan_${tag}_$suffix',
        'browser_download_url': 'https://example.com/$tag/$suffix',
        'digest': 'sha256:test-checksum',
      },
  ],
};

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late UpdateService service;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    service = UpdateService(
      prefs,
      '2.5.3',
      GithubResourceService(AppConfigProvider(prefs)),
    );
  });

  test(
    'production preview check selects .12 with its own assets and notes',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            for (final number in [9, 8, 12, 11, 10, 6])
              release('v2.5.4-preview.$number'),
          ]),
          200,
        ),
      );
      addTearDown(client.close);
      final latest = await http.runWithClient(
        service.getLatestPrereleaseFromGitHub,
        () => client,
      );
      expect(latest.tagName, 'v2.5.4-preview.12');
      expect(latest.downloadUrl, contains('/v2.5.4-preview.12/'));
      expect(latest.body, 'Notes for v2.5.4-preview.12');
      expect(latest.checksumSha256, 'test-checksum');
    },
  );

  test(
    'developer-page selection uses maximum stable and preview versions',
    () async {
      final client = MockClient(
        (_) async => http.Response(
          jsonEncode([
            release('v2.5.2', preview: false),
            release('v2.5.4-preview.9'),
            release('v2.5.4-preview.12'),
            release('v2.5.3', preview: false),
          ]),
          200,
        ),
      );
      addTearDown(client.close);
      final (stable, preview) = await http.runWithClient(
        service.getAllLatestReleases,
        () => client,
      );
      expect(stable?.tagName, 'v2.5.3');
      expect(preview?.tagName, 'v2.5.4-preview.12');
    },
  );

  test(
    'preview checks reject an older candidate even with the old package version',
    () async {
      final client = MockClient(
        (_) async =>
            http.Response(jsonEncode([release('v2.5.4-preview.9')]), 200),
      );
      addTearDown(client.close);
      final result = await http.runWithClient(
        () => service.checkPreviewUpdate('2.5.3', 'v2.5.4-preview.12'),
        () => client,
      );
      expect(result.noUpdate, isTrue);
    },
  );

  test(
    'uses the stable endpoint when the list contains only previews',
    () async {
      final paths = <String>[];
      final client = MockClient((request) async {
        paths.add(request.url.path);
        return http.Response(
          jsonEncode(
            request.url.path.endsWith('/latest')
                ? release('v2.5.3', preview: false)
                : [release('v2.5.4-preview.12')],
          ),
          200,
        );
      });
      addTearDown(client.close);
      final (stable, preview) = await http.runWithClient(
        service.getAllLatestReleases,
        () => client,
      );
      expect(stable?.tagName, 'v2.5.3');
      expect(preview?.tagName, 'v2.5.4-preview.12');
      expect(paths.last, endsWith('/releases/latest'));
    },
  );
}
