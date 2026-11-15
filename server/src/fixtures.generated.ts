// Written by scripts/embed-fixtures.mjs from protocol/fixtures. Do not edit: run `npm run fixtures`.
export const fixtures: Record<string, unknown> = {
  "display-order": {
    "about": "By `at`, not arrival: a2 (:08) arrives after u2 (:10) and goes before it. t9 has no `at`: it sorts at the `at` of the message before it when first taken. Equal `at` keeps the order taken.",
    "client": {
      "start": {
        "cursor": "c:1",
        "messages": [
          {
            "sessionUpdate": "user_message",
            "messageId": "m1",
            "content": [
              {
                "type": "text",
                "text": "Why is the build red?"
              }
            ],
            "_meta": {
              "agentchatkit": {
                "at": "2026-11-15T05:00:00.000Z",
                "sender": {
                  "login": "jai",
                  "name": "Jai"
                },
                "status": "delivered",
                "clientRef": "ref-1"
              }
            }
          }
        ],
        "state": null
      },
      "messages": [
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u2",
              "content": [
                {
                  "type": "text",
                  "text": "Also check the iPad."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:10.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "pending",
                  "clientRef": "ref-u2"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:2"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "agent_message",
              "messageId": "a2",
              "content": [
                {
                  "type": "text",
                  "text": "The iPhone run is green."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:08.000Z"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:3"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "tool_call_update",
              "toolCallId": "t9",
              "title": "xcodebuild test",
              "name": "Bash",
              "kind": "execute",
              "status": "completed",
              "_meta": {
                "agentchatkit": {
                  "at": null
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:4"
              }
            }
          }
        }
      ],
      "expect": {
        "cursor": "c:4",
        "messages": [
          {
            "id": "m1",
            "kind": "user",
            "text": "Why is the build red?",
            "status": "delivered"
          },
          {
            "id": "a2",
            "kind": "agent",
            "text": "The iPhone run is green.",
            "status": null
          },
          {
            "id": "u2",
            "kind": "user",
            "text": "Also check the iPad.",
            "status": "pending"
          },
          {
            "id": "t9",
            "kind": "tool",
            "text": "xcodebuild test",
            "status": null
          }
        ],
        "state": null,
        "question": null
      }
    }
  },
  "messages": {
    "about": "Each JSON-RPC message the profile uses, with our _meta. Both sides decode and encode every one.",
    "client_to_host": [
      {
        "name": "initialize",
        "message": {
          "jsonrpc": "2.0",
          "id": 1,
          "method": "initialize",
          "params": {
            "protocolVersion": 2,
            "clientCapabilities": {
              "elicitation": {
                "form": {}
              }
            },
            "clientInfo": {
              "name": "AgentChatLive",
              "version": "0.3.0"
            }
          }
        }
      },
      {
        "name": "resume from start",
        "message": {
          "jsonrpc": "2.0",
          "id": 2,
          "method": "session/resume",
          "params": {
            "sessionId": "chat-1",
            "cwd": "/",
            "replayFrom": {
              "type": "start"
            }
          }
        }
      },
      {
        "name": "resume from a cursor",
        "message": {
          "jsonrpc": "2.0",
          "id": 3,
          "method": "session/resume",
          "params": {
            "sessionId": "chat-1",
            "cwd": "/",
            "replayFrom": {
              "type": "_cursor",
              "cursor": "c:2"
            }
          }
        }
      },
      {
        "name": "prompt",
        "message": {
          "jsonrpc": "2.0",
          "id": 4,
          "method": "session/prompt",
          "params": {
            "sessionId": "chat-1",
            "prompt": [
              {
                "type": "text",
                "text": "Merge it."
              },
              {
                "type": "image",
                "mimeType": "image/jpeg",
                "data": "/9j/4AAQ"
              }
            ],
            "_meta": {
              "agentchatkit": {
                "clientRef": "ref-7",
                "force": false
              }
            }
          }
        }
      },
      {
        "name": "edit",
        "message": {
          "jsonrpc": "2.0",
          "id": 5,
          "method": "_agentchatkit/edit",
          "params": {
            "sessionId": "chat-1",
            "messageId": "u7",
            "prompt": [
              {
                "type": "text",
                "text": "Merge it, then tag."
              }
            ]
          }
        }
      },
      {
        "name": "send now",
        "message": {
          "jsonrpc": "2.0",
          "id": 7,
          "method": "_agentchatkit/edit",
          "params": {
            "sessionId": "chat-1",
            "messageId": "u7",
            "force": true
          }
        }
      },
      {
        "name": "remove",
        "message": {
          "jsonrpc": "2.0",
          "id": 6,
          "method": "_agentchatkit/remove",
          "params": {
            "sessionId": "chat-1",
            "messageId": "u8"
          }
        }
      },
      {
        "name": "answer",
        "message": {
          "jsonrpc": "2.0",
          "id": 900,
          "result": {
            "action": "accept",
            "content": {
              "choice": "merge",
              "text": "and tag it"
            }
          }
        }
      }
    ],
    "host_to_client": [
      {
        "name": "initialized",
        "message": {
          "jsonrpc": "2.0",
          "id": 1,
          "result": {
            "protocolVersion": 2,
            "agentCapabilities": {
              "loadSession": true
            },
            "agentInfo": {
              "name": "agentchat-live",
              "version": "0.3.0"
            }
          }
        }
      },
      {
        "name": "user message",
        "message": {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "m1",
              "content": [
                {
                  "type": "text",
                  "text": "Why is the build red?"
                },
                {
                  "type": "resource_link",
                  "name": "screenshot.jpg",
                  "uri": "acp/attachments/a1?sig=abc",
                  "mimeType": "image/jpeg",
                  "size": 412803,
                  "_meta": {
                    "agentchatkit": {
                      "width": 1179,
                      "height": 2556,
                      "durationMs": null
                    }
                  }
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:00.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "delivered",
                  "clientRef": "ref-1"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:1"
              }
            }
          }
        }
      },
      {
        "name": "state",
        "message": {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "state_update",
              "state": "running",
              "_meta": {
                "agentchatkit": {
                  "activity": "Reading the CI log",
                  "problem": null
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:2"
              }
            }
          }
        }
      },
      {
        "name": "agent message",
        "message": {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "agent_message",
              "messageId": "m3",
              "content": [
                {
                  "type": "text",
                  "text": "A test times out on the simulator."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:05.000Z"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:3"
              }
            }
          }
        }
      },
      {
        "name": "agent message chunk",
        "message": {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "agent_message_chunk",
              "messageId": "m9",
              "content": {
                "type": "text",
                "text": "Looking at"
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:4"
              }
            }
          }
        }
      },
      {
        "name": "tool call",
        "message": {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "tool_call_update",
              "toolCallId": "t4",
              "title": "swift test",
              "name": "Bash",
              "kind": "execute",
              "status": "completed",
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:06.000Z"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:5"
              }
            }
          }
        }
      },
      {
        "name": "model and reasoning",
        "message": {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "config_option_update",
              "configOptions": [
                {
                  "id": "model",
                  "name": "Model",
                  "type": "select",
                  "currentValue": "claude-opus-5-5",
                  "options": [
                    {
                      "value": "claude-opus-5-5",
                      "name": "Claude Opus 5.5"
                    }
                  ]
                }
              ]
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:6"
              }
            }
          }
        }
      },
      {
        "name": "question",
        "message": {
          "jsonrpc": "2.0",
          "id": 900,
          "method": "elicitation/create",
          "params": {
            "sessionId": "chat-1",
            "mode": "form",
            "message": "Merge now or wait for review?",
            "requestedSchema": {
              "type": "object",
              "properties": {
                "choice": {
                  "type": "string",
                  "enum": [
                    "merge",
                    "wait"
                  ],
                  "enumNames": [
                    "Merge now",
                    "Wait for review"
                  ]
                },
                "text": {
                  "type": "string",
                  "description": "Anything to add"
                }
              }
            }
          }
        }
      },
      {
        "name": "prompt taken",
        "message": {
          "jsonrpc": "2.0",
          "id": 4,
          "result": {
            "messageId": "u7"
          }
        }
      },
      {
        "name": "cursor expired",
        "message": {
          "jsonrpc": "2.0",
          "id": 3,
          "error": {
            "code": -32602,
            "message": "cursor expired"
          }
        }
      },
      {
        "name": "not queued any more",
        "message": {
          "jsonrpc": "2.0",
          "id": 5,
          "error": {
            "code": -32009,
            "message": "conflict"
          }
        }
      },
      {
        "name": "question taken elsewhere",
        "message": {
          "jsonrpc": "2.0",
          "method": "$/cancel_request",
          "params": {
            "requestId": 900
          }
        }
      }
    ]
  },
  "prompt-lifecycle": {
    "about": "Prompts sent while the agent works: inserted at once as queued, edited, then forced (send it now: queued becomes pending), delivered; another removed. A repeat clientRef answers the first messageId and adds nothing. A removed message stays held (its status is known) but has no bubble. A message that failed (the host says so: a `host` step) is retried with edit {force: true}: failed becomes pending, same id and clientRef; it can also be removed.",
    "server": {
      "before": [
        {
          "sessionUpdate": "user_message",
          "messageId": "m1",
          "content": [
            {
              "type": "text",
              "text": "Why is the build red?"
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:00.000Z",
              "sender": {
                "login": "jai",
                "name": "Jai"
              },
              "status": "delivered",
              "clientRef": "ref-1"
            }
          }
        },
        {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Running tests",
              "problem": null
            }
          }
        }
      ],
      "resume": "@2",
      "writes": [
        {
          "request": {
            "method": "session/prompt",
            "params": {
              "sessionId": "chat-1",
              "prompt": [
                {
                  "type": "text",
                  "text": "Merge it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "clientRef": "ref-7",
                  "force": false
                }
              }
            }
          },
          "result": {
            "messageId": "@u7"
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u7",
              "content": [
                {
                  "type": "text",
                  "text": "Merge it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:10.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "queued",
                  "clientRef": "ref-7"
                }
              }
            }
          ]
        },
        {
          "request": {
            "method": "session/prompt",
            "params": {
              "sessionId": "chat-1",
              "prompt": [
                {
                  "type": "text",
                  "text": "Merge it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "clientRef": "ref-7",
                  "force": false
                }
              }
            }
          },
          "result": {
            "messageId": "@u7"
          },
          "stream": []
        },
        {
          "request": {
            "method": "_agentchatkit/edit",
            "params": {
              "sessionId": "chat-1",
              "messageId": "@u7",
              "prompt": [
                {
                  "type": "text",
                  "text": "Merge it, then tag."
                }
              ]
            }
          },
          "result": {
            "messageId": "@u7"
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u7",
              "content": [
                {
                  "type": "text",
                  "text": "Merge it, then tag."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:10.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "queued",
                  "clientRef": "ref-7"
                }
              }
            }
          ]
        },
        {
          "request": {
            "method": "_agentchatkit/edit",
            "params": {
              "sessionId": "chat-1",
              "messageId": "@u7",
              "force": true
            }
          },
          "result": {
            "messageId": "@u7"
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u7",
              "content": [
                {
                  "type": "text",
                  "text": "Merge it, then tag."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:10.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "pending",
                  "clientRef": "ref-7"
                }
              }
            }
          ]
        },
        {
          "request": {
            "method": "session/prompt",
            "params": {
              "sessionId": "chat-1",
              "prompt": [
                {
                  "type": "text",
                  "text": "Never mind."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "clientRef": "ref-8",
                  "force": false
                }
              }
            }
          },
          "result": {
            "messageId": "@u8"
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u8",
              "content": [
                {
                  "type": "text",
                  "text": "Never mind."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:11.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "queued",
                  "clientRef": "ref-8"
                }
              }
            }
          ]
        },
        {
          "request": {
            "method": "_agentchatkit/remove",
            "params": {
              "sessionId": "chat-1",
              "messageId": "@u8"
            }
          },
          "result": {
            "messageId": "@u8"
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u8",
              "content": [
                {
                  "type": "text",
                  "text": "Never mind."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:11.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "removed",
                  "clientRef": "ref-8"
                }
              }
            }
          ]
        },
        {
          "request": {
            "method": "_agentchatkit/remove",
            "params": {
              "sessionId": "chat-1",
              "messageId": "@u8"
            }
          },
          "error": -32009,
          "stream": []
        },
        {
          "request": {
            "method": "session/prompt",
            "params": {
              "sessionId": "chat-1",
              "prompt": [
                {
                  "type": "text",
                  "text": "Tag it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "clientRef": "ref-9",
                  "force": true
                }
              }
            }
          },
          "result": {
            "messageId": "@u9"
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u9",
              "content": [
                {
                  "type": "text",
                  "text": "Tag it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:12.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "pending",
                  "clientRef": "ref-9"
                }
              }
            }
          ]
        },
        {
          "host": {
            "sessionUpdate": "user_message",
            "messageId": "@u9",
            "_meta": {
              "agentchatkit": {
                "status": "failed",
                "detail": "The builder stopped while passing this on."
              }
            }
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u9",
              "_meta": {
                "agentchatkit": {
                  "status": "failed",
                  "detail": "The builder stopped while passing this on."
                }
              }
            }
          ]
        },
        {
          "request": {
            "method": "_agentchatkit/edit",
            "params": {
              "sessionId": "chat-1",
              "messageId": "@u9",
              "force": true
            }
          },
          "retry": true,
          "result": {
            "messageId": "@u9"
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u9",
              "content": [
                {
                  "type": "text",
                  "text": "Tag it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:12.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "pending",
                  "clientRef": "ref-9"
                }
              }
            }
          ]
        },
        {
          "host": {
            "sessionUpdate": "user_message",
            "messageId": "@u9",
            "_meta": {
              "agentchatkit": {
                "status": "failed",
                "detail": "The builder stopped while passing this on."
              }
            }
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u9",
              "_meta": {
                "agentchatkit": {
                  "status": "failed",
                  "detail": "The builder stopped while passing this on."
                }
              }
            }
          ]
        },
        {
          "request": {
            "method": "_agentchatkit/remove",
            "params": {
              "sessionId": "chat-1",
              "messageId": "@u9"
            }
          },
          "result": {
            "messageId": "@u9"
          },
          "stream": [
            {
              "sessionUpdate": "user_message",
              "messageId": "u9",
              "content": [
                {
                  "type": "text",
                  "text": "Tag it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:12.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "removed",
                  "clientRef": "ref-9",
                  "detail": "The builder stopped while passing this on."
                }
              }
            }
          ]
        }
      ]
    },
    "client": {
      "start": {
        "cursor": "c:2",
        "messages": [
          {
            "sessionUpdate": "user_message",
            "messageId": "m1",
            "content": [
              {
                "type": "text",
                "text": "Why is the build red?"
              }
            ],
            "_meta": {
              "agentchatkit": {
                "at": "2026-11-15T05:00:00.000Z",
                "sender": {
                  "login": "jai",
                  "name": "Jai"
                },
                "status": "delivered",
                "clientRef": "ref-1"
              }
            }
          }
        ],
        "state": null
      },
      "messages": [
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u7",
              "content": [
                {
                  "type": "text",
                  "text": "Merge it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:10.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "queued",
                  "clientRef": "ref-7"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:3"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u7",
              "content": [
                {
                  "type": "text",
                  "text": "Merge it, then tag."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:10.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "queued",
                  "clientRef": "ref-7"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:4"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u7",
              "content": [
                {
                  "type": "text",
                  "text": "Merge it, then tag."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:10.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "pending",
                  "clientRef": "ref-7"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:5"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u7",
              "content": [
                {
                  "type": "text",
                  "text": "Merge it, then tag."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:10.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "delivering",
                  "clientRef": "ref-7"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:6"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u7",
              "content": [
                {
                  "type": "text",
                  "text": "Merge it, then tag."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:10.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "delivered",
                  "clientRef": "ref-7"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:7"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u8",
              "content": [
                {
                  "type": "text",
                  "text": "Never mind."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:11.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "queued",
                  "clientRef": "ref-8"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:8"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u8",
              "content": [
                {
                  "type": "text",
                  "text": "Never mind."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:11.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "removed",
                  "clientRef": "ref-8"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:9"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u9",
              "content": [
                {
                  "type": "text",
                  "text": "Tag it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:12.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "pending",
                  "clientRef": "ref-9"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:10"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u9",
              "content": [
                {
                  "type": "text",
                  "text": "Tag it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:12.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "failed",
                  "clientRef": "ref-9",
                  "detail": "The builder stopped while passing this on."
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:11"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u9",
              "content": [
                {
                  "type": "text",
                  "text": "Tag it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:12.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "pending",
                  "clientRef": "ref-9"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:12"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u9",
              "content": [
                {
                  "type": "text",
                  "text": "Tag it."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:12.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "delivered",
                  "clientRef": "ref-9"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:13"
              }
            }
          }
        }
      ],
      "expect": {
        "cursor": "c:13",
        "messages": [
          {
            "id": "m1",
            "kind": "user",
            "text": "Why is the build red?",
            "status": "delivered"
          },
          {
            "id": "u7",
            "kind": "user",
            "text": "Merge it, then tag.",
            "status": "delivered"
          },
          {
            "id": "u8",
            "kind": "user",
            "text": "Never mind.",
            "status": "removed"
          },
          {
            "id": "u9",
            "kind": "user",
            "text": "Tag it.",
            "status": "delivered"
          }
        ],
        "state": null,
        "question": null
      },
      "bubbles": [
        "m1",
        "u7",
        "u9"
      ],
      "ticks": {
        "u7": 2,
        "u9": 2
      }
    }
  },
  "question": {
    "about": "The agent asks. Both clients get elicitation/create and the state turns requires_action. Client A answers; the host cancels the request on client B, shows the answer as a user message, and moves on.",
    "server": {
      "before": [
        {
          "sessionUpdate": "user_message",
          "messageId": "m1",
          "content": [
            {
              "type": "text",
              "text": "Why is the build red?"
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:00.000Z",
              "sender": {
                "login": "jai",
                "name": "Jai"
              },
              "status": "delivered",
              "clientRef": "ref-1"
            }
          }
        },
        {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Checking CI",
              "problem": null
            }
          }
        }
      ],
      "clients": 2,
      "ask": {
        "sessionId": "chat-1",
        "mode": "form",
        "message": "Merge now or wait for review?",
        "requestedSchema": {
          "type": "object",
          "properties": {
            "choice": {
              "type": "string",
              "enum": [
                "merge",
                "wait"
              ],
              "enumNames": [
                "Merge now",
                "Wait for review"
              ]
            },
            "text": {
              "type": "string",
              "description": "Anything to add"
            }
          }
        }
      },
      "stream_both": [
        "elicitation/create",
        {
          "sessionUpdate": "state_update",
          "state": "requires_action",
          "_meta": {
            "agentchatkit": {
              "activity": null,
              "problem": null
            }
          }
        }
      ],
      "answer_from": 0,
      "answer": {
        "action": "accept",
        "content": {
          "choice": "merge",
          "text": "and tag it"
        }
      },
      "to_other": "$/cancel_request",
      "then": [
        {
          "sessionUpdate": "user_message",
          "messageId": "u12",
          "content": [
            {
              "type": "text",
              "text": "Merge now: and tag it"
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:42.000Z",
              "sender": {
                "login": "jai",
                "name": "Jai"
              },
              "status": "pending"
            }
          }
        },
        {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Merging",
              "problem": null
            }
          }
        }
      ]
    },
    "client": {
      "start": {
        "cursor": "c:2",
        "messages": [
          {
            "sessionUpdate": "user_message",
            "messageId": "m1",
            "content": [
              {
                "type": "text",
                "text": "Why is the build red?"
              }
            ],
            "_meta": {
              "agentchatkit": {
                "at": "2026-11-15T05:00:00.000Z",
                "sender": {
                  "login": "jai",
                  "name": "Jai"
                },
                "status": "delivered",
                "clientRef": "ref-1"
              }
            }
          }
        ],
        "state": null
      },
      "messages": [
        {
          "jsonrpc": "2.0",
          "id": 900,
          "method": "elicitation/create",
          "params": {
            "sessionId": "chat-1",
            "mode": "form",
            "message": "Merge now or wait for review?",
            "requestedSchema": {
              "type": "object",
              "properties": {
                "choice": {
                  "type": "string",
                  "enum": [
                    "merge",
                    "wait"
                  ],
                  "enumNames": [
                    "Merge now",
                    "Wait for review"
                  ]
                },
                "text": {
                  "type": "string",
                  "description": "Anything to add"
                }
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "state_update",
              "state": "requires_action",
              "_meta": {
                "agentchatkit": {
                  "activity": null,
                  "problem": null
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:3"
              }
            }
          }
        }
      ],
      "expect": {
        "cursor": "c:3",
        "messages": [
          {
            "id": "m1",
            "kind": "user",
            "text": "Why is the build red?",
            "status": "delivered"
          }
        ],
        "state": {
          "state": "requires_action",
          "activity": null
        },
        "question": 900
      },
      "then": [
        {
          "jsonrpc": "2.0",
          "method": "$/cancel_request",
          "params": {
            "requestId": 900
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "u12",
              "content": [
                {
                  "type": "text",
                  "text": "Merge now: and tag it"
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:42.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "pending"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:4"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "state_update",
              "state": "running",
              "_meta": {
                "agentchatkit": {
                  "activity": "Merging",
                  "problem": null
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:5"
              }
            }
          }
        }
      ],
      "expect_then": {
        "cursor": "c:5",
        "messages": [
          {
            "id": "m1",
            "kind": "user",
            "text": "Why is the build red?",
            "status": "delivered"
          },
          {
            "id": "u12",
            "kind": "user",
            "text": "Merge now: and tag it",
            "status": "pending"
          }
        ],
        "state": {
          "state": "running",
          "activity": "Merging"
        },
        "question": null
      }
    }
  },
  "resume-cursor": {
    "about": "Resume from the cursor after update 2: only what came after it, the current state, then live updates.",
    "server": {
      "before": [
        {
          "sessionUpdate": "user_message",
          "messageId": "m1",
          "content": [
            {
              "type": "text",
              "text": "Why is the build red?"
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:00.000Z",
              "sender": {
                "login": "jai",
                "name": "Jai"
              },
              "status": "delivered",
              "clientRef": "ref-1"
            }
          }
        },
        {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Reading the CI log",
              "problem": null
            }
          }
        },
        {
          "sessionUpdate": "agent_message",
          "messageId": "m3",
          "content": [
            {
              "type": "text",
              "text": "A test times out on the simulator."
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:05.000Z"
            }
          }
        }
      ],
      "resume": "@2",
      "during": [
        {
          "sessionUpdate": "agent_message",
          "messageId": "m5",
          "content": [
            {
              "type": "text",
              "text": "I raised the timeout to 30 s."
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:08.000Z"
            }
          }
        }
      ],
      "stream": [
        {
          "sessionUpdate": "agent_message",
          "messageId": "m3",
          "content": [
            {
              "type": "text",
              "text": "A test times out on the simulator."
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:05.000Z"
            }
          }
        },
        {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Reading the CI log",
              "problem": null
            }
          }
        },
        {
          "sessionUpdate": "agent_message",
          "messageId": "m5",
          "content": [
            {
              "type": "text",
              "text": "I raised the timeout to 30 s."
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:08.000Z"
            }
          }
        }
      ]
    },
    "client": {
      "start": {
        "cursor": "c:2",
        "messages": [
          {
            "sessionUpdate": "user_message",
            "messageId": "m1",
            "content": [
              {
                "type": "text",
                "text": "Why is the build red?"
              }
            ],
            "_meta": {
              "agentchatkit": {
                "at": "2026-11-15T05:00:00.000Z",
                "sender": {
                  "login": "jai",
                  "name": "Jai"
                },
                "status": "delivered",
                "clientRef": "ref-1"
              }
            }
          }
        ],
        "state": {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Reading the CI log",
              "problem": null
            }
          }
        }
      },
      "messages": [
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "agent_message",
              "messageId": "m3",
              "content": [
                {
                  "type": "text",
                  "text": "A test times out on the simulator."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:05.000Z"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:3"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "state_update",
              "state": "running",
              "_meta": {
                "agentchatkit": {
                  "activity": "Reading the CI log",
                  "problem": null
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:3"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "agent_message",
              "messageId": "m5",
              "content": [
                {
                  "type": "text",
                  "text": "I raised the timeout to 30 s."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:08.000Z"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:4"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "state_update",
              "state": "idle",
              "_meta": {
                "agentchatkit": {
                  "activity": null,
                  "problem": null
                }
              },
              "stopReason": "end_turn"
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:5"
              }
            }
          }
        }
      ],
      "expect": {
        "cursor": "c:5",
        "messages": [
          {
            "id": "m1",
            "kind": "user",
            "text": "Why is the build red?",
            "status": "delivered"
          },
          {
            "id": "m3",
            "kind": "agent",
            "text": "A test times out on the simulator.",
            "status": null
          },
          {
            "id": "m5",
            "kind": "agent",
            "text": "I raised the timeout to 30 s.",
            "status": null
          }
        ],
        "state": {
          "state": "idle",
          "activity": null
        },
        "question": null
      }
    }
  },
  "resume-expired": {
    "about": "A cursor the host can't resume from answers -32602; the client resumes from start, and the replay replaces everything it held.",
    "server": {
      "before": [
        {
          "sessionUpdate": "user_message",
          "messageId": "m1",
          "content": [
            {
              "type": "text",
              "text": "Why is the build red?"
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:00.000Z",
              "sender": {
                "login": "jai",
                "name": "Jai"
              },
              "status": "delivered",
              "clientRef": "ref-1"
            }
          }
        },
        {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Reading the CI log",
              "problem": null
            }
          }
        },
        {
          "sessionUpdate": "agent_message",
          "messageId": "m3",
          "content": [
            {
              "type": "text",
              "text": "A test times out on the simulator."
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:05.000Z"
            }
          }
        }
      ],
      "resume": "expired",
      "error": -32602
    },
    "client": {
      "start": {
        "cursor": "c:9",
        "messages": [
          {
            "sessionUpdate": "user_message",
            "messageId": "m1",
            "content": [
              {
                "type": "text",
                "text": "Why is the build red?"
              }
            ],
            "_meta": {
              "agentchatkit": {
                "at": "2026-11-15T05:00:00.000Z",
                "sender": {
                  "login": "jai",
                  "name": "Jai"
                },
                "status": "delivered",
                "clientRef": "ref-1"
              }
            }
          },
          {
            "sessionUpdate": "agent_message",
            "messageId": "m3",
            "content": [
              {
                "type": "text",
                "text": "A test times out on the simulator."
              }
            ],
            "_meta": {
              "agentchatkit": {
                "at": "2026-11-15T05:00:05.000Z"
              }
            }
          },
          {
            "sessionUpdate": "agent_message",
            "messageId": "m5",
            "content": [
              {
                "type": "text",
                "text": "I raised the timeout to 30 s."
              }
            ],
            "_meta": {
              "agentchatkit": {
                "at": "2026-11-15T05:00:08.000Z"
              }
            }
          }
        ],
        "state": {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Reading the CI log",
              "problem": null
            }
          }
        }
      },
      "error": -32602,
      "replay": [
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "agent_message",
              "messageId": "n1",
              "content": [
                {
                  "type": "text",
                  "text": "A fresh session: the transcript was replaced."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:30.000Z"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "e2:1"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "state_update",
              "state": "idle",
              "_meta": {
                "agentchatkit": {
                  "activity": null,
                  "problem": null
                }
              },
              "stopReason": "end_turn"
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "e2:1"
              }
            }
          }
        }
      ],
      "expect": {
        "cursor": "e2:1",
        "messages": [
          {
            "id": "n1",
            "kind": "agent",
            "text": "A fresh session: the transcript was replaced.",
            "status": null
          }
        ],
        "state": {
          "state": "idle",
          "activity": null
        },
        "question": null
      }
    }
  },
  "resume-start": {
    "about": "No cursor held: resume from start replays the retained history, then the current state, then live updates.",
    "server": {
      "before": [
        {
          "sessionUpdate": "user_message",
          "messageId": "m1",
          "content": [
            {
              "type": "text",
              "text": "Why is the build red?"
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:00.000Z",
              "sender": {
                "login": "jai",
                "name": "Jai"
              },
              "status": "delivered",
              "clientRef": "ref-1"
            }
          }
        },
        {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Reading the CI log",
              "problem": null
            }
          }
        },
        {
          "sessionUpdate": "agent_message",
          "messageId": "m3",
          "content": [
            {
              "type": "text",
              "text": "A test times out on the simulator."
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:05.000Z"
            }
          }
        }
      ],
      "resume": "start",
      "during": [
        {
          "sessionUpdate": "tool_call_update",
          "toolCallId": "t4",
          "title": "swift test",
          "name": "Bash",
          "kind": "execute",
          "status": "completed",
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:06.000Z"
            }
          }
        }
      ],
      "stream": [
        {
          "sessionUpdate": "user_message",
          "messageId": "m1",
          "content": [
            {
              "type": "text",
              "text": "Why is the build red?"
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:00.000Z",
              "sender": {
                "login": "jai",
                "name": "Jai"
              },
              "status": "delivered",
              "clientRef": "ref-1"
            }
          }
        },
        {
          "sessionUpdate": "agent_message",
          "messageId": "m3",
          "content": [
            {
              "type": "text",
              "text": "A test times out on the simulator."
            }
          ],
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:05.000Z"
            }
          }
        },
        {
          "sessionUpdate": "state_update",
          "state": "running",
          "_meta": {
            "agentchatkit": {
              "activity": "Reading the CI log",
              "problem": null
            }
          }
        },
        {
          "sessionUpdate": "tool_call_update",
          "toolCallId": "t4",
          "title": "swift test",
          "name": "Bash",
          "kind": "execute",
          "status": "completed",
          "_meta": {
            "agentchatkit": {
              "at": "2026-11-15T05:00:06.000Z"
            }
          }
        }
      ]
    },
    "client": {
      "start": null,
      "messages": [
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "user_message",
              "messageId": "m1",
              "content": [
                {
                  "type": "text",
                  "text": "Why is the build red?"
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:00.000Z",
                  "sender": {
                    "login": "jai",
                    "name": "Jai"
                  },
                  "status": "delivered",
                  "clientRef": "ref-1"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:1"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "agent_message",
              "messageId": "m3",
              "content": [
                {
                  "type": "text",
                  "text": "A test times out on the simulator."
                }
              ],
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:05.000Z"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:3"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "state_update",
              "state": "running",
              "_meta": {
                "agentchatkit": {
                  "activity": "Reading the CI log",
                  "problem": null
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:3"
              }
            }
          }
        },
        {
          "jsonrpc": "2.0",
          "method": "session/update",
          "params": {
            "sessionId": "chat-1",
            "update": {
              "sessionUpdate": "tool_call_update",
              "toolCallId": "t4",
              "title": "swift test",
              "name": "Bash",
              "kind": "execute",
              "status": "completed",
              "_meta": {
                "agentchatkit": {
                  "at": "2026-11-15T05:00:06.000Z"
                }
              }
            },
            "_meta": {
              "agentchatkit": {
                "cursor": "c:4"
              }
            }
          }
        }
      ],
      "expect": {
        "cursor": "c:4",
        "messages": [
          {
            "id": "m1",
            "kind": "user",
            "text": "Why is the build red?",
            "status": "delivered"
          },
          {
            "id": "m3",
            "kind": "agent",
            "text": "A test times out on the simulator.",
            "status": null
          },
          {
            "id": "t4",
            "kind": "tool",
            "text": "swift test",
            "status": null
          }
        ],
        "state": {
          "state": "running",
          "activity": "Reading the CI log"
        },
        "question": null
      }
    }
  },
  "transport": {
    "about": "What the client does on each HTTP answer and when the stream ends; the back-off and keep-alive.",
    "statuses": [
      {
        "status": 202,
        "action": "wait for the answer on the stream"
      },
      {
        "status": 200,
        "action": "follow"
      },
      {
        "status": 401,
        "action": "reauth"
      },
      {
        "status": 403,
        "action": "stop"
      },
      {
        "status": 404,
        "action": "initialize again",
        "about": "a connection id the server no longer knows"
      },
      {
        "status": 500,
        "action": "reconnect"
      },
      {
        "status": 503,
        "action": "reconnect"
      }
    ],
    "ended": {
      "about": "the stream ends, or nothing heard for quiet_limit_ms",
      "action": "reconnect"
    },
    "backoff_ms": [
      1000,
      2000,
      4000,
      8000,
      15000,
      15000
    ],
    "jitter": 0.2,
    "backoff_resets_after_ms": 10000,
    "keep_alive_ms": 15000,
    "quiet_limit_ms": 40000,
    "retained_messages": 200,
    "headers": {
      "connection": "Acp-Connection-Id",
      "session": "Acp-Session-Id"
    }
  }
};
