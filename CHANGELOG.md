# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.1.1] - 2026-02-13

### Updated

- **Cloud Models Documentation**
  - Expanded cloud model listings from 6 to 26 models across README, Cloud API guide, and Ollama Setup guide
  - Added new models: `minimax-m2.5:cloud`, `glm-5:cloud`, `deepseek-v3.2:cloud`, `gemini-3-flash-preview:cloud`, `kimi-k2.5:cloud`, `devstral-2:123b-cloud`, `devstral-small-2:24b-cloud`, `cogito-2.1:671b-cloud`, `qwen3-coder-next:cloud`, `qwen3-next:80b-cloud`, `nemotron-3-nano:30b-cloud`, `qwen3-vl:235b-cloud`, `ministral-3:cloud`, `rnj-1:8b-cloud`, `glm-4.6:cloud`, `glm-4.7:cloud`, `minimax-m2:cloud`, `minimax-m2.1:cloud`
  - Added parameters, context window, and feature columns to cloud model table in Cloud API guide
  - Organized README cloud models into categories: Coding & Agentic, General Purpose & Reasoning, Multimodal & Specialized

- **Thinking Mode Documentation**
  - Added `deepseek-v3.1:671b-cloud`, `gemini-3-flash-preview:cloud`, `kimi-k2.5:cloud`, `minimax-m2.5:cloud`, and `nemotron-3-nano:30b-cloud` to compatible thinking models table

## [0.1.0] - 2026-01-08

### Added

- **Core API**
  - `Ollixir.chat/2` - Chat completions with message history
  - `Ollixir.completion/2` / `Ollixir.generate/2` - Text generation
  - `Ollixir.embed/2` - Generate embeddings for text
  - `Ollixir.embeddings/2` - Legacy embeddings API (deprecated)

- **Model Management**
  - `Ollixir.list_models/1` / `Ollixir.list/1` - List available models
  - `Ollixir.show_model/2` / `Ollixir.show/2` - Get model details
  - `Ollixir.list_running/1` / `Ollixir.ps/1` - List running models
  - `Ollixir.create_model/2` / `Ollixir.create/2` - Create custom models
  - `Ollixir.copy_model/2` / `Ollixir.copy/2` - Copy models
  - `Ollixir.delete_model/2` / `Ollixir.delete/2` - Delete models
  - `Ollixir.pull_model/2` / `Ollixir.pull/2` - Pull models from registry
  - `Ollixir.push_model/2` / `Ollixir.push/2` - Push models to registry
  - `Ollixir.preload/2` - Preload model into memory
  - `Ollixir.unload/2` - Unload model from memory

- **Streaming**
  - Enumerable mode (`stream: true`) - Returns lazy stream
  - Process mode (`stream: pid`) - Sends chunks to specified process
  - Full support for chat, completion, and model operations

- **Tool Use (Function Calling)**
  - `Ollixir.Tool.define/2` - Define tools with JSON Schema
  - `Ollixir.Tool.from_function/1` - Convert Elixir functions to tools
  - `Ollixir.Tool.from_mfa/3` - Convert MFA to tool definition
  - Automatic extraction of `@spec` and `@doc` for tool schemas

- **Structured Outputs**
  - JSON format enforcement (`format: "json"`)
  - JSON Schema validation (`format: schema`)
  - Compatible with Ecto changesets for validation

- **Multimodal Support**
  - `Ollixir.Image.encode/1` - Encode images to Base64
  - Automatic encoding of file paths, binaries, and URLs
  - Support for PNG, JPEG, WebP, and GIF formats

- **Typed Responses**
  - `response_format: :struct` option for typed response structs
  - `Ollixir.Types.*` - Response type definitions
  - Application-level default via `:ollixir, :response_format` config

- **Options & Presets**
  - `Ollixir.Options` - Typed inference options struct
  - `Ollixir.Options.Presets` - Pre-configured option sets
    - `creative/0`, `precise/0`, `code/0`, `chat/0`, `fast/0`, `large_context/0`

- **HuggingFace Hub Integration** (optional dependency)
  - `Ollixir.HuggingFace.list_gguf_files/1` - Discover GGUF files
  - `Ollixir.HuggingFace.auto_select/2` - Auto-select optimal quantization
  - `Ollixir.HuggingFace.model_ref/2` - Build Ollama model references
  - `Ollixir.HuggingFace.pull/3` - Pull HuggingFace models
  - `Ollixir.HuggingFace.chat/4` - Chat with HuggingFace models
  - Support for 45K+ GGUF models

- **Cloud API**
  - `Ollixir.web_search/2` - Web search via Ollama API
  - `Ollixir.web_fetch/2` - Fetch web pages via Ollama API
  - `Ollixir.Web.Tools` - Pre-defined tool definitions for web operations

- **Error Handling**
  - `Ollixir.ConnectionError` - Server connection failures
  - `Ollixir.RequestError` - Pre-request validation errors
  - `Ollixir.ResponseError` - API response errors with status codes
  - `Ollixir.Errors.retryable?/1` - Check if error is retryable
  - `Ollixir.Retry` - Retry utilities

- **Client Configuration**
  - URL string, host option, or `Req.Request` struct initialization
  - Environment variable support (`OLLAMA_HOST`, `OLLAMA_API_KEY`)
  - Custom headers and timeout configuration
  - Automatic `/api` suffix handling

- **Documentation**
  - Comprehensive guides for all features
  - 40+ runnable example scripts
  - Cheatsheet for quick reference

[0.1.1]: https://github.com/nshkrdotcom/ollixir/releases/tag/v0.1.1
[0.1.0]: https://github.com/nshkrdotcom/ollixir/releases/tag/v0.1.0
