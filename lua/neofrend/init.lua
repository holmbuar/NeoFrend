local M = {}

local chat_buf = nil
local chat_win = nil
local current_model = "gemini-3-flash-preview"
local current_job = nil

local function create_window()
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    vim.api.nvim_set_current_win(chat_win)
    return
  end

  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then
    chat_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = chat_buf })
    vim.api.nvim_set_option_value("textwidth", 0, { buf = chat_buf })
    vim.api.nvim_set_option_value("wrapmargin", 0, { buf = chat_buf })

    local lines = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
    if #lines == 0 or (#lines == 1 and lines[1] == "") then
      local welcome_msg = {
        "Welcome to **NeoFrend**! Type your prompt below.",
        "",
        "> **Modes:**",
        "> - `/chat <msg>`: Standard conversation (default).",
        "> - `/do <task>`: Agent mode in current workspace.",
        "> - `⚠️ /config <task>`: Agent mode in Neovim config.",
        ">",
        "> *The active mode is saved in the header (e.g. `## User (/do)`).* ",
        "> *Subsequent messages will use this mode unless you use a new prefix.*",
        "",
        "---",
        "## User (Chat)",
        ""
      }
      vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, welcome_msg)
    end

    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(0, true)
    end, { buffer = chat_buf, silent = true, desc = "Close NeoFrend" })

    vim.keymap.set("n", "<Esc>", function()
      if current_job then
        current_job:kill(9)
        current_job = nil
        print("NeoFrend: Process aborted.")
      end
    end, { buffer = chat_buf, silent = true, desc = "Abort running process" })

    vim.keymap.set("i", "<S-CR>", "<CR>", { buffer = chat_buf, noremap = true, silent = true, desc = "New line" })

    vim.keymap.set({ "n", "i" }, "<CR>", function()
      if vim.fn.mode() == 'i' then
        vim.cmd("stopinsert")
      end
      M.submit_prompt()
    end, { buffer = chat_buf, silent = true, desc = "Submit to NeoFrend" })
  end

  local width = math.floor(vim.o.columns * 0.8)
  local height = math.floor(vim.o.lines * 0.8)
  local col = math.floor((vim.o.columns - width) / 2)
  local row = math.floor((vim.o.lines - height) / 2)

  chat_win = vim.api.nvim_open_win(chat_buf, true, {
    relative = "editor",
    width = width,
    height = height,
    col = col,
    row = row,
    style = "minimal",
    border = "rounded",
    title = " NeoFrend (Enter: send, Esc: abort, q: quit) ",
    title_pos = "center"
  })

  vim.api.nvim_set_option_value("wrap", true, { win = chat_win })
  vim.api.nvim_set_option_value("conceallevel", 2, { win = chat_win })
  vim.api.nvim_set_option_value("concealcursor", "nc", { win = chat_win })
  vim.api.nvim_set_option_value("winhighlight", "NormalFloat:Pmenu,FloatBorder:Pmenu", { win = chat_win })

  vim.api.nvim_set_option_value("filetype", "markdown", { buf = chat_buf })
  pcall(vim.treesitter.start, chat_buf, "markdown")
end

function M.toggle()
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    vim.api.nvim_win_close(chat_win, true)
    chat_win = nil
  else
    create_window()
    
    local line_count = vim.api.nvim_buf_line_count(chat_buf)
    local last_line = vim.api.nvim_buf_get_lines(chat_buf, line_count - 1, line_count, false)[1]
    
    if last_line and last_line:match("^## User") then
      vim.api.nvim_buf_set_lines(chat_buf, line_count, line_count, false, { "" })
      line_count = line_count + 1
    end

    vim.api.nvim_win_set_cursor(chat_win, { line_count, 0 })
    vim.cmd("startinsert")
  end
end

