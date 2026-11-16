# Changelog

## [0.6.0](https://github.com/jai/agentchatkit/compare/v0.5.0...v0.6.0) (2026-11-16)


### Features

* chatMessageContent takes a claimed message's Copy text and VoiceOver label and can leave out the bubble's menu; ChatWorkingLine adds no second ellipsis ([#20](https://github.com/jai/agentchatkit/issues/20)) ([2c14a03](https://github.com/jai/agentchatkit/commit/2c14a0312d673f45c5eb39214265346f5853666c))
* ChatTheme.controls sets the action buttons' style and the Reply button's words, and symbols.reply its symbol, for a host's own design ([#18](https://github.com/jai/agentchatkit/issues/18)) ([a8f0889](https://github.com/jai/agentchatkit/commit/a8f0889949f8101a6be70bbd5ece8c2120018ef2))
* ReplyQueueController.offersSendNow follows a thread whose reply modes change while open ([#16](https://github.com/jai/agentchatkit/issues/16)), and onEdit hands an edited reply's words to a host's own draft ([#17](https://github.com/jai/agentchatkit/issues/17)) ([53094ac](https://github.com/jai/agentchatkit/commit/53094acdc6fd4e1b9e7d1c1104bc769f1d4d9549))
* Summarize on a long agent reply writes a short summary under its bubble with Apple Intelligence on the device; on by default, a host turns it off with chatSummaries(.off) ([#2](https://github.com/jai/agentchatkit/issues/2)) ([b774162](https://github.com/jai/agentchatkit/commit/b7741629e8c8a427ea93cf8a6873245cd256a0f8))
* ThreadQuestion takes a context role, colour and line limit, a question line limit that leaves the answers alone, and a container identifier ([#15](https://github.com/jai/agentchatkit/issues/15)) ([3afb5ca](https://github.com/jai/agentchatkit/commit/3afb5cac132d73b7523e8daba3d435e8230deb15))
* ThreadQueuedReplies.compact() puts each reply on one line with icon buttons, and maxHeight(_:) scrolls the replies past a limit, for a phone ([#19](https://github.com/jai/agentchatkit/issues/19)) ([6d9d82c](https://github.com/jai/agentchatkit/commit/6d9d82cd758ad82e3854ac14adc8d2c69ef31cd2))

## [0.5.0](https://github.com/jai/agentchatkit/compare/v0.4.2...v0.5.0) (2026-11-16)


### Features

* chatMessageContent lets a host draw the messages it claims inside the kit's bubble (a link card, a meal card); the rest stay Markdown ([#11](https://github.com/jai/agentchatkit/issues/11)) ([49412d3](https://github.com/jai/agentchatkit/commit/49412d373d91da3d26eb6f6947908bcf4469cd74))
* ChatWorkingLine, the agent at work under a chat's messages (a spinner and its activity, identifier chat-working), out of the demo into the kit ([#13](https://github.com/jai/agentchatkit/issues/13)) ([e3b531e](https://github.com/jai/agentchatkit/commit/e3b531efae49249dfadc4f88c99ccf4c1e62af4f))
* each ChatView message is one accessibility element, chat-message-you-/agent-/tool- and its id, for a host's UI tests ([#12](https://github.com/jai/agentchatkit/issues/12)) ([08c9292](https://github.com/jai/agentchatkit/commit/08c9292951e37be7d468211d0acc92aa35d05a18))


### Bug Fixes

* a sent screenshot strip keeps its row while its pictures load, so a chat read at its end does not grow past it and leave the thumbnails under the reply bar; the chat's end marker includes its bottom margin ([#7](https://github.com/jai/agentchatkit/issues/7)) ([d920c96](https://github.com/jai/agentchatkit/commit/d920c9685964d34bbeb424b503aad9424aeaf9fb))

## [0.4.2](https://github.com/jai/agentchatkit/compare/v0.4.1...v0.4.2) (2026-11-16)


### Bug Fixes

* a sent screenshot's thumbnail is a fixed square whose accessibility frame is where it is drawn, and the strip scrolls only when its thumbnails do not fit ([#6](https://github.com/jai/agentchatkit/issues/6)) ([0a9a08d](https://github.com/jai/agentchatkit/commit/0a9a08d72ba442e5b8357e7cdadb51bfe9ec2e74))
