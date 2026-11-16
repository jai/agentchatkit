# Changelog

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
