
-------------------------------------------------------------------------------
-- Tour Narrator
-- Script editor, compact presenter, and minimap controls.
-------------------------------------------------------------------------------

-- The position of the next line to send. Not saved; it restarts at line 1.
local TourNarratorIndex = 1

-------------------------------------------------------------------------------
-- CONFIGURATION AND DATABASE
-------------------------------------------------------------------------------

local ADDON_NAME = "TourNarrator"

local DEFAULT_MINIMAP_ANGLE = 45
local MINIMAP_RADIUS = 110

local MAX_CHAT_MESSAGE_LENGTH = 250
TourNarratorDB = TourNarratorDB or {}

-------------------------------------------------------------------------------
-- SCRIPT PARSING
-------------------------------------------------------------------------------

local scriptLines = {}

-- A recognised prefix changes the chat type and colour for that line.
-- The selected type remains active until another prefix is encountered.
local CHAT_TYPES = {
    { type = "SAY",           color = "|cFFFFFFFF", commands = { "s", "say" } },
    { type = "EMOTE",         color = "|cFFFF8000", commands = { "e", "emote", "me" } },
    { type = "YELL",          color = "|cFFFF4040", commands = { "y", "yell" } },
    { type = "PARTY",         color = "|cFFAAAAAF", commands = { "p", "party" } },
    { type = "RAID",          color = "|cFFFFB000", commands = { "ra", "raid" } },
    { type = "GUILD",         color = "|cFF40FF40", commands = { "g", "guild" } },
}

-- Builds a pattern that matches a slash command in any capitalisation,
-- followed by a space. For example, "say" becomes "^/[sS][aA][yY]%s+".
local function CommandPattern(command)
    local letters = command:gsub("%a", function(letter)
        return "[" .. letter:lower() .. letter:upper() .. "]"
    end)

    return "^/" .. letters .. "%s+"
end

local CHAT_PREFIXES = {}

for _, chatType in ipairs(CHAT_TYPES) do
    for _, command in ipairs(chatType.commands) do
        CHAT_PREFIXES[#CHAT_PREFIXES + 1] = {
            pattern = CommandPattern(command),
            type = chatType.type,
            color = chatType.color,
        }
    end
end

-------------------------------------------------------------------------------
-- STANDARD EMOTE COMMANDS (/bow, /sit, /laugh, ...)
-------------------------------------------------------------------------------

-- These are not chat messages. WoW performs them with its emote function, so
-- a script line such as "/bow" becomes an "action" line instead of being sent
-- to a chat channel. The command list is read from WoW's own emote strings
-- (EMOTE<n>_TOKEN and EMOTE<n>_CMD<n>), so every emote the game knows about is
-- supported, in the player's own language.
local ACTION_TYPE = "ACTION"
local ACTION_COLOR = "|cFF66CCFF"

-- The emote numbers have gaps, and the highest number is not exposed to
-- addons, so scan a generous range and skip numbers that don't exist.
local EMOTE_SCAN_LIMIT = 2000

local emoteCommands = nil

local function BuildEmoteCommands()
    local commands = {}

    for index = 1, EMOTE_SCAN_LIMIT do
        local token = _G["EMOTE" .. index .. "_TOKEN"]

        if token then
            local number = 1
            local command = _G["EMOTE" .. index .. "_CMD" .. number]

            while command do
                commands[strupper(command)] = token
                number = number + 1
                command = _G["EMOTE" .. index .. "_CMD" .. number]
            end
        end
    end

    -- Blizzard's chat frame keeps the same list. Merge it in as a safety net
    -- in case the scan above missed anything.
    local blizzardList = _G.hash_EmoteTokenList

    if type(blizzardList) == "table" then
        for command, token in pairs(blizzardList) do
            if type(command) == "string"
                and type(token) == "string"
                and command:sub(1, 1) == "/" then
                local key = strupper(command)
                commands[key] = commands[key] or token
            end
        end
    end

    return commands
end

-- Returns the emote token for a slash command such as "/bow", or nil.
local function GetEmoteToken(command)
    if not emoteCommands then
        emoteCommands = BuildEmoteCommands()
    end

    return emoteCommands[strupper(command)]
end

-------------------------------------------------------------------------------
-- SCRIPT EDITOR FRAME
-------------------------------------------------------------------------------

local editor = CreateFrame(
    "Frame",
    "TourNarratorFrame",
    UIParent,
    "BackdropTemplate"
)

editor:SetSize(420, 390)
editor:SetPoint("CENTER")
editor:SetMovable(true)
editor:EnableMouse(true)
editor:RegisterForDrag("LeftButton")
editor:SetScript("OnDragStart", editor.StartMoving)
editor:SetScript("OnDragStop", editor.StopMovingOrSizing)
editor:Hide()

editor:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
    tile = true,
    tileSize = 16,
    edgeSize = 16,
    insets = {
        left = 4,
        right = 4,
        top = 4,
        bottom = 4,
    },
})

editor:SetBackdropColor(0, 0, 0, 0.9)

local editorTitle = editor:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontNormalLarge"
)

editorTitle:SetPoint("TOPLEFT", editor, "TOPLEFT", 16, -14)
editorTitle:SetText("Tour Narrator — Script Editor")

-- Border surrounding the script text area.
local editorBorder = CreateFrame(
    "Frame",
    nil,
    editor,
    "BackdropTemplate"
)

editorBorder:SetPoint("TOPLEFT", editor, "TOPLEFT", 15, -72)
editorBorder:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -15, 86)

editorBorder:SetBackdrop({
    bgFile = "Interface\\Buttons\\WHITE8x8",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 12,
    insets = {
        left = 3,
        right = 3,
        top = 3,
        bottom = 3,
    },
})

editorBorder:SetBackdropColor(0.05, 0.05, 0.05, 0.7)
editorBorder:SetBackdropBorderColor(0.5, 0.5, 0.5, 0.8)

-- Scrollable script input.
local scrollArea = CreateFrame(
    "ScrollFrame",
    "TourNarratorScroll",
    editorBorder,
    "UIPanelScrollFrameTemplate"
)

scrollArea:SetPoint("TOPLEFT", editorBorder, "TOPLEFT", 8, -8)
scrollArea:SetPoint("BOTTOMRIGHT", editorBorder, "BOTTOMRIGHT", -26, 8)

local editBox = CreateFrame(
    "EditBox",
    "TourNarratorEditBox",
    scrollArea
)

editBox:SetMultiLine(true)
editBox:SetMaxLetters(99999)
editBox:SetWidth(340)
editBox:SetFontObject("GameFontHighlight")
editBox:SetAutoFocus(false)

scrollArea:SetScrollChild(editBox)

-- Status text below the script area.
local statusLabel = editor:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontNormal"
)

statusLabel:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 16, 52)

-- Warning line shown above the status text (for example, overly long lines).
local warningLabel = editor:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontNormalSmall"
)

warningLabel:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 16, 68)
warningLabel:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -16, 68)
warningLabel:SetJustifyH("LEFT")
warningLabel:SetWordWrap(false)

-- Script selector row: [<]  Script name (1/2)  [>]      [New][Rename][Delete]
local editorPrevButton = CreateFrame(
    "Button",
    nil,
    editor,
    "UIPanelButtonTemplate"
)

editorPrevButton:SetSize(22, 22)
editorPrevButton:SetPoint("TOPLEFT", editor, "TOPLEFT", 15, -42)
editorPrevButton:SetText("<")

