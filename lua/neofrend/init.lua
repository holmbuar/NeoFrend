local M = {}

local chat_buf = nil
local chat_win = nil
local chat_history = {}
local current_model = "gemini-3-flash-preview"

local function create_window()
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    vim.api.nvim_set_current_win(chat_win)
    return
  end

  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then
    chat_buf = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_set_option_value("buftype", "nofile", { buf = chat_buf })
    vim.api.nvim_set_option_value("filetype", "markdown", { buf = chat_buf })
    vim.api.nvim_set_option_value("textwidth", 0, { buf = chat_buf })
    vim.api.nvim_set_option_value("wrapmargin", 0, { buf = chat_buf })

    -- Initialize buffer with User header if empty
    local lines = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
    if #lines == 0 or (#lines == 1 and lines[1] == "") then
      vim.api.nvim_buf_set_lines(chat_buf, 0, -1, false, { "## User", "" })
    end

    -- Keymap to close
    vim.keymap.set("n", "q", function()
      vim.api.nvim_win_close(0, true)
    end, { buffer = chat_buf, silent = true, desc = "Close NeoFrend" })

    -- Keymap to add a new line without submitting
    vim.keymap.set("i", "<S-CR>", "<CR>", { buffer = chat_buf, noremap = true, silent = true, desc = "New line" })

    -- Keymap to submit
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
    title = " NeoFrend (Press Enter to send, q to quit) ",
    title_pos = "center"
  })

  vim.api.nvim_set_option_value("wrap", true, { win = chat_win })
  vim.api.nvim_set_option_value("conceallevel", 2, { win = chat_win })
  vim.api.nvim_set_option_value("concealcursor", "nc", { win = chat_win })
end

function M.toggle()
  if chat_win and vim.api.nvim_win_is_valid(chat_win) then
    vim.api.nvim_win_close(chat_win, true)
    chat_win = nil
  else
    create_window()
    -- Move cursor to bottom
    local line_count = vim.api.nvim_buf_line_count(chat_buf)
    vim.api.nvim_win_set_cursor(chat_win, { line_count, 0 })
    vim.cmd("startinsert")
  end
end

