# wow_addon_hello_world

C:\Windows\system32>mklink /D "C:\Users\nybo\Downloads\wow\Interface\AddOns\vanilla-addon" "C:\Users\nybo\Documents\GitHub\vanilla-addon"

## Important Notes FOR GPT:
- **Do not change the arguments of `onCombatEvent()` and `onHealthEvent()` functions.** The `arg1` parameter refers to the event argument and is used globally by WoW's event handling system.
- Lua version: 5.0
### Event Handling Clarification:
In World of Warcraft, event handler functions use global variables for event arguments. Specifically, `arg1` is a global variable used to capture the first argument of an event. This addon relies on this convention, so do not modify the function signatures of `onCombatEvent()` and `onHealthEvent()`.

### References:
- [Vanilla WoW Lua Definitions](https://github.com/refaim/Vanilla-WoW-Lua-Definitions)

## Files:
- `window.lua`
- `dmg.lua`
- `health.lua`
