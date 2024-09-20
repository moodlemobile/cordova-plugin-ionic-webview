<!--
# license: Licensed to the Apache Software Foundation (ASF) under one
#         or more contributor license agreements.  See the NOTICE file
#         distributed with this work for additional information
#         regarding copyright ownership.  The ASF licenses this file
#         to you under the Apache License, Version 2.0 (the
#         "License"); you may not use this file except in compliance
#         with the License.  You may obtain a copy of the License at
#
#           http://www.apache.org/licenses/LICENSE-2.0
#
#         Unless required by applicable law or agreed to in writing,
#         software distributed under the License is distributed on an
#         "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY
#         KIND, either express or implied.  See the License for the
#         specific language governing permissions and limitations
#         under the License.
-->

<!-- TODO: remove beta in README.md and CONTRIBUTING.md -->

# Ionic Web View for Cordova (fork)

This is a fork of `cordova-plugin-ionic-webview` by [Moodle HQ](https://moodle.com/). If you are looking for the documentation, you can read the original at [ionic-team/cordova-plugin-ionic-webview](https://github.com/ionic-team/cordova-plugin-ionic-webview).

## Modifications from the original

We created this fork because we needed to include the following modifications in [our mobile application](https://github.com/moodlehq/moodleapp):

| PR | Description |
| -- | ----------- |
| [#651](https://github.com/ionic-team/cordova-plugin-ionic-webview/pull/651) | allow enabling fullscreen functions |
| [#677](https://github.com/ionic-team/cordova-plugin-ionic-webview/pull/677) | Webkit ios 16.4 enable inspection   |
| - | Use unique instances for request headers to fix media (extracted from [this capacitor PR](https://github.com/ionic-team/capacitor/pull/5956))  |
| - | Only allow enabling fullscreen in iOS 17+  |
| [#692](https://github.com/ionic-team/cordova-plugin-ionic-webview/pull/692) | Support Range requests for reading local files (iOS) |

## Installation

You can install this package using the original installation instructions, but installing this package instead:

```sh
cordova plugin add @moodlehq/cordova-plugin-ionic-webview@5.0.0-moodle.5
```
