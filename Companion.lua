-- Clique Spellbook Companion: row context menus, using Clique's saved bind-sets.
local _, companion = ...
local menu = {}
companion.bindingMenu = menu

local options = {
    where = {
        {"frames", "Unit frames (default)"},
        {"anyunit", "Any unit under the mouse (hovercast)"},
        {"anywhere", "Anywhere (global)"},
        {"disabled", "Disabled"},
    },
    units = {{"all", "All"}, {"friend", "Friendly"}, {"enemy", "Hostile"}},
    when = {{"always", "Always"}, {"ooc", "Out of combat"}, {"combat", "In combat"}},
}

function menu:Find(addon, binding)
    for index, candidate in ipairs(addon.bindings or {}) do
        if candidate == binding then return index end
    end
end

function menu:Choices(binding)
    local sets = binding.sets or {}
    return {
        where = not next(sets) and "disabled"
            or sets.hovercast and "anyunit" or sets.global and "anywhere" or "frames",
        units = not sets.global and sets.friend and not sets.enemy and "friend"
            or not sets.global and sets.enemy and not sets.friend and "enemy" or "all",
        when = sets.ooc and not sets.combat and "ooc"
            or sets.combat and not sets.ooc and "combat" or "always",
    }
end

function menu:CanChange(addon, binding)
    return not InCombatLockdown() and self:Find(addon, binding) ~= nil
end

function menu:Backup(addon)
    CliqueSpellbookCompanionDB = CliqueSpellbookCompanionDB or {}
    local db = CliqueSpellbookCompanionDB
    db.menuBackups = db.menuBackups or {}
    local profile = addon.db:GetCurrentProfile()
    if not db.menuBackups[profile] then
        db.menuBackups[profile] = {
            bindings = CopyTable(addon.bindings), created = time(), version = companion.version,
        }
    end
end

