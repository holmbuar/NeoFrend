# NeoFrend

An autonomous Gemini Agent and minimalist chat interface living directly inside your Neovim buffer.

NeoFrend is more than just a chatbot. While it provides a distraction-free, floating scratch buffer for asking quick programming questions, its true power lies in its **Agent Mode**. By leveraging the Gemini CLI in the background, NeoFrend can autonomously read your workspace, formulate plans, and actively modify your files or editor configuration without ever leaving Neovim.

*Inspired by the excellent [CodeCompanion.nvim](https://github.com/olimorris/codecompanion.nvim), but focused on raw agentic power and a stripped-down, pure chat experience.*

## Features

- 🤖 **Autonomous Agent**: Unleash the Gemini CLI on your local workspace or Neovim config directory to write code, refactor files, or install plugins autonomously.
- 💬 **Minimalist Chat**: A clean, floating markdown buffer that doesn't get in your way.
- 🚀 **Zero Heavy Dependencies**: Relies on `curl` and the `gemini` CLI. No massive context-provisioning engines or bloated Lua libraries.
- 🎨 **Markdown Native**: Seamlessly integrates with tools like `render-markdown.nvim` for beautiful, rendered responses.

## Requirements

- Neovim >= 0.9.0
- `curl` installed on your system.
- The [Gemini CLI](https://github.com/google/gemini-cli) installed and authenticated.
- An active Gemini API key exported in your environment as `GEMINI_API_KEY` (for standard chat mode).

## Installation

Using [lazy.nvim](https://github.com/folke/lazy.nvim):

```lua
{
  "holmbuar/NeoFrend",
  keys = {
    { "<leader>b", function() require("neofrend").toggle() end, desc = "Toggle NeoFrend" },
  },
  cmd = "Frend",
  config = function()
    require("neofrend").setup()
  end,
}
```

## Usage

1. **Toggle NeoFrend**: Press `<leader>b` to open or close the floating window.
2. **Chat**: Type your prompt under the `## User` heading.
3. **Send**: Press `Enter` (in Insert or Normal mode) to submit your prompt to Gemini. The response will stream below.
4. **Agent Mode (The Magic)**: You can invoke the autonomous Gemini Agent to read, write, and execute commands on your behalf.
   * `/do <prompt>`: Runs the agent in your **current workspace** (e.g., `/do create a python script that prints hello world and run it`).
   * `/config <prompt>`: Runs the agent directly in your **Neovim configuration directory** (`~/.config/nvim`). Perfect for querying your setup, installing plugins, or changing editor settings. Examples:
     * `/config what git plugins am I currently using?`
     * `/config what is my leader key mapped to?`
     * `/config install Neogit in my lazy.nvim setup`
   * **⚠️ WARNING**: Using `/do` or `/config` gives the AI autonomous access to your system and files without prompting for confirmation (YOLO mode). Use with extreme caution. The NeoFrend developers assume absolutely no responsibility for any unintended changes, data loss, or system issues caused by the agent. Review your git diffs frequently!
5. **Change Model**: Use the `:Frend <model_name>` command to switch models on the fly (e.g., `:Frend gemini-2.5-pro`). Running `:Frend` without arguments prints the current model. The default is `gemini-3-flash-preview`.
6. **Close**: Press `q` in Normal mode to dismiss the window.

## Examples

### General Chat
```markdown
## User
how to exit?

## NeoFrend
Hey there! Welcome to Neovim. Exiting is a rite of passage! 😄

To exit, you need to be in **Normal mode** (press `Esc` if you're typing). Then, type a colon `:` to open the command line at the bottom, followed by `q`, and hit `Enter`. 

So, the full command is:
`:q` (short for "quit")

If you have unsaved changes in your file (buffer) and want to force Neovim to close anyway, you can use:
`:q!`
```

### Agent Mode (Querying Config)
```markdown
## User
/config what is my Git plugin?

## NeoFrend (Agent)
**⚠️ WARNING: Entering Autonomous Mode**
> The agent is now executing commands and modifying files in your **Neovim configuration (~/.config/nvim)** without confirmation.
> *NeoFrend developers assume no responsibility for data loss or unintended changes.*

Running Gemini CLI agent... (this may take a while)

Based on your `lazy-lock.json` and Neovim configuration files, you have two Git plugins installed:

1. **`neogit`**: A Magit clone for full Git operations within Neovim.
2. **`gitsigns.nvim`**: Provides inline Git decorations (signs, diffs, and blame) in the editor.
```