script_name("GetTable")
script_author("legacy")
script_version("1.45")

local fa = require('fAwesome6_solid')
local imgui = require 'mimgui'
local encoding = require 'encoding'
local ffi = require('ffi')
local dlstatus = require("moonloader").download_status
local effil = require("effil")
local json = require("json")
local iconv = require("iconv")

encoding.default = 'CP1251'
local u8 = encoding.UTF8

local settingsPath = getWorkingDirectory() .. '\\config\\settings.json'

local windowSettings = {
    x = nil,
    y = nil,
    w = nil,
    h = nil,
    buyVc = 1,
    sellVc = 1,
    customCsvURL = "",
    colorRed = 1.0,
    colorGreen = 1.0,
    colorBlue = 1.0,
    colorAlpha = 1.0,
    textColorRed = 1.0,
    textColorGreen = 1.0,
    textColorBlue = 1.0,
    textColorAlpha = 1.0,
    copyMode = "spaced"
}

local function loadSettings()
    local f = io.open(settingsPath, "r")
    if f then
        local content = f:read("*a")
        f:close()
        local ok, data = pcall(json.decode, content)
        if ok and type(data) == "table" then
            for k, v in pairs(data) do
                windowSettings[k] = v
            end
        end
    end
end

local function saveSettings()
    local f = io.open(settingsPath, "w+")
    if f then
        f:write(json.encode(windowSettings))
        f:close()
    end
end

loadSettings()

local updateInfoUrl = "https://raw.githubusercontent.com/legacety/Geties/refs/heads/main/update.json"
local csvURL = nil
local allowedNicknames = {}

local renderWindow = imgui.new.bool(false)
local showAccessDeniedWindow = imgui.new.bool(false)
local showSettings = imgui.new.bool(false)
local sheetData = nil
local lastGoodSheetData = nil
local isLoading = false
local firstLoadComplete = false
local searchInput = ffi.new("char[128]", "")
local isAccessDenied = false

local buyVcInput = ffi.new("float[1]", windowSettings.buyVc)
local sellVcInput = ffi.new("float[1]", windowSettings.sellVc)
local customCsvURLInput = ffi.new("char[512]", windowSettings.customCsvURL)
local colorInput = ffi.new("float[4]", {windowSettings.colorRed, windowSettings.colorGreen, windowSettings.colorBlue, windowSettings.colorAlpha})
local textColorInput = ffi.new("float[4]", {windowSettings.textColorRed, windowSettings.textColorGreen, windowSettings.textColorBlue, windowSettings.textColorAlpha})

local function toLowerCyrillic(str)
    local map = {
        ["А"]="а",["Б"]="б",["В"]="в",["Г"]="г",["Д"]="д",["Е"]="е",["Ё"]="ё",["Ж"]="ж",["З"]="з",["И"]="и",
        ["Й"]="й",["К"]="к",["Л"]="л",["М"]="м",["Н"]="н",["О"]="о",["П"]="п",["Р"]="р",["С"]="с",["Т"]="т",
        ["У"]="у",["Ф"]="ф",["Х"]="х",["Ц"]="ц",["Ч"]="ч",["Ш"]="ш",["Щ"]="щ",["Ъ"]="ъ",["Ы"]="ы",["Ь"]="ь",
        ["Э"]="э",["Ю"]="ю",["Я"]="я"
    }
    for up, low in pairs(map) do str = str:gsub(up, low) end
    return str:lower()
end

local function versionToNumber(v)
    local clean = tostring(v):gsub("[^%d]", "")
    return tonumber(clean) or 0
end

local function isNicknameAllowed()
    local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
    local rawNick = sampGetPlayerNickname(id)
    local nick = rawNick:match("%]%s*(.+)") or rawNick
    for _, allowed in ipairs(allowedNicknames) do
        if nick == allowed then return true end
    end
    return false
end

