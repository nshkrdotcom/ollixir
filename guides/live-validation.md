# Live release validation

Ollixir 0.2.0 targets **Ollama 0.40.18**. The standard ExUnit suite checks request
and response behavior with controlled servers. The live workflow below checks
that the same client works with real models, runners, and accounts. A failure
in a live profile exits nonzero and lists the checks that failed. A profile
you did not run stays unverified.

## Start here

From the repository root on Linux x86-64, run:

```sh
examples/live/live.sh doctor
```

This shows the GPU, free VRAM and disk, and server versions on ports 11434 and
41434. An existing server on **11434** can stay up. The release workflow uses **41434**
and stores the server bundle, model files, account key files, and results under
`tmp/ollixir-live/`. Keep that directory private if you sign in.

You need Elixir/Mix and standard Linux userland utilities, including `curl`,
GNU tar, `zstd`, and `sha256sum`. An NVIDIA driver must expose the GPU to the
server. Allow **at least 35 GB of free disk** for the extracted bundle, model
fixtures and temporary files. Check free VRAM before inference. The workflow
loads one model at a time with a 4K default context and one parallel request.
GPU offload still depends on the runner, quantization, and free VRAM. Use
`nvidia-smi` or the server log to verify offload during inference. [Ollama hardware support](https://docs.ollama.com/gpu)

### Terminal 1

```sh
examples/live/live.sh setup
examples/live/live.sh serve
```

`setup` downloads the official Linux amd64 release bundle and verifies its
pinned SHA-256 before extraction. The download is about 1.65 GB. The full bundle
includes the runner files needed by the server. The script uses no system
installation or service manager. Leave `serve` in the foreground. Stop it
with Ctrl+C when finished. [Ollama v0.40.18 release](https://github.com/ollama/ollama/releases/tag/v0.40.18)

### Terminal 2

```sh
mix deps.get
examples/live/live.sh mock
examples/live/live.sh registry
examples/live/live.sh models
examples/live/live.sh check
```

Run `registry` before `models` on a fresh store to exercise an actual download
through Ollixir. Repeating it against a populated store checks the cached path.
`models` pulls missing fixtures and stops on the first failed pull. Every live
profile verifies the isolated process and server version before sending requests.
`check` exercises local APIs. It makes no credentialed calls and does not fetch
model weights. It creates randomly named disposable models and cleans up their
tags. The isolated store can retain uploaded or cached blobs.

| Check | Default fixture and expected evidence |
| --- | --- |
| Native generate/chat, thinking, tools, JSON, preload/unload | [qwen3:4b](https://ollama.com/library/qwen3:4b). Nonempty output, completed native streams, a tool call and result history, JSON output, and model presence in `ps`. |
| Fill-in-the-middle | [codegemma:2b](https://ollama.com/library/codegemma:2b). Generation with a supplied code suffix. |
| Embeddings and registry pull | [nomic-embed-text](https://ollama.com/library/nomic-embed-text). Terminal pull success, native vectors, legacy embeddings, and OpenAI base64 output. |
| Vision | [gemma3:4b](https://ollama.com/library/gemma3:4b) and the repository image. Native image chat. |
| System One | [nimble](https://ollama.com/library/nimble) for ordered choice, noul, and score. [clef-flash](https://ollama.com/library/clef-flash) for an image question. Answer shape and token usage are checked. |
| Mixed embedding | [embeddinggemma-2:740m-q8_0](https://ollama.com/library/embeddinggemma-2:740m-q8_0) is a candidate with the audio and vision encoders. It must return three vectors from one text/image/audio request. A tag that serves only text/image on this runner leaves mixed audio coverage open. |
| Speech and audio input | [lfm3-audio:2b-q4_K_M](https://ollama.com/library/lfm3-audio:2b-q4_K_M) exercises speech in English and French, transcription, and translation. The GGUF tag was pulled on Linux and uses the llama.cpp runner. Check WAV/PCM, transcript text and segments, and the final SSE event. |
| Provider compatibility | The text model exercises OpenAI models, chat, completions, embeddings, Responses, and compact, plus Anthropic Messages. Stream checks require the relevant protocol terminal. |
| Model management and account errors | Disposable blob and model management, typed manifests, server discovery, missing-model errors, and cloud-disabled identity. |

Each profile writes its console output under `tmp/ollixir-live/results/`. Check
`inventory.json` there for the model tags and digests used. Tags can change independently of the pinned server. A model override
should match the row's capability and log its actual digest. The defaults are
documented candidates awaiting this live run. To change a fixture, use the
same variable for `models` and `check`. For example:

```sh
export LIVE_TEXT=qwen3:4b
examples/live/live.sh models
examples/live/live.sh check
```

Other overrides are `LIVE_EMBED`, `LIVE_VISION`, `LIVE_FIM`, `LIVE_DECISION`,
`LIVE_DECISION_IMAGE`, `LIVE_MULTIMODAL`, `LIVE_ASR`, `LIVE_SPEECH`, and
`LIVE_SPEECH_FR`. The speech defaults reuse the ASR model and select voices
with `LIVE_SPEECH_VOICE` and `LIVE_SPEECH_FR_VOICE`. `LIVE_IMAGE` selects an
alternate image. The speech check writes `speech-english.wav` and
`speech-french.wav` for listening and as fallback input fixtures.

For independent input fixtures, run `examples/live/live.sh fixtures` if
`espeak-ng` is installed. Alternatively, set `LIVE_ENGLISH_WAV` and
`LIVE_FRENCH_WAV` to short recordings of “The capital of France is Paris”
and “La capitale de la France est Paris”. Explicit recordings take precedence
over eSpeak recordings and synthesized fallback samples. This lets
transcription, translation and mixed embeddings run even when speech fails.

## Hosted, Hugging Face and push checks

Run the HF profile while the isolated local server is running. It explicitly
downloads one small 1B GGUF and checks chat and generate. Allow bandwidth and
disk space for that fixture.

```sh
examples/live/live.sh hf
```

For the cloud profile, stop `serve` and start the same isolated server in the
foreground with cloud enabled:

```sh
examples/live/live.sh serve-cloud
```

Then, from the other terminal, sign into that isolated server and provide your
hosted key to the shell without writing it into history:

```sh
examples/live/live.sh signin
read -rsp 'Ollama API key: ' OLLAMA_API_KEY; echo
export OLLAMA_API_KEY
examples/live/live.sh cloud
unset OLLAMA_API_KEY
```

This checks signed-in identity, quota, recommendations, local proxy search/fetch,
and direct hosted search/fetch. A plan or authorization error leaves the
affected check open. Signout and the legacy disconnect alias remain mock-only.

Only run `push` with permission to write a **fresh, disposable public Ollama
registry tag** under an account you control. It copies the text model to the
selected local tag, uploads it, verifies terminal success, and removes the
local tag. Delete the remote artifact yourself if the registry permits it.
Use a known-unused remote tag because a push can update an existing one.

```sh
LIVE_PUSH_TARGET=my-namespace/ollixir-audit-nov25:trial examples/live/live.sh push
```

## Review before publishing

Record the source SHA, server version, fixture digests, GPU offload, and result
of each profile. Keep failure/skip reasons and distinguish a real transfer from
a cached one. The live runner exercises common end-to-end paths. Transport
adversarial cases, account mutation, parser edge cases, and unsupported runner
combinations remain covered by the applicable mocks and source audit. Use the
[individual examples](../examples/README.md) to inspect a scenario manually.

Run the affected checks again after code or fixture changes. For sign-off:

1. Run `examples/live/live.sh mock` and `examples/live/live.sh check`. Record
   the registry pull and any applicable HF, cloud, or authorized push results.
2. Push the chosen release commit and verify that all GitHub CI matrix jobs
   pass for that SHA.
3. From the repository root, confirm the working tree is clean and HEAD
   matches the SHA verified by CI. Build and inspect the artifacts:

   ```sh
   mix deps.get
   mix format --check-formatted
   mix compile --warnings-as-errors
   mix dialyzer
   mix docs
   mkdir -p tmp
   mix hex.build -o tmp/ollixir-0.2.0.tar
   tar -tf tmp/ollixir-0.2.0.tar
   tar -xOf tmp/ollixir-0.2.0.tar contents.tar.gz | tar -tzf -
   sha256sum tmp/ollixir-0.2.0.tar
   ```

4. Confirm the version is available on Hex and there is no existing local or
   remote `v0.2.0` tag. Publish manually with `mix hex.publish` from the
   repository root. Tag the exact release commit after confirming publication.

The package digest applies to the exact artifact you inspected. Rebuild it
after any change to package contents.
