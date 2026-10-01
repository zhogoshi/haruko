assert(ScreenGui and MainFrame, "window was not created")
assert(MainFrame.Visible, "window is hidden after boot")

local moduleCount = 0
for _, mod in pairs(modUi) do
    moduleCount += 1
    mod.onToggle(true)
    mod.onToggle(false)
end
assert(moduleCount == 7, "expected 7 modules, got " .. moduleCount)

for _, name in ipairs({ "General", "Objects", "Tour", "Settings" }) do
    showPage(name)
end
for _, kind in ipairs({ "info", "success", "warn", "error" }) do
    notify("smoke " .. kind, kind)
end

setRender(true)
setRender(false)
setAntiPause(true)
setAntiPause(false)

table.insert(lists, newList("Smoke"))
persistNow()
assert(__files["Haruko/configs/Default.json"], "default config was not written")
assert(__files["Haruko/settings.json"], "settings were not written")
assert(__files["Haruko/locations/Default.json"], "default list was not written")
assert(__files["Haruko/locations/Smoke.json"], "second list was not written")

table.remove(lists)
persistNow()
assert(not __files["Haruko/locations/Smoke.json"], "removed list file was kept")

unload()