local function checkForUpdates()
    local function asyncHttpRequest(method, url, args, resolve, reject)
        local thread = effil.thread(function(method, url, args)
            local requests = require("requests")
            local ok, response = pcall(requests.request, method, url, args)
            if ok then
                response.json, response.xml = nil, nil
                return true, response
            else
                return false, response
            end
        end)(method, url, args)

        lua_thread.create(function()
            while true do
                local status, err = thread:status()
                if not err then
                    if status == "completed" then
                        local ok, response = thread:get()
                        if ok then resolve(response) else reject(response) end
                        return
                    elseif status == "canceled" then
                        reject("Canceled")
                        return
                    end
                else
                    reject(err)
                    return
                end
                wait(0)
            end
        end)
    end

    asyncHttpRequest("GET", updateInfoUrl, nil, function(response)
        if response.status_code == 200 then
            local data = json.decode(response.text)
            if data and data.version and data.url and data.csv then
                csvURL = data.csv
                allowedNicknames = data.nicknames or {}
                local current = versionToNumber(thisScript().version)
                local remote = versionToNumber(data.version)
                if remote > current then
                    if not isNicknameAllowed() then return end
                    local tempPath = thisScript().path
                    local thread = effil.thread(function(url, tempPath)
                        local requests = require("requests")
                        local ok, response = pcall(requests.get, url)
                        if not ok or response.status_code ~= 200 then return false end
                        local f = io.open(tempPath, "wb")
                        if not f then return false end
                        f:write(response.text)
                        f:close()
                        return true
                    end)(data.url, tempPath)

                    lua_thread.create(function()
                        while true do
                            local status = thread:status()
                            if status == "completed" then
                                local ok = thread:get()
                                if ok then
                                    sampAddChatMessage("{00FF00}[GT]{FFFFFF} Обновление загружено.", 0xFFFFFF)
                                end
                                return
                            elseif status == "canceled" then return end
                            wait(0)
                        end
                    end)
                end
            end
        else
            isAccessDenied = true
        end
    end, function(err)
        isAccessDenied = true
    end)
end

local function theme()
    local s = imgui.GetStyle()
    local c = imgui.Col
    local clr = s.Colors
    s.WindowRounding = 0
    s.WindowTitleAlign = imgui.ImVec2(0.5, 0.84)
    s.ChildRounding = 0
    s.FrameRounding = 5.0
    s.ItemSpacing = imgui.ImVec2(10, 10)
    s.ScrollbarSize = 18
    s.ScrollbarRounding = 0
    s.GrabRounding = 0
    s.GrabMinSize = 38

    local R, G, B, A = windowSettings.colorRed, windowSettings.colorGreen, windowSettings.colorBlue, windowSettings.colorAlpha

    clr[c.Text] = imgui.ImVec4(windowSettings.textColorRed, windowSettings.textColorGreen, windowSettings.textColorBlue, windowSettings.textColorAlpha)
    clr[c.Separator] = imgui.ImVec4(R, G, B, 0.1)
    clr[c.FrameBg] = imgui.ImVec4(R * 0.2, G * 0.2, B * 0.2, A)
    clr[c.ChildBg] = imgui.ImVec4(R * 0.08, G * 0.08, B * 0.08, A)
    clr[c.Border] = imgui.ImVec4(R, G, B, 0.1)

    clr[c.WindowBg] = imgui.ImVec4(R * 0.1, G * 0.1, B * 0.1, A)
    clr[c.PopupBg] = clr[c.WindowBg]

    clr[c.FrameBgHovered] = imgui.ImVec4(R * 0.3, G * 0.3, B * 0.3, A)
    clr[c.FrameBgActive] = imgui.ImVec4(R * 0.4, G * 0.4, B * 0.4, A)

    clr[c.Button] = imgui.ImVec4(R * 0.3, G * 0.3, B * 0.3, A)
    clr[c.ButtonHovered] = imgui.ImVec4(R * 0.5, G * 0.5, B * 0.5, A)
    clr[c.ButtonActive] = imgui.ImVec4(R * 0.7, G * 0.7, B * 0.7, A)

    clr[c.Header] = imgui.ImVec4(R * 0.4, G * 0.4, B * 0.4, A)
    clr[c.HeaderHovered] = imgui.ImVec4(R * 0.6, G * 0.6, B * 0.6, A)
    clr[c.HeaderActive] = imgui.ImVec4(R * 0.8, G * 0.8, B * 0.8, A)

    clr[c.TitleBg] = imgui.ImVec4(R * 0.15, G * 0.15, B * 0.15, A)
    clr[c.TitleBgActive] = imgui.ImVec4(R * 0.25, G * 0.25, B * 0.25, A)
    clr[c.TitleBgCollapsed] = imgui.ImVec4(R * 0.1, G * 0.1, B * 0.1, 0.75 * A)

    clr[c.ScrollbarBg] = imgui.ImVec4(R * 0.05, G * 0.05, B * 0.05, A)
    clr[c.ScrollbarGrab] = imgui.ImVec4(R * 0.3, G * 0.3, B * 0.3, A)
    clr[c.ScrollbarGrabHovered] = imgui.ImVec4(R * 0.5, G * 0.5, B * 0.5, A)
    clr[c.ScrollbarGrabActive] = imgui.ImVec4(R * 0.7, G * 0.7, B * 0.7, A)
