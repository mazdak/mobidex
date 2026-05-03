#!/usr/bin/env bash
set -euo pipefail

CODEX_SOURCE_DIR="${CODEX_SOURCE_DIR:-$HOME/Code/codex}"
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SCHEMA_DIR="$CODEX_SOURCE_DIR/codex-rs/app-server-protocol/schema/typescript"
V2_SCHEMA_DIR="$SCHEMA_DIR/v2"
APP_VIEW_MODEL="$ROOT_DIR/Sources/Mobidex/ViewModels/AppViewModel.swift"

fail() {
  echo "App-server schema verification failed: $*" >&2
  exit 1
}

require_file() {
  local path="$1"
  [[ -f "$path" ]] || fail "missing $path"
}

require_contains() {
  local path="$1"
  local needle="$2"
  local label="$3"
  rg -Fq "$needle" "$path" || fail "$label not found in $path"
}

require_file "$SCHEMA_DIR/ClientRequest.ts"
require_file "$SCHEMA_DIR/ClientNotification.ts"
require_file "$SCHEMA_DIR/ServerNotification.ts"
require_file "$SCHEMA_DIR/ServerRequest.ts"
require_file "$APP_VIEW_MODEL"

for method in \
  initialize \
  thread/list \
  thread/loaded/list \
  thread/read \
  thread/resume \
  thread/start \
  turn/start \
  turn/steer \
  turn/interrupt; do
  require_contains "$SCHEMA_DIR/ClientRequest.ts" "\"method\": \"$method\"" "client method $method"
done

require_contains "$SCHEMA_DIR/ClientNotification.ts" "\"method\": \"initialized\"" "client notification initialized"

require_contains "$V2_SCHEMA_DIR/ThreadListParams.ts" "sortKey?" "thread/list sort key"
require_contains "$V2_SCHEMA_DIR/ThreadListParams.ts" "sortDirection?" "thread/list sort direction"
require_contains "$V2_SCHEMA_DIR/ThreadListParams.ts" "archived?" "thread/list archived filter"
require_contains "$V2_SCHEMA_DIR/ThreadListParams.ts" "cwd?" "thread/list cwd filter"
require_contains "$V2_SCHEMA_DIR/ThreadListParams.ts" "sourceKinds?" "thread/list source-kinds filter"
require_contains "$V2_SCHEMA_DIR/ThreadReadParams.ts" "includeTurns" "thread/read includeTurns"
require_contains "$V2_SCHEMA_DIR/TurnStartParams.ts" "threadId: string" "turn/start threadId"
require_contains "$V2_SCHEMA_DIR/TurnStartParams.ts" "input: Array<UserInput>" "turn/start input"
require_contains "$V2_SCHEMA_DIR/TurnSteerParams.ts" "expectedTurnId: string" "turn/steer expectedTurnId"
require_contains "$V2_SCHEMA_DIR/UserInput.ts" "text_elements" "text input text_elements"

for source_kind in \
  '"cli"' \
  '"vscode"' \
  '"exec"' \
  '"appServer"' \
  '"subAgent"' \
  '"subAgentReview"' \
  '"subAgentCompact"' \
  '"subAgentThreadSpawn"' \
  '"subAgentOther"' \
  '"unknown"'; do
  require_contains "$V2_SCHEMA_DIR/ThreadSourceKind.ts" "$source_kind" "thread source kind $source_kind"
done

for notification in \
  thread/started \
  turn/started \
  turn/completed \
  item/started \
  item/completed \
  item/agentMessage/delta \
  item/plan/delta \
  turn/plan/updated \
  turn/diff/updated \
  command/exec/outputDelta \
  item/commandExecution/outputDelta \
  item/commandExecution/terminalInteraction \
  item/fileChange/outputDelta \
  item/fileChange/patchUpdated \
  serverRequest/resolved \
  item/mcpToolCall/progress \
  item/reasoning/summaryTextDelta \
  item/reasoning/summaryPartAdded \
  item/reasoning/textDelta; do
  require_contains "$SCHEMA_DIR/ServerNotification.ts" "\"method\": \"$notification\"" "server notification $notification"
done

for handled_notification in \
  turn/plan/updated \
  turn/diff/updated \
  item/commandExecution/terminalInteraction \
  serverRequest/resolved \
  item/mcpToolCall/progress; do
  require_contains "$APP_VIEW_MODEL" "case \"$handled_notification\"" "view-model handler $handled_notification"
done

