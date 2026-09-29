# Dayflow Studio queue

This service keeps completed Dayflow screenshot batches on the always-on Mac Studio. It stores uploads on disk, waits for the configured time window, sends one batch at a time to the GPU queue endpoint, then keeps results until the laptop imports and acknowledges them. It does not call a cloud model.

## Install on the Studio

1. Make this folder available on the Studio (clone the fork or copy `server.py`). Install Python 3.9 or newer. The service uses only the Python standard library.
2. Confirm the GPU queue has a Dayflow client endpoint and that it points to the local llama-swap endpoint. Do not point `DAYFLOW_GPU_URL` directly at llama-swap if that would bypass `gpu-queue` admission control. This app does not edit the existing `gpu-queue` configuration.
3. Copy `com.dayflow.studio-queue.plist.template` to `~/Library/LaunchAgents/com.dayflow.studio-queue.plist`. Set the absolute script path and log paths in the plist. Set `DAYFLOW_GPU_URL` to the actual Dayflow client URL from `gpu-queue` (the template uses port 8103 as an example).
4. Generate a shared token with `openssl rand -hex 32`. Put it in the plist's `DAYFLOW_QUEUE_TOKEN` and in Dayflow's Storage settings. Keep the plist private (`chmod 600`). The server refuses to start without a token.
5. Set the GPU endpoint, token and service URL, then load the LaunchAgent:

   ```sh
   mkdir -p ~/Library/LaunchAgents ~/Library/Logs
   chmod 600 ~/Library/LaunchAgents/com.dayflow.studio-queue.plist
   launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.dayflow.studio-queue.plist
   ```

6. Allow inbound TCP port 8765 only from the laptop on the home network or tailnet. The service uses HTTP; use the tailnet for encrypted transport when away from home. Do not expose this port to the public internet.

The template processes from **07:00 until 01:00 Helsinki time**, leaving 01:00–07:00 for Narmo and Paikallislehti. The laptop also sends this window with each batch, and the Studio worker waits through excluded hours. Set these values in Dayflow's Storage settings. To change the Studio defaults for recovery or health reporting, edit `DAYFLOW_WINDOW_START` and `DAYFLOW_WINDOW_END` in the plist.

The queue is stored under `~/Library/Application Support/dayflow-studio-queue/`. Pending uploads, active work, completed results and exhausted failures are separated into folders. Back up or remove this directory according to your local data retention preferences. The server retries failed model calls up to five times.

## Configure Dayflow on the laptop

Open **Settings → Storage → Studio batch processing**:

- Studio queue URL: `http://<studio-tailnet-name>:8765` (or the Studio's LAN address at home).
- Shared token: the same token as the LaunchAgent.
- Start/stop: `07:00` and `01:00`, in Helsinki time.
- Batch duration: choose 5–60 minutes; the default is 15 minutes.

With a queue URL set, completed batches upload automatically. Uploads that are interrupted by sleep remain pending locally and retry when Dayflow runs again. The Studio can process while the laptop sleeps. Results import the next time Dayflow is awake. Leave the URL empty to use Dayflow's normal local provider.

The app samples at most 15 evenly spaced frames from each batch and sends resized JPEG copies. Original screenshots stay in the laptop's recording database. Batches shorter than Dayflow's existing five-minute minimum and locally recognized idle periods do not use the model.

Check service health from the laptop or Studio with:

```sh
curl -H "Authorization: Bearer YOUR_TOKEN" http://<studio>:8765/health
```

Logs are written to the two paths in the LaunchAgent plist. `launchctl print gui/$(id -u)/com.dayflow.studio-queue` shows service state.

## Limits

The Studio makes timeline cards directly from the sampled frames. It currently does not run Dayflow's local observation/transcription, distraction extraction, or timelapse pipeline for remotely analyzed batches. If the model or GPU queue endpoint is unavailable, the worker retries; after five failed calls the job is placed in `failed/` for inspection. Reprocess that batch in Dayflow to enqueue it again after correcting the issue.