end

imgui.OnInitialize(function()
    fa.Init(14)
    theme()
    imgui.GetIO().IniFilename = nil
end)

local function parseCSV(data)
    local rows = {}
    local ok, converted = pcall(function()
        local conv = iconv.new("CP1251", "UTF-8")
        return conv:iconv(data)
    end)
    if not ok then
        return nil
    end
    for line in converted:gmatch("[^\r\n]+") do
        local row, i, inQuotes, cell = {}, 1, false, ''
        for c in (line .. ','):gmatch('.') do
            if c == '"' then
                inQuotes = not inQuotes
            elseif c == ',' and not inQuotes then
                row[i] = cell:gsub('^%s*"(.-)"%s*$', '%1'):gsub('""', '"')
                i = i + 1
                cell = ''
            else
                cell = cell .. c
            end
        end
        table.insert(rows, row)
    end
    return rows
end

local function drawSpinner()
    local center = imgui.GetWindowPos() + imgui.GetWindowSize() * 0.5
    local radius, thickness, segments = 32.0, 3.0, 30
    local time = imgui.GetTime()
    local angle_offset = (time * 3) % (2 * math.pi)
    local drawList = imgui.GetWindowDrawList()
    for i = 0, segments - 1 do
        local a0 = i / segments * 2 * math.pi
        local a1 = (i + 1) / segments * 2 * math.pi
        local alpha = (i / segments)
        if alpha > 0.25 and alpha < 0.75 then
            local x0 = center.x + radius * math.cos(a0 + angle_offset)
            local y0 = center.y + radius * math.sin(a0 + angle_offset)
            local x1 = center.x + radius * math.cos(a1 + angle_offset)
            local y1 = center.y + radius * math.sin(a1 + angle_offset)
            drawList:AddLine(imgui.ImVec2(x0, y0), imgui.ImVec2(x1, y1), imgui.GetColorU32(imgui.Col.Text), thickness)
        end
    end
end

local function CenterTextInColumn(text)
    local columnWidth = imgui.GetColumnWidth()
    local textWidth = imgui.CalcTextSize(text).x
    local wrapWidth = columnWidth * 0.8
    local offset = (columnWidth - math.min(textWidth, wrapWidth)) * 0.5
    if offset > 0 then imgui.SetCursorPosX(imgui.GetCursorPosX() + offset) end
    local cursorPosX = imgui.GetCursorPosX()
    imgui.PushTextWrapPos(cursorPosX + wrapWidth)
    imgui.TextWrapped(text)
    imgui.PopTextWrapPos()
end

local function CenterText(text)
    local windowWidth = imgui.GetWindowSize().x
    local textWidth = imgui.CalcTextSize(text).x
    local offset = (windowWidth - textWidth) * 0.5
    if offset > 0 then imgui.SetCursorPosX(offset) end
    imgui.TextWrapped(text)
end

local function formatNumberWithSpaces(n)
    local s = tostring(math.floor(n))
    local formatted = ""
    local count = 0
    for i = #s, 1, -1 do
        formatted = s:sub(i, i) .. formatted
        count = count + 1
        if count % 3 == 0 and i > 1 then
            formatted = " " .. formatted
        end
    end
    return formatted
end