local function execute_cli(prompt, mode, is_retry, loading_line)
  local yolo = (mode == "do" or mode == "config")
  local cwd = (mode == "config") and vim.fn.stdpath("config") or nil
  
  -- Prepend a small formatting instruction if it's standard chat
  local final_prompt = prompt
  if mode == "chat" then
    final_prompt = "Format answers cleanly in Markdown without H1/H2 headers.\n\n" .. prompt
  end

  local cmd = { "gemini", "-p", final_prompt, "--model=" .. current_model }
  if yolo then
    table.insert(cmd, "--approval-mode=yolo")
  end
  if not is_retry then
    table.insert(cmd, "-r")
    table.insert(cmd, "1")
  end

  local sys_opts = { text = true }
  if cwd then
    sys_opts.cwd = cwd
  end

  current_job = vim.system(cmd, sys_opts, vim.schedule_wrap(function(out)
    -- If it fails because of no previous session, retry without `-r 1`
    if out.code == 42 and not is_retry then
      execute_cli(prompt, mode, true, loading_line)
      return
    end

    current_job = nil
    local reply = out.stdout or ""
    if out.code ~= 0 then
      reply = reply .. "\n\n**Error (Code " .. out.code .. "):**\n```\n" .. (out.stderr or "") .. "\n```"
    end
    
    -- Clean up CLI noise and ANSI escapes
    reply = string.gsub(reply, '\27%[[0-9;]*[mK]', '')
    reply = string.gsub(reply, "Positional arguments now default to interactive mode%. To run in non%-interactive mode, use the %-%-prompt %(%-p%) flag%.%s*", "")
    reply = string.gsub(reply, "Loaded cached credentials%.%s*", "")
    reply = string.gsub(reply, "YOLO mode is enabled%. All tool calls will be automatically approved%.%s*", "")
    reply = vim.trim(reply)

    if reply == "" then
      reply = "Task completed with no output."
    end

    local reply_lines = vim.split(reply, "\n")
    vim.api.nvim_buf_set_lines(chat_buf, loading_line, loading_line + 1, false, reply_lines)
    
    -- Prepare next header based on current mode
    local next_header = "## User (Chat)"
    if mode == "do" then next_header = "## User (/do)" end
    if mode == "config" then next_header = "## User (/config)" end
    
    vim.api.nvim_buf_set_lines(chat_buf, -1, -1, false, { "", next_header, "" })
    
    local line_count = vim.api.nvim_buf_line_count(chat_buf)
    if chat_win and vim.api.nvim_win_is_valid(chat_win) then
      vim.api.nvim_win_set_cursor(chat_win, { line_count, 0 })
    end
    vim.cmd("checktime")
  end))
end

function M.submit_prompt()
  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then return end

  local lines = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
  local prompt_lines = {}
  local last_header = "## User (Chat)"

  -- Find the last User block
  for i = #lines, 1, -1 do
    if lines[i]:match("^## User") then
      last_header = lines[i]
      for j = i + 1, #lines do
        table.insert(prompt_lines, lines[j])
      end
      break
    end
  end

  local prompt = vim.fn.join(prompt_lines, "\n")
  prompt = vim.trim(prompt)
  if prompt == "" then
    print("Empty prompt. Type something under the header before pressing Enter.")
    return
  end

  -- Determine inherited mode from the header
  local mode = "chat"
  if last_header:match("%(/do%)") then mode = "do" end
  if last_header:match("%(/config%)") then mode = "config" end
  if last_header:match("%(Chat%)") then mode = "chat" end

  -- Override mode if a prefix is used
  if string.sub(prompt, 1, 4) == "/do " then
    mode = "do"
    prompt = vim.trim(string.sub(prompt, 5))
  elseif string.sub(prompt, 1, 8) == "/config " then
    mode = "config"
    prompt = vim.trim(string.sub(prompt, 9))
  elseif string.sub(prompt, 1, 6) == "/chat " then
    mode = "chat"
    prompt = vim.trim(string.sub(prompt, 7))
  end

  local ai_header = "## NeoFrend"
  if mode == "do" then ai_header = "## NeoFrend (Workspace Agent)" end
  if mode == "config" then ai_header = "## NeoFrend (Config Agent)" end

  vim.api.nvim_buf_set_lines(chat_buf, -1, -1, false, { "", ai_header, "Thinking..." })
  local loading_line = vim.api.nvim_buf_line_count(chat_buf) - 1
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    vim.api.nvim_win_set_cursor(chat_win, { loading_line + 1, 0 })
  end

  execute_cli(prompt, mode, false, loading_line)
end

function M.setup()
  vim.api.nvim_create_user_command("Frend", function(opts)
    if opts.args ~= "" then
      current_model = opts.args
      print("NeoFrend model set to: " .. current_model)
    else
      print("NeoFrend current model: " .. current_model .. " (use :Frend <model_name> to change)")
    end
  end, { nargs = "?", desc = "Change NeoFrend model (e.g., :Frend gemini-2.5-pro)" })
end

return M
