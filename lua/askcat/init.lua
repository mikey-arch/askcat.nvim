-- askcat - AI Assistant Plugin for Neovim
-- lightweight AI assistant that integrates with Ollama for quick answers

local M = {}

-- window and buffer management
local window = nil
local buffer = nil
local last_response = nil
local last_prompt = nil

-- query state management
local is_querying = false
local current_job = nil
local current_prompt_display = nil

-- Default configuration
-- should override in own setup, as this just default common model and local Ollama
local config = {
    model = "llama3.2:3b",
    ollama_url = "http://localhost:11434/api/generate",
    system_prompt = ""
}

--- Cancel the current query in progress
---@return boolean true if a query was cancelled, false otherwise
local function cancel_query()
    if current_job then
        local job_to_kill = current_job
        current_job = nil
        is_querying = false
        current_prompt_display = nil

        job_to_kill:kill(9)
        vim.notify("🐱 Cancelled!", vim.log.levels.WARN, { timeout = 1000})

        if window and vim.api.nvim_win_is_valid(window) then
            vim.api.nvim_win_close(window, true)
        end
        return true
    end
    return false
end

--- Ollama API with a prompt
---@param prompt string The user's prompt
---@param callback function Callback to handle the response
local function query_ollama(prompt, callback)
    --cancel any existing query first
    if current_job then
        cancel_query()
        vim.wait(100)
    end

    --build prompt with system instructions
    local full_prompt = ""
    if config.system_prompt and config.system_prompt ~= "" then
        full_prompt = config.system_prompt .. "\n\n" .. prompt
    else
        full_prompt = prompt
    end

    current_prompt_display = prompt

    local cmd = {
        'curl',
        '-X', 'POST',
        config.ollama_url,
        '-H', 'Content-Type: application/json',
        '-d', vim.json.encode({
            model = config.model,
            prompt = full_prompt,
            stream = false
        })
    }

    current_job = vim.system(cmd, { text = true }, function(result)
        -- Check if the job was cancelled 
        if not current_job then
            return
        end

        current_job = nil
        current_prompt_display = nil

        if result.code == 0 then
            local success, response = pcall(vim.json.decode, result.stdout)
            if success and response.response then
                -- Filter out <think>...</think> tags if present (e.g for from DeepSeek model)
                local filtered_response = response.response
                filtered_response = filtered_response:gsub("<think>.-</think>%s*", "")
                filtered_response = vim.trim(filtered_response)

                callback(nil, filtered_response, prompt)
            else
                -- Handle partial JSON from cancellation
                if result.stdout and #result.stdout < 100 then
                    return
                end
                callback("Error: Failed to parse response", nil, prompt)
            end
        elseif result.signal == 9 or result.signal == 15 or result.code == 143 then
            -- process was killed dont need to show error
            return
        else
            callback("Error: " .. (result.stderr or "Unknown error"), nil, prompt)
        end
    end)
end

---Display the response ina floating window
---@param text string response to show
---@param prompt  string prompt to show
local function show_response(text, prompt)

    if text == nil and prompt == nil then
        return
    end

    last_response = text
    last_prompt = prompt

    if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
    end

    local opts = {
        relative = 'editor',
        width = vim.o.columns - 4,
        height = 8,
        col = 2,
        row = vim.o.lines - 10,
        style = 'minimal',
        border = 'none',
    }

    local display_text = prompt .. "\n" .. text
    local lines = vim.split(display_text, '\n')

    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    window = vim.api.nvim_open_win(buffer, true, opts)
    vim.api.nvim_win_set_option(window, 'wrap', true)
    vim.api.nvim_win_set_option(window, 'linebreak', true)
end

