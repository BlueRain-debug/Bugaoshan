import 'dart:convert';

import 'package:bugaoshan/services/update_checker.dart';
import 'package:bugaoshan/utils/release_version.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

Map<String, dynamic> release(String tag, {bool preview = true}) => {
  'tag_name': tag,
  'prerelease': preview,
};

void main() {
  group('release version precedence', () {
    final ascending = [
      '1.0.0-alpha',
      '1.0.0-alpha.1',
      '1.0.0-alpha.beta',
      '1.0.0-beta',
      '1.0.0-beta.2',
      '1.0.0-beta.11',
      '1.0.0-rc.1',
      '1.0.0',
      '1.0.1',
      '1.1.0',
      '2.0.0',
    ];
    for (int i = 1; i < ascending.length; i++) {
      test('${ascending[i]} is newer than ${ascending[i - 1]}', () {
        expect(checkHasUpdate(ascending[i - 1], ascending[i]), isTrue);
        expect(checkHasUpdate(ascending[i], ascending[i - 1]), isFalse);
      });
    }

    test('supports historical preN and rcN tags', () {
      expect(checkHasUpdate('v2.5.4-pre9', 'v2.5.4-pre12'), isTrue);
      expect(checkHasUpdate('v2.5.4-rc9', 'v2.5.4-rc10'), isTrue);
      expect(checkHasUpdate('v2.5.4-rc10', 'v2.5.4-rc.10'), isFalse);
    });

    test('ignores build metadata and optional v prefix', () {
      expect(
        checkHasUpdate('V2.5.4-preview.12+a', '2.5.4-preview.12+b'),
        isFalse,
      );
      expect(checkHasUpdate('2.5.4+1', 'v2.5.4+2'), isFalse);
    });

    test('compares large numeric identifiers without overflowing', () {
      expect(
        checkHasUpdate(
          '2.5.4-preview.99999999999999999999',
          '2.5.4-preview.100000000000000000000',
        ),
        isTrue,
      );
    });

    test('rejects malformed versions', () {
      for (final value in [
        '',
        'null',
        '2.5',
        '2.5.4.1',
        '02.5.4',
        '2.5.4-preview.01',
        '2.5.4-preview..1',
        '2.5.4+',
        '2.5.4\n',
      ]) {
        expect(ReleaseVersion.tryParse(value), isNull, reason: value);
      }
    });
  });

  group('preview update regressions', () {
    test('preview.9 discovers preview.12', () {
      expect(
        isNewerPrerelease('v2.5.4-preview.12', '2.5.3', 'v2.5.4-preview.9'),
        isTrue,
      );
    });

    test('preview.12 never recommends preview.9', () {
      expect(
        isNewerPrerelease('v2.5.4-preview.9', '2.5.3', 'v2.5.4-preview.12'),
        isFalse,
      );
    });

    test('equal normalized tags do not produce an update', () {
      expect(
        isNewerPrerelease('v2.5.4-preview.12+new', '2.5.3', '2.5.4-preview.12'),
        isFalse,
      );
    });

    test('does not downgrade from a newer preview base version', () {
      expect(
        isNewerPrerelease('v2.5.4-preview.12', '2.5.3', 'v2.5.5-preview'),
        isFalse,
      );
    });

    test('stable builds reject previews of their installed version', () {
      expect(
        isNewerPrerelease('v2.5.4-preview.12', '2.5.4', 'v2.5.4'),
        isFalse,
      );
    });

    test('builds without git metadata still discover a higher preview', () {
      expect(isNewerPrerelease('v2.5.4-preview.12', '2.5.3', 'null'), isTrue);
      expect(isNewerPrerelease('v2.5.3-preview.12', '2.5.3', 'null'), isFalse);
    });

    test('rejects stable or invalid tags in the preview channel', () {
      expect(isNewerPrerelease('v2.5.4', '2.5.3', 'v2.5.3'), isFalse);
      expect(isNewerPrerelease('invalid', '2.5.3', 'v2.5.3'), isFalse);
    });
  });

  group('GitHub release selection', () {
    test('selects .12 from the observed 9/8/12/11/10/6 order', () {
      final releases = [
        for (final number in [9, 8, 12, 11, 10, 6])
          release('v2.5.4-preview.$number'),
      ];
      expect(
        selectLatestGithubRelease(releases, prerelease: true)?['tag_name'],
        'v2.5.4-preview.12',
      );
      expect(
        selectLatestGithubRelease(
          releases.reversed,
          prerelease: true,
        )?['tag_name'],
        'v2.5.4-preview.12',
      );
    });

    test('filters drafts, malformed tags and mismatched channels', () {
      final releases = [
        {...release('v9.0.0-preview'), 'draft': true},
        release('invalid'),
        release('v9.0.0'),
        release('v9.0.0-preview', preview: false),
        release('v2.5.4-preview.12'),
        release('v2.5.2', preview: false),
        release('v2.5.3', preview: false),
        {'prerelease': true},
        null,
      ];
      expect(
        selectLatestGithubRelease(releases, prerelease: true)?['tag_name'],
        'v2.5.4-preview.12',
      );
      expect(
        selectLatestGithubRelease(releases, prerelease: false)?['tag_name'],
        'v2.5.3',
      );
    });

    test('uses default pagination and reads only one page', () async {
      final requests = <Uri>[];
      final client = MockClient((request) async {
        requests.add(request.url);
        return http.Response(
          jsonEncode([
            for (final number in [9, 8, 12, 11, 10, 6])
              release('v2.5.4-preview.$number'),
          ]),
          200,
          headers: {
            'link': '<https://api.github.com/repos/$kGithubRepo/releases'
                '?page=2>; rel="next"',
          },
        );
      });
      addTearDown(client.close);
      expect(
        await fetchLatestPrereleaseFromGithub(client: client),
        '2.5.4-preview.12',
      );
      expect(requests, hasLength(1));
      expect(requests.single.queryParameters, isEmpty);
    });

    test('propagates an API error without scanning more pages', () async {
      int requests = 0;
      final client = MockClient((_) async {
        requests++;
        return http.Response('', 403);
      });
      addTearDown(client.close);
      await expectLater(
        fetchLatestPrereleaseFromGithub(client: client),
        throwsA(
          isA<Exception>().having(
            (e) => e.toString(),
            'message',
            contains('403'),
          ),
        ),
      );
      expect(requests, 1);
    });
  });
}