local function copyToClipboard(text)
    local textToCopy
    if windowSettings.copyMode == "spaced" then
        textToCopy = text
    else
        textToCopy = text:gsub(" ", "")
    end
    setClipboardText(textToCopy)
    sampAddChatMessage("{00FF00}[GT]{FFFFFF} Цена успешно скопирована в буфер обмена: {00FF00}" .. textToCopy, 0xFFFFFF)
end

local function drawTable(data)
    if isLoading or not firstLoadComplete or not data then
        drawSpinner()
        imgui.Dummy(imgui.ImVec2(0, 40))
        CenterText(u8"Загрузка таблицы...")
        return
    end

    if #data == 0 then return end

    local filter = toLowerCyrillic(u8:decode(ffi.string(searchInput)))
    local filtered = {}

    table.insert(filtered, data[1])
    for i = 2, #data do
        local row = data[i]
        local match = false
        for _, cell in ipairs(row) do
            if toLowerCyrillic(tostring(cell)):find(filter, 1, true) then
                match = true break
            end
        end
        if match then table.insert(filtered, row) end
    end

    imgui.BeginChild("scrollingRegion", imgui.ImVec2(-1, -1), true)

    if #filtered == 1 and filter ~= "" then
        drawSpinner()
        imgui.Dummy(imgui.ImVec2(0, 20))
        CenterText(u8"Совпадений нет.")
        imgui.EndChild()
        return
    end

    local regionWidth = imgui.GetContentRegionAvail().x
    local columnWidth = regionWidth / 3
    local pos = imgui.GetCursorScreenPos()
    local y0 = pos.y - imgui.GetStyle().ItemSpacing.y
    local y1 = pos.y + imgui.GetContentRegionAvail().y + imgui.GetScrollMaxY() + 7
    local x1 = pos.x + columnWidth
    local x2 = pos.x + 2 * columnWidth

    local draw = imgui.GetWindowDrawList()
    local sepColor = imgui.GetColorU32(imgui.Col.Separator)
    draw:AddLine(imgui.ImVec2(x1, y0), imgui.ImVec2(x1, y1), sepColor, 1)
    draw:AddLine(imgui.ImVec2(x2, y0), imgui.ImVec2(x2, y1), sepColor, 1)

    imgui.Columns(3, nil, false)
    for i = 1, 3 do
        CenterTextInColumn(u8(tostring(filtered[1][i] or "")))
        imgui.NextColumn()
    end
    imgui.Separator()

    local currentBuyVc = buyVcInput[0]
    local currentSellVc = sellVcInput[0]

    for i = 2, #filtered do
        for col = 1, 3 do
            local cellValue = tostring(filtered[i][col] or "")
            if col == 1 then
                CenterTextInColumn(u8(cellValue))
            elseif col == 2 then
                local numStr = cellValue:gsub("[^%d%.%-]+", "")
                local num = tonumber(numStr)
                if num then
                    cellValue = formatNumberWithSpaces(num * currentBuyVc)
                end

                local itemHovered = false
                local textWidth = imgui.CalcTextSize(u8(cellValue)).x
                local columnWidth = imgui.GetColumnWidth()
                local cursorPosX = imgui.GetCursorPosX()
                imgui.SetCursorPosX(cursorPosX + (columnWidth - textWidth) / 2)
                imgui.Text(u8(cellValue))
                itemHovered = imgui.IsItemHovered()

                if itemHovered then
                    imgui.SetMouseCursor(imgui.MouseCursor.Hand)
                    imgui.SetTooltip(u8"Нажмите, чтобы скопировать")
                    if imgui.IsMouseClicked(0) then
                        copyToClipboard(cellValue)
                    end
                end
            elseif col == 3 then
                local numStr = cellValue:gsub("[^%d%.%-]+", "")
                local num = tonumber(numStr)
                if num then
                    cellValue = formatNumberWithSpaces(num * currentSellVc)
                end

                local itemHovered = false
                local textWidth = imgui.CalcTextSize(u8(cellValue)).x
                local columnWidth = imgui.GetColumnWidth()
                local cursorPosX = imgui.GetCursorPosX()
                imgui.SetCursorPosX(cursorPosX + (columnWidth - textWidth) / 2)
                imgui.Text(u8(cellValue))
                itemHovered = imgui.IsItemHovered()

                if itemHovered then
                    imgui.SetMouseCursor(imgui.MouseCursor.Hand)
                    imgui.SetTooltip(u8"Нажмите, чтобы скопировать")
                    if imgui.IsMouseClicked(0) then
                        copyToClipboard(cellValue)
                    end
                end
            end
            imgui.NextColumn()
        end
        imgui.Separator()
    end

    imgui.Columns(1)
    imgui.EndChild()
