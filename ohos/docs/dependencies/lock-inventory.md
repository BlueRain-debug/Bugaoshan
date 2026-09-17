# Dart 依赖完整锁表

> 由 `python ohos/tool/generate_ohos_dependency_inventory.py` 生成，请勿手工编辑。
> 每个单元格的格式为 `版本 / 来源 / 依赖关系`。Git 来源同时显示锁定提交。

根锁文件共 205 个包，鸿蒙锁文件共 194 个包。
其中 141 项相同、43 项不同、
21 项仅根锁存在、10 项仅鸿蒙锁存在。

| SDK constraint | Root lock | OH lock |
| --- | --- | --- |
| Dart | `>=3.12.0 <4.0.0` | `>=3.11.0 <4.0.0` |
| Flutter | `>=3.44.0` | `>=3.38.0` |

| Package | Root lock | OH lock | Status |
| --- | --- | --- | --- |
| `_fe_analyzer_shared` | `100.0.0` / hosted / transitive | `93.0.0` / hosted / transitive | different |
| `analyzer` | `13.0.0` / hosted / transitive | `10.0.1` / hosted / transitive | different |
| `android_file_picker` | `1.0.0` / hosted / transitive | - | root only |
| `ansicolor` | `2.0.3` / hosted / transitive | `2.0.3` / hosted / transitive | same |
| `archive` | `4.0.9` / hosted / direct main | `4.0.9` / hosted / direct main | same |
| `args` | `2.7.0` / hosted / transitive | `2.7.0` / hosted / transitive | same |
| `asn1lib` | `1.6.5` / hosted / transitive | `1.6.5` / hosted / transitive | same |
| `async` | `2.13.1` / hosted / direct main | `2.13.1` / hosted / direct main | same |
| `boolean_selector` | `2.1.2` / hosted / transitive | `2.1.2` / hosted / transitive | same |
| `build` | `4.0.7` / hosted / transitive | `4.0.7` / hosted / transitive | same |
| `build_config` | `1.3.2` / hosted / transitive | `1.3.2` / hosted / transitive | same |
| `build_daemon` | `4.1.4` / hosted / transitive | `4.1.4` / hosted / transitive | same |
| `build_runner` | `2.15.1` / hosted / direct dev | `2.15.1` / hosted / direct dev | same |
| `built_collection` | `5.1.1` / hosted / transitive | `5.1.1` / hosted / transitive | same |
| `built_value` | `8.12.7` / hosted / transitive | `8.12.7` / hosted / transitive | same |
| `characters` | `1.4.1` / hosted / transitive | `1.4.1` / hosted / transitive | same |
| `checked_yaml` | `2.0.4` / hosted / transitive | `2.0.4` / hosted / transitive | same |
| `cli_util` | `0.4.2` / hosted / transitive | `0.4.2` / hosted / transitive | same |
| `clock` | `1.1.2` / hosted / transitive | `1.1.2` / hosted / transitive | same |
| `code_assets` | `1.2.1` / hosted / transitive | - | root only |
| `code_builder` | `4.11.1` / hosted / transitive | `4.11.1` / hosted / transitive | same |
| `collection` | `1.19.1` / hosted / transitive | `1.19.1` / hosted / transitive | same |
| `convert` | `3.1.2` / hosted / transitive | `3.1.2` / hosted / transitive | same |
| `cross_file` | `0.3.5+4` / hosted / transitive | `0.3.5+4` / hosted / transitive | same |
| `crypto` | `3.0.7` / hosted / direct main | `3.0.7` / hosted / direct main | same |
| `dart_sm` | `0.1.5` / hosted / direct main | `0.1.5` / hosted / direct main | same |
| `dart_style` | `3.1.9` / hosted / transitive | `3.1.7` / hosted / transitive | different |
| `dbus` | `0.7.14` / hosted / transitive | `0.7.14` / hosted / transitive | same |
| `device_info_plus` | `13.2.0` / hosted / direct main | - | root only |
| `device_info_plus_platform_interface` | `8.1.0` / hosted / transitive | - | root only |
| `encrypt` | `5.0.3` / hosted / direct main | `5.0.3` / hosted / direct main | same |
| `equatable` | `2.1.0` / hosted / transitive | `2.1.0` / hosted / transitive | same |
| `fake_async` | `1.3.3` / hosted / direct dev | `1.3.3` / hosted / direct dev | same |
| `ffi` | `2.2.0` / hosted / transitive | `2.2.0` / hosted / transitive | same |
| `ffi_leak_tracker` | `0.1.2` / hosted / transitive | - | root only |
| `file` | `7.0.1` / hosted / transitive | `7.0.1` / hosted / transitive | same |
| `file_picker` | `12.0.0` / hosted / direct main | - | root only |
| `file_picker_darwin` | `1.0.0` / hosted / transitive | - | root only |
| `file_picker_linux` | `1.0.0` / hosted / transitive | - | root only |
| `file_picker_ohos` | - | `10.3.8` / git @ `1a38f43d7c2e976c2add2c057da79223a0913f84` / direct main | OH only |
| `file_picker_platform_interface` | `3.0.0` / hosted / transitive | - | root only |
| `file_picker_web` | `3.0.0` / hosted / transitive | - | root only |
| `file_selector_linux` | `0.9.4` / hosted / transitive | `0.9.4` / hosted / transitive | same |
| `file_selector_macos` | `0.9.5` / hosted / transitive | `0.9.5` / hosted / transitive | same |
| `file_selector_platform_interface` | `2.7.0` / hosted / transitive | `2.7.0` / hosted / transitive | same |
| `file_selector_windows` | `0.9.3+5` / hosted / transitive | `0.9.3+5` / hosted / transitive | same |
| `fixnum` | `1.1.1` / hosted / transitive | `1.1.1` / hosted / transitive | same |
| `fl_chart` | `1.2.0` / hosted / direct main | `1.2.0` / hosted / direct main | same |
| `flutter` | `0.0.0` / sdk / direct main | `0.0.0` / sdk / direct main | same |
| `flutter_app_group_directory` | `1.1.0` / hosted / direct main | `1.1.0` / hosted / direct main | same |
| `flutter_colorpicker` | `1.1.0` / hosted / direct main | `1.1.0` / hosted / direct main | same |
| `flutter_driver` | `0.0.0` / sdk / direct dev | `0.0.0` / sdk / direct dev | same |
| `flutter_inappwebview` | `6.2.0-beta.3` / git @ `666bc33f776285076327e4a94aafc103c693e17a` / direct main | `6.1.5` / git @ `528fa913763148719cde7dae2dc22dc33f15da36` / direct main | different |
| `flutter_inappwebview_android` | `1.2.0-beta.4` / git @ `666bc33f776285076327e4a94aafc103c693e17a` / transitive | `1.1.3` / git @ `528fa913763148719cde7dae2dc22dc33f15da36` / direct overridden | different |
| `flutter_inappwebview_internal_annotations` | `1.3.0` / hosted / transitive | `1.1.1` / git @ `528fa913763148719cde7dae2dc22dc33f15da36` / direct overridden | different |
| `flutter_inappwebview_ios` | `1.2.0-beta.3` / hosted / transitive | `1.1.2` / git @ `528fa913763148719cde7dae2dc22dc33f15da36` / direct overridden | different |
| `flutter_inappwebview_linux` | `0.1.0-beta.1` / hosted / transitive | - | root only |
| `flutter_inappwebview_macos` | `1.2.0-beta.3` / hosted / transitive | `1.1.2` / git @ `528fa913763148719cde7dae2dc22dc33f15da36` / direct overridden | different |
| `flutter_inappwebview_ohos` | - | `1.1.3` / git @ `528fa913763148719cde7dae2dc22dc33f15da36` / direct overridden | OH only |
| `flutter_inappwebview_platform_interface` | `1.4.0-beta.3` / hosted / transitive | `1.3.0+1` / git @ `528fa913763148719cde7dae2dc22dc33f15da36` / direct overridden | different |
| `flutter_inappwebview_web` | `1.2.0-beta.3` / hosted / transitive | `1.1.2` / git @ `528fa913763148719cde7dae2dc22dc33f15da36` / direct overridden | different |
| `flutter_inappwebview_windows` | `0.7.0-beta.4` / git @ `666bc33f776285076327e4a94aafc103c693e17a` / transitive | `0.6.0` / git @ `528fa913763148719cde7dae2dc22dc33f15da36` / direct overridden | different |
| `flutter_launcher_icons` | `0.14.4` / hosted / direct dev | `0.14.4` / hosted / direct dev | same |
| `flutter_lints` | `6.0.0` / hosted / direct dev | `6.0.0` / hosted / direct dev | same |
| `flutter_localizations` | `0.0.0` / sdk / direct main | `0.0.0` / sdk / direct main | same |
| `flutter_markdown_plus` | `1.0.12` / hosted / direct main | `1.0.12` / hosted / direct main | same |
| `flutter_plugin_android_lifecycle` | `2.0.35` / hosted / transitive | `2.0.35` / hosted / transitive | same |
| `flutter_secure_storage` | `10.3.1` / hosted / direct main | `9.2.4` / git @ `ecc4257040163da3c4dd64d4fced5d4d24676a53` / direct main | different |
| `flutter_secure_storage_darwin` | `0.3.2` / hosted / transitive | - | root only |
| `flutter_secure_storage_linux` | `3.0.1` / hosted / transitive | `1.2.3` / hosted / transitive | different |
| `flutter_secure_storage_macos` | - | `3.1.3` / hosted / transitive | OH only |
| `flutter_secure_storage_ohos` | - | `1.2.2` / git @ `ecc4257040163da3c4dd64d4fced5d4d24676a53` / direct main | OH only |
| `flutter_secure_storage_platform_interface` | `2.0.3` / hosted / transitive | `1.1.2` / hosted / transitive | different |
| `flutter_secure_storage_web` | `2.1.1` / hosted / transitive | `1.2.1` / hosted / transitive | different |
| `flutter_secure_storage_windows` | `4.2.2` / hosted / transitive | `3.1.2` / hosted / transitive | different |
| `flutter_test` | `0.0.0` / sdk / direct dev | `0.0.0` / sdk / direct dev | same |
| `flutter_web_plugins` | `0.0.0` / sdk / transitive | `0.0.0` / sdk / transitive | same |
| `frontend_server_client` | `4.0.0` / hosted / transitive | `4.0.0` / hosted / transitive | same |
| `fuchsia_remote_debug_protocol` | `0.0.0` / sdk / transitive | `0.0.0` / sdk / transitive | same |
| `gal` | `2.3.3` / hosted / direct main | - | root only |
| `get_it` | `9.2.1` / hosted / direct main | `9.2.1` / hosted / direct main | same |
| `glob` | `2.1.3` / hosted / transitive | `2.1.3` / hosted / transitive | same |
| `google_fonts` | `8.2.1` / hosted / direct main | `8.2.1` / hosted / direct main | same |
| `graphs` | `2.3.2` / hosted / transitive | `2.3.2` / hosted / transitive | same |
| `hooks` | `2.0.2` / hosted / transitive | - | root only |
| `hotreloader` | `4.4.0` / hosted / transitive | `4.4.0` / hosted / transitive | same |
| `http` | `1.6.0` / hosted / direct main | `1.6.0` / hosted / direct main | same |
| `http_multi_server` | `3.2.2` / hosted / transitive | `3.2.2` / hosted / transitive | same |
| `http_parser` | `4.1.2` / hosted / transitive | `4.1.2` / hosted / transitive | same |
| `image` | `4.8.0` / hosted / transitive | `4.8.0` / hosted / transitive | same |
| `image_gallery_saver_plus` | - | `3.0.5` / git @ `163bd578508fcf99a11e699e2bea8a6140218f93` / direct main | OH only |
| `image_picker` | `1.2.3` / hosted / direct main | `1.2.1` / git @ `1a027ce4c1739b26356fe30556c027bfad47aa94` / direct main | different |
| `image_picker_android` | `0.8.13+19` / hosted / transitive | `0.8.13+17` / hosted / transitive | different |
| `image_picker_for_web` | `3.1.1` / hosted / transitive | `3.1.1` / hosted / transitive | same |
| `image_picker_ios` | `0.8.13+6` / hosted / transitive | `0.8.13+6` / hosted / transitive | same |
| `image_picker_linux` | `0.2.2` / hosted / transitive | `0.2.2` / hosted / transitive | same |
| `image_picker_macos` | `0.2.2+1` / hosted / transitive | `0.2.2+1` / hosted / transitive | same |
| `image_picker_ohos` | - | `0.8.13+7` / git @ `1a027ce4c1739b26356fe30556c027bfad47aa94` / direct overridden | OH only |
| `image_picker_platform_interface` | `2.11.1` / hosted / transitive | `2.11.1` / hosted / transitive | same |
| `image_picker_windows` | `0.2.2` / hosted / transitive | `0.2.2` / hosted / transitive | same |
| `injectable` | `3.0.0` / hosted / direct main | `3.0.0` / hosted / direct main | same |
| `injectable_generator` | `3.1.1` / hosted / direct dev | `3.0.2` / hosted / direct dev | different |
| `intl` | `0.20.2` / hosted / direct main | `0.20.2` / hosted / direct main | same |
| `io` | `1.0.5` / hosted / transitive | `1.0.5` / hosted / transitive | same |
| `jni` | `1.0.3` / hosted / transitive | `1.0.3` / hosted / transitive | same |
| `jni_flutter` | `1.0.2` / hosted / transitive | `1.0.2` / hosted / transitive | same |
| `jni_util` | `1.0.0` / hosted / transitive | `1.0.0` / hosted / transitive | same |
| `js` | `0.7.2` / hosted / transitive | `0.6.7` / hosted / transitive | different |
| `json_annotation` | `4.12.0` / hosted / direct main | `4.12.0` / hosted / direct main | same |
| `json_serializable` | `6.14.1` / hosted / direct dev | `6.14.1` / hosted / direct dev | same |
| `leak_tracker` | `11.0.2` / hosted / transitive | `11.0.2` / hosted / transitive | same |
| `leak_tracker_flutter_testing` | `3.0.10` / hosted / transitive | `3.0.10` / hosted / transitive | same |
| `leak_tracker_testing` | `3.0.2` / hosted / transitive | `3.0.2` / hosted / transitive | same |
| `lean_builder` | `1.2.0` / hosted / transitive | `0.1.10` / hosted / transitive | different |
| `lints` | `6.1.0` / hosted / transitive | `6.1.0` / hosted / transitive | same |
| `logging` | `1.3.0` / hosted / transitive | `1.3.0` / hosted / transitive | same |
| `markdown` | `7.3.1` / hosted / transitive | `7.3.1` / hosted / transitive | same |
| `matcher` | `0.12.19` / hosted / transitive | `0.12.19` / hosted / transitive | same |
| `material_color_utilities` | `0.13.0` / hosted / transitive | `0.13.0` / hosted / transitive | same |
| `meta` | `1.18.0` / hosted / transitive | `1.17.0` / hosted / transitive | different |
| `mime` | `2.0.0` / hosted / transitive | `2.0.0` / hosted / transitive | same |
| `native_toolchain_c` | `0.19.2` / hosted / transitive | - | root only |
| `objective_c` | `9.5.0` / hosted / transitive | - | root only |
| `open_filex` | `4.7.0` / hosted / direct main | `4.7.0` / git @ `850a9abd0220316dc2bb45924315cb2304ff4ab6` / direct main | different |
| `os_type` | `0.2.2` / hosted / direct main | `0.2.2` / hosted / direct main | same |
| `package_config` | `2.2.0` / hosted / transitive | `2.2.0` / hosted / transitive | same |
| `package_info_plus` | `10.2.1` / hosted / direct main | `9.0.0` / git @ `bc4df814a726042a9dad1a267ebb1d2973544e24` / direct main | different |
| `package_info_plus_platform_interface` | `4.1.0` / hosted / transitive | `3.2.1` / hosted / transitive | different |
| `path` | `1.9.1` / hosted / direct main | `1.9.1` / hosted / direct main | same |
| `path_provider` | `2.1.6` / hosted / direct main | `2.1.5` / git @ `7cc9f4cfbd464943096dc7c87288252c543df5cb` / direct main | different |
| `path_provider_android` | `2.3.1` / hosted / transitive | `2.3.1` / hosted / transitive | same |
| `path_provider_foundation` | `2.6.0` / hosted / transitive | `2.5.1` / hosted / transitive | different |
| `path_provider_linux` | `2.2.2` / hosted / transitive | `2.2.2` / hosted / transitive | same |
| `path_provider_ohos` | - | `2.2.17` / git @ `7cc9f4cfbd464943096dc7c87288252c543df5cb` / direct overridden | OH only |
| `path_provider_platform_interface` | `2.1.3` / hosted / transitive | `2.1.3` / hosted / transitive | same |
| `path_provider_windows` | `2.3.0` / hosted / transitive | `2.3.0` / hosted / transitive | same |
| `petitparser` | `7.0.2` / hosted / transitive | `7.0.2` / hosted / transitive | same |
| `photo_view` | `0.15.0` / hosted / direct main | `0.15.0` / hosted / direct main | same |
| `platform` | `3.1.6` / hosted / transitive | `3.1.6` / hosted / transitive | same |
| `plugin_platform_interface` | `2.1.8` / hosted / transitive | `2.1.8` / hosted / transitive | same |
| `pointycastle` | `3.9.1` / hosted / transitive | `3.9.1` / hosted / transitive | same |
| `pool` | `1.5.2` / hosted / transitive | `1.5.2` / hosted / transitive | same |
| `posix` | `6.5.2` / hosted / transitive | `6.5.2` / hosted / transitive | same |
| `process` | `5.0.5` / hosted / transitive | `5.0.5` / hosted / transitive | same |
| `pub_semver` | `2.2.0` / hosted / transitive | `2.2.0` / hosted / transitive | same |
| `pubspec_parse` | `1.5.0` / hosted / transitive | `1.5.0` / hosted / transitive | same |
| `recase` | `4.1.0` / hosted / transitive | `4.1.0` / hosted / transitive | same |
| `record_use` | `0.6.0` / hosted / transitive | - | root only |
| `screen_retriever` | `0.2.2` / hosted / direct main | - | root only |
| `screen_retriever_linux` | `0.2.2` / hosted / transitive | - | root only |
| `screen_retriever_macos` | `0.2.2` / hosted / transitive | - | root only |
| `screen_retriever_platform_interface` | `0.2.2` / hosted / transitive | - | root only |
| `screen_retriever_windows` | `0.2.2` / hosted / transitive | - | root only |
| `scu_ocr_lite` | `2.0.0` / git @ `6fa09e88676505e2e55376456c1b7716f07a6112` / direct main | `2.0.0` / git @ `6fa09e88676505e2e55376456c1b7716f07a6112` / direct main | same |
| `share_plus` | `13.3.0` / hosted / direct main | `12.0.1` / git @ `bfd882da6893c4c8bfa1648ac637c2d557e6f4fa` / direct main | different |
| `share_plus_platform_interface` | `7.2.0` / hosted / transitive | `6.1.0` / git @ `bfd882da6893c4c8bfa1648ac637c2d557e6f4fa` / direct overridden | different |
| `shared_preferences` | `2.5.5` / hosted / direct main | `2.5.4` / git @ `19bd50ff6d5eaa96f18c63796c51e1b4e78a7480` / direct main | different |
| `shared_preferences_android` | `2.4.27` / hosted / transitive | `2.4.23` / hosted / transitive | different |
| `shared_preferences_foundation` | `2.5.6` / hosted / transitive | `2.5.6` / hosted / transitive | same |
| `shared_preferences_linux` | `2.4.1` / hosted / transitive | `2.4.1` / hosted / transitive | same |
| `shared_preferences_ohos` | - | `2.5.4` / git @ `19bd50ff6d5eaa96f18c63796c51e1b4e78a7480` / direct overridden | OH only |
| `shared_preferences_platform_interface` | `2.4.2` / hosted / transitive | `2.4.2` / hosted / transitive | same |
| `shared_preferences_web` | `2.4.3` / hosted / transitive | `2.4.3` / hosted / transitive | same |
| `shared_preferences_windows` | `2.4.1` / hosted / transitive | `2.4.1` / hosted / transitive | same |
| `shelf` | `1.4.2` / hosted / transitive | `1.4.2` / hosted / transitive | same |
| `shelf_web_socket` | `3.0.0` / hosted / transitive | `3.0.0` / hosted / transitive | same |
| `sky_engine` | `0.0.0` / sdk / transitive | `0.0.0` / sdk / transitive | same |
| `source_gen` | `4.2.4` / hosted / transitive | `4.2.4` / hosted / transitive | same |
| `source_helper` | `1.3.13` / hosted / transitive | `1.3.13` / hosted / transitive | same |
| `source_span` | `1.10.2` / hosted / transitive | `1.10.2` / hosted / transitive | same |
| `sqflite` | `2.4.3` / hosted / direct main | `2.4.2` / git @ `5ef0761001378455e872e46d1c0620d39dcc1002` / direct main | different |
| `sqflite_android` | `2.4.3` / hosted / transitive | `2.4.2+3` / hosted / transitive | different |
| `sqflite_common` | `2.5.11` / hosted / transitive | `2.5.8` / hosted / transitive | different |
| `sqflite_common_ffi` | `2.4.2` / hosted / direct main | - | root only |
| `sqflite_darwin` | `2.4.3+1` / hosted / transitive | `2.4.2` / hosted / transitive | different |
| `sqflite_ohos` | - | `2.4.2` / git @ `5ef0761001378455e872e46d1c0620d39dcc1002` / direct overridden | OH only |
| `sqflite_platform_interface` | `2.4.1` / hosted / transitive | `2.4.0` / hosted / transitive | different |
| `sqlite3` | `3.5.1` / hosted / transitive | - | root only |
| `stack_trace` | `1.12.1` / hosted / transitive | `1.12.1` / hosted / transitive | same |
| `stream_channel` | `2.1.4` / hosted / transitive | `2.1.4` / hosted / transitive | same |
| `stream_transform` | `2.1.1` / hosted / transitive | `2.1.1` / hosted / transitive | same |
| `string_scanner` | `1.4.1` / hosted / transitive | `1.4.1` / hosted / transitive | same |
| `sync_http` | `0.3.1` / hosted / transitive | `0.3.1` / hosted / transitive | same |
| `synchronized` | `3.4.1+1` / hosted / transitive | `3.4.0+1` / hosted / transitive | different |
| `system_theme` | `3.3.0` / hosted / direct main | `3.2.0` / hosted / direct main | different |
| `system_theme_web` | `0.0.5` / hosted / transitive | `0.0.5` / hosted / transitive | same |
| `term_glyph` | `1.2.2` / hosted / transitive | `1.2.2` / hosted / transitive | same |
| `test_api` | `0.7.11` / hosted / transitive | `0.7.10` / hosted / transitive | different |
| `tyme` | `1.5.0` / hosted / direct main | `1.5.0` / hosted / direct main | same |
| `typed_data` | `1.4.0` / hosted / transitive | `1.4.0` / hosted / transitive | same |
| `url_launcher` | `6.3.2` / hosted / direct main | `6.3.2` / git @ `f31db0d72e7a1d91dd023325a23dc2fba4b6ce4b` / direct main | different |
| `url_launcher_android` | `6.3.32` / hosted / transitive | `6.3.30` / hosted / transitive | different |
| `url_launcher_ios` | `6.4.1` / hosted / transitive | `6.4.1` / hosted / transitive | same |
| `url_launcher_linux` | `3.2.2` / hosted / transitive | `3.2.2` / hosted / transitive | same |
| `url_launcher_macos` | `3.2.5` / hosted / transitive | `3.2.5` / hosted / transitive | same |
| `url_launcher_ohos` | - | `6.3.2` / git @ `f31db0d72e7a1d91dd023325a23dc2fba4b6ce4b` / direct overridden | OH only |
| `url_launcher_platform_interface` | `2.3.2` / hosted / transitive | `2.3.2` / hosted / transitive | same |
| `url_launcher_web` | `2.4.3` / hosted / transitive | `2.4.3` / hosted / transitive | same |
| `url_launcher_windows` | `3.1.5` / hosted / transitive | `3.1.5` / hosted / transitive | same |
| `uuid` | `4.6.0` / hosted / transitive | `4.6.0` / hosted / transitive | same |
| `vector_math` | `2.2.0` / hosted / transitive | `2.2.0` / hosted / transitive | same |
| `vm_service` | `15.2.0` / hosted / transitive | `15.2.0` / hosted / transitive | same |
| `watcher` | `1.2.1` / hosted / transitive | `1.2.1` / hosted / transitive | same |
| `web` | `1.1.1` / hosted / transitive | `1.1.1` / hosted / transitive | same |
| `web_socket` | `1.0.1` / hosted / transitive | `1.0.1` / hosted / transitive | same |
| `web_socket_channel` | `3.0.3` / hosted / transitive | `3.0.3` / hosted / transitive | same |
| `webdriver` | `3.1.0` / hosted / transitive | `3.1.0` / hosted / transitive | same |
| `win32` | `6.4.0` / hosted / transitive | `5.15.0` / hosted / transitive | different |
| `win32_registry` | `3.0.3` / hosted / transitive | - | root only |
| `window_manager` | `0.5.2` / hosted / direct main | - | root only |
| `windows_file_picker` | `1.0.0` / hosted / transitive | - | root only |
| `xdg_directories` | `1.1.0` / hosted / transitive | `1.1.0` / hosted / transitive | same |
| `xml` | `6.6.1` / hosted / transitive | `6.6.1` / hosted / transitive | same |
| `xxh3` | `1.2.0` / hosted / transitive | `1.2.0` / hosted / transitive | same |
| `yaml` | `3.1.3` / hosted / transitive | `3.1.3` / hosted / transitive | same |
