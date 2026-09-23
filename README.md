# TSS Speed Zones

Standalone one-time average-speed challenges for StreetKings.

## Behaviour

- Driving through a start blip in the correct direction at 15+ MPH starts the zone.
- StreetKings-style checkpoints, GPS routing, waypoint beams, HUD and results are shown.
- Average speed is course distance divided by server-timed elapsed time.
- Cash, player XP and vehicle XP are awarded only on the first successful completion.
- Completed start blips turn green. Completed zones remain replayable for personal bests.
- Runs cancel when the player leaves the driver's seat, dies, leaves freeroam, or takes more than two minutes to reach the next checkpoint.

## Configuration

Edit `config.lua` to add routes or tune targets and rewards. Each route requires a unique
`id`, a `start`, a `targetAverageMph`, a `reward` table, and ordered `checkpoints`.