end

local function extractGoogleSheetIds(googleSheetUrl)
    local spreadsheetId = googleSheetUrl:match("/d/([a-zA-Z0-9_-]+)")
    local gid = googleSheetUrl:match("gid=(%d+)") or "0"
    return spreadsheetId, gid
end

local function updateCSV()
    local urlToUse = csvURL
    if windowSettings.customCsvURL and windowSettings.customCsvURL ~= "" then
        local customUrl = windowSettings.customCsvURL
        local spreadsheetId, gid = extractGoogleSheetIds(customUrl)
        if spreadsheetId then
            urlToUse = string.format("https://docs.google.com/spreadsheets/d/%s/gviz/tq?tqx=out:csv&gid=%s", spreadsheetId, gid)
        else
            urlToUse = customUrl
        end
    end

    if not urlToUse then return end

    isLoading = true
    firstLoadComplete = false
    local tmpPath = os.tmpname() .. ".csv"
    downloadUrlToFile(urlToUse, tmpPath, function(success)
        if success then
            local f = io.open(tmpPath, "rb")
            if f then
                local content = f:read("*a")
                f:close()
                sheetData = parseCSV(content)
                if sheetData then
                    lastGoodSheetData = sheetData
                else
                    sheetData = lastGoodSheetData
                end
                os.remove(tmpPath)
            else
                sheetData = lastGoodSheetData
            end
        else
            sheetData = lastGoodSheetData
        end
        isLoading = false
        firstLoadComplete = true
    end)
end

