if length == 0 or any(.[]; type != "object" or (.type | type) != "string") then
  error("invalid Pi event stream")
else . end
| [.[] | select(.type == "agent_end")]
| if length != 1 then error("expected one completed Pi run") else .[0] end
| [.messages[] | select(.role == "assistant")]
| if length == 0 then error("missing final assistant") else last end
| if .stopReason != "stop" then error("Pi did not complete successfully") else . end
| [.content[] | select(.type == "text") | .text]
| join("\n")