function M.submit_prompt()
  if not chat_buf or not vim.api.nvim_buf_is_valid(chat_buf) then return end

  local lines = vim.api.nvim_buf_get_lines(chat_buf, 0, -1, false)
  local prompt_lines = {}

  -- Find the last User block
  for i = #lines, 1, -1 do
    if lines[i] == "## User" then
      for j = i + 1, #lines do
        table.insert(prompt_lines, lines[j])
      end
      break
    end
  end

  local prompt = vim.fn.join(prompt_lines, "\n")
  prompt = vim.trim(prompt)
  if prompt == "" then
    print("Empty prompt. Type something under '## User' before pressing Enter.")
    return
  end

  local is_agent = false
  local agent_cwd = nil
  local display_cmd = ""
  local target_env = "local workspace"

  if string.sub(prompt, 1, 4) == "/do " then
    is_agent = true
    display_cmd = "/do"
    prompt = vim.trim(string.sub(prompt, 5))
  elseif string.sub(prompt, 1, 8) == "/config " then
    is_agent = true
    display_cmd = "/config"
    target_env = "Neovim configuration (" .. vim.fn.stdpath("config") .. ")"
    agent_cwd = vim.fn.stdpath("config")
    prompt = vim.trim(string.sub(prompt, 9))
  end

  if is_agent then
    table.insert(chat_history, { role = "user", parts = { { text = display_cmd .. " " .. prompt } } })
    
    local warning_msg = {
      "", 
      "## NeoFrend (Agent)", 
      "**⚠️ WARNING: Entering Autonomous Mode**",
      "> The agent is now executing commands and modifying files in your **" .. target_env .. "** without confirmation.",
      "> *NeoFrend developers assume no responsibility for data loss or unintended changes.*",
      "",
      "Running Gemini CLI agent... (this may take a while)"
    }
    vim.api.nvim_buf_set_lines(chat_buf, -1, -1, false, warning_msg)
    local loading_line = vim.api.nvim_buf_line_count(chat_buf) - 1

    local agent_instruction = "CRITICAL INSTRUCTION: You must ONLY operate within the current working directory (" .. (agent_cwd or vim.fn.getcwd()) .. ") and its subdirectories. Do not modify or read any files outside of this boundary. Task: "
    local cmd = { "gemini", agent_instruction .. prompt, "--approval-mode=yolo", "--model=gemini-3.1-pro-preview" }
    local sys_opts = { text = true }
    if agent_cwd then
      sys_opts.cwd = agent_cwd
    end
    
    vim.system(cmd, sys_opts, vim.schedule_wrap(function(out)
      local reply = out.stdout or ""
      if out.code ~= 0 then
        reply = reply .. "\n\n**Error:**\n```\n" .. (out.stderr or "") .. "\n```"
      end
      
      -- Clean ANSI escape sequences from the CLI output
      reply = string.gsub(reply, '\27%[[0-9;]*[mK]', '')
      reply = vim.trim(reply)
      if reply == "" then
        reply = "Task completed with no output."
      end

      table.insert(chat_history, { role = "model", parts = { { text = reply } } })

      local reply_lines = vim.split(reply, "\n")
      vim.api.nvim_buf_set_lines(chat_buf, loading_line, loading_line + 1, false, reply_lines)
      vim.api.nvim_buf_set_lines(chat_buf, -1, -1, false, { "", "## User", "" })
      
      local line_count = vim.api.nvim_buf_line_count(chat_buf)
      if chat_win and vim.api.nvim_win_is_valid(chat_win) then
        vim.api.nvim_win_set_cursor(chat_win, { line_count, 0 })
      end
      vim.cmd("checktime")
    end))
    return
  end

  -- Add to history
  table.insert(chat_history, { role = "user", parts = { { text = prompt } } })

  -- Append NeoFrend header and loading state
  vim.api.nvim_buf_set_lines(chat_buf, -1, -1, false, { "", "## NeoFrend", "Thinking..." })
  local loading_line = vim.api.nvim_buf_line_count(chat_buf) - 1

  local api_key = os.getenv("GEMINI_API_KEY")
  if not api_key then
    vim.api.nvim_buf_set_lines(chat_buf, loading_line, loading_line + 1, false, { "Error: GEMINI_API_KEY environment variable not set." })
    vim.api.nvim_buf_set_lines(chat_buf, -1, -1, false, { "", "## User", "" })
    return
  end

  local url = "https://generativelanguage.googleapis.com/v1beta/models/" .. current_model .. ":generateContent?key=" .. api_key

  local system_prompt = [[
You are an expert Neovim assistant embedded directly within the user's editor.
Your goal is to infer the user's competence level based on their question and adjust your tone and detail accordingly.
- For a "total noob" (e.g., asking "how to exit?" or "what is a buffer?"): Provide super short, friendly, and encouraging advice. Briefly explain Neovim terminology (e.g., clarify that a "buffer" is essentially an open "file", `<C>` means the "Control" key, and `<Leader>` usually means the "Spacebar").
- For a more experienced user (e.g., asking "how to map a key to a lua function" or "how to toggle Neogit"): Provide concise, direct, and technical answers without patronizing explanations of basic concepts. Provide code snippets directly.
Format your answers in clean, standard Markdown.
- DO NOT use H1 or H2 headers (e.g. # or ##) in your response, as they interfere with the chat UI. Use H3 (###) or bold text instead.
- Always use Markdown code blocks with the correct language identifier for code snippets.
- Use bullet points and formatting to make your answers easily scannable.
- Prioritize using native vim or lua API solutions when appropriate.
]]

  local payload = {
    contents = chat_history,
    systemInstruction = {
      role = "system",
      parts = { { text = system_prompt } }
    }
  }

  local json_payload = vim.fn.json_encode(payload)
  local tmp_file = vim.fn.tempname()
  vim.fn.writefile({json_payload}, tmp_file)

  vim.system({
    "curl", "-s", "-X", "POST",
    "-H", "Content-Type: application/json",
    "-d", "@" .. tmp_file,
    url
  }, { text = true }, vim.schedule_wrap(function(out)
    vim.fn.delete(tmp_file)
    if out.code ~= 0 then
      vim.api.nvim_buf_set_lines(chat_buf, loading_line, loading_line + 1, false, { "Error: Network request failed." })
      return
    end

    local ok, response = pcall(vim.fn.json_decode, out.stdout)
    if not ok or not response or response.error then
      local err_msg = response and response.error and response.error.message or "Invalid API response."
      vim.api.nvim_buf_set_lines(chat_buf, loading_line, loading_line + 1, false, { "Error: " .. err_msg })
      return
    end

    local reply = ""
    if response.candidates and response.candidates[1] and response.candidates[1].content and response.candidates[1].content.parts then
      reply = response.candidates[1].content.parts[1].text
    end

    table.insert(chat_history, { role = "model", parts = { { text = reply } } })

    local reply_lines = vim.split(reply, "\n")
    vim.api.nvim_buf_set_lines(chat_buf, loading_line, loading_line + 1, false, reply_lines)
    vim.api.nvim_buf_set_lines(chat_buf, -1, -1, false, { "", "## User", "" })
    
    -- Scroll to bottom
    local line_count = vim.api.nvim_buf_line_count(chat_buf)
    if chat_win and vim.api.nvim_win_is_valid(chat_win) then
      vim.api.nvim_win_set_cursor(chat_win, { line_count, 0 })
    end
  end))
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