--- show loading indicators
---@param prompt any the prompt
local function show_loading(prompt)
    if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
    end

    local opts = {
        relative = 'editor',
        width = vim.o.columns - 4,
        height = 8,
        col = 2,
        row = vim.o.lines - 10,
        style = 'minimal',
        border = 'none',
    }

    local display_text = prompt .. "\n🐱 Loading..."
    local lines = vim.split(display_text, '\n')

    buffer = vim.api.nvim_create_buf(false, true)
    vim.api.nvim_buf_set_lines(buffer, 0, -1, false, lines)
    window = vim.api.nvim_open_win(buffer, true, opts)
    vim.api.nvim_win_set_option(window, 'wrap', true)
    vim.api.nvim_win_set_option(window, 'linebreak', true)
end

--- gets the current line or visual selection
---@return any the selected prompt
local function get_current_prompt()
    local mode = vim.fn.mode()
    local prompt

    --yank visual mode selection to register then restores visual selection
    if mode == "v" or mode == "V" then
        vim.cmd('normal! y')
        prompt = vim.fn.getreg('"')
        vim.cmd('normal! gv') 
    else
        prompt = vim.api.nvim_get_current_line()
    end

    prompt = prompt:gsub("^%s*%-%-+%s*", "")

    return vim.trim(prompt)
end

--- Main function to query the LLM
local function ask_ai()
    if is_querying then
        vim.notify("🐱 Replacing previous query...", vim.log.levels.INFO, { timeout = 500})
        if not cancel_query() then
            vim.notify("🐱 Still processing...", vim.log.levels.WARN, { timeout = 1000})
            return
        end
    end

    local prompt = get_current_prompt()
    if prompt == "" then
        vim.notify("🐱 Empty", vim.log.levels.WARN, { timeout = 2000 })
        return
    end

    is_querying = true
    vim.notify("🐱...", vim.log.levels.INFO, { timeout = 1000})
    show_loading(prompt)

    query_ollama(prompt, function(err,resp,original_prompt)
        vim.schedule(function()
            is_querying = false

            if err then
                show_response(err, original_prompt or prompt)
                vim.notify("🐱E...", vim.log.levels.ERROR, { timeout = 1000})
            else
                show_response(resp, original_prompt or prompt)
            end
        end)
    end)
end

---toggles repsone window or triggers a new query
local function toggle_window()
    local mode = vim.fn.mode()

    if mode == "v" or mode == "V" then
        ask_ai()
        return
    end

    if window and vim.api.nvim_win_is_valid(window) then
        vim.api.nvim_win_close(window, true)
        window = nil
    else
        if is_querying then
            -- Show current status instead of blocking
            if current_prompt_display then
                local preview = string.sub(current_prompt_display, 1, 40)
                vim.notify("🐱 Processing: " .. preview .. "...\n  Press <leader>tt to cancel", vim.log.levels.INFO, { timeout = 2000})
            else
                vim.notify("🐱 Still processing... Press <leader>c to cancel", vim.log.levels.INFO, { timeout = 1500})
            end
            return
        end

        if last_response then
            show_response(last_response, last_prompt)
        else
            ask_ai()
        end
    end
end

---Setup function for the plugin
---@param opts table configuration options
---@param opts.model string the Ollama model to use
---@param opts.ollama_url string The Ollama API endpoint
---@param opts.system_prompt string System instructions for LLM
function M.setup(opts)
    opts = opts or {}

    if opts.model then config.model = opts.model end
    if opts.ollama_url then config.ollama_url = opts.ollama_url end
    if opts.system_prompt then config.system_prompt = opts.system_prompt end

    -- Register keybindings
    vim.keymap.set({'n', 'x'}, '<leader>t', toggle_window, 
        { desc = 'Asks ai and toggle AI window' })
    vim.keymap.set({'n', 'x'}, '<leader>tt', function()
        if cancel_query() then
            vim.notify("🐱 Query cancelled!", vim.log.levels.INFO, { timeout = 1000})
        else
            vim.notify("🐱 Nothing to cancel", vim.log.levels.INFO, { timeout = 500})
        end
    end, { desc = 'Cancel AI query' })

    vim.cmd('echo "🐱 askcat loaded: <leader>t to ask, <leader>tt to cancel"')
end

return M