function menu:SetChoice(addon, binding, group, value, refresh)
    if not self:CanChange(addon, binding) then return false end
    local valid = false
    for _, option in ipairs(options[group] or {}) do
        if option[1] == value then valid = true end
    end
    if not valid then return false end
    local choice = self:Choices(binding)
    if group ~= "where" and choice.where == "disabled" then return false end
    if group == "units" and choice.where == "anywhere" then return false end
    self:Backup(addon)
    -- Only replace the selected dimension. In particular, spec restrictions and
    -- unfamiliar bind-sets must survive quick edits to another setting.
    local sets = CopyTable(binding.sets or {})
    if group == "where" then
        sets.default, sets.hovercast, sets.global = nil, nil, nil
        if value == "disabled" then
            sets = {}
        elseif value == "frames" then
            sets.default = true
        elseif value == "anyunit" then
            sets.hovercast = true
        else
            sets.global = true
            -- Global bindings have no unit to test (same rule as Clique's editor).
            sets.friend, sets.enemy = nil, nil
        end
    elseif group == "units" then
        sets.friend, sets.enemy = nil, nil
        if value ~= "all" then sets[value] = true end
    else
        sets.ooc, sets.combat = nil, nil
        if value ~= "always" then sets[value] = true end
    end
    binding.sets = sets
    addon:FireMessage("BINDINGS_CHANGED")
    refresh(true)
    return true
end

function menu:Delete(addon, binding, refresh)
    if not self:CanChange(addon, binding) then return false end
    self:Backup(addon)
    -- Clique's DeleteBinding matches action/key, which can select a different
    -- binding with identical action/key but different friendly/combat conditions.
    table.remove(addon.bindings, self:Find(addon, binding))
    addon:FireMessage("BINDINGS_CHANGED")
    refresh(true)
    return true
end

function menu:Edit(addon, binding, hide)
    if not self:CanChange(addon, binding) then return false end
    local config = addon.GetBindingConfig and addon:GetBindingConfig()
    if not config or type(config.SwitchToEditPage) ~= "function" then
        addon:Printf("Open Clique's binding editor to edit this binding.")
        return false
    end
    hide()
    addon:ShowBindingConfig()
    config:SwitchToEditPage(binding, false)
    return true
end

function menu:Show(owner, addon, binding, refresh, hide)
    if not self:CanChange(addon, binding) then return end
    if not MenuUtil or not MenuUtil.CreateContextMenu then
        addon:Printf("The binding menu is unavailable on this game client.")
        return
    end
    GameTooltip:Hide()
    MenuUtil.CreateContextMenu(owner, function(_, root)
        root:CreateTitle("Clique binding: " .. addon:GetBindingKeyComboText(binding))
        root:CreateButton("Edit binding...", function() self:Edit(addon, binding, hide) end)
        root:CreateButton("Delete binding", function() self:Delete(addon, binding, refresh) end)
        root:CreateDivider()
        local choice = self:Choices(binding)
        local headings = {
            {"where", "Where the binding is active"},
            {"units", "Which units the binding is active for"},
            {"when", "When the binding is active"},
        }
        for _, heading in ipairs(headings) do
            local group = heading[1]
            local submenu = root:CreateButton(heading[2])
            submenu:SetEnabled(group == "where" or (choice.where ~= "disabled"
                and (group ~= "units" or choice.where ~= "anywhere")))
            for _, option in ipairs(options[group]) do
                local value = option[1]
                submenu:CreateRadio(option[2],
                    function() return self:Choices(binding)[group] == value end,
                    function() self:SetChoice(addon, binding, group, value, refresh) end)
            end
        end
    end)
end

-- Clique Spellbook Companion 1.2.0 - WoW Forever / EllesmereUI classic spellbook.
-- Copyright (c) 2026 Afoekon. MIT License; see LICENSE.
-- Only our own frames capture input; the protected spell buttons stay intact.
local companionName, companion = ...
_G.CliqueSpellbookCompanion = companion
companion.version = "1.2.0"
local addon = Clique
if not addon or not addon.ProjectIsForever or not addon:ProjectIsForever() then return end
local bank = Enum.SpellBookSpellBank.Player
local attached

local function Settings()
    CliqueSpellbookCompanionDB = CliqueSpellbookCompanionDB or {}
    return CliqueSpellbookCompanionDB
end

-- Only explicit acknowledgement marks a release read. Login UI resets and
-- Escape can hide a frame before the player has had a chance to read it.
function companion:ShowWhatsNew(manual)
    if InCombatLockdown() then return false end
    local db = Settings()
    if not manual and (db.suppressUpdatePopups or db.acknowledgedNewsVersion == self.version) then return false end
    local frame = self.whatsNewFrame
    if not frame then
        frame = CreateFrame("Frame", "CSC_WhatsNew", UIParent, "BackdropTemplate")
        self.whatsNewFrame = frame
        frame:Hide()
        frame:SetSize(440, 420)
        frame:SetPoint("CENTER")
        frame:SetFrameStrata("DIALOG")
        frame:SetClampedToScreen(true)
        frame:EnableMouse(true)
        frame:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background",
            edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16,
            edgeSize=16, insets={left=4,right=4,top=4,bottom=4}})
        frame:SetBackdropColor(0.06, 0.06, 0.06, 1)
        local heading = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
        heading:SetPoint("TOPLEFT", 22, -22)
        heading:SetText("Clique Spellbook Companion")
        local release = frame:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        release:SetPoint("TOPLEFT", 22, -52)
        release:SetText("What's New - " .. self.version)
        local body = frame:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
        body:SetPoint("TOPLEFT", 22, -85)
        body:SetWidth(396)
        body:SetJustifyH("LEFT")
        body:SetText("|cffffd200Right-click your spellbook binding list|r\n"
            .. "Edit a binding in Clique's full editor, or delete the selected binding.\n\n"
            .. "|cffffd200Quick options with radio buttons|r\n"
            .. "Use the arrow submenus to choose where a binding works, which units it applies to, and whether it works in or out of combat.\n\n"
            .. "|cffffd200Clearer binding details|r\n"
            .. "The list shows readable settings such as Friendly and In combat. Your saved bindings stay as they are until you edit them.\n\n"
            .. "Reopen these notes with the What's new button or /csc news.")
        local suppress = CreateFrame("CheckButton", "CSC_SuppressUpdatePopups", frame, "UICheckButtonTemplate")
        suppress:SetPoint("BOTTOMLEFT", 16, 52)
        local suppressText = _G.CSC_SuppressUpdatePopupsText or suppress.Text or suppress.text
        suppressText:SetText("Don't show update popups")
        suppress:SetScript("OnClick", function(self)
            Settings().suppressUpdatePopups = not not self:GetChecked()
        end)
        self.whatsNewSuppress = suppress
        local dismiss = CreateFrame("Button", nil, frame, "UIPanelButtonTemplate")
        dismiss:SetSize(120, 26)
        dismiss:SetPoint("BOTTOM", 0, 20)
        dismiss:SetText("Got it")
        dismiss:SetScript("OnClick", function()
            Settings().acknowledgedNewsVersion = companion.version
            frame:Hide()
        end)
        UISpecialFrames = UISpecialFrames or {}
        table.insert(UISpecialFrames, "CSC_WhatsNew")
        self.whatsNewDismiss = dismiss
    end
    self.whatsNewSuppress:SetChecked(not not db.suppressUpdatePopups)
    frame.suspendedForCombat = false
    frame:Show()
    return true
