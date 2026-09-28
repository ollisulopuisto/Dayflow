# Brief: batch Dayflow's analysis for the home Mac Studio

Written 2026-09-29 for a new agent. Local fork of JerryZLiu/Dayflow (MIT) in
~/Documents/koodi/dayflow, branch `koti-batching`. Don't push anywhere unless the user asks.

## Goal
Dayflow (on the user's MacBook) records the screen and sends frames to a vision LLM for
timeline analysis. The model is the household's Gemma 4 26B on the Mac Studio, not a
cloud API. Analysis should run **in batches at times the Mac Studio's GPU is free**, not
continuously - the model is big, cold-loads in ~20-30 s and shares one GPU.

## The endpoint
- OpenAI-compatible llama-swap on the Mac Studio: `http://192.168.1.222:8000/v1` at home,
  `http://mac-studio.narwhal-tyrannosaurus.ts.net:8000/v1` over Tailscale.
- Model id **`gemma4-vision`**: Gemma 4 26B-A4B (household mixed quant, 12.2 GB) + vision
  projector. Unloads after 300 s idle; first request after that pays the cold load.
  Thinking off: send `chat_template_kwargs: {enable_thinking: false}`.
- Dayflow's "Custom model" engine: Base URL as above, Model ID `gemma4-vision`, no key.

## Hard constraints (the Mac Studio's owner)
- **01:00-07:00 Helsinki is Narmo's and Paikallislehti's window** on the same model
  (gpu-queue admits them). Dayflow must not send work then.
- **One GPU job at a time**: model training on the Mac Studio crashes Metal if the 26B is
  loaded at the same time. Batches should be short and schedulable.
- Screens stay in the home network / tailnet: no cloud fallback for analysis.
- An admission-control proxy already exists: gpu-queue
  (`~/Library/Application Support/gpu-queue/`, config.json; the port identifies the
  client, with weights and allowed hours). A Dayflow client port (e.g. 8103, hours
  07:00-01:00) is the natural way to queue fairly - ask the user before changing it.

## Where to look in Dayflow
`Dayflow/Dayflow/Core/AI/`: LocalEngine.swift, OllamaProvider+Transcription.swift,
LocalEndpointUtilities.swift; tests in Dayflow/DayflowTests/ (OpenAICompatibleConfigurationTests).
Find how often it calls the model, how many frames per call, and whether it can defer and
catch up (a queue of unanalysed chunks processed in a window) instead of calling live.
