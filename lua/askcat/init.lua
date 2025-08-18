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
    api_url = "http://localhost:11434/api/generate",
    api_key = nil,
    system_prompt = ""
}

--- Detect API provider from URL
---@param url string the API URL
---@return string The deteced provider type
local function detect_api_type(url)
    if url:match("generativelanguage%.googleapis%.com") then
        return "gemini"
    else
        return "ollama"
    end
end

--- Build request payload for different providers
---@param prompt string The user prompt
---@param api_type string The API provider type
---@return table The request payload
local function build_request_payload(prompt, api_type)
    local full_prompt = ""
    if config.system_prompt and config.system_prompt ~= "" then
        full_prompt = config.system_prompt .. "\n\n" .. prompt
    else
        full_prompt = prompt
    end

    if api_type == "gemini" then
        return {
            contents = {
                {
                    parts = {
                        { text = full_prompt }
                    }
                }
            },
            generationConfig = {
                temperature = 0.7,
                maxOutputTokens = 1000
            }
        }
    else -- ollama
        return {
            model = config.model,
            prompt = full_prompt,
            stream = false
        }
    end
end

--- Build curl command for different providers
---@param payload table The request payload
---@param api_type string The API provider type
---@return table The curl command array
local function build_curl_command(payload, api_type)
    local cmd = {'curl', '-X', 'POST'}
    
    if api_type == "gemini" then
        local url = config.api_url
        if not url:match("key=") then
            url = url .. "?key=" .. (config.api_key or "")
        end
        table.insert(cmd, url)
        table.insert(cmd, '-H')
        table.insert(cmd, 'Content-Type: application/json')
        
    else -- ollama
        table.insert(cmd, config.api_url)
        table.insert(cmd, '-H')
        table.insert(cmd, 'Content-Type: application/json')
    end
    
    table.insert(cmd, '-d')
    table.insert(cmd, vim.json.encode(payload))
    
    return cmd
end

--- Parse response from different providers
---@param response_text string The raw response
---@param api_type string The API provider type
---@return string|nil The extracted text response
local function parse_response(response_text, api_type)
    local success, response = pcall(vim.json.decode, response_text)
    if not success then
        return nil
    end

    if api_type == "gemini" then
        if response.candidates and response.candidates[1] and 
           response.candidates[1].content and response.candidates[1].content.parts and
           response.candidates[1].content.parts[1] then
            return response.candidates[1].content.parts[1].text
        end
        
    else -- ollama
        if response.response then
            return response.response
        end
    end
    
    return nil
end

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

--- query API with a prompt
---@param prompt string The user's prompt
---@param callback function Callback to handle the response
local function query_ai(prompt, callback)
    --cancel any existing query first
    if current_job then
        cancel_query()
        vim.wait(100)
    end

    current_prompt_display = prompt

    local api_type = detect_api_type(config.api_url)
    local payload = build_request_payload(prompt, api_type)
    local cmd = build_curl_command(payload, api_type)

    current_job = vim.system(cmd, { text = true }, function(result)
        -- Check if the job was cancelled 
        if not current_job then
            return
        end

        current_job = nil
        current_prompt_display = nil

        if result.code == 0 then
        local response_text = parse_response(result.stdout, api_type)
            if response_text then
                -- Filter out <think>...</think> tags if present
                local filtered_response = response_text:gsub("<think>.-</think>%s*", "")
                filtered_response = vim.trim(filtered_response)
                callback(nil, filtered_response, prompt)
            else
                callback("Error: Failed to parse " .. api_type .. " response", nil, prompt)
            end
        elseif result.signal == 9 or result.signal == 15 or result.code == 143 then
            -- Process was killed, don't show error
            return
        else
            local error_msg = result.stderr or "Unknown error"
            -- Try to parse error for better messages
            local success, error_response = pcall(vim.json.decode, result.stdout or "")
            if success and error_response.error then
                if type(error_response.error) == "table" and error_response.error.message then
                    error_msg = error_response.error.message
                elseif type(error_response.error) == "string" then
                    error_msg = error_response.error
                end
            end
            callback("Error: " .. error_msg, nil, prompt)
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

    query_ai(prompt, function(err,resp,original_prompt)
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
---@param opts.model string the model to use
---@param opts.api_url string the API endpint
---@param opts.api_key string API key (can also be set via env var)
---@param opts.system_prompt string System instructions for LLM
function M.setup(opts)
    opts = opts or {}

    if opts.model then config.model = opts.model end
    if opts.api_url then config.api_url = opts.api_url end
    if opts.ollama_url then config.api_url = opts.ollama_url end 
    if opts.api_key then config.api_key = opts.api_key end
    if opts.system_prompt then config.system_prompt = opts.system_prompt end

    -- Auto-detect API key from environment if not provided
    if not config.api_key then
        local api_type = detect_api_type(config.api_url)
        if api_type == "gemini" then
            config.api_key = os.getenv("GEMINI_API_KEY")
        end
    end

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

    local api_type = detect_api_type(config.api_url)
    vim.cmd('echo "🐱 askcat loaded (' .. api_type .. '): <leader>t to ask, <leader>tt to cancel"')
end

return M
