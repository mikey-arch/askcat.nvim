# askcat.nvim 

A lightweight AI assistant plugin for Neovim that integrates with Ollama.

## Features
- Query AI directly from Neovim
- Visual mode support for selected text
- Floating window responses  
- Cancel ongoing queries
- Support for remote Ollama instances

## Requirements
- Ollama running locally or remotely
- curl

## Installation

### Using lazy.nvim
```lua
{
  "mikey-arch/askcat.nvim",
  config = function()
    require("askcat").setup({
      model = "llama3.2:3b",
      ollama_url = "http://localhost:11434/api/generate",
    })
  end,
}
```

## Usage

- <leader>t - Ask AI / Toggle response window
- <leader>tt - Cancel current query
Select text in visual mode and press <leader>t to query about selection.

## Configuration

```lua
luarequire("askcat").setup({
  model = "deepseek-r1:8b",  -- Your preferred model
  ollama_url = "http://localhost:11434/api/generate",
  system_prompt = "Custom instructions here"
})
```
