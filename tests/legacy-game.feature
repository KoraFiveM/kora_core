# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_core — game tests

  @kora_core @legacy:core-lang-cmd @target:3
  Scenario: Language menu opens with /language
    """
    1. Type /language in chat.
    Expect: a menu titled "Language" lists languages (English, Deutsch, Francais and so on) and marks your current one with "Current language".
    """
    When I run the command "/language"
    Then a menu titled "Language" opens
    And I confirm: the menu lists languages such as English, Deutsch and Francais
    And I confirm: my current language is marked "Current language"

  @kora_core @legacy:core-lang-pick @target:3 @checklist @checklist:kora_core:language-command @cat:core-and-libraries
  Scenario: Pick a language
    """
    1. Run /language.
    2. Choose Deutsch (or any other language).
    Expect: a success notification says "Language set to Deutsch." and the menu closes. Run /language again: the new language now shows "Current language".
    Also checklist kora_core:language-command (Language selector (/language)): Run /language to open the language menu, pick a language and confirm the "Language set" notify.
    """
    When I run the command "/language"
    And I manually: choose Deutsch in the menu
    Then I should see a notification containing "Language set to Deutsch."
    And I should see a success notification
    And I confirm: the language menu closes
    When I run the command "/language"
    Then I confirm: Deutsch is now marked "Current language"

  @kora_core @legacy:core-lang-cancel @target:3
  Scenario: Close language menu without choosing
    """
    1. Run /language.
    2. Press Escape to close it.
    Expect: the menu closes, no notification appears and your language is unchanged.
    """
    When I run the command "/language"
    And I press the "Escape" key
    Then I confirm: the language menu closes
    And I confirm: no notification appears
    And I confirm: my language is unchanged

  @kora_core @legacy:core-lang-keybind @target:3 @checklist @checklist:kora_core:language-keybind @cat:core-and-libraries @manual
  Scenario: Language menu key binding exists
    """
    1. Open Settings > Key Bindings > FiveM.
    2. Find "Open language selector" (it has no default key).
    3. Bind a key, close settings, press it once.
    Expect: the language menu opens once per key press. Without a bound key nothing happens.
    Also checklist kora_core:language-keybind (Language selector key (F10)): Press F10 (rebindable in Settings > Key Bindings > FiveM) and confirm the language menu opens once per press.
    """
    When I manually: open Settings > Key Bindings > FiveM
    And I manually: find "Open language selector" and bind a key to it
    And I manually: close settings and press the bound key once
    Then I confirm: the language menu opens once per key press
    And I confirm: without a bound key nothing happens

  @kora_core @legacy:core-lang-persist @target:3
  Scenario: Language survives reconnect
    """
    1. Set a non-English language with /language.
    2. Disconnect and reconnect.
    3. Run /language.
    Expect: your chosen language is still marked "Current language".
    """
    When I run the command "/language"
    And I manually: choose a non-English language
    And I manually: disconnect and reconnect to the server
    And I run the command "/language"
    Then I confirm: my chosen language is still marked "Current language"

  @kora_core @legacy:core-pause-title @target:3 @checklist @checklist:kora_core:pause-menu-title @cat:core-and-libraries
  Scenario: Server name in pause menu
    """
    1. Press Escape to open the pause menu.
    2. Look at the title in the top header.
    Expect: the title shows the server name set in Config.server.name (default "Roleplay Server Name") instead of the stock GTA Online title.
    Also checklist kora_core:pause-menu-title (Server name in pause menu): Open the pause menu and confirm the title shows the configured Config.server.name.
    """
    When I press the "Escape" key
    And I manually: look at the title in the top header of the pause menu
    Then I confirm: the title shows the server name from Config.server.name (default "Roleplay Server Name") instead of the stock GTA Online title

  @kora_core @legacy:core-new-char-money @target:3
  Scenario: New character starting money
    """
    1. Create a brand new character and spawn in.
    2. Check your cash and bank (inventory and bank app).
    Expect: starting balances are cash 500, bank 5000, crypto 0.
    """
    When I manually: create a brand new character and spawn in
    And I open my inventory
    Then my cash balance should be 500
    And my bank balance should be 5000
    And my crypto balance should be 0
    And I confirm: the bank app shows bank 5000 and crypto 0

  @kora_core @legacy:core-new-char-job @target:3
  Scenario: New character starts unemployed
    """
    1. On a brand new character run /job.
    2. Run /gang.
    Expect: /job shows "Job: Civilian | Grade: Freelancer | Duty: true" and /gang shows "Gang: No Gang | Grade: None".
    """
    When I manually: create a brand new character and spawn in
    And I run the command "/job"
    Then I confirm: /job shows "Job: Civilian | Grade: Freelancer | Duty: true"
    When I run the command "/gang"
    Then I confirm: /gang shows "Gang: No Gang | Grade: None"

  @kora_core @legacy:core-new-char-needs @target:3
  Scenario: New character needs full
    """
    1. Spawn a brand new character.
    2. Open the HUD or your status display and read hunger and thirst.
    Expect: hunger and thirst start at 100 and stress at 0.
    """
    When I manually: spawn a brand new character
    Then my metadata "hunger" should be "100"
    And my metadata "thirst" should be "100"
    And my metadata "stress" should be "0"
    And I confirm: the HUD or status display shows hunger and thirst at 100 and stress at 0

  @kora_core @legacy:core-cmd-nonadmin @target:3
  Scenario: Admin commands refused for normal players
    """
    1. As a normal non-admin player run /car adder.
    2. Also try /tp 1, /dv and /givemoney 1 cash 100.
    Expect: each command is refused (nothing spawns, teleports or changes and no money is given). Where a message appears it reads "You do not have permission to use this command." or the command is not offered in chat.
    """
    When I run the command "/car"
    And I manually: type /car adder as a normal non-admin player
    And I manually: also run /tp 1, /dv and /givemoney 1 cash 100
    Then I confirm: each command is refused and nothing spawns, teleports or changes
    And I confirm: no money is given
    And I confirm: any message reads "You do not have permission to use this command." or the command is not offered in chat

  @kora_core @legacy:core-cmd-suggest @target:3 @needs:admin @manual
  Scenario: Chat suggestions for stock commands
    """
    1. Type / in chat and scroll the suggestions as an admin.
    2. Look for car, dv, setjob, givemoney, ooc, me.
    Expect: the stock commands are listed with help text such as "Spawn Vehicle (Admin Only)" and "Check Your Job", with argument names like id, model, moneytype.
    """
    When I manually: as an admin type / in chat and scroll the suggestions
    And I manually: look for car, dv, setjob, givemoney, ooc and me
    Then I confirm: the stock commands are listed with help text such as "Spawn Vehicle (Admin Only)" and "Check Your Job"
    And I confirm: the suggestions show argument names like id, model and moneytype

  @kora_core @legacy:core-tp-player @target:3 @needs:admin @manual
  Scenario: /tp to a player id
    """
    1. As admin, with a second player online, run /tp <their id>.
    Expect: you are teleported to that player.
    """
    When I manually: ask a second player to be online and tell me their id
    And I manually: as admin run /tp with their id
    Then I confirm: I am teleported to that player

  @kora_core @legacy:core-tp-coords @target:3 @needs:admin
  Scenario: /tp to coordinates
    """
    1. As admin run /tp 200 -900 30.
    Expect: you are teleported to roughly those coordinates (near Legion Square).
    """
    When I run the command "/tp 200 -900 30"
    Then I should be within 20 metres of "core_tp_coords"
    And I confirm: I am near Legion Square

  @kora_core @legacy:core-tp-bad @target:3 @needs:admin
  Scenario: /tp bad target
    """
    1. As admin run /tp 9999.
    2. Then run /tp 200 abc 30.
    Expect: the first shows "Player not online", the second shows "Incorrect format". You do not move.
    """
    When I run the command "/tp 9999"
    Then I should see a notification containing "Player not online"
    When I run the command "/tp 200 abc 30"
    Then I should see a notification containing "Incorrect format"
    And I confirm: I do not move

  @kora_core @legacy:core-tp-partial @target:3 @needs:admin
  Scenario: /tp with only two coordinates
    """
    1. As admin run /tp 200 -900.
    Expect: you see "Not every argument has been entered (x, y, z)" and do not move.
    """
    When I run the command "/tp 200 -900"
    Then I should see a notification containing "Not every argument has been entered (x, y, z)"
    And I confirm: I do not move

  @kora_core @legacy:core-tpm @target:3 @needs:admin
  Scenario: /tpm to waypoint
    """
    1. Set a waypoint on the map.
    2. As admin run /tpm.
    Expect: you are teleported to the waypoint and placed on the ground.
    """
    When I manually: set a waypoint on the map
    And I run the command "/tpm"
    Then I should see a notification containing "Teleported to waypoint"
    And I confirm: I am teleported to the waypoint and placed on the ground

  @kora_core @legacy:core-pvp-toggle @target:3 @needs:admin
  Scenario: /togglepvp message
    """
    1. As admin run /togglepvp.
    2. Run it again.
    Expect: first call shows "PVP disabled", second shows "PVP enabled". Both are success notifications.
    """
    When I run the command "/togglepvp"
    Then I should see a notification containing "PVP disabled"
    And I should see a success notification
    When I run the command "/togglepvp"
    Then I should see a notification containing "PVP enabled"
    And I should see a success notification

  @kora_core @legacy:core-pvp-off-damage @target:3 @needs:admin
  Scenario: PVP off stops player damage
    """
    1. As admin run /togglepvp until it says "PVP disabled".
    2. Have a second player shoot or punch another player.
    Expect: friendly player damage is blocked while PVP is disabled, and works again after /togglepvp says "PVP enabled".
    """
    When I run the command "/togglepvp"
    And I manually: run /togglepvp again until it says "PVP disabled"
    And I manually: ask a second player to shoot or punch another player
    Then I confirm: the other player's damage is blocked while PVP is disabled
    When I run the command "/togglepvp"
    Then I should see a notification containing "PVP enabled"
    When I manually: ask a second player to shoot or punch another player again
    Then I confirm: the other player's damage works again

  @kora_core @legacy:core-pvp-join @target:3 @needs:admin
  Scenario: Joining while PVP is off
    """
    1. Run /togglepvp so PVP is disabled.
    2. Have a third player connect and load in.
    3. Try to hurt another player from that new player.
    Expect: the new player also cannot hurt others (the PVP off state is sent to players who join).
    """
    When I run the command "/togglepvp"
    And I manually: make sure PVP is disabled (the message says "PVP disabled")
    And I manually: ask a third player to connect and load in
    And I manually: ask the third player to try to hurt another player
    Then I confirm: the third player cannot hurt others because the PVP off state was sent on join

  @kora_core @legacy:core-perm-add @target:3 @needs:admin @manual
  Scenario: /addpermission
    """
    1. As a god-level player run /addpermission <id> mod.
    2. Then try the same as an admin who is not god.
    Expect: the god-level player can grant it. The admin gets "You do not have permission to use this command."
    """
    When I manually: as a god-level player run /addpermission with a player id and mod
    Then I confirm: the god-level player can grant the permission
    When I manually: ask an admin who is not god to run the same command
    Then I confirm: the other player (the admin) sees "You do not have permission to use this command."

  @kora_core @legacy:core-perm-bad-level @target:3 @needs:admin
  Scenario: /addpermission invalid level
    """
    1. As god run /addpermission <id> superman.
    Expect: it is refused with "Permission must be one of: god, admin, mod".
    """
    When I manually: as god, run /addpermission with a target player id and the level superman
    Then I should see a notification containing "Permission must be one of: god, admin, mod"

  @kora_core @legacy:core-perm-remove @target:3 @needs:admin @manual
  Scenario: /removepermission
    """
    1. As god run /removepermission <id> mod on the player you promoted.
    Expect: the permission is removed; that player is refused on a mod-only action again.
    """
    When I manually: as god, run /removepermission with the id of the promoted player and the level mod
    Then I confirm: the permission is removed from that player
    And I confirm: the other player is refused again on a mod-only action

  @kora_core @legacy:core-server-close @target:3 @needs:admin
  Scenario: /closeserver kicks and blocks
    """
    1. As admin run /closeserver testing.
    2. Watch a non-admin player.
    3. Have the non-admin try to rejoin.
    Expect: you see "The server has been closed"; players without the whitelist permission are kicked with the reason "testing" and cannot connect while closed.
    """
    When I run the command "/closeserver testing"
    Then I should see a notification containing "The server has been closed"
    And I confirm: the other player without the whitelist permission is kicked with the reason "testing"
    When I manually: ask a second player without the whitelist permission to try to rejoin
    Then I confirm: the other player cannot connect while the server is closed

  @kora_core @legacy:core-server-close-noreason @target:3 @needs:admin
  Scenario: /closeserver without reason
    """
    1. As admin run /closeserver with no text.
    2. Have a non-admin try to join.
    Expect: the refusal screen shows the reason "No reason specified".
    """
    When I run the command "/closeserver"
    And I manually: ask a second non-admin player to try to join
    Then I confirm: the other player's refusal screen shows the reason "No reason specified"

  @kora_core @legacy:core-server-open @target:3 @needs:admin
  Scenario: /openserver
    """
    1. After closing, run /openserver as admin.
    2. Have a normal player connect.
    Expect: you see "The server has been opened" and the player can join. Running it again says "The server is already open".
    """
    When I manually: close the server to new connections (the way your admin tools allow)
    And I run the command "/openserver"
    Then I should see a notification containing "The server has been opened"
    When I manually: ask a second normal player to connect to the server
    Then I confirm: the other player can join the server
    When I run the command "/openserver"
    Then I should see a notification containing "The server is already open"

  @kora_core @legacy:core-server-close-twice @target:3 @needs:admin
  Scenario: /closeserver twice
    """
    1. Run /closeserver, then run /closeserver again.
    Expect: the second call says "The server is already closed". Remember to run /openserver afterwards.
    """
    When I run the command "/closeserver"
    And I run the command "/closeserver"
    Then I should see a notification containing "The server is already closed"
    When I run the command "/openserver"

  @kora_core @legacy:core-car-spawn @target:3 @needs:admin
  Scenario: /car spawns and seats you
    """
    1. As admin run /car adder.
    Expect: an Adder appears under you and you are seated in the driver seat.
    """
    When I run the command "/car adder"
    Then I should be in a "adder"
    And I should be in the driver seat

  @kora_core @legacy:core-car-replace @target:3 @needs:admin
  Scenario: /car replaces current vehicle
    """
    1. Sit in a car you spawned with /car asea.
    2. Run /car panto.
    Expect: the Asea is deleted and a Panto spawns with you inside.
    """
    When I run the command "/car asea"
    And I run the command "/car panto"
    Then I confirm: the Asea is deleted
    And I should be in a "panto"
    And I should be in the driver seat

  @kora_core @legacy:core-car-bad-model @target:3 @needs:admin
  Scenario: /car invalid model
    """
    1. Run /car notacar.
    2. Run /car bad-name!.
    Expect: the first reports "Unable to spawn that vehicle" (or nothing spawns), the second "Incorrect format". No vehicle is created.
    """
    When I run the command "/car notacar"
    Then I confirm: it reports "Unable to spawn that vehicle" or nothing spawns
    When I run the command "/car bad-name!"
    Then I should see a notification containing "Incorrect format"
    And I confirm: no vehicle was created by either command

  @kora_core @legacy:core-car-networked @target:3 @needs:admin
  Scenario: /car vehicle is shared
    """
    1. Spawn a car with /car sultan.
    2. Get out and have a second player look at it and drive it.
    Expect: the second player sees the same car and can drive it (it is a real networked vehicle, not local-only).
    """
    When I run the command "/car sultan"
    And I get out of the vehicle
    And I manually: ask a second player to look at the car and drive it
    Then I confirm: the other player sees the same car and can drive it (it is a real networked vehicle)

  @kora_core @legacy:core-car-keys @target:3 @needs:admin
  Scenario: /car grants vehicle keys
    """
    1. Spawn a car with /car asea (needs kora_vehiclekeys running).
    2. Exit, lock the car and try to start it again.
    Expect: you own the keys for the spawned plate and can lock and unlock it.
    """
    When I run the command "/car asea"
    And I get out of the vehicle
    And I lock the vehicle
    Then the vehicle should be locked
    When I get in the vehicle
    And I turn the engine on
    Then the vehicle engine should be running
    When I get out of the vehicle
    And I unlock the vehicle
    Then the vehicle should be unlocked

  @kora_core @legacy:core-dv-occupied @target:3 @needs:admin
  Scenario: /dv deletes your vehicle
    """
    1. Sit in a spawned car.
    2. Run /dv as admin.
    Expect: the car you are in is deleted.
    """
    Given I am in the driver seat of a "sultan"
    When I run the command "/dv"
    Then the vehicle should be deleted

  @kora_core @legacy:core-dv-nearby @target:3 @needs:admin
  Scenario: /dv deletes nearby vehicles
    """
    1. Spawn two cars next to each other, step out, stand within 5 m.
    2. Run /dv.
    Expect: vehicles within about 5 m are deleted; cars farther away are untouched.
    """
    Given a "sultan" is spawned in front of me
    And a "sultan" is spawned in front of me
    When I manually: stand within 5 m of both cars
    And I run the command "/dv"
    Then I confirm: vehicles within about 5 m of me are deleted
    And I confirm: cars farther away are untouched

  @kora_core @legacy:core-dvall @target:3 @needs:admin
  Scenario: /dvall
    """
    1. Park several cars around the map.
    2. As admin run /dvall.
    Expect: a success notification says "Deleted N entities" and all vehicles are gone.
    """
    When I manually: park several cars around the map
    And I run the command "/dvall"
    Then I should see a notification containing "Deleted"
    And I confirm: the notification says "Deleted N entities" and all vehicles are gone

  @kora_core @legacy:core-dvp @target:3 @needs:admin
  Scenario: /dvp deletes peds but not players
    """
    1. Stand in a street with ambient pedestrians (or spawn peds).
    2. Run /dvp with another player nearby.
    Expect: ambient peds disappear and "Deleted N entities" appears. Player characters stay.
    """
    When I manually: stand in a street with ambient pedestrians and ask a second player to stand nearby
    And I run the command "/dvp"
    Then I should see a notification containing "Deleted"
    And I confirm: ambient peds disappear and "Deleted N entities" appears
    And I confirm: player characters stay

  @kora_core @legacy:core-dvo @target:3 @needs:admin
  Scenario: /dvo
    """
    1. Place or find dropped objects/props around.
    2. Run /dvo as admin.
    Expect: a success notification says "Deleted N entities"; server-side objects disappear.
    """
    Given a "bench" prop is spawned in front of me
    When I manually: place or find more dropped objects and props around
    And I run the command "/dvo"
    Then I should see a notification containing "Deleted"
    And I confirm: the notification says "Deleted N entities" and server-side objects disappear

  @kora_core @legacy:core-givemoney-cash @target:3 @needs:admin
  Scenario: /givemoney cash
    """
    1. As admin run /givemoney <id> cash 250.
    2. Open inventory and check cash.
    Expect: the target gains 250 cash, shown as a cash item amount in the inventory.
    """
    When I manually: run /givemoney with the target player id, cash and 250
    And I open my inventory
    Then I confirm: the target gains 250 cash, shown as a cash item amount in the inventory

  @kora_core @legacy:core-givemoney-bank @target:3 @needs:admin @manual
  Scenario: /givemoney bank
    """
    1. Run /givemoney <id> bank 1000.
    2. Check the bank balance.
    Expect: the bank balance rises by 1000 with no tax taken.
    """
    When I manually: run /givemoney with the target player id, bank and 1000
    Then I confirm: the bank balance rises by 1000 with no tax taken

  @kora_core @legacy:core-givemoney-bad-type @target:3 @needs:admin
  Scenario: /givemoney invalid account
    """
    1. Run /givemoney <id> gold 100.
    Expect: it shows "Type of money must be one of: cash, bank, crypto" and no money changes.
    """
    When I manually: run /givemoney with the target player id, gold and 100
    Then I should see a notification containing "Type of money must be one of: cash, bank, crypto"
    And I confirm: no money changes

  @kora_core @legacy:core-givemoney-bad-amount @target:3 @needs:admin
  Scenario: /givemoney invalid amount
    """
    1. Run /givemoney <id> cash abc.
    2. Run /givemoney 9999 cash 100.
    Expect: the first shows "Incorrect format", the second "Player not online". No money changes.
    """
    When I manually: run /givemoney with the target player id, cash and abc
    Then I should see a notification containing "Incorrect format"
    When I run the command "/givemoney 9999 cash 100"
    Then I should see a notification containing "Player not online"
    And I confirm: no money changes

  @kora_core @legacy:core-setmoney @target:3 @needs:admin
  Scenario: /setmoney sets balance
    """
    1. Run /setmoney <id> bank 12345.
    2. Check the bank balance.
    Expect: the bank balance is exactly 12345 (set, not added).
    """
    When I manually: run /setmoney with my own player id, bank and 12345
    Then my bank balance should be 12345

  @kora_core @legacy:core-setmoney-cash @target:3 @needs:admin
  Scenario: /setmoney cash
    """
    1. Run /setmoney <id> cash 700.
    2. Open the inventory.
    Expect: the cash item stack shows exactly 700.
    """
    When I manually: run /setmoney with my own player id, cash and 700
    And I open my inventory
    Then my cash balance should be 700
    And I confirm: the cash item stack in my inventory shows exactly 700

  @kora_core @legacy:core-money-persist @target:3 @needs:admin
  Scenario: Money survives relog
    """
    1. Set bank to 4321 with /setmoney.
    2. Wait a few seconds, disconnect and reconnect to the same character.
    Expect: bank is still 4321.
    """
    When I manually: run /setmoney with my own player id, bank and 4321
    And I wait 5 seconds
    And I manually: disconnect and reconnect to the same character
    Then my bank balance should be 4321

  @kora_core @legacy:core-setjob @target:3 @needs:admin
  Scenario: /setjob and /job
    """
    1. As admin run /setjob <id> police 0.
    2. The target runs /job.
    Expect: /job shows "Job: Law Enforcement | Grade: Cadet | Duty: false" (grade 0 is the first grade).
    """
    When I manually: run /setjob with my own player id, police and 0 (needs admin permission)
    And I run the command "/job"
    Then the chat should show "Job: Law Enforcement | Grade: Cadet | Duty: false"
    And my job should be "police"
    And I confirm: grade 0 is the first grade (Cadet)

  @kora_core @legacy:core-setjob-grades @target:3 @needs:admin
  Scenario: /setjob grade numbers
    """
    1. Run /setjob <id> police 4.
    2. Run /job.
    Expect: the grade reads Chief (grade numbers are zero-based: 0 Cadet, 1 Officer, 2 Sergeant, 3 Lieutenant, 4 Chief).
    """
    When I manually: run /setjob with my own player id, police and 4
    And I run the command "/job"
    Then the chat should show "Chief"
    And my job should be "police" at grade 4

  @kora_core @legacy:core-setjob-bad @target:3 @needs:admin
  Scenario: /setjob invalid input
    """
    1. Run /setjob <id> police -1.
    2. Run /setjob 9999 police 0.
    3. Run /setjob <id> nojob 0.
    Expect: the first shows "Grade must be a whole number of 0 or more", the second "Player not online", the third "Could not set job:" plus a reason. The job is unchanged.
    """
    When I manually: run /setjob with my own player id, police and -1
    Then I confirm: the message "Grade must be a whole number of 0 or more" is shown
    When I run the command "/setjob 9999 police 0"
    Then I confirm: the message "Player not online" is shown
    When I manually: run /setjob with my own player id, nojob and 0
    Then I confirm: a message starting with "Could not set job:" plus a reason is shown
    And I confirm: my job is unchanged

  @kora_core @legacy:core-setjob-case @target:3 @needs:admin
  Scenario: /setjob lowercases the name
    """
    1. Run /setjob <id> POLICE 0.
    Expect: the job is set to Law Enforcement anyway.
    """
    When I manually: run /setjob with my own player id, POLICE and 0
    Then my job should be "police"

  @kora_core @legacy:core-job-persist @target:3 @needs:admin
  Scenario: Job survives relog
    """
    1. Set a job with /setjob.
    2. Reconnect.
    3. Run /job.
    Expect: the same job and grade are shown.
    """
    When I manually: set my job with /setjob using my own player id
    And I manually: disconnect and reconnect
    And I run the command "/job"
    Then I confirm: the same job and grade as before are shown

  @kora_core @legacy:core-setgang @target:3 @needs:admin
  Scenario: /setgang and /gang
    """
    1. Run /setgang <id> ballas 2.
    2. The target runs /gang.
    Expect: /gang shows "Gang: Ballas | Grade: Boss".
    """
    When I manually: run /setgang with my own player id, ballas and 2
    And I run the command "/gang"
    Then the chat should show "Gang: Ballas | Grade: Boss"
    And my gang should be "ballas"

  @kora_core @legacy:core-setgang-none @target:3 @needs:admin
  Scenario: /setgang none clears the gang
    """
    1. Run /setgang <id> none 0.
    2. Run /gang.
    Expect: it shows "Gang: No Gang | Grade: None".
    """
    When I manually: run /setgang with my own player id, none and 0
    And I run the command "/gang"
    Then my gang should be "none"
    And the chat should show "Gang: No Gang | Grade: None"

  @kora_core @legacy:core-setgang-bad @target:3 @needs:admin @manual
  Scenario: /setgang invalid input
    """
    1. Run /setgang <id> ballas 1.5.
    Expect: it shows "Grade must be a whole number of 0 or more" and the gang does not change.
    """
    When I manually: run /setgang with my own player id, ballas and 1.5
    Then I confirm: the message "Grade must be a whole number of 0 or more" is shown
    And I confirm: my gang does not change

  @kora_core @legacy:core-ooc-near @target:3
  Scenario: /ooc nearby
    """
    1. Stand near another player.
    2. Run /ooc hello there.
    Expect: both of you see a chat line "OOC | <your name>" with the text hello there.
    """
    When I manually: ask a second player to stand near me
    And I run the command "/ooc hello there"
    Then the chat should show "hello there"
    And I confirm: the chat line is labelled "OOC | <my name>"
    And I confirm: the other player also sees that chat line

  @kora_core @legacy:core-ooc-far @target:3
  Scenario: /ooc far player
    """
    1. Stand more than 20 m from another normal player.
    2. Run /ooc can you see this.
    Expect: the far normal player sees nothing. An admin who has opted in sees "Proximity OOC | <name>".
    """
    When I manually: ask a second normal player to stay more than 20 m away from me
    And I run the command "/ooc can you see this"
    Then I confirm: the other player (far, normal) sees nothing
    And I confirm: an admin who has opted in sees "Proximity OOC | <name>"

  @kora_core @legacy:core-ooc-empty @target:3
  Scenario: /ooc with no text
    """
    1. Run /ooc with no message.
    Expect: you get an error "All arguments must be filled out!" and no chat line is sent.
    """
    When I run the command "/ooc"
    Then I should see a notification containing "All arguments must be filled out!"
    And I should see an error notification
    And I confirm: no chat line is sent

  @kora_core @legacy:core-me-near @target:3
  Scenario: /me text above head
    """
    1. Stand near another player.
    2. Run /me waves.
    Expect: the text "waves" is drawn in 3D above your character for about 5 seconds, for you and players within 20 m.
    """
    When I manually: ask a second player to stand near me
    And I run the command "/me waves"
    Then I confirm: the text "waves" is drawn in 3D above my character for about 5 seconds
    And I confirm: the other player within 20 m also sees the text

  @kora_core @legacy:core-me-far @target:3
  Scenario: /me far player
    """
    1. Be more than 20 m from another player and run /me far away.
    Expect: the far player does not see the 3D text.
    """
    When I manually: ask a second player to stay more than 20 m away from me
    And I run the command "/me far away"
    Then I confirm: the far player does not see the 3D text

  @kora_core @legacy:core-me-empty @target:3
  Scenario: /me with no text
    """
    1. Run /me with no message.
    Expect: you get an error "All arguments must be filled out!".
    """
    When I run the command "/me"
    Then I should see a notification containing "All arguments must be filled out!"
    And I should see an error notification

  @kora_core @legacy:core-jail @target:3 @needs:admin
  Scenario: /jail
    """
    1. As admin run /jail <id> 2 testing.
    Expect: the target is teleported to the Bolingbroke prison yard and sees "You have been jailed for 2 minutes."
    """
    When I manually: run /jail with my own player id, 2 and testing
    Then I should be within 20 metres of "prison_yard"
    And I should see a notification containing "You have been jailed for 2 minutes."

  @kora_core @legacy:core-jail-contain @target:3 @needs:admin @manual
  Scenario: Jail containment
    """
    1. While jailed, try to run out of the yard (about 30 m from the spot you appeared).
    Expect: you are snapped back to the yard spot when you cross the radius.
    """
    When I manually: run /jail with my own player id and a few minutes
    And I manually: try to run out of the yard, about 30 m from the spot I appeared
    Then I confirm: I am snapped back to the yard spot when I cross the radius

  @kora_core @legacy:core-jail-timer @target:3 @needs:admin
  Scenario: Jail auto release
    """
    1. Jail a player for 1 minute with /jail <id> 1.
    2. Wait one minute.
    Expect: the player sees "You have been released." and containment ends.
    """
    When I manually: run /jail with my own player id and 1
    And I wait 60 seconds
    Then I should see a notification containing "You have been released."
    And I confirm: jail containment has ended and I can leave the yard

  @kora_core @legacy:core-unjail @target:3 @needs:admin @manual
  Scenario: /unjail
    """
    1. Jail a player for 10 minutes, then run /unjail <id>.
    Expect: the player sees "You have been released." and can leave the yard.
    """
    When I manually: ask a second player for their server id
    And I manually: run /jail <id> 10 on the second player
    And I manually: run /unjail <id> on the second player
    Then I confirm: the other player sees a notification "You have been released."
    And I confirm: the other player can leave the prison yard

  @kora_core @legacy:core-jail-relog @target:3 @needs:admin @checklist @checklist:kora_core:jail-relog @cat:core-and-libraries @manual
  Scenario: Jail sentence resumes on rejoin
    """
    1. Jail a player for 5 minutes.
    2. Have them disconnect and reconnect.
    Expect: after loading in they are teleported back to the yard with the remaining time, then released when it runs out.
    Also checklist kora_core:jail-relog (Jail sentence resumes on rejoin): Jail a player, have them reconnect: they are teleported back to the yard with the remaining time and auto-released at 0.
    """
    When I manually: ask a second player for their server id
    And I manually: run /jail <id> 5 on the second player
    And I manually: ask the second player to disconnect and reconnect
    Then I confirm: after loading in the other player is teleported back to the prison yard with the remaining time
    And I confirm: the other player is released when the time runs out

  @kora_core @legacy:core-needs-decay @target:3
  Scenario: Hunger and thirst decay
    """
    1. Note hunger and thirst, then wait 2 to 3 minutes without eating.
    Expect: both go down by 1 about every minute.
    """
    When I manually: note my hunger and thirst values
    And I wait 120 seconds
    Then my metadata "hunger" should have decreased
    And my metadata "thirst" should have decreased
    And I confirm: both hunger and thirst have gone down by about 1 per minute

  @kora_core @legacy:core-needs-persist @target:3 @manual
  Scenario: Needs survive relog
    """
    1. Note hunger and thirst, reconnect.
    Expect: values after reconnecting match what you had (not reset to 100).
    """
    When I manually: note my hunger and thirst values
    And I manually: disconnect and reconnect
    Then I confirm: my hunger and thirst match the noted values and were not reset to 100

  @kora_core @legacy:core-consume-food @target:3
  Scenario: Eat a sandwich
    """
    1. Get a sandwich and note hunger.
    2. Use it from the inventory.
    Expect: hunger rises by the sandwich effect and the item is consumed.
    """
    Given I have 1 "sandwich"
    When I manually: note my hunger value
    And I open my inventory
    And I use a "sandwich"
    Then my "sandwich" count should have changed by -1
    And my metadata "hunger" should have increased

  @kora_core @legacy:core-consume-drink @target:3
  Scenario: Drink water
    """
    1. Get a water_bottle and note thirst.
    2. Use it.
    Expect: thirst rises and the bottle is consumed.
    """
    Given I have 1 "water_bottle"
    When I manually: note my thirst value
    And I use a "water_bottle"
    Then my metadata "thirst" should have increased
    And my "water_bottle" count should have changed by -1

  @kora_core @legacy:core-consume-cap @target:3
  Scenario: Needs cap at 100
    """
    1. Eat or drink while already at 100.
    Expect: the value stays at 100 and never goes above.
    """
    Given my metadata "hunger" is "100"
    And my metadata "thirst" is "100"
    And I have 1 "sandwich"
    And I have 1 "water_bottle"
    When I use a "sandwich"
    And I use a "water_bottle"
    Then my metadata "hunger" should be "100"
    And my metadata "thirst" should be "100"

  @kora_core @legacy:core-paycheck-on @target:3
  Scenario: Paycheck on duty
    """
    1. Set yourself to police with /setjob <id> police 1.
    2. Make sure you are on duty (check with /job).
    3. Note your cash, then wait about 5 minutes.
    Expect: you receive a paycheck of 75 (Officer grade payment) as cash in your inventory.
    """
    Given my job is "police" at grade 1
    And I am on duty
    When I manually: note my cash
    And I wait 120 seconds
    And I wait 120 seconds
    And I wait 60 seconds
    Then my cash balance should have changed by 75

  @kora_core @legacy:core-paycheck-off @target:3
  Scenario: No paycheck off duty
    """
    1. Set a job and go off duty.
    2. Wait for a paycheck tick.
    Expect: no money is paid because off-duty pay is disabled for default jobs.
    """
    Given my job is "police"
    And I am off duty
    When I wait 120 seconds
    And I wait 120 seconds
    And I wait 60 seconds
    Then my cash balance should have changed by 0

  @kora_core @legacy:core-paycheck-civ @target:3
  Scenario: Unemployed paycheck
    """
    1. With the Civilian job (Freelancer), note your cash and wait for a paycheck tick (about 5 minutes).
    Expect: you receive 10 cash.
    """
    Given my job is "unemployed"
    When I manually: note my cash
    And I wait 120 seconds
    And I wait 120 seconds
    And I wait 60 seconds
    Then my cash balance should have changed by 10

  @kora_core @legacy:core-air-car @target:3
  Scenario: No air control for cars
    """
    1. Spawn a car with /car sultan.
    2. Jump it off a ramp and try to steer, pitch and roll in the air.
    Expect: you cannot steer, pitch or roll while airborne. Controls work normally again once all wheels touch the ground, even if upside down.
    """
    Given I am in the driver seat of a "sultan"
    When I manually: jump the car off a ramp and try to steer, pitch and roll in the air
    Then I confirm: I cannot steer, pitch or roll while airborne (only applies when Config.vehicleAirControl.disable is on)
    And I confirm: controls work normally again once all wheels touch the ground, even if upside down

  @kora_core @legacy:core-air-exempt @target:3
  Scenario: Bikes and aircraft keep air control
    """
    1. Jump a motorbike, then fly a helicopter or plane.
    Expect: a motorcycle (or bicycle), boat and aircraft keep full control in the air.
    """
    Given I am in the driver seat of a "bati"
    When I manually: jump the motorbike off a ramp
    Then I confirm: I keep full control in the air on the motorbike
    When I manually: get in a helicopter or plane and fly it
    Then I confirm: the aircraft keeps full control in the air

  @kora_core @legacy:core-compat-bootstrap @target:3 @needs:admin
  Scenario: qb-core resources load
    """
    1. Start a legacy qb-core based resource that calls exports["qb-core"]:GetCoreObject().
    Expect: it starts without errors in the F8 and server console.
    """
    When I manually: start a legacy qb-core based resource that calls exports["qb-core"]:GetCoreObject()
    And the F8 console should show no errors
    Then I confirm: the server console shows no errors from the started resource
    And there should be no script errors
