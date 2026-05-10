import { WTerm } from "@wterm/dom";
import { GhosttyCore } from "@wterm/ghostty";
import "@wterm/dom/css";
import "./mobidex-terminal.css";

type BridgeMessage =
  | { type: "ready" }
  | { type: "input"; data: string }
  | { type: "resize"; cols: number; rows: number }
  | { type: "error"; message: string };

declare global {
  interface Window {
    MobidexAndroid?: { postMessage(message: string): void };
    webkit?: { messageHandlers?: { mobidexTerminal?: { postMessage(message: BridgeMessage): void } } };
    mobidexTerminal?: {
      writeBase64(data: string): void;
      send(data: string): void;
      clear(): void;
      focus(): void;
    };
    MobidexTerminalWasmUrl?: string;
  }
}

const terminalElement = document.getElementById("terminal");
if (!terminalElement) {
  throw new Error("Missing terminal element");
}

function post(message: BridgeMessage) {
  window.webkit?.messageHandlers?.mobidexTerminal?.postMessage(message);
  window.MobidexAndroid?.postMessage(JSON.stringify(message));
}

function decodeBase64(data: string): Uint8Array {
  const binary = atob(data);
  const bytes = new Uint8Array(binary.length);
  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }
  return bytes;
}

async function boot() {
  const core = await GhosttyCore.load({ wasmPath: window.MobidexTerminalWasmUrl ?? "./ghostty-vt.wasm" });
  const term = new WTerm(terminalElement, {
    core,
    cols: 80,
    rows: 24,
    cursorBlink: true,
    onData: (data) => post({ type: "input", data }),
    onResize: (cols, rows) => post({ type: "resize", cols, rows }),
  });

  await term.init();

  window.mobidexTerminal = {
    writeBase64(data: string) {
      term.write(decodeBase64(data));
    },
    send(data: string) {
      post({ type: "input", data });
    },
    clear() {
      term.write("\x1bc");
    },
    focus() {
      term.focus();
    },
  };

  post({ type: "ready" });
}

boot().catch((error: unknown) => {
  const message = error instanceof Error ? error.message : String(error);
  terminalElement.textContent = `Terminal failed: ${message}`;
  post({ type: "error", message });
});