local editorScriptName = editor:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
)

editorScriptName:SetSize(140, 22)
editorScriptName:SetPoint("LEFT", editorPrevButton, "RIGHT", 6, 0)
editorScriptName:SetJustifyH("CENTER")
editorScriptName:SetWordWrap(false)

local editorNextButton = CreateFrame(
    "Button",
    nil,
    editor,
    "UIPanelButtonTemplate"
)

editorNextButton:SetSize(22, 22)
editorNextButton:SetPoint("LEFT", editorScriptName, "RIGHT", 6, 0)
editorNextButton:SetText(">")

local deleteScriptButton = CreateFrame(
    "Button",
    nil,
    editor,
    "UIPanelButtonTemplate"
)

deleteScriptButton:SetSize(52, 22)
deleteScriptButton:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -15, -42)
deleteScriptButton:SetText("Delete")

local renameScriptButton = CreateFrame(
    "Button",
    nil,
    editor,
    "UIPanelButtonTemplate"
)

renameScriptButton:SetSize(56, 22)
renameScriptButton:SetPoint("RIGHT", deleteScriptButton, "LEFT", -4, 0)
renameScriptButton:SetText("Rename")

local newScriptButton = CreateFrame(
    "Button",
    nil,
    editor,
    "UIPanelButtonTemplate"
)

newScriptButton:SetSize(40, 22)
newScriptButton:SetPoint("RIGHT", renameScriptButton, "LEFT", -4, 0)
newScriptButton:SetText("New")

-------------------------------------------------------------------------------
-- COMPACT PRESENTER FRAME
-------------------------------------------------------------------------------

local presenter = CreateFrame(
    "Frame",
    "TourNarratorPresenterFrame",
    UIParent,
    "BackdropTemplate"
)

presenter:SetSize(360, 200)
presenter:SetPoint("CENTER", 150, 0)
presenter:SetMovable(true)
presenter:EnableMouse(true)
presenter:RegisterForDrag("LeftButton")
presenter:SetScript("OnDragStart", presenter.StartMoving)
presenter:SetScript("OnDragStop", presenter.StopMovingOrSizing)
presenter:Hide()

presenter:SetBackdrop({
    bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
    edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
    tile = true,
    tileSize = 12,
    edgeSize = 12,
    insets = {
        left = 3,
        right = 3,
        top = 3,
        bottom = 3,
    },
})

presenter:SetBackdropColor(0, 0, 0, 0.95)
presenter:SetBackdropBorderColor(0.8, 0.6, 0, 1)

local presenterTitle = presenter:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontNormalSmall"
)

presenterTitle:SetPoint("TOPLEFT", presenter, "TOPLEFT", 12, -8)
presenterTitle:SetText("TOUR PRESENTER")

-- Stage direction from the most recent "##" comment line in the script.
local directionLabel = presenter:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightSmall"
)

directionLabel:SetPoint("TOPLEFT", presenter, "TOPLEFT", 12, -50)
directionLabel:SetPoint("TOPRIGHT", presenter, "TOPRIGHT", -12, -50)
directionLabel:SetJustifyH("LEFT")
directionLabel:SetJustifyV("TOP")
directionLabel:SetMaxLines(3)
directionLabel:SetText("")

local queueLabel = presenter:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontNormalSmall"
)

queueLabel:SetPoint("TOPLEFT", directionLabel, "BOTTOMLEFT", 0, -6)
queueLabel:SetTextColor(0.7, 0.7, 0.7)
queueLabel:SetText("NEXT LINE QUEUED:")

local previewText = presenter:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlight"
)

previewText:SetPoint("TOPLEFT", queueLabel, "BOTTOMLEFT", 0, -4)
previewText:SetPoint("BOTTOMRIGHT", presenter, "BOTTOMRIGHT", -12, 42)
previewText:SetJustifyH("LEFT")
previewText:SetJustifyV("TOP")
previewText:SetText("No text loaded.")

-- Script selector row: [<]  Script name (1/2)  [>]
local presenterPrevButton = CreateFrame(
    "Button",
    nil,
    presenter,
    "UIPanelButtonTemplate"
)

presenterPrevButton:SetSize(22, 18)
presenterPrevButton:SetPoint("TOPLEFT", presenter, "TOPLEFT", 10, -27)
presenterPrevButton:SetText("<")

local presenterNextButton = CreateFrame(
    "Button",
    nil,
    presenter,
    "UIPanelButtonTemplate"
)

presenterNextButton:SetSize(22, 18)
presenterNextButton:SetPoint("TOPRIGHT", presenter, "TOPRIGHT", -10, -27)
presenterNextButton:SetText(">")

local presenterScriptName = presenter:CreateFontString(
    nil,
    "OVERLAY",
    "GameFontHighlightSmall"
)

presenterScriptName:SetPoint("LEFT", presenterPrevButton, "RIGHT", 6, 0)
presenterScriptName:SetPoint("RIGHT", presenterNextButton, "LEFT", -6, 0)
presenterScriptName:SetJustifyH("CENTER")
presenterScriptName:SetWordWrap(false)

-------------------------------------------------------------------------------
-- SCRIPT STORAGE HELPERS
-------------------------------------------------------------------------------

-- While true, changes to the edit box are NOT written back to the database.
-- This is set whenever the addon itself swaps the text (switching scripts), so
-- a programmatic SetText can never overwrite the wrong script.
local isLoadingScript = false

local function GetActiveScript()
    local scripts = TourNarratorDB.scripts
    return scripts and scripts[TourNarratorDB.activeScript]
end

local function RefreshScriptLabels()
    local scripts = TourNarratorDB.scripts
    local active = GetActiveScript()
    local label = "|cFF888888(no script)|r"

    if active then
        label = string.format(
            "%s (%d/%d)",
            active.name,
            TourNarratorDB.activeScript,
            #scripts
        )
    end

    editorScriptName:SetText(label)
    presenterScriptName:SetText(label)
end

-------------------------------------------------------------------------------
-- SCRIPT PARSING AND STATUS UPDATES
-------------------------------------------------------------------------------

-- Lines longer than MAX_CHAT_MESSAGE_LENGTH are cut off when sent. The parser
-- records how many there are, and the position of the first one, so the
-- editor and presenter can warn about them.
local longLineCount = 0
local firstLongLine = nil

-- Lines starting with "##" are comments (stage directions). They are never
-- sent. Each line remembers the most recent comment above it, and the last
-- comment in the script is kept for when the script has finished.
local scriptEndDirection = nil