imgui.OnFrame(function() return renderWindow[0] or showAccessDeniedWindow[0] end, function()
    theme()

    if showAccessDeniedWindow[0] then
        local sx, sy = getScreenResolution()
        local windowWidth, windowHeight = 630, 315
        local x = (sx - windowWidth) / 2
        local y = (sy - windowHeight) / 2
        imgui.SetNextWindowPos(imgui.ImVec2(x, y), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowSize(imgui.ImVec2(windowWidth, windowHeight), imgui.Cond.Always)
        imgui.Begin("GetTable", showAccessDeniedWindow, imgui.WindowFlags.NoResize)

        local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        local rawNick = sampGetPlayerNickname(id)
        local nick = rawNick:match("%]%s*(.+)") or rawNick

        CenterText(u8"Уважаемый пользователь ")
        imgui.SameLine()
        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(1.0, 0.78, 0.0, 1.0))
        imgui.Text(u8(nick))
        imgui.PopStyleColor()
        CenterText(u8"к сожалению, доступ к данному скрипту для вашего аккаунта временно ограничен.")
        imgui.Spacing()
        CenterText(u8"Возможные причины блокировки:")
        CenterText(u8"- Истёк срок вашей подписки.")
        CenterText(u8"- Неоплаченный период продления.")
        CenterText(u8"- Нарушение условий использования скрипта.")
        imgui.Spacing()
        CenterText(u8"Если вы считаете, что это ошибка, или хотите возобновить доступ,")
        CenterText(u8"а также для покупки или продления подписки,")
        CenterText(u8"свяжитесь с разработчиком по ссылке ниже:")
        local link = "t.me/legacy"
        local textSize = imgui.CalcTextSize(link)
        local windowSize = imgui.GetWindowSize()
        imgui.SetCursorPosX((windowSize.x - textSize.x) / 2)

        imgui.PushStyleColor(imgui.Col.Text, imgui.ImVec4(0, 0.5, 1, 1))
        imgui.Text(link)
        imgui.PopStyleColor()

        if imgui.IsItemHovered() then
            imgui.SetMouseCursor(imgui.MouseCursor.Hand)
            if imgui.IsMouseClicked(0) then
                if package.config:sub(1,1) == '\\' then
                    os.execute('start "" "https://' .. link .. '"')
                else
                    os.execute('xdg-open "https://' .. link .. '"')
                end
            end
        end
        imgui.End()
    elseif renderWindow[0] then
        local sx, sy = getScreenResolution()
        local w = windowSettings.w or math.min(900, sx - 50)
        local h = windowSettings.h or 500
        local x = windowSettings.x or (sx - w) / 2
        local y = windowSettings.y or (sy - h) / 2
        imgui.SetNextWindowPos(imgui.ImVec2(x, y), imgui.Cond.FirstUseEver)
        imgui.SetNextWindowSize(imgui.ImVec2(w, h), imgui.Cond.FirstUseEver)

        if imgui.Begin(string.format("Google Table %s", thisScript().version), renderWindow) then
            local availWidth = imgui.GetContentRegionAvail().x

            local function iconButton(icon, tooltip, action)
                imgui.PushStyleColor(imgui.Col.Button, imgui.ImVec4(0, 0, 0, 0))
                imgui.PushStyleColor(imgui.Col.ButtonHovered, imgui.ImVec4(0.15, 0.20, 0.23, 0.3))
                imgui.PushStyleColor(imgui.Col.ButtonActive, imgui.ImVec4(0.15, 0.20, 0.23, 0.5))
                if imgui.SmallButton(icon) then action() end
                imgui.PopStyleColor(3)
                if imgui.IsItemHovered() then imgui.SetTooltip(tooltip) end
            end

            if showSettings[0] then
                iconButton(fa.ARROW_LEFT, u8"Назад к таблице", function()
                    showSettings[0] = false
                end)
                imgui.SameLine()
            else
                imgui.PushItemWidth(availWidth * 0.75)
                imgui.InputTextWithHint("##search", u8"Поиск по таблице...", searchInput, ffi.sizeof(searchInput))
                imgui.PopItemWidth()

                imgui.SameLine()
                iconButton(fa.ERASER, u8"Очистить поиск", function()
                    ffi.fill(searchInput, ffi.sizeof(searchInput))
                end)

                imgui.SameLine()
                iconButton(fa.ROTATE, u8"Обновить таблицу", function()
                    updateCSV()
                end)

                imgui.SameLine()
                iconButton(fa.GEARS, u8"Настройки", function()
                    showSettings[0] = not showSettings[0]
                end)
            end

            imgui.Spacing()

            if showSettings[0] then
                CenterText(u8"Settings legacy script <3")
                imgui.Text(u8"Курс множителя цен в таблице")
                imgui.Separator()

                local function inputMultiplier(label, var)
                    local formatStr = (var[0] == math.floor(var[0])) and "%.0f" or "%.2f"
                    imgui.PushItemWidth(availWidth * 0.2)
                    imgui.InputFloat(label, var, 0.0, 0.0, formatStr)
                    imgui.PopItemWidth()
                end

                inputMultiplier(u8"Курс покупки VC$", buyVcInput)
                windowSettings.buyVc = buyVcInput[0]

                inputMultiplier(u8"Курс продажи VC$", sellVcInput)
                windowSettings.sellVc = sellVcInput[0]

                imgui.Spacing()
  imgui.Text(u8"Settings копирование")
                imgui.Separator()
                
                local isSeamless = windowSettings.copyMode == "seamless"
                local isSpaced = windowSettings.copyMode == "spaced"
                
                if imgui.Checkbox(u8"Копировать слитно", imgui.new.bool(isSeamless)) then
                    if not isSeamless then
                        windowSettings.copyMode = "seamless"
                    end
                end
                
                if imgui.Checkbox(u8"Копировать раздельно", imgui.new.bool(isSpaced)) then
                    if not isSpaced then
                        windowSettings.copyMode = "spaced"
                    end
                end

                imgui.Spacing()
                imgui.Separator()

                imgui.Text(u8"Пользовательская ссылка на CSV-таблицу:")
                imgui.PushItemWidth(availWidth * 0.8)
                imgui.InputTextWithHint("##customCsvURL", u8"Вставьте ссылку на Google Таблицу...", customCsvURLInput, ffi.sizeof(customCsvURLInput))
                windowSettings.customCsvURL = u8:decode(ffi.string(customCsvURLInput))
                imgui.PopItemWidth()
                if imgui.IsItemHovered() then imgui.SetTooltip(u8"Ваша ссылка на Google Таблицу. Если поле пустое, будет использоваться ссылка по умолчанию.") end

                imgui.SameLine()
                iconButton(fa.TRASH_CAN, u8"Очистить ссылку", function()
                    ffi.fill(customCsvURLInput, ffi.sizeof(customCsvURLInput))
                    windowSettings.customCsvURL = ""
                end)

                CenterText(u8"Как использовать Google Таблицу в скрипте:")
                imgui.Text(u8"1 - Если у вас уже есть ссылка на открытую Google Таблицу, просто скопируйте её и вставьте в поле ниже.")
                imgui.Text(u8"2 - Если таблица закрытая, откройте её в Google Sheets и опубликуйте в интернете")
                imgui.Text(u8"3 - Меню: Файл > Опубликовать в интернете")
                imgui.Text(u8"4 - Скопируйте ссылку публикации и вставьте в поле скрипта.")
                imgui.Text(u8"5 - После вставки нажмите «Обновить таблицу» для загрузки данных.")
                imgui.Text(u8"6 - Скрипт автоматически преобразует обычные ссылки из адресной строки.")
                imgui.Text(u8"7 - Убедитесь, что таблица доступна по ссылке для корректной загрузки.")
                imgui.Text(u8"8 - P.s пжшка, учтите, если таблица закрыта и не опубликована, данные с таблицы не будут загружены")

                imgui.Separator()
                imgui.Text(u8"Настройка цвета скрипта by Stray_Scofield")
                if imgui.ColorEdit4("##colorPicker", colorInput) then
                    windowSettings.colorRed = colorInput[0]
                    windowSettings.colorGreen = colorInput[1]
                    windowSettings.colorBlue = colorInput[2]
                    windowSettings.colorAlpha = colorInput[3]
                    theme()
                end

                imgui.Text(u8"Настройка цвета текста")
                if imgui.ColorEdit4("##textColorPicker", textColorInput) then
                    windowSettings.textColorRed = textColorInput[0]
                    windowSettings.textColorGreen = textColorInput[1]
                    windowSettings.textColorBlue = textColorInput[2]
                    windowSettings.textColorAlpha = textColorInput[3]
                    theme()
                end

                imgui.Separator()
            else
                drawTable(sheetData)
            end

            local pos, size = imgui.GetWindowPos(), imgui.GetWindowSize()
            windowSettings.x, windowSettings.y = pos.x, pos.y
            windowSettings.w, windowSettings.h = size.x, size.y
            saveSettings()
            imgui.End()
        else
            local pos, size = imgui.GetWindowPos(), imgui.GetWindowSize()
            windowSettings.x, windowSettings.y = pos.x, pos.y
            windowSettings.w, windowSettings.h = size.x, size.y
            saveSettings()
        end
    end
end)

