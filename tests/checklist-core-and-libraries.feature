# Converted from the communitybot legacy tests by kora-qa-panel/scripts/convert-legacy.mjs.
# The """ block under each Scenario is the original test text, verbatim. Review before applying.
Feature: kora_core — Core & Libraries

  @kora_core @checklist @checklist:kora_core:character-login @cat:core-and-libraries
  Scenario: Character select and login
    """
    Checklist test: Join with a fresh char: multichar flow auto-selects or UI shows; spawn with default cash 500/bank 5000 and unemployed job.
    """
    When I manually: join with a fresh character and go through the multichar flow
    Then I confirm: the multichar flow auto-selects or the UI shows
    And my cash balance should be 500
    And my bank balance should be 5000
    And my job should be "unemployed"

  @kora_core @checklist @checklist:kora_core:jail-command @cat:core-and-libraries @needs:admin @manual
  Scenario: Admin /jail and /unjail
    """
    Checklist test: As admin run /jail <id> <minutes> [reason]: target teleports to Bolingbroke yard. /unjail <id> releases them.
    """
    When I manually: ask a second player for their server id
    And I manually: run /jail <id> <minutes> [reason] on the second player
    Then I confirm: the other player is teleported to the Bolingbroke yard
    When I manually: run /unjail <id> on that player
    Then I confirm: the other player is released

  @kora_core @checklist @checklist:kora_core:default-cmds-teleport @cat:core-and-libraries @needs:admin
  Scenario: Stock commands: /tp /tpm
    """
    Checklist test: Run /tp and /tpm as admin to teleport to coords/waypoint; non-admin should be denied.
    """
    When I manually: run /tp with coordinates
    Then I confirm: I am teleported to the coordinates
    When I run the command "/tpm"
    Then I confirm: I am teleported to my waypoint
    When I manually: ask a non-admin player to run /tp and /tpm
    Then I confirm: the other player is denied with "No access to this command"

  @kora_core @checklist @checklist:kora_core:default-cmds-vehicle @cat:core-and-libraries @needs:admin
  Scenario: Stock commands: /car /dv /dvall /dvp /dvo
    """
    Checklist test: As admin spawn with /car <model>, delete nearest with /dv, and test /dvall /dvp /dvo variants.
    """
    When I manually: run /car sultan
    Then I should be in a "sultan"
    When I run the command "/dv"
    Then the vehicle should be deleted
    When I run the command "/dvall"
    And I run the command "/dvp"
    And I run the command "/dvo"
    Then I confirm: each variant deletes the expected entities

  @kora_core @checklist @checklist:kora_core:default-cmds-money @cat:core-and-libraries @needs:admin
  Scenario: Stock commands: /givemoney /setmoney
    """
    Checklist test: As admin run /givemoney <id> <cash|bank> <amount> and /setmoney; check balances in inventory/bank.
    """
    Given my cash balance is 500
    And my bank balance is 5000
    When I manually: as admin run /givemoney with my id, cash and an amount of 100
    Then my cash balance should have changed by 100
    When I manually: as admin run /givemoney with my id, bank and an amount of 100
    Then my bank balance should have changed by 100
    When I manually: as admin run /setmoney with my id, cash and an amount of 300
    Then my cash balance should be 300

  @kora_core @checklist @checklist:kora_core:default-cmds-job-gang @cat:core-and-libraries @needs:admin
  Scenario: Stock commands: /job /setjob /gang /setgang
    """
    Checklist test: Run /setjob <id> <job> <grade> and /setgang; /job and /gang show current job/gang info.
    """
    When I manually: as admin run /setjob with my id, a job and a grade
    And I run the command "/job"
    Then I confirm: /job shows the job and grade I was given
    When I manually: as admin run /setgang with my id and a gang
    And I run the command "/gang"
    Then I confirm: /gang shows the gang I was given

  @kora_core @checklist @checklist:kora_core:default-cmds-perm-server @cat:core-and-libraries @needs:admin @manual
  Scenario: Stock commands: permissions, open/close server
    """
    Checklist test: Test /addpermission, /removepermission, /openserver, /closeserver, /togglepvp as admin; confirm non-admins are refused.
    """
    When I manually: as admin run /addpermission, /removepermission, /openserver, /closeserver and /togglepvp
    Then I confirm: each command works as intended (permission changed, server opened/closed, PVP toggled with a message)
    When I manually: ask a second non-admin player to run the same commands
    Then I confirm: the other player is refused each command

  @kora_core @checklist @checklist:kora_core:default-cmds-chat @cat:core-and-libraries @manual
  Scenario: Stock commands: /ooc and /me
    """
    Checklist test: Run /ooc <text> and /me <text> as a normal player; confirm others nearby/all see the message.
    """
    When I manually: ask a second player to stand near me
    And I manually: run /ooc with some text as a normal player
    And I manually: run /me with some text
    Then I confirm: the other player nearby sees the /ooc message
    And I confirm: the other player nearby sees the /me text

  @kora_core @checklist @checklist:kora_core:needs-decay @cat:core-and-libraries
  Scenario: Hunger and thirst decay
    """
    Checklist test: Wait ~1 min of play: hunger and thirst drop by 1 per tick; at zero the ped takes periodic damage on each update.
    """
    When I wait 60 seconds
    Then my metadata "hunger" should have decreased
    And my metadata "thirst" should have decreased
    And I confirm: my hunger and thirst each dropped by 1 per tick
    And I confirm: at zero hunger or thirst my ped takes periodic damage on each update

  @kora_core @checklist @checklist:kora_core:consumable-effects @cat:core-and-libraries
  Scenario: Consumable items apply hunger/thirst/stress
    """
    Checklist test: Use food/drink items (e.g. sandwich, water_bottle) from inventory; hunger/thirst/stress values change per item effect.
    """
    Given I have 1 "sandwich"
    And I have 1 "water_bottle"
    When I use a "sandwich"
    Then my "sandwich" count should have changed by -1
    And my metadata "hunger" should have increased
    When I use a "water_bottle"
    Then my "water_bottle" count should have changed by -1
    And my metadata "thirst" should have increased
    And I confirm: hunger, thirst and stress values changed per each item's effect

  @kora_core @checklist @checklist:kora_core:paycheck @cat:core-and-libraries
  Scenario: Job paycheck timer
    """
    Checklist test: Hold a paid job, on duty: after the paycheck interval (5 min) receive payment; off duty pays offDutyPay or nothing.
    """
    Given my job is "police"
    And I am on duty
    When I wait 120 seconds
    And I manually: keep waiting until the 5 minute paycheck interval has passed
    Then my bank balance should have changed by 1
    And I confirm: I received a paycheck payment
    When I manually: go off duty and wait for the next paycheck interval
    Then I confirm: I received offDutyPay or nothing

  @kora_core @checklist @checklist:kora_core:duty-toggle @cat:core-and-libraries
  Scenario: Job duty flag toggle
    """
    Checklist test: Toggle duty via a job resource (e.g. /ems-duty) and confirm the on-duty state updates and paycheck rules follow it.
    """
    Given my job is "ambulance"
    And I am on duty
    When I run the command "/ems-duty"
    Then I should be off duty
    When I run the command "/ems-duty"
    Then I should be on duty
    And I confirm: the next paycheck follows my duty state

  @kora_core @checklist @checklist:kora_core:money-accounts @cat:core-and-libraries @needs:admin @manual
  Scenario: Cash, bank and crypto accounts
    """
    Checklist test: Add/remove money via admin commands; confirm cash/bank/crypto balances update in HUD/bank and bank can go negative to the limit.
    """
    When I manually: run /givecash to add money to my cash, bank and crypto accounts, then /spend or /removeitem-style removal to take some away from each
    Then I confirm: my HUD and bank app show the updated cash, bank and crypto balances
    When I manually: as admin remove more bank money than I have, until the bank balance reaches the limit of -50000
    Then I confirm: my bank balance goes negative but not below -50000

  @kora_core @checklist @checklist:kora_core:garage-owned-vehicles @cat:core-and-libraries @needs:admin @manual
  Scenario: Owned vehicle persistence (garage module)
    """
    Checklist test: Give a vehicle to a player (admin /givevehicle), store and take it out; plate, fuel and body/engine health persist.
    """
    When I manually: as admin run /givevehicle to give myself a vehicle
    And I manually: store the vehicle in a garage and take it out again
    Then I confirm: the plate, fuel and body/engine health are the same as before

  @kora_core @checklist @checklist:kora_core:dev-mode @cat:core-and-libraries @needs:admin
  Scenario: Development mode (god, no needs, fast walk)
    """
    Checklist test: Admin /devmode: ped invincible, stamina infinite, hunger/thirst frozen and faster walking; disable and confirm it reverts.
    """
    When I run the command "/devmode"
    Then I confirm: my ped is invincible and stamina is infinite
    And I confirm: my hunger and thirst stay frozen and I walk faster
    When I run the command "/devmode"
    Then I confirm: invincibility, needs and walk speed revert to normal

  @kora_core @checklist @checklist:kora_core:dispatch-alerts @cat:core-and-libraries
  Scenario: Job dispatch alert fan-out
    """
    Checklist test: Trigger an EMS/police alert (e.g. /911e); on-duty members of the job receive the alert and blip.
    """
    Given my job is "ambulance"
    And I am on duty
    When I run the command "/911e"
    Then I confirm: on-duty members of the job receive the alert and a blip

  @kora_core @checklist @checklist:kora_core:vehicle-air-control @cat:core-and-libraries
  Scenario: Vehicle air control disabled
    """
    Checklist test: Jump a car off a ramp: driver cannot steer/pitch/roll in the air; bikes, boats and aircraft keep control.
    """
    Given I am in the driver seat of a "sultan"
    When I manually: jump the car off a ramp
    Then I confirm: I cannot steer, pitch or roll in the air
    When I manually: repeat the jump with a bike, a boat and an aircraft
    Then I confirm: bikes, boats and aircraft keep control in the air

  @kora_core @checklist @checklist:kora_core:kora_core-compat @cat:core-and-libraries @manual
  Scenario: Legacy qb-core compat layer
    """
    Checklist test: Run an unmodified qb-core based resource: GetCoreObject, callbacks, PlayerData events and stress events (hud:server:GainStress) work.
    """
    When I manually: start an unmodified qb-core based resource and use its features (e.g. a command or menu that loads player data and uses callbacks)
    Then I confirm: the resource works, with GetCoreObject, callbacks and PlayerData updates behaving as in stock qb-core
    When I manually: do something in the resource that adds stress, such as shooting a weapon
    Then I confirm: my stress value changes as expected
    When the F8 console should show no errors

  @kora_core @checklist @checklist:kora_core:compat-vehicle-spawn @cat:core-and-libraries @manual
  Scenario: Compat vehicle spawn callbacks (limited mode)
    """
    Checklist test: Spawn via QBCore.Functions.SpawnVehicle within 75m; max 2 live vehicles, 2s cooldown, keys granted, deleted on drop.
    """
    When I manually: spawn a vehicle via QBCore.Functions.SpawnVehicle within 75m
    Then I confirm: the vehicle spawns and I get keys (only applies when vehicleSpawnCallbacks is limited)
    When I manually: spawn a third vehicle, and another within 2 seconds
    Then I confirm: at most 2 live vehicles and the 2 second cooldown are enforced
    When I manually: disconnect and rejoin
    Then I confirm: the spawned vehicles were deleted on drop