local function ParseTextToLines()
    wipe(scriptLines)
    longLineCount = 0
    firstLongLine = nil
    scriptEndDirection = nil

    local text = editBox:GetText() or ""
    local currentChatType = "SAY"
    local currentColor = "|cFFFFFFFF"
    local currentDirection = nil

    -- Ignore empty lines and normalise surrounding whitespace.
    for line in text:gmatch("[^\r\n]+") do
        line = line:match("^%s*(.-)%s*$")

        if line:sub(1, 2) == "##" then
            -- A comment. An empty "##" line is ignored.
            local comment = line:sub(3):match("^%s*(.-)%s*$")

            if comment ~= "" then
                currentDirection = comment
                scriptEndDirection = comment
            end
        elseif line ~= "" then
            -- A prefix updates the chat type for this line and subsequent
            -- lines. Only the first matching prefix is removed.
            local matchedPrefix = false

            for _, prefix in ipairs(CHAT_PREFIXES) do
                if line:match(prefix.pattern) then
                    currentChatType = prefix.type
                    currentColor = prefix.color
                    line = line:gsub(prefix.pattern, "", 1)
                    matchedPrefix = true
                    break
                end
            end

            -- Standard emote commands (/bow, /sit, ...) become action lines.
            -- They don't change the chat type used by the lines around them.
            local emoteToken, emoteTarget

            if not matchedPrefix then
                local command, rest = line:match("^(/%S+)%s*(.-)$")

                if command then
                    emoteToken = GetEmoteToken(command)

                    if emoteToken and rest ~= "" then
                        emoteTarget = rest
                    end
                end
            end

            if emoteToken then
                scriptLines[#scriptLines + 1] = {
                    text = line,
                    type = ACTION_TYPE,
                    color = ACTION_COLOR,
                    emoteToken = emoteToken,
                    emoteTarget = emoteTarget,
                    tooLong = false,
                    direction = currentDirection,
                }
            elseif line ~= "" then
                local tooLong = #line > MAX_CHAT_MESSAGE_LENGTH

                scriptLines[#scriptLines + 1] = {
                    text = line,
                    type = currentChatType,
                    color = currentColor,
                    tooLong = tooLong,
                    direction = currentDirection,
                }

                if tooLong then
                    longLineCount = longLineCount + 1
                    firstLongLine = firstLongLine or #scriptLines
                end
            end
        end
    end
end

-- The stage direction that applies to the queued line: the last comment above
-- it. Once the script has finished, the last comment in the script.
local function GetCurrentDirection()
    local lineData = scriptLines[math.max(TourNarratorIndex, 1)]

    if lineData then
        return lineData.direction
    end

    return scriptEndDirection
end

local function FormatDirection(direction)
    if not direction then
        return ""
    end

    return "|cFF66DD66DIRECTION: " .. direction .. "|r"
end

local QUEUE_LABEL_DEFAULT = "NEXT LINE QUEUED:"
local QUEUE_LABEL_TOO_LONG =
    "NEXT LINE QUEUED:  |cFFFF5555(too long - will be cut off)|r"

local function GetLengthWarning()
    if longLineCount == 0 then
        return ""
    end

    if longLineCount == 1 then
        return string.format(
            "|cFFFF5555! Line %d is over %d characters and will be cut off.|r",
            firstLongLine,
            MAX_CHAT_MESSAGE_LENGTH
        )
    end

    return string.format(
        "|cFFFF5555! %d lines are over %d characters and will be cut off " ..
        "(first: line %d).|r",
        longLineCount,
        MAX_CHAT_MESSAGE_LENGTH,
        firstLongLine
    )
end

-- Removes a trailing colour/link sequence that was cut off before its "|r",
-- which would otherwise render as broken text.
local function TrimUnfinishedEscape(text)
    local _, opened = text:gsub("|c", "")
    local _, closed = text:gsub("|r", "")

    if opened > closed then
        local lastOpen
        local init = 1

        while true do
            local found = text:find("|c", init, true)

            if not found then
                break
            end

            lastOpen = found
            init = found + 1
        end

        if lastOpen then
            text = text:sub(1, lastOpen - 1)
        end
    end

    -- A lone trailing pipe would combine with whatever follows it.
    if text:sub(-1) == "|" then
        text = text:sub(1, -2)
    end

    return text
end

-- Shortens text to maxLength bytes (including the "..."), without splitting
-- a multi-byte UTF-8 character or leaving a half-finished colour/link code.
-- Used on every line before it is sent to chat.
local function TruncateText(text, maxLength)
    if #text <= maxLength then
        return text
    end

    local cut = math.max(maxLength - 3, 0)

    -- If the first dropped byte is a continuation byte (10xxxxxx), the cut
    -- would land inside a character, so step back to the character's start.
    while cut > 0 do
        local nextByte = text:byte(cut + 1)

        if nextByte < 0x80 or nextByte >= 0xC0 then
            break
        end

        cut = cut - 1
    end

    return TrimUnfinishedEscape(text:sub(1, cut)) .. "..."
end

local function UpdateStatusAll()
    RefreshScriptLabels()
    ParseTextToLines()

    warningLabel:SetText(GetLengthWarning())
    queueLabel:SetText(QUEUE_LABEL_DEFAULT)
    directionLabel:SetText(FormatDirection(GetCurrentDirection()))

    local totalLines = #scriptLines

    if totalLines == 0 then
        statusLabel:SetText("No text detected.")
        previewText:SetText("|cFF888888[Empty script context]|r")
        return
    end

    if TourNarratorIndex > totalLines then
        statusLabel:SetText("Finished! (Click Restart to loop)")
        previewText:SetText(
            "|cFF00FF00Script completed successfully! Click Restart.|r"
        )
        return
    end

    -- Keep the current index within the valid range if the script shrinks.
    if TourNarratorIndex < 1 then
        TourNarratorIndex = 1
    end

    local lineData = scriptLines[TourNarratorIndex]

    statusLabel:SetText(string.format(
        "Ready: Line %d of %d [%s]",
        TourNarratorIndex,
        totalLines,
        lineData.type
    ))

    if lineData.tooLong then
        queueLabel:SetText(QUEUE_LABEL_TOO_LONG)
    end

    -- The whole line is shown. The presenter can be resized to fit it.
    local label = string.format("[%s]: ", lineData.type)

    previewText:SetText(
        string.format("%s%s%s|r", lineData.color, label, lineData.text)
    )
end

-------------------------------------------------------------------------------
-- SCRIPT EDITOR EVENTS
-------------------------------------------------------------------------------

editBox:SetScript("OnTextChanged", function(self)
    if not isLoadingScript then
        local active = GetActiveScript()

        if active then
            active.text = self:GetText()
        end
    end

    UpdateStatusAll()
end)

-------------------------------------------------------------------------------
-- SCRIPT EDITOR BEHAVIOUR
-------------------------------------------------------------------------------

-- A multi-line edit box inside a scroll frame is only as tall as its text and
-- doesn't scroll by itself. The code below makes the whole text area behave
-- like a normal text editor.

-- Keep the edit box as wide as the visible area, so there is no dead strip at
-- the right-hand edge.
scrollArea:HookScript("OnSizeChanged", function(_, width)
    if width and width > 0 then
        editBox:SetWidth(width)
    end
end)

-- Clicking empty space below the text (or anywhere the edit box doesn't
-- reach) focuses the editor and places the cursor at the end of the text.
scrollArea:EnableMouse(true)

scrollArea:SetScript("OnMouseDown", function(_, button)
    if button == "LeftButton" then
        editBox:SetFocus()
        editBox:SetCursorPosition(editBox:GetNumLetters())
    end
end)

-- Escape leaves the editor, so keybinds work again.
editBox:SetScript("OnEscapePressed", function(self)
    self:ClearFocus()
end)

-- Scroll to keep the cursor in view while typing or moving it. The scroll is
-- applied on the next frame, because the scroll range is only updated once
-- WoW has re-measured the text.
local pendingCursorTop = nil
local pendingCursorHeight = 0

editBox:SetScript("OnCursorChanged", function(self, _, y, _, height)
    if self:HasFocus() and not isLoadingScript then
        pendingCursorTop = -y
        pendingCursorHeight = height or 0
    end
end)

