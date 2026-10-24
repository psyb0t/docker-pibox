def short: tostring | gsub("[\r\n]"; " ") | .[:1000];
fromjson
| if .type == "session" then "[start] Pi session"
  elif .type == "message_end" and .message.role == "assistant" then
    .message.content[] | select(.type == "text") | "[pi] " + (.text | short)
  elif .type == "tool_execution_start" then
    "[tool] " + .toolName + ": " + (.args | tojson | short)
  elif .type == "tool_execution_end" then
    "[result] " + ([.result.content[]? | select(.type == "text") | .text] | join(" ") | short)
  elif .type == "agent_end" then "[done] Pi run ended"
  else empty end
