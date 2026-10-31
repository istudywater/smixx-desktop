# Contributing

Keep Smixx Desktop focused on five interchangeable sources and four mixes for teaching/video calls. Discuss changes to control scope or audio architecture before broad rewrites. Do not add bundled third-party drivers.

Run `scripts/test.sh` and `scripts/build-app.sh`. Changes to audio adapters require actual-device verification as well as deterministic tests. Include source/output identifiers, OS/app versions, sample rates, callback sizes, reproduction steps, and limitations. Never claim a meter proves an active call or successful recording. See `docs/VERIFICATION.md` for pending hardware checks.

Audio callbacks must not perform allocation, file I/O, UI work, or blocking synchronization. Persisted state needs validation and atomic writes. Preserve disconnected assignments and user mute states. Report unavailable capabilities rather than showing simulated audio as real.