-- While drag-selecting with the mouse held above or below the text area, scroll
-- in that direction. The further outside the mouse is, the faster it scrolls.
local EDGE_SCROLL_SPEED = 8          -- pixels per second, per pixel outside
local EDGE_SCROLL_MAX_DISTANCE = 60  -- pixels outside the area that count

local mouseWasDown = false
local dragSelecting = false

local function ScrollToCursor()
    if not pendingCursorTop then
        return
    end

    local cursorTop = pendingCursorTop
    local cursorBottom = pendingCursorTop + pendingCursorHeight
    pendingCursorTop = nil

    local viewHeight = scrollArea:GetHeight()
    local scroll = scrollArea:GetVerticalScroll()

    if cursorTop < scroll then
        scrollArea:SetVerticalScroll(cursorTop)
    elseif cursorBottom > scroll + viewHeight then
        scrollArea:SetVerticalScroll(cursorBottom - viewHeight)
    end
end

local function ScrollWhileDragging(elapsed)
    local mouseDown = IsMouseButtonDown("LeftButton")

    if not mouseDown then
        mouseWasDown = false
        dragSelecting = false
        return
    end

    -- Only a drag that started inside the text area counts. This keeps
    -- dragging the scroll bar or other buttons from triggering it.
    if not mouseWasDown then
        mouseWasDown = true
        dragSelecting = scrollArea:IsMouseOver()
    end

    if not dragSelecting or not editBox:HasFocus() then
        return
    end

    local top = scrollArea:GetTop()
    local bottom = scrollArea:GetBottom()

    if not top or not bottom then
        return
    end

    local _, mouseY = GetCursorPosition()
    mouseY = mouseY / scrollArea:GetEffectiveScale()

    local outside = 0

    if mouseY > top then
        outside = mouseY - top           -- above the text area: scroll up
    elseif mouseY < bottom then
        outside = mouseY - bottom        -- below the text area: scroll down
    end

    if outside == 0 then
        return
    end

    local distance = math.min(math.abs(outside), EDGE_SCROLL_MAX_DISTANCE)
    local step = distance * EDGE_SCROLL_SPEED * elapsed

    if outside > 0 then
        step = -step
    end

    local newScroll = scrollArea:GetVerticalScroll() + step
    newScroll = math.max(0, math.min(newScroll, scrollArea:GetVerticalScrollRange()))

    scrollArea:SetVerticalScroll(newScroll)
end

editBox:SetScript("OnUpdate", function(_, elapsed)
    ScrollToCursor()
    ScrollWhileDragging(elapsed)
end)

-------------------------------------------------------------------------------
-- PRESENTER ACTIONS
-------------------------------------------------------------------------------

-- Performs a standard emote such as /bow, aimed at the player's current
-- target unless the script line names someone else (or "none").
local function PerformEmoteAction(lineData)
    local perform = (C_ChatInfo and C_ChatInfo.PerformEmote) or DoEmote

    if not perform then
        return
    end

    local restricted

    if lineData.emoteTarget then
        restricted = perform(lineData.emoteToken, lineData.emoteTarget)
    else
        restricted = perform(lineData.emoteToken)
    end

    -- WoW reports emotes that this character can't use (for example, a
    -- faction-only emote).
    if restricted then
        print(
            "|cFF00FF00[Tour Narrator]|r Your character can't use " ..
            lineData.text:match("^%S+") .. "."
        )
    end
end

local function FireCurrentLine()
    ParseTextToLines()

    local lineData = scriptLines[TourNarratorIndex]

    if not lineData then
        UpdateStatusAll()
        return
    end

    if lineData.emoteToken then
        PerformEmoteAction(lineData)
        TourNarratorIndex = TourNarratorIndex + 1
        UpdateStatusAll()
        return
    end

    -- WoW can disconnect a player who sends a chat message that is too long,
    -- so over-long lines are always cut down here (without splitting a
    -- multi-byte character or leaving a broken colour/link code).
    local message = TruncateText(lineData.text, MAX_CHAT_MESSAGE_LENGTH)

    -- Use the namespaced API when available, otherwise fall back to the
    -- standard WoW chat function.
    if C_ChatInfo and C_ChatInfo.SendChatMessage then
        C_ChatInfo.SendChatMessage(message, lineData.type)
    else
        SendChatMessage(message, lineData.type)
    end

    TourNarratorIndex = TourNarratorIndex + 1
    UpdateStatusAll()
end

local function StepBackward()
    if TourNarratorIndex > 1 then
        TourNarratorIndex = TourNarratorIndex - 1
    end

    UpdateStatusAll()
end

local function StepForwardSkip()
    ParseTextToLines()

    if TourNarratorIndex <= #scriptLines then
        TourNarratorIndex = TourNarratorIndex + 1
    end

    UpdateStatusAll()
end

local function ResetSequence()
    TourNarratorIndex = 1
    UpdateStatusAll()
end

-------------------------------------------------------------------------------
-- SCRIPT MANAGEMENT
-------------------------------------------------------------------------------

-- Database layout:
--   TourNarratorDB.scripts      = { { name = "...", text = "..." }, ... }
--   TourNarratorDB.activeScript = index into scripts
--   TourNarratorDB.savedText    = legacy single-script text (kept as a backup,
--                                 no longer read once scripts exist)
local function EnsureDatabase()
    TourNarratorDB = TourNarratorDB or {}

    local db = TourNarratorDB
    db.minimapAngle = db.minimapAngle or DEFAULT_MINIMAP_ANGLE

    -- Migrate from the old single-script format, or create a first script.
    if type(db.scripts) ~= "table" or #db.scripts == 0 then
        db.scripts = {
            { name = "Script 1", text = db.savedText or "" },
        }
        db.activeScript = 1
    end

    if not db.scripts[db.activeScript or 0] then
        db.activeScript = 1
    end

    -- Version of the saved-data layout (1 = multiple scripts). A future update
    -- can check this to convert older data safely.
    db.dbVersion = db.dbVersion or 1
end

-- Puts the active script's text into the editor and restarts at line 1.
local function LoadActiveScript()
    local active = GetActiveScript()

    isLoadingScript = true
    editBox:SetText(active and active.text or "")
    isLoadingScript = false

    scrollArea:SetVerticalScroll(0)
    TourNarratorIndex = 1
    UpdateStatusAll()
end