for item_type in \
  userMessage \
  agentMessage \
  reasoning \
  plan \
  commandExecution \
  fileChange \
  mcpToolCall \
  dynamicToolCall \
  collabAgentToolCall \
  webSearch \
  imageView \
  imageGeneration \
  enteredReviewMode \
  exitedReviewMode \
  contextCompaction; do
  require_contains "$V2_SCHEMA_DIR/ThreadItem.ts" "\"type\": \"$item_type\"" "thread item $item_type"
done

for request in \
  item/commandExecution/requestApproval \
  item/fileChange/requestApproval \
  item/permissions/requestApproval \
  item/tool/requestUserInput \
  mcpServer/elicitation/request \
  item/tool/call \
  account/chatgptAuthTokens/refresh \
  applyPatchApproval \
  execCommandApproval; do
  require_contains "$SCHEMA_DIR/ServerRequest.ts" "\"method\": \"$request\"" "server request $request"
done

for handled_request in \
  item/commandExecution/requestApproval \
  item/fileChange/requestApproval \
  item/permissions/requestApproval \
  item/tool/requestUserInput \
  mcpServer/elicitation/request \
  item/tool/call \
  account/chatgptAuthTokens/refresh \
  applyPatchApproval \
  execCommandApproval; do
  require_contains "$APP_VIEW_MODEL" "$handled_request" "view-model request handling $handled_request"
done

require_contains "$V2_SCHEMA_DIR/CommandExecutionRequestApprovalResponse.ts" "decision: CommandExecutionApprovalDecision" "command approval decision type"
require_contains "$V2_SCHEMA_DIR/FileChangeRequestApprovalResponse.ts" "decision: FileChangeApprovalDecision" "file-change approval decision type"
require_contains "$V2_SCHEMA_DIR/PermissionsRequestApprovalResponse.ts" "permissions: GrantedPermissionProfile" "permissions approval permissions type"
require_contains "$V2_SCHEMA_DIR/PermissionsRequestApprovalResponse.ts" "scope: PermissionGrantScope" "permissions approval scope type"
require_contains "$V2_SCHEMA_DIR/ToolRequestUserInputResponse.ts" "answers: { [key in string]?: ToolRequestUserInputAnswer }" "tool input answers map type"
require_contains "$V2_SCHEMA_DIR/McpServerElicitationRequestResponse.ts" "action: McpServerElicitationAction" "MCP elicitation action type"
require_contains "$V2_SCHEMA_DIR/McpServerElicitationRequestResponse.ts" "content: JsonValue | null" "MCP elicitation content type"
require_contains "$V2_SCHEMA_DIR/McpServerElicitationRequestResponse.ts" "_meta: JsonValue | null" "MCP elicitation metadata type"
require_contains "$V2_SCHEMA_DIR/DynamicToolCallResponse.ts" "contentItems: Array<DynamicToolCallOutputContentItem>" "dynamic tool contentItems type"
require_contains "$V2_SCHEMA_DIR/DynamicToolCallResponse.ts" "success: boolean" "dynamic tool success type"
require_contains "$SCHEMA_DIR/ApplyPatchApprovalResponse.ts" "decision: ReviewDecision" "legacy apply-patch approval decision type"
require_contains "$SCHEMA_DIR/ExecCommandApprovalResponse.ts" "decision: ReviewDecision" "legacy exec approval decision type"
require_contains "$V2_SCHEMA_DIR/ChatgptAuthTokensRefreshResponse.ts" "accessToken: string" "auth-token refresh access token type"

require_contains "$V2_SCHEMA_DIR/CommandExecutionApprovalDecision.ts" '"accept"' "command approval accept literal"
require_contains "$V2_SCHEMA_DIR/CommandExecutionApprovalDecision.ts" '"decline"' "command approval decline literal"
require_contains "$V2_SCHEMA_DIR/FileChangeApprovalDecision.ts" '"accept"' "file-change approval accept literal"
require_contains "$V2_SCHEMA_DIR/FileChangeApprovalDecision.ts" '"decline"' "file-change approval decline literal"
require_contains "$V2_SCHEMA_DIR/PermissionGrantScope.ts" '"turn"' "permissions approval turn scope literal"
require_contains "$V2_SCHEMA_DIR/McpServerElicitationAction.ts" '"decline"' "MCP elicitation decline literal"
require_contains "$SCHEMA_DIR/ReviewDecision.ts" '"approved"' "legacy approval approved literal"
require_contains "$SCHEMA_DIR/ReviewDecision.ts" '"denied"' "legacy approval denied literal"

echo "App-server schema verification succeeded."
