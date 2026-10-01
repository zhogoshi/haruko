# Haruko

[![test](https://github.com/zhogoshi/haruko/actions/workflows/test.yml/badge.svg)](https://github.com/zhogoshi/haruko/actions/workflows/test.yml)

```lua
loadstring(game:HttpGet("https://raw.githubusercontent.com/zhogoshi/haruko/main/script.lua"))()
```

## Files

Haruko stores its data in the executor `workspace/Haruko` folder:

- `settings.json` holds autoload and autosave
- `configs/<name>.json` holds one config per file
- `locations/<name>.json` holds one location list per file

Files dropped into `configs/` or `locations/` are picked up on the next start.

## Tests

```sh
bash tests/run.sh
```

This compiles `script.lua` and boots it under a Roblox mock. The script is checked for syntax errors and the 200 local register limit, the UI and modules are exercised, and the config and location files are checked.