-- Selects a script by position. Wraps around at either end.
local function SwitchScript(position)
    local scripts = TourNarratorDB.scripts

    if not scripts or #scripts == 0 then
        return
    end

    TourNarratorDB.activeScript = ((position - 1) % #scripts) + 1

    editBox:ClearFocus()
    LoadActiveScript()
end

-- Finds a script by exact name, then number, then name prefix.
local function FindScript(query)
    query = strlower(strtrim(query or ""))

    if query == "" then
        return nil
    end

    local scripts = TourNarratorDB.scripts

    for index, script in ipairs(scripts) do
        if strlower(script.name) == query then
            return index
        end
    end

    local number = tonumber(query)

    if number and scripts[number] then
        return number
    end

    for index, script in ipairs(scripts) do
        if strlower(script.name):sub(1, #query) == query then
            return index
        end
    end

    return nil
end

local function CreateScript(name)
    name = strtrim(name or "")

    if name == "" then
        return
    end

    local scripts = TourNarratorDB.scripts
    scripts[#scripts + 1] = { name = name, text = "" }

    SwitchScript(#scripts)
end

local function RenameActiveScript(name)
    name = strtrim(name or "")

    local active = GetActiveScript()

    if name == "" or not active then
        return
    end

    active.name = name
    RefreshScriptLabels()
end

local function DeleteActiveScript()
    local scripts = TourNarratorDB.scripts

    if #scripts <= 1 then
        print("|cFF00FF00[Tour Narrator]|r You can't delete your only script.")
        return
    end

    local position = TourNarratorDB.activeScript
    table.remove(scripts, position)

    SwitchScript(math.min(position, #scripts))
end

-- Reads the text box of a StaticPopup across WoW versions.
local function GetPopupText(popup)
    local box = (popup.GetEditBox and popup:GetEditBox())
        or popup.EditBox
        or popup.editBox

    return box and box:GetText() or ""
end

StaticPopupDialogs["TOURNARRATOR_NEW_SCRIPT"] = {
    text = "Name for the new script:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 40,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = function(self)
        CreateScript(GetPopupText(self))
    end,
    EditBoxOnEnterPressed = function(self)
        CreateScript(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
}

StaticPopupDialogs["TOURNARRATOR_RENAME_SCRIPT"] = {
    text = "New name for this script:",
    button1 = ACCEPT,
    button2 = CANCEL,
    hasEditBox = true,
    maxLetters = 40,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnShow = function(self)
        local box = (self.GetEditBox and self:GetEditBox())
            or self.EditBox
            or self.editBox
        local active = GetActiveScript()

        if box and active then
            box:SetText(active.name)
            box:HighlightText()
        end
    end,
    OnAccept = function(self)
        RenameActiveScript(GetPopupText(self))
    end,
    EditBoxOnEnterPressed = function(self)
        RenameActiveScript(self:GetText())
        self:GetParent():Hide()
    end,
    EditBoxOnEscapePressed = function(self)
        self:GetParent():Hide()
    end,
}

StaticPopupDialogs["TOURNARRATOR_DELETE_SCRIPT"] = {
    text = "Delete the script \"%s\"? This cannot be undone.",
    button1 = "Delete",
    button2 = CANCEL,
    showAlert = true,
    timeout = 0,
    whileDead = true,
    hideOnEscape = true,
    preferredIndex = 3,
    OnAccept = DeleteActiveScript,
}

-- Selector and management buttons.
local function SelectPrevious()
    SwitchScript(TourNarratorDB.activeScript - 1)
end

local function SelectNext()
    SwitchScript(TourNarratorDB.activeScript + 1)
end

editorPrevButton:SetScript("OnClick", SelectPrevious)
editorNextButton:SetScript("OnClick", SelectNext)
presenterPrevButton:SetScript("OnClick", SelectPrevious)
presenterNextButton:SetScript("OnClick", SelectNext)

newScriptButton:SetScript("OnClick", function()
    StaticPopup_Show("TOURNARRATOR_NEW_SCRIPT")
end)

renameScriptButton:SetScript("OnClick", function()
    if GetActiveScript() then
        StaticPopup_Show("TOURNARRATOR_RENAME_SCRIPT")
    end
end)

deleteScriptButton:SetScript("OnClick", function()
    local active = GetActiveScript()

    if active then
        StaticPopup_Show("TOURNARRATOR_DELETE_SCRIPT", active.name)
    end
end)

-------------------------------------------------------------------------------
-- PUBLIC API (used by Key Bindings and slash commands)
-------------------------------------------------------------------------------

-- Keybinds and macros can be used while the presenter window is hidden, so
-- these wrappers print a short chat message in that case.
local function Feedback(message)
    if not presenter:IsShown() then
        print("|cFF00FF00[Tour Narrator]|r " .. message)
    end
end

-- With the presenter hidden, a keybind or macro user can't see the stage
-- directions, so print each new one to chat.
local lastReportedDirection = nil

local function ReportDirection()
    local direction = GetCurrentDirection()

    if direction and direction ~= lastReportedDirection then
        Feedback("|cFF66DD66Direction: " .. direction .. "|r")
    end

    lastReportedDirection = direction
end

TourNarrator = TourNarrator or {}

function TourNarrator.SendNext()
    FireCurrentLine()

    if TourNarratorIndex > #scriptLines and #scriptLines > 0 then
        Feedback("Script finished. Use Restart to start again.")
    end

    ReportDirection()
end

function TourNarrator.Skip()
    StepForwardSkip()
    Feedback(statusLabel:GetText())
    ReportDirection()
end

function TourNarrator.Back()
    StepBackward()
    Feedback(statusLabel:GetText())
    ReportDirection()
end

function TourNarrator.Reset()
    ResetSequence()
    Feedback(statusLabel:GetText())
    ReportDirection()
end

local function ReportActiveScript()
    local active = GetActiveScript()

    if active then
        Feedback(string.format(
            "Switched to \"%s\" (%d/%d), starting at line 1.",
            active.name,
            TourNarratorDB.activeScript,
            #TourNarratorDB.scripts
        ))

        -- A different script has different directions, so report afresh.
        lastReportedDirection = nil
        ReportDirection()
    end
end

function TourNarrator.NextScript()
    SelectNext()
    ReportActiveScript()
end

function TourNarrator.PrevScript()
    SelectPrevious()
    ReportActiveScript()
end

-- Accepts a script name (or the start of one) or its number.
function TourNarrator.SelectScript(query)
    local position = FindScript(query)

    if not position then
        print(
            "|cFF00FF00[Tour Narrator]|r No script matches \"" ..
            strtrim(query or "") .. "\". Use /tn scripts to list them."
        )
        return
    end

    SwitchScript(position)
    ReportActiveScript()
end

-------------------------------------------------------------------------------
-- EDITOR BUTTONS
-------------------------------------------------------------------------------

local editorCloseButton = CreateFrame(
    "Button",
    nil,
    editor,
    "UIPanelButtonTemplate"
)

editorCloseButton:SetSize(24, 24)
editorCloseButton:SetPoint("TOPRIGHT", editor, "TOPRIGHT", -8, -8)
editorCloseButton:SetText("X")
editorCloseButton:SetScript("OnClick", function()
    editor:Hide()
end)

local editorSendButton = CreateFrame(
    "Button",
    nil,
    editor,
    "UIPanelButtonTemplate"
)

editorSendButton:SetSize(130, 30)
editorSendButton:SetPoint("BOTTOMLEFT", editor, "BOTTOMLEFT", 15, 14)
editorSendButton:SetText("Send Next Line")
editorSendButton:SetScript("OnClick", FireCurrentLine)

local saveCloseButton = CreateFrame(
    "Button",
    nil,
    editor,
    "UIPanelButtonTemplate"
)

saveCloseButton:SetSize(120, 30)
saveCloseButton:SetPoint("BOTTOMRIGHT", editor, "BOTTOMRIGHT", -15, 14)
saveCloseButton:SetText("Save and Close")

saveCloseButton:SetScript("OnClick", function()
    local active = GetActiveScript()

    if active then
        active.text = editBox:GetText() or ""
    end

    UpdateStatusAll()
    editor:Hide()
end)

-------------------------------------------------------------------------------
-- PRESENTER BUTTONS
-------------------------------------------------------------------------------

local presenterCloseButton = CreateFrame(
    "Button",
    nil,
    presenter,
    "UIPanelButtonTemplate"
)

presenterCloseButton:SetSize(18, 18)
presenterCloseButton:SetPoint("TOPRIGHT", presenter, "TOPRIGHT", -6, -6)
presenterCloseButton:SetText("X")
presenterCloseButton:SetScript("OnClick", function()
    presenter:Hide()
end)

local presenterResetButton = CreateFrame(
    "Button",
    nil,
    presenter,
    "UIPanelButtonTemplate"
)

presenterResetButton:SetSize(58, 18)
presenterResetButton:SetPoint("RIGHT", presenterCloseButton, "LEFT", -4, 0)
presenterResetButton:SetText("Restart")
presenterResetButton:SetScript("OnClick", ResetSequence)

local presenterBackButton = CreateFrame(
    "Button",
    nil,
    presenter,
    "UIPanelButtonTemplate"
)

presenterBackButton:SetSize(65, 24)
presenterBackButton:SetText("Back")
presenterBackButton:SetScript("OnClick", StepBackward)

local presenterSendButton = CreateFrame(
    "Button",
    nil,
    presenter,
    "UIPanelButtonTemplate"
)

presenterSendButton:SetSize(200, 24)
presenterSendButton:SetPoint("BOTTOM", presenter, "BOTTOM", 0, 10)

-- Buttons keep their size when the window is resized; the group simply stays
-- centred along the bottom edge.
presenterBackButton:SetPoint("RIGHT", presenterSendButton, "LEFT", -5, 0)
presenterSendButton:SetText("Send Next Line")
presenterSendButton:SetScript("OnClick", FireCurrentLine)

local presenterSkipButton = CreateFrame(
    "Button",
    nil,
    presenter,
    "UIPanelButtonTemplate"
)

presenterSkipButton:SetSize(65, 24)
presenterSkipButton:SetPoint("LEFT", presenterSendButton, "RIGHT", 5, 0)
presenterSkipButton:SetText("Skip")
presenterSkipButton:SetScript("OnClick", StepForwardSkip)

-------------------------------------------------------------------------------
-- TOOLTIPS
-------------------------------------------------------------------------------

-- Shows a tooltip with a title and an optional description on mouse-over.
local function AddTooltip(widget, title, description, anchor)
    widget:HookScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, anchor or "ANCHOR_TOP")
        GameTooltip:SetText(title, 1, 1, 1)

        if description then
            GameTooltip:AddLine(description, 1, 0.82, 0, true)
        end

        GameTooltip:Show()
    end)

    widget:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end

-------------------------------------------------------------------------------
-- HELP WINDOW
-------------------------------------------------------------------------------

do
    local HELP_WIDTH = 430

    local function Heading(text)
        return "|cFFFFD100" .. text .. "|r"
    end

    local helpLines = {
        Heading("Quick start"),
        "Right-click the minimap button (or type /tn) to open the Script Editor. " ..
        "Type or paste your script, with one chat line per line of text. " ..
        "Left-click the minimap button to open the Presenter, then press " ..
        "Send to send each line.",
        "",
        Heading("Chat types"),
        "Start a line with a prefix to change how it is sent. The type stays " ..
        "active until you use another prefix.",
        "/s or /say - Say (the default)",
        "/e, /emote or /me - Emote text",
        "/y or /yell - Yell",
        "/p or /party - Party",
        "/ra or /raid - Raid",
        "/g or /guild - Guild",
        "",
        Heading("Emote commands"),
        "Standard emotes such as /bow, /sit or /laugh work when put on their " ..
        "own line. They are aimed at your target. Add a name to aim at someone " ..
        "else (/bow Thrall), or the word none to aim at nobody.",
        "",
        Heading("Comments and directions"),
        "A line starting with ## is never sent. The Presenter shows the most " ..
        "recent one in green as a direction, which is handy for notes such as " ..
        "where to stand.",
        "",
        Heading("Presenter buttons"),
        "Send - sends the queued line and moves on.",
        "Skip - moves past the queued line without sending it.",
        "Back - steps back one line.",
        "Restart - goes back to line 1. Your script text is not changed.",
        "",
        Heading("Multiple scripts"),
        "Use the < and > buttons to switch between scripts. Switching always " ..
        "starts at line 1. New, Rename and Delete manage your scripts.",
        "",
        Heading("Keybinds and macros"),
        "Set keys under Options > Keybindings > AddOns > Tour Narrator. In " ..
        "macros you can use /tn next, /tn skip, /tn back, /tn restart and " ..
        "/tn script <name>.",
        "",
        Heading("Tips"),
        "Lines over 250 characters are cut off when sent, and a red warning " ..
        "appears in the editor.",
        "Press Esc to leave the editor so your keybinds work again.",
        "Drag the corner handle of a window to resize it.",
        "If something goes wrong, type /console scriptErrors 1 and tell the " ..
        "author what the error message says.",
    }

    local helpFrame = CreateFrame(
        "Frame",
        "TourNarratorHelpFrame",
        UIParent,
        "BackdropTemplate"
    )

    helpFrame:SetSize(HELP_WIDTH, 470)
    helpFrame:SetPoint("TOPLEFT", editor, "TOPRIGHT", 8, 0)
    helpFrame:SetClampedToScreen(true)
    helpFrame:SetToplevel(true)
    helpFrame:SetMovable(true)
    helpFrame:EnableMouse(true)
    helpFrame:RegisterForDrag("LeftButton")
    helpFrame:SetScript("OnDragStart", helpFrame.StartMoving)
    helpFrame:SetScript("OnDragStop", helpFrame.StopMovingOrSizing)
    helpFrame:Hide()

    helpFrame:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\DialogFrame\\UI-DialogBox-Border",
        tile = true,
        tileSize = 16,
        edgeSize = 16,
        insets = { left = 4, right = 4, top = 4, bottom = 4 },
    })

    helpFrame:SetBackdropColor(0, 0, 0, 0.9)

    -- Escape closes the help window.
    if UISpecialFrames then
        table.insert(UISpecialFrames, "TourNarratorHelpFrame")
    end

    local helpTitle = helpFrame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontNormalLarge"
    )

    helpTitle:SetPoint("TOPLEFT", helpFrame, "TOPLEFT", 16, -14)
    helpTitle:SetText("Tour Narrator — Help")

    local getMetadata = (C_AddOns and C_AddOns.GetAddOnMetadata)
        or GetAddOnMetadata
    local version = getMetadata and getMetadata(ADDON_NAME, "Version")
        or "unknown"

    local versionText = helpFrame:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlightSmall"
    )

    versionText:SetPoint("TOPLEFT", helpFrame, "TOPLEFT", 16, -40)
    versionText:SetText("Version " .. version)

    local helpCloseButton = CreateFrame(
        "Button",
        nil,
        helpFrame,
        "UIPanelButtonTemplate"
    )

    helpCloseButton:SetSize(24, 24)
    helpCloseButton:SetPoint("TOPRIGHT", helpFrame, "TOPRIGHT", -8, -8)
    helpCloseButton:SetText("X")
    helpCloseButton:SetScript("OnClick", function()
        helpFrame:Hide()
    end)

    local helpScroll = CreateFrame(
        "ScrollFrame",
        nil,
        helpFrame,
        "UIPanelScrollFrameTemplate"
    )

    helpScroll:SetPoint("TOPLEFT", helpFrame, "TOPLEFT", 16, -62)
    helpScroll:SetPoint("BOTTOMRIGHT", helpFrame, "BOTTOMRIGHT", -34, 16)

    local helpContent = CreateFrame("Frame", nil, helpScroll)
    helpContent:SetSize(HELP_WIDTH - 60, 10)
    helpScroll:SetScrollChild(helpContent)

    local helpText = helpContent:CreateFontString(
        nil,
        "OVERLAY",
        "GameFontHighlight"
    )

    helpText:SetPoint("TOPLEFT", helpContent, "TOPLEFT", 0, 0)
    helpText:SetWidth(HELP_WIDTH - 66)
    helpText:SetJustifyH("LEFT")
    helpText:SetJustifyV("TOP")
    helpText:SetSpacing(2)
    helpText:SetText(table.concat(helpLines, "\n"))

    -- The scroll area needs to know how tall the text is.
    helpFrame:SetScript("OnShow", function()
        helpContent:SetHeight(helpText:GetStringHeight() + 10)
    end)

    function TourNarrator.ToggleHelp()
        if helpFrame:IsShown() then
            helpFrame:Hide()
        else
            helpFrame:Show()
        end
    end

    -- A "?" button in the editor's title bar, next to the close button.
    local helpButton = CreateFrame(
        "Button",
        nil,
        editor,
        "UIPanelButtonTemplate"
    )

    helpButton:SetSize(24, 24)
    helpButton:SetPoint("RIGHT", editorCloseButton, "LEFT", -4, 0)
    helpButton:SetText("?")
    helpButton:SetScript("OnClick", function()
        TourNarrator.ToggleHelp()
    end)

    AddTooltip(helpButton, "Help", "Opens a quick guide to using Tour Narrator.", "ANCHOR_BOTTOM")
    AddTooltip(helpCloseButton, "Close", nil, "ANCHOR_BOTTOM")
end

-------------------------------------------------------------------------------
-- BUTTON TOOLTIPS
-------------------------------------------------------------------------------

local SEND_TOOLTIP =
    "Sends the queued line to chat (or performs the emote), then moves on " ..
    "to the next line."

local SWITCH_TOOLTIP = "Switches script and starts again from line 1."

AddTooltip(
    presenterResetButton,
    "Restart Script",
    "Goes back to the first line of this script. Your script text is not changed.",
    "ANCHOR_BOTTOM"
)
AddTooltip(presenterCloseButton, "Close", nil, "ANCHOR_BOTTOM")
AddTooltip(presenterPrevButton, "Previous Script", SWITCH_TOOLTIP, "ANCHOR_BOTTOM")
AddTooltip(presenterNextButton, "Next Script", SWITCH_TOOLTIP, "ANCHOR_BOTTOM")

AddTooltip(editorSendButton, "Send Next Line", SEND_TOOLTIP)
AddTooltip(
    saveCloseButton,
    "Save and Close",
    "Your script saves automatically as you type. This just closes the window."
)
AddTooltip(editorCloseButton, "Close", nil, "ANCHOR_BOTTOM")
AddTooltip(editorPrevButton, "Previous Script", SWITCH_TOOLTIP, "ANCHOR_BOTTOM")
AddTooltip(editorNextButton, "Next Script", SWITCH_TOOLTIP, "ANCHOR_BOTTOM")
AddTooltip(newScriptButton, "New Script", "Creates an empty script and switches to it.", "ANCHOR_BOTTOM")
AddTooltip(renameScriptButton, "Rename Script", "Changes the name of the current script.", "ANCHOR_BOTTOM")
AddTooltip(
    deleteScriptButton,
    "Delete Script",
    "Permanently deletes the current script and its text. You will be asked to confirm.",
    "ANCHOR_BOTTOM"
)

-------------------------------------------------------------------------------
-- RESIZABLE WINDOWS
-------------------------------------------------------------------------------

local WINDOW_LIMITS = {
    editor = { minWidth = 400, minHeight = 320, maxWidth = 900, maxHeight = 900 },
    presenter = { minWidth = 350, minHeight = 160, maxWidth = 800, maxHeight = 500 },
}

local function ClampWindowSize(kind, width, height)
    local limits = WINDOW_LIMITS[kind]

    return
        math.max(limits.minWidth, math.min(width, limits.maxWidth)),
        math.max(limits.minHeight, math.min(height, limits.maxHeight))
end

-- Adds a drag handle to the bottom-right corner of a window. The new size is
-- remembered between sessions.
local function MakeResizable(frame, kind)
    local limits = WINDOW_LIMITS[kind]

    frame:SetResizable(true)

    if frame.SetResizeBounds then
        frame:SetResizeBounds(
            limits.minWidth, limits.minHeight,
            limits.maxWidth, limits.maxHeight
        )
    else
        frame:SetMinResize(limits.minWidth, limits.minHeight)
        frame:SetMaxResize(limits.maxWidth, limits.maxHeight)
    end

    local grip = CreateFrame("Button", nil, frame)
    grip:SetSize(16, 16)
    grip:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", -2, 2)
    grip:SetFrameLevel(frame:GetFrameLevel() + 10)
    grip:SetNormalTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Up")
    grip:SetHighlightTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Highlight")
    grip:SetPushedTexture("Interface\\ChatFrame\\UI-ChatIM-SizeGrabber-Down")
    AddTooltip(grip, "Resize", "Drag to resize this window.", "ANCHOR_LEFT")

    grip:SetScript("OnMouseDown", function(_, button)
        if button == "LeftButton" then
            frame:StartSizing("BOTTOMRIGHT")
        end
    end)

    grip:SetScript("OnMouseUp", function()
        frame:StopMovingOrSizing()

        if TourNarratorDB then
            TourNarratorDB[kind .. "Width"] = math.floor(frame:GetWidth() + 0.5)
            TourNarratorDB[kind .. "Height"] = math.floor(frame:GetHeight() + 0.5)
        end
    end)

    return grip
end

MakeResizable(editor, "editor")
MakeResizable(presenter, "presenter")

local function ApplySavedWindowSizes()
    local db = TourNarratorDB
    local windows = { editor = editor, presenter = presenter }

    for kind, frame in pairs(windows) do
        local width = db[kind .. "Width"]
        local height = db[kind .. "Height"]

        if type(width) == "number" and type(height) == "number" then
            frame:SetSize(ClampWindowSize(kind, width, height))
        end
    end
end

-------------------------------------------------------------------------------
-- MINIMAP BUTTON
-------------------------------------------------------------------------------

local minimapButton = CreateFrame(
    "Button",
    "TourNarratorMinimapButton",
    Minimap
)

minimapButton:SetSize(31, 31)
minimapButton:SetFrameLevel(Minimap:GetFrameLevel() + 10)
minimapButton:SetToplevel(true)
minimapButton:SetHighlightTexture(
    "Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight"
)
minimapButton:RegisterForClicks("LeftButtonUp", "RightButtonUp")
minimapButton:RegisterForDrag("LeftButton")

local minimapIcon = minimapButton:CreateTexture(nil, "BACKGROUND")
minimapIcon:SetSize(20, 20)
minimapIcon:SetPoint("CENTER", 0, 0)
minimapIcon:SetTexture("Interface\\AddOns\\TourNarrator\\Media\\TN_Logo.tga")

local minimapBorder = minimapButton:CreateTexture(nil, "OVERLAY")
minimapBorder:SetSize(53, 53)
minimapBorder:SetPoint("TOPLEFT", -1, 1)
minimapBorder:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")

local function PositionMinimapButton(angle)
    local radians = math.rad(angle)
    local x = math.cos(radians) * MINIMAP_RADIUS
    local y = math.sin(radians) * MINIMAP_RADIUS

    minimapButton:ClearAllPoints()
    minimapButton:SetPoint("CENTER", Minimap, "CENTER", x, y)
end

-------------------------------------------------------------------------------
-- MINIMAP BUTTON INTERACTION
-------------------------------------------------------------------------------

minimapButton:SetScript("OnClick", function(_, button)
    if button == "LeftButton" then
        if presenter:IsShown() then
            presenter:Hide()
        else
            presenter:Show()
            UpdateStatusAll()
        end

    elseif button == "RightButton" then
        if editor:IsShown() then
            editor:Hide()
        else
            editor:Show()
            UpdateStatusAll()
        end
    end
end)

minimapButton:SetScript("OnEnter", function(self)
    GameTooltip:SetOwner(self, "ANCHOR_LEFT")
    GameTooltip:AddLine("Tour Narrator", 1, 0.82, 0)
    GameTooltip:AddLine(
        "|cFFFFFFFFLeft-Click:|r Toggle Compact Presenter View",
        1, 1, 1
    )
    GameTooltip:AddLine(
        "|cFFFFFFFFRight-Click:|r Toggle Script Editor Frame",
        1, 1, 1
    )
    GameTooltip:AddLine(
        "Drag icon to adjust minimap placement positions.",
        0.5, 0.5, 0.5
    )
    GameTooltip:Show()
end)

minimapButton:SetScript("OnLeave", function()
    GameTooltip:Hide()
end)

minimapButton:SetScript("OnDragStart", function(self)
    self:LockHighlight()

    self:SetScript("OnUpdate", function()
        local cursorX, cursorY = GetCursorPosition()
        local scale = Minimap:GetEffectiveScale()
        local centerX, centerY = Minimap:GetCenter()

        local angle = math.deg(math.atan2(
            (cursorY / scale) - centerY,
            (cursorX / scale) - centerX
        ))

        TourNarratorDB = TourNarratorDB or {}
        TourNarratorDB.minimapAngle = angle

        PositionMinimapButton(angle)
    end)
end)

minimapButton:SetScript("OnDragStop", function(self)
    self:SetScript("OnUpdate", nil)
    self:UnlockHighlight()
end)

-------------------------------------------------------------------------------
-- SLASH COMMANDS
-------------------------------------------------------------------------------

local function ToggleEditor()
    if editor:IsShown() then
        editor:Hide()
    else
        editor:Show()
        UpdateStatusAll()
    end
end

local function TogglePresenter()
    if presenter:IsShown() then
        presenter:Hide()
    else
        presenter:Show()
        UpdateStatusAll()
    end
end

local function PrintHelp()
    print("|cFF00FF00[Tour Narrator]|r commands:")
    print("  /tn - toggle script editor")
    print("  /tnp - toggle presenter")
    print("  /tn next - send the next line")
    print("  /tn skip - skip the next line")
    print("  /tn back - go back one line")
    print("  /tn restart - go back to line 1")
    print("  /tn scripts - list your saved scripts")
    print("  /tn script <name or number> - switch script (restarts at line 1)")
    print("  /tn nextscript, /tn prevscript - cycle through scripts")
    print("  /tn help - open the help window")
    print("  Shortcuts: /tnnext, /tnskip, /tnback, /tnrestart")
end

local function ListScripts()
    print("|cFF00FF00[Tour Narrator]|r scripts:")

    for index, script in ipairs(TourNarratorDB.scripts or {}) do
        local marker = ""

        if index == TourNarratorDB.activeScript then
            marker = " |cFFFFD100(active)|r"
        end

        print(string.format("  %d. %s%s", index, script.name, marker))
    end
end

-- /tn with no argument keeps its original behaviour (toggle the editor).
SLASH_TOURNARRATOR1 = "/tour"
SLASH_TOURNARRATOR2 = "/tn"

SlashCmdList["TOURNARRATOR"] = function(msg)
    local cmd, arg = (msg or ""):match("^%s*(%S*)%s*(.-)%s*$")
    cmd = strlower(cmd)

    if cmd == "" or cmd == "editor" then
        ToggleEditor()
    elseif cmd == "next" or cmd == "send" then
        TourNarrator.SendNext()
    elseif cmd == "skip" then
        TourNarrator.Skip()
    elseif cmd == "back" or cmd == "prev" then
        TourNarrator.Back()
    elseif cmd == "restart" or cmd == "reset" then
        TourNarrator.Reset()
    elseif cmd == "presenter" then
        TogglePresenter()
    elseif cmd == "scripts" then
        ListScripts()
    elseif cmd == "script" then
        if arg == "" then
            ListScripts()
        else
            TourNarrator.SelectScript(arg)
        end
    elseif cmd == "nextscript" then
        TourNarrator.NextScript()
    elseif cmd == "prevscript" then
        TourNarrator.PrevScript()
    elseif cmd == "help" then
        TourNarrator.ToggleHelp()
    else
        PrintHelp()
    end
end

SLASH_TOURNARRATORPRESENTER1 = "/tourp"
SLASH_TOURNARRATORPRESENTER2 = "/tnp"

SlashCmdList["TOURNARRATORPRESENTER"] = TogglePresenter

-- Short, dedicated commands for use in macros.
SLASH_TOURNARRATORNEXT1 = "/tnnext"
SlashCmdList["TOURNARRATORNEXT"] = TourNarrator.SendNext

SLASH_TOURNARRATORSKIP1 = "/tnskip"
SlashCmdList["TOURNARRATORSKIP"] = TourNarrator.Skip

SLASH_TOURNARRATORBACK1 = "/tnback"
SlashCmdList["TOURNARRATORBACK"] = TourNarrator.Back

SLASH_TOURNARRATORRESET1 = "/tnrestart"
SLASH_TOURNARRATORRESET2 = "/tnreset"
SlashCmdList["TOURNARRATORRESET"] = TourNarrator.Reset

-------------------------------------------------------------------------------
-- KEY BINDING LABELS (shown in Options > Keybindings > AddOns)
-------------------------------------------------------------------------------

BINDING_HEADER_TOURNARRATOR = "Tour Narrator"
BINDING_NAME_TOURNARRATOR_NEXT = "Send Next Line"
BINDING_NAME_TOURNARRATOR_SKIP = "Skip Line"
BINDING_NAME_TOURNARRATOR_BACK = "Back One Line"
BINDING_NAME_TOURNARRATOR_RESET = "Restart Script"
BINDING_NAME_TOURNARRATOR_PRESENTER = "Toggle Presenter"

-------------------------------------------------------------------------------
-- ADDON INITIALISATION
-------------------------------------------------------------------------------

editor:RegisterEvent("ADDON_LOADED")

editor:SetScript("OnEvent", function(self, event, addonName)
    if event ~= "ADDON_LOADED" or addonName ~= ADDON_NAME then
        return
    end

    EnsureDatabase()
    ApplySavedWindowSizes()
    LoadActiveScript()

    PositionMinimapButton(TourNarratorDB.minimapAngle)
    minimapButton:Show()

    self:UnregisterEvent("ADDON_LOADED")
end)

-------------------------------------------------------------------------------
-- LOAD MESSAGE
-------------------------------------------------------------------------------

print(
    "|cFF00FF00[Tour Narrator]|r loaded! " ..
    "Left-click minimap for Presenter, Right-click for Script Editor. " ..
    "Type /tn help for commands."
)
