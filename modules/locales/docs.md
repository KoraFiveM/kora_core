# Locales module

`Core.locales.openSelector()` opens the player's language selector. It is also
available through `/language`. The selected code is written to kora_lib client KVP
storage, so changing or creating a character does not alter it.

Server owners configure the client-readable default with `setr qb_locale "en"`
and choices with `setr qb_locales "en,de"`.
