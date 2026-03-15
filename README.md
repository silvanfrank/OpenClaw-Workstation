# OpenClaw Workstation

A full Linux desktop with OpenClaw AI pre-installed, accessible from your browser.

## What You Get

```
┌─────────────────────────────────────────────────────────────┐
│  Your Browser                                               │
│  https://workstation.your-domain.com                        │
└─────────────────────────┬───────────────────────────────────┘
                          │
                          ▼
┌─────────────────────────────────────────────────────────────┐
│  All-in-One Container                                       │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  Linux Desktop (Ubuntu XFCE)                        │    │
│  │  - Firefox, Terminal, File Manager                  │    │
│  │  - OpenClaw Gateway (background service)            │    │
│  │                                                     │    │
│  │  Access from inside:                                │    │
│  │  → http://localhost:18789     (OpenClaw Dashboard)  │    │
│  │  → http://localhost:3001+     (Dev Servers)         │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
```

**Key benefit:** Since OpenClaw runs *inside* the same container, any dev server it spins up is accessible at `localhost:PORT` from the desktop browser.

## Deployment & Configuration

For full deployment instructions, environment variables, security guidelines, and troubleshooting using Coolify, please see [DEPLOY_COOLIFY.md](DEPLOY_COOLIFY.md).

## Usage

1. **Access the Desktop:** Open your deployed Workstation URL in your browser.
2. **Open Firefox** (pre-installed in the desktop).
3. **Access OpenClaw:** Go to `http://localhost:18789/chat?session=main&token=YOUR_TOKEN`
   > **Note:** You MUST include the `token` parameter in the URL to authenticate.
4. **Dev Servers:** Any server OpenClaw starts is accessible at `http://localhost:PORT` directly from the desktop browser.

### OpenRouter SDK Streaming Example

```ts
import { OpenRouter } from "@openrouter/sdk";

const openrouter = new OpenRouter({
  apiKey: "<OPENROUTER_API_KEY>"
});

// Stream the response to get reasoning tokens in usage
const stream = await openrouter.chat.send({
  model: "minimax/minimax-m2.5",
  messages: [
    {
      role: "user",
      content: "How many r's are in the word 'strawberry'?"
    }
  ],
  stream: true
});

let response = "";
for await (const chunk of stream) {
  const content = chunk.choices[0]?.delta?.content;
  if (content) {
    response += content;
    process.stdout.write(content);
  }

  // Usage information comes in the final chunk
  if (chunk.usage) {
    console.log("\nReasoning tokens:", chunk.usage.reasoningTokens);
  }
}
```

## How It Works

1. Container starts with LinuxServer.io's Webtop base image (Ubuntu KDE)
2. Our custom script (`openclaw-run`) runs via S6 overlay's `services.d` to keep OpenClaw running.
3. OpenClaw gateway starts in background on port 18789
4. You access the desktop via browser on port 3000
5. From inside the desktop, `localhost:18789` = OpenClaw, `localhost:3001+` = dev servers
