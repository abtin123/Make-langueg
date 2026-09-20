# AbtinMaps — Free Multi-Engine Language Builder

This version removes Google/Azure API keys and paid-provider configuration.

## Online free/public engines

The builder can use these concurrently with automatic failover:

- Google GTX public endpoint
- MyMemory anonymous translation endpoint
- Multiple public Lingva instances
- Public Argos/LibreTranslate instance

Lingva exposes public REST APIs without authentication, while Argos Translate is
open-source and can also run locally. Public services can change availability
or impose their own limits, so the builder treats them as disposable workers
rather than assuming unlimited capacity.

## Offline fallback

`ARGOS_LOCAL=1` is enabled by default. If `argostranslate` and the required
language models are installed in the runner, translation can continue without
internet access.

## Speed / concurrency

Default translation workers: `18`.

Each public provider has its own small rate limiter. Increasing workers does
not bypass a provider's limits; it increases useful parallelism across
independent providers/instances. The persistent cache remains the main
protection against repeated requests.

## Optional environment variables

```text
TRANSLATION_WORKERS=18
PROVIDER_MAX_ATTEMPTS=3
PROVIDER_INTERVAL=0.20
FREE_TRANSLATION_PROVIDERS=google,mymemory,lingva,argos
ARGOS_LOCAL=1
```

Optional public Lingva instances can be replaced with a semicolon-separated
list via `LINGVA_INSTANCES`.

No API keys are required and no Azure configuration is required.

## Important

This is deliberately fail-soft: a 429/5xx/timeout on one public engine does
not fail the language pack immediately. It rotates to another engine/instance.
A language pack is still written only after every source key has a translation
and the key set has been validated.


## CI fix in this revision

The previous generated script failed immediately with:

`NameError: name 'load_json' is not defined`

The current `generate_languages.py` is self-contained and restores all required
helpers (`load_json`, cache I/O, ABL writer, token protection/validation, hash
generation, and response parsing). No API keys are required.
