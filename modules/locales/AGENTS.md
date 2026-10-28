# Locales module guide

The selector is client-only. It must only call kora_lib's locale API: language
choice belongs in client KVP storage and must never be written to PlayerData or
character persistence.