end

local function Attach()
    local book = EUI_ClassicSpellbook
    if attached or not book or not book.spells then return attached end
    if type(addon.GetCapturedKey) ~= "function" or type(addon.AddBinding) ~= "function"
        or type(addon.FireMessage) ~= "function" or type(addon.ShowBindingConfig) ~= "function"
        or type(addon.GetBindingActionText) ~= "function" or type(addon.GetBindingKeyComboText) ~= "function"
        or type(addon.bindings) ~= "table" or not addon.db then
        companion.problem = "Clique's interface changed. Companion update needed."
        return false
    end
    CliqueSpellbookCompanionDB = CliqueSpellbookCompanionDB or { backups = {} }
    CliqueSpellbookCompanionDB.backups = CliqueSpellbookCompanionDB.backups or {}
    attached = true
    local holder = CreateFrame("Frame", nil, book)
    holder:SetAllPoints(book)
    holder:Hide()
    local root = CreateFrame("Frame", nil, holder)
    root:SetAllPoints(holder)
    RegisterStateDriver(root, "visibility", "[combat] hide; show")
    local captureHolder = CreateFrame("Frame", nil, root)
    captureHolder:SetAllPoints(root)
    captureHolder:Hide()

    local panel = CreateFrame("Frame", nil, root, "BackdropTemplate")
    panel:SetSize(390, 540)
    panel:SetPoint("TOPLEFT", book, "TOPRIGHT", 16, -15)
    panel:SetFrameLevel(book:GetFrameLevel() + 20)
    panel:SetBackdrop({bgFile="Interface\\DialogFrame\\UI-DialogBox-Background", edgeFile="Interface\\Tooltips\\UI-Tooltip-Border", tile=true, tileSize=16, edgeSize=16, insets={left=4,right=4,top=4,bottom=4}})
    panel:SetBackdropColor(0.08, 0.08, 0.08, 0.98)
    local title = panel:CreateFontString(nil, "OVERLAY", "GameFontNormalLarge")
    title:SetPoint("TOPLEFT", 16, -16)
    title:SetText("Clique - Spellbook Bindings")
    local help = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    help:SetPoint("TOPLEFT", 16, -44)
    help:SetWidth(354)
    help:SetJustifyH("LEFT")
    local function SetBindingMode(enabled)
        captureHolder:SetShown(not not enabled)
        help:SetText(enabled and "Binding mode: hover a spell, then click or press its key."
            or "Right-click a binding to edit, delete, or change where it works.")
    end
    SetBindingMode(false)
    local highest = CreateFrame("CheckButton", "CSC_HighestRank", panel, "UICheckButtonTemplate")
    highest:SetPoint("TOPLEFT", 10, -80)
    highest:SetChecked(CliqueSpellbookCompanionDB.highestRank ~= false)
    highest.text = _G["CSC_HighestRankText"] or highest.Text or highest.text
    highest.text:SetText("Always use highest learned rank")
    highest:SetScript("OnClick", function(self)
        CliqueSpellbookCompanionDB.highestRank = not not self:GetChecked()
    end)
    local autoShow = CreateFrame("CheckButton", "CSC_AutoShowBindings", panel, "UICheckButtonTemplate")
    autoShow:SetPoint("TOPLEFT", 10, -108)
    autoShow:SetChecked(CliqueSpellbookCompanionDB.showWithSpellbook ~= false)
    local autoShowText = _G.CSC_AutoShowBindingsText or autoShow.Text or autoShow.text
    autoShowText:SetText("Show this list when the spellbook opens")
    autoShow:SetScript("OnClick", function(self)
        CliqueSpellbookCompanionDB.showWithSpellbook = not not self:GetChecked()
    end)

    local actionHeading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    actionHeading:SetPoint("TOPLEFT", 18, -146)
    actionHeading:SetText("Action")
    local keyHeading = panel:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    keyHeading:SetPoint("TOPRIGHT", -34, -146)
    keyHeading:SetText("Binding")
    local scroll = CreateFrame("ScrollFrame", "CSC_BindingScroll", panel, "UIPanelScrollFrameTemplate")
    scroll:SetPoint("TOPLEFT", 16, -166)
    scroll:SetPoint("BOTTOMRIGHT", -34, 156)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(338, 1)
    scroll:SetScrollChild(content)
    local rows, lastSignature = {}, nil
    local RefreshBindings
    local function BindingText(bind)
        local text
        if bind.type == "spell" then
            local name = type(bind.spell) == "number" and C_Spell.GetSpellName(bind.spell) or bind.spell
            text = tostring(name or "Unknown spell")
            text = text .. (bind.spellSubName and " (" .. bind.spellSubName .. ")" or " [MAX]")
        elseif bind.type == "macro" then
            text = bind.macro and ("Macro: " .. bind.macro) or "Custom macro"
        else
            text = addon:GetBindingActionText(bind.type, bind)
        end
        return text
    end
    RefreshBindings = function(force)
        local entries, signature = {}, {}
        for index, bind in ipairs(addon.bindings or {}) do
            local sets = {}
            for set, enabled in pairs(bind.sets or {}) do
                if enabled then sets[#sets + 1] = set end
            end
            table.sort(sets)
            local action = BindingText(bind)
            local key = addon:GetBindingKeyComboText(bind)
            local details = type(addon.GetBindSetsDisplayText) == "function"
                and addon:GetBindSetsDisplayText(bind) or table.concat(sets, ", ")
            if details == "" then details = "Disabled" end
            entries[#entries + 1] = {action=action, key=key, details=details, bind=bind, index=index}
            signature[#signature + 1] = table.concat({action, key, details, tostring(bind.icon), tostring(bind.macrotext)}, "\001")
        end
        local current = table.concat(signature, "\002")
        if not force and current == lastSignature then return end
        lastSignature = current
        table.sort(entries, function(a,b)
            if a.action == b.action then
                if a.key == b.key then return a.index < b.index end
                return a.key < b.key
            end
            return a.action < b.action
        end)
        content:SetHeight(math.max(1, #entries * 44))
        for i, entry in ipairs(entries) do
            local row = rows[i]
            if not row then
                row = CreateFrame("Button", nil, content)
                row:SetSize(338, 44)
                row:SetPoint("TOPLEFT", 0, -(i-1)*44)
                row:SetHighlightTexture("Interface\\QuestFrame\\UI-QuestTitleHighlight", "ADD")
                row:RegisterForClicks("RightButtonUp")
                row:SetScript("OnClick", function(self)
                    if companion.bindingMenu then
                        companion.bindingMenu:Show(self, addon, self.entry.bind, RefreshBindings, function()
                            SetBindingMode(false)
                            holder:Hide()
                            book:Hide()
                        end)
                    end
                end)
                row.icon = row:CreateTexture(nil, "ARTWORK")
                row.icon:SetSize(24,24)
                row.icon:SetPoint("LEFT", 0, 1)
                row.action = row:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
                row.action:SetPoint("TOPLEFT", 30, -4)
                row.action:SetWidth(190)
                row.action:SetJustifyH("LEFT")
                row.action:SetWordWrap(false)
                row.key = row:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
                row.key:SetPoint("TOPRIGHT", -1, -4)
                row.key:SetWidth(108)
                row.key:SetJustifyH("RIGHT")
                row.key:SetWordWrap(false)
                row.details = row:CreateFontString(nil, "OVERLAY", "GameFontDisableSmall")
                row.details:SetPoint("TOPLEFT", 30, -22)
                row.details:SetWidth(305)
                row.details:SetJustifyH("LEFT")
                row.details:SetWordWrap(false)
                row:SetScript("OnEnter", function(self)
                    GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                    GameTooltip:SetText(self.entry.action)
                    GameTooltip:AddLine(self.entry.key, 1, 0.82, 0)
                    GameTooltip:AddLine(self.entry.details, 0.7, 0.7, 0.7, true)
                    GameTooltip:AddLine("Right-click for binding options", 0, 1, 0)
                    if self.entry.bind.macrotext then GameTooltip:AddLine(self.entry.bind.macrotext, 1, 1, 1, true) end
                    GameTooltip:Show()
                end)
                row:SetScript("OnLeave", function() GameTooltip:Hide() end)
                rows[i] = row
            end
            row.entry = entry
            row.icon:SetTexture(entry.bind.icon or "Interface\\Icons\\INV_Misc_QuestionMark")
            row.action:SetText(entry.action)
            row.key:SetText(entry.key)
            row.details:SetText(entry.details)
            row:Show()
        end
        for i = #entries+1, #rows do rows[i]:Hide() end
    end
    panel:SetScript("OnShow", function() RefreshBindings(true) end)
    local elapsed = 0
    panel:SetScript("OnUpdate", function(_, delta)
        elapsed = elapsed + delta
        if elapsed >= 0.25 then elapsed = 0; RefreshBindings(false) end
    end)
    local status = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlight")
    status:SetPoint("BOTTOMLEFT", 18, 112)
    status:SetWidth(354)
    status:SetJustifyH("LEFT")
    status:SetText("[MAX] follows your highest learned rank. Right-click a row for options.")

    local function SaveSpell(original, input)
        if InCombatLockdown() or not captureHolder:IsShown() then return end
        local id = original.spellID
        if not id or original.passive then return end
        local key = addon:GetCapturedKey(input)
        if not key then return end
        local name = C_Spell.GetSpellName(id)
        if not name then return end
        local sub = not highest:GetChecked() and C_Spell.GetSpellSubtext(id) or nil
        if sub == "" then sub = nil end
        -- Replace a normal unit-frame binding on this key, preserving specialized
        -- friendly/enemy/combat/spec bindings on the same key.
        local existing
        for _, bind in ipairs(addon.bindings) do
            local sets = bind.sets
            if bind.key == key and sets and sets.default then
                local count = 0
                for _ in pairs(sets) do count = count + 1 end
                if count == 1 then existing = bind; break end
            end
        end
        if existing then
            existing.type, existing.spell, existing.spellSubName = "spell", name, sub
            existing.icon = C_Spell.GetSpellTexture(id)
            existing.macro, existing.macrotext, existing.item, existing.unit = nil, nil, nil, nil
            addon:FireMessage("BINDINGS_CHANGED")
        else
            addon:AddBinding({type="spell", spell=name, spellSubName=sub,
                key=key, icon=C_Spell.GetSpellTexture(id), sets={default=true}})
        end
        local text = name .. (sub and " (" .. sub .. ")" or " (highest rank)") .. " -> " .. key
        status:SetText(text)
        RefreshBindings(true)
        addon:Printf("Spellbook: %s", text)
    end

    for _, original in ipairs(book.spells) do
        local capture = CreateFrame("Button", nil, captureHolder)
        capture.original = original
        capture:EnableKeyboard(false)
        capture:SetAllPoints(original)
        capture:SetFrameLevel(panel:GetFrameLevel() + 1)
        capture:RegisterForClicks("AnyUp")
        capture:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
        capture:EnableMouseWheel(true)
        capture:SetScript("OnClick", function(self, button) SaveSpell(self.original, button) end)
        capture:SetScript("OnMouseWheel", function(self, delta) SaveSpell(self.original, delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN") end)
        capture:SetScript("OnEnter", function(self)
            self:EnableKeyboard(true)
            self:SetPropagateKeyboardInput(false)
            if original.slot then
                GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
                GameTooltip:SetSpellBookItem(original.slot, bank)
                GameTooltip:AddLine("Clique: click or press a key to bind", 0, 1, 0)
                GameTooltip:Show()
            end
        end)
        capture:SetScript("OnLeave", function(self) self:EnableKeyboard(false); GameTooltip:Hide() end)
        capture:SetScript("OnHide", function(self) self:EnableKeyboard(false) end)
        capture:SetScript("OnKeyDown", function(self, key)
            if not self:IsMouseOver() then self:SetPropagateKeyboardInput(true); return end
            if key == "ESCAPE" then
                self:EnableKeyboard(false)
                SetBindingMode(false)
                return
            end
            self:SetPropagateKeyboardInput(false)
            SaveSpell(self.original, key)
        end)
    end

    local convert = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    convert:SetSize(354, 26)
    convert:SetPoint("BOTTOM", 0, 72)
    convert:SetText("Use highest rank for existing bindings")
    convert:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        -- Keep a profile-local recovery snapshot before the first conversion.
        local profileName = addon.db:GetCurrentProfile()
        local backups = CliqueSpellbookCompanionDB.backups
        if not backups[profileName] then
            backups[profileName] = {bindings=CopyTable(addon.bindings), created=time(), version=companion.version}
        end
        local count = 0
        for _, bind in ipairs(addon.bindings) do
            if bind.type == "spell" then
                if type(bind.spell) == "number" then
                    local name = C_Spell.GetSpellName(bind.spell)
                    if name then bind.spell = name; count = count + 1 end
                end
                if bind.spellSubName and bind.spellSubName:match("^Rank %d+$") then
                    bind.spellSubName = nil
                    count = count + 1
                end
            end
        end
        addon:FireMessage("BINDINGS_CHANGED")
        RefreshBindings(true)
        status:SetText("Updated " .. count .. " spell binding fields to highest rank in this profile. Macros keep their own text.")
        addon:Printf("Spellbook: highest-rank conversion complete for this profile (%d changes).", count)
    end)
    local manage = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    manage:SetSize(110, 26)
    manage:SetPoint("BOTTOMLEFT", 140, 30)
    manage:SetText("Bind other...")
    manage:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        holder:Hide(); book:Hide(); addon:ShowBindingConfig()
    end)
    local done = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    done:SetSize(110, 26)
    done:SetPoint("BOTTOMRIGHT", -18, 30)
    done:SetText("Done")
    done:SetScript("OnClick", function() holder:Hide() end)
    local news = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    news:SetSize(130, 18)
    news:SetPoint("BOTTOM", 0, 7)
    news:SetText("What's new")
    news:SetScript("OnClick", function() companion:ShowWhatsNew(true) end)
    local bindButton = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
    bindButton:SetSize(110, 26)
    bindButton:SetPoint("BOTTOMLEFT", 18, 30)
    bindButton:SetText("Bind spells")
    bindButton:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        SetBindingMode(not captureHolder:IsShown())
    end)
    captureHolder:HookScript("OnShow", function() bindButton:SetText("Stop binding") end)
    captureHolder:HookScript("OnHide", function() bindButton:SetText("Bind spells") end)
    holder:HookScript("OnHide", function() SetBindingMode(false) end)

    local listButton = CreateFrame("Button", "CSC_ShowBindingsButton", book, "UIPanelButtonTemplate")
    listButton:SetSize(104, 23)
    listButton:SetPoint("BOTTOM", book, "BOTTOM", -14, 72)
    listButton:SetText("Bindings")
    listButton:SetScript("OnClick", function()
        if InCombatLockdown() then return end
        SetBindingMode(false)
        holder:SetShown(not holder:IsShown())
    end)

    local tab = CreateFrame("Button", "CSC_SpellbookTab", book)
    tab:SetSize(32, 32)
    local function PlaceTab()
        if InCombatLockdown() then return end
        tab:ClearAllPoints()
        local last = book.tabs and book.tabs[#book.tabs]
        if last then tab:SetPoint("TOPLEFT", last, "BOTTOMLEFT", 0, -17)
        else tab:SetPoint("TOPLEFT", book, "TOPRIGHT", -32, -212) end
    end
    PlaceTab()
    tab:SetNormalTexture("Interface\\AddOns\\CliqueSpellbookCompanion\\Icon")
    tab:SetHighlightTexture("Interface\\Buttons\\ButtonHilight-Square", "ADD")
    tab:SetScript("OnClick", function()
        if InCombatLockdown() then addon:Printf("Finish combat before binding spells."); return end
        local enabled = not captureHolder:IsShown()
        holder:Show()
        SetBindingMode(enabled)
    end)
    tab:SetScript("OnEnter", function(self)
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText("Clique: bind from your spellbook")
        GameTooltip:Show()
    end)
    tab:SetScript("OnLeave", function() GameTooltip:Hide() end)
    book:HookScript("OnShow", function()
        PlaceTab()
        if not InCombatLockdown() and CliqueSpellbookCompanionDB.showWithSpellbook ~= false then
            SetBindingMode(false)
            holder:Show()
        end
    end)
    book:HookScript("OnHide", function() holder:Hide() end)
    local combat = CreateFrame("Frame")
    combat:RegisterEvent("PLAYER_REGEN_DISABLED")
    combat:SetScript("OnEvent", function() holder:Hide() end)
    companion.ui = {holder=holder, highest=highest, convert=convert, tab=tab,
        listButton=listButton, news=news, refresh=RefreshBindings, setBindingMode=SetBindingMode}
    if book:IsShown() and CliqueSpellbookCompanionDB.showWithSpellbook ~= false then holder:Show() end
    return true
end

-- Retry while login finishes or the classic spellbook is created.
local timer
local newsPending, enteredWorld = false, false
local function QueueNews()
    if not enteredWorld or newsPending then return end
    local db = Settings()
    if db.suppressUpdatePopups or db.acknowledgedNewsVersion == companion.version then return end
    newsPending = true
    C_Timer.After(2, function()
        newsPending = false
        -- If combat started in the meantime, PLAYER_REGEN_ENABLED retries.
        companion:ShowWhatsNew(false)
    end)
end
local function Start()
    if attached then QueueNews(); return end
    if not InCombatLockdown() and Attach() then QueueNews(); return end
    if not timer then
        local attempts = 0
        timer = C_Timer.NewTicker(1, function(ticker)
            attempts = attempts + 1
            if not InCombatLockdown() and Attach() then
                ticker:Cancel()
                timer = nil
                QueueNews()
            elseif attempts >= 120 then
                ticker:Cancel()
                timer = nil
            end
        end)
    end
end
local events = CreateFrame("Frame")
events:RegisterEvent("PLAYER_LOGIN")
events:RegisterEvent("PLAYER_ENTERING_WORLD")
events:RegisterEvent("PLAYER_REGEN_ENABLED")
events:RegisterEvent("PLAYER_REGEN_DISABLED")
events:SetScript("OnEvent", function(_, event)
    if event == "PLAYER_REGEN_DISABLED" then
        local frame = companion.whatsNewFrame
        if frame and frame:IsShown() then
            frame.suspendedForCombat = true
            frame:Hide()
        end
    else
        if event == "PLAYER_ENTERING_WORLD" then enteredWorld = true end
        Start()
    end
end)
SLASH_CLIQUESPELLBOOKCOMPANION1 = "/csc"
SlashCmdList.CLIQUESPELLBOOKCOMPANION = function(msg)
    if msg == "news" or msg == "whatsnew" then
        if not companion:ShowWhatsNew(true) then print("Finish combat to view What's New.") end
        return
    end
    if msg == "version" or msg == "status" then
        local get = C_AddOns.GetAddOnMetadata
        print("Clique Spellbook Companion " .. companion.version)
        print("Clique: " .. tostring(get("Clique", "Version")))
        print("EllesmereUI Forever Essentials: " .. tostring(get("EllesmereUIForeverEssentials", "Version")))
        print("Spellbook attached: " .. tostring(not not attached))
        if companion.problem then print(companion.problem) end
        return
    end
    if InCombatLockdown() then print("Finish combat before binding spells."); return end
    Start()
    if companion.ui then
        EUI_ClassicSpellbook:Show()
        companion.ui.holder:Show()
        companion.ui.setBindingMode(true)
    else
        print(companion.problem or "Enable EllesmereUI's Classic Spellbook, open it with P, then try /csc again.")
    end
end
if IsLoggedIn() then Start() end