function main()
    while not isSampAvailable() do wait(0) end

    checkForUpdates()

    while csvURL == nil and #allowedNicknames == 0 and not isAccessDenied do wait(0) end

    if isAccessDenied or not isNicknameAllowed() then
        isAccessDenied = true
        local _, id = sampGetPlayerIdByCharHandle(PLAYER_PED)
        local rawNick = sampGetPlayerNickname(id)
        local nick = rawNick:match("%]%s*(.+)") or rawNick
        sampAddChatMessage(string.format("{00FF00}[GT] {FFC800}%s{FFFFFF} , вам доступ запрещён.", nick), -1)
 sampAddChatMessage("{00FF00}[GT]{FFFFFF} Скрипт загружен. Для активации используйте {00FF00}/gt", 0xFFFFFF)
    else
        sampAddChatMessage("{00FF00}[GT]{FFFFFF} Скрипт загружен. Для активации используйте {00FF00}/gt", 0xFFFFFF)
    end

    sampRegisterChatCommand('gt', function()
        if isAccessDenied then
            showAccessDeniedWindow[0] = not showAccessDeniedWindow[0]
        else
            renderWindow[0] = not renderWindow[0]
            if renderWindow[0] and not firstLoadComplete and not showSettings[0] then
                updateCSV()
            end
        end
    end)

    wait(-1)
end
