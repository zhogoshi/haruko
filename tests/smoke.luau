assert(ScreenGui and MainFrame, "window was not created")
assert(MainFrame.Visible, "window is hidden after boot")

local moduleCount = 0
for _, mod in pairs(modUi) do
    moduleCount += 1
    mod.onToggle(true)
    mod.onToggle(false)
end
assert(moduleCount == 10, "expected 10 modules, got " .. moduleCount)
assert(#__queued == 0, "auto execute stayed queued after turning off")

modUi.autoexec.onToggle(true)
modUi.autoexec.onToggle(true)
assert(#__queued == 1, "auto execute should queue exactly once")
assert(__queued[1]:find("zhogoshi/haruko", 1, true), "queued code does not load Haruko")

assert(not pages.Tour, "Tour page should be removed")
for _, name in ipairs({ "General", "Objects", "Settings" }) do
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

local saved = HttpService:JSONDecode(__files["Haruko/configs/Default.json"])
assert(saved.name == "Default", "config does not store its name")
assert(saved.settings.opacity == 1, "default opacity is not 100%")
settings.opacity = 0.7
persistNow()
saved = HttpService:JSONDecode(__files["Haruko/configs/Default.json"])
assert(saved.settings.opacity == 0.7, "opacity change was not autosaved")

modUi.autoexec.switch.Set(true)
modUi.tour.switch.Set(true)
persistNow()
saved = HttpService:JSONDecode(__files["Haruko/configs/Default.json"])
assert(saved.modules.autoexec.on == true, "auto execute state was not saved")
assert(saved.modules.tour.on == true, "tour state was not saved")
assert(saved.tour.list == "Default", "active list was not saved")

unload()
