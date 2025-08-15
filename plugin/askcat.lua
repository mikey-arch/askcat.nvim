-- Lazy.nvim plugin specs
return {
    name = "ai-assistant",
    dir = vim.fn.stdpath("config") .. "/lua/plugins",  
    lazy = false,
    -- Example config - should customise this
    config = function ()
        require("askcat").setup({
            -- model = "qwen2.5:7b",       -- Example: Use Qwen 2.5
            -- model = "llama3.2:3b",         -- Example: use Llama 3.2 3B
            model = "deepseek-r1:8b",

            --for local Ollama instance
            --ollama_url = "http://localhost:11434/api/generate",

            -- For remote Ollama instance (e.g., via Tailscale)
            -- ollama_url = "http://your-remote-ip:11434/api/generate",

            -- optional: add system instrucs
            system_prompt = 
                [[
You are a helpful coding and fast question assistant.
Provide only the final answer without showing your reasoning process.
Be direct, concise and quick.
Provide working code with brief comments when asked for code.
]]
        })
    end,
}

