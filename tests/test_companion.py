import sys
from pathlib import Path
from lupa import LuaRuntime

lua = LuaRuntime(unpack_returned_tuples=True)
lua.execute(r'''
frames = {}
local methods = {}
local function noop() end
function NewFrame(name, parent)
 local f = {name=name, parent=parent, shown=true, scripts={}, hooks={}}
 setmetatable(f, {__index=function(_, key) return methods[key] or noop end})
 if name then _G[name]=f end
 table.insert(frames, f)
 return f
end
function CreateFrame(kind, name, parent, template)
 local f=NewFrame(name,parent)
 if template == 'UICheckButtonTemplate' then _G[name..'Text']=NewFrame(nil,f) end
 return f
end
function methods:CreateFontString() return NewFrame(nil,self) end
function methods:CreateTexture() return NewFrame(nil,self) end
function methods:SetText(t) self.textValue=t end
function methods:SetSize(w,h) self.width=w; self.height=h end
function methods:SetHeight(h) self.height=h end
function methods:GetFrameLevel() return 1 end
function methods:SetScript(k,v) self.scripts[k]=v end
function methods:HookScript(k,v) self.hooks[k]=v end
function methods:Show()
 local changed=not self.shown; self.shown=true
 if changed then if self.scripts.OnShow then self.scripts.OnShow(self) end; if self.hooks.OnShow then self.hooks.OnShow(self) end end
end
function methods:Hide()
 local changed=self.shown; self.shown=false
 if changed then if self.scripts.OnHide then self.scripts.OnHide(self) end; if self.hooks.OnHide then self.hooks.OnHide(self) end end
end
function methods:SetShown(v) if v then self:Show() else self:Hide() end end
function methods:IsShown() local p=rawget(self,'parent'); return self.shown and (not p or p:IsShown()) end
function methods:SetChecked(v) self.checked=v end
function methods:GetChecked() return self.checked end
function methods:EnableKeyboard(v) self.keyboard=v end
function methods:IsMouseOver() return self.hovered end
function methods:SetPropagateKeyboardInput(v) self.propagate=v end
UIParent=NewFrame('UIParent')
GameTooltip=NewFrame('GameTooltip')
Enum={SpellBookSpellBank={Player=0}}
C_Spell={GetSpellName=function(id) return ({[774]='Rejuvenation',[5185]='Healing Touch'})[id] end,
 GetSpellTexture=function(id) return id end, GetSpellSubtext=function() return 'Rank 1' end}
C_AddOns={GetAddOnMetadata=function() return 'test' end}
C_Timer={NewTicker=function() error('Unexpected retry timer') end}
function InCombatLockdown() return false end
function RegisterStateDriver() end
function IsLoggedIn() return true end
function time() return 1 end
function CopyTable(x) local t={} for k,v in pairs(x) do t[k]=type(v)=='table' and CopyTable(v) or v end return t end
SlashCmdList={}
Clique={bindings={
 {type='spell',spell='Rejuvenation',key='Q',sets={default=true}},
 {type='spell',spell='Healing Touch',key='Q',spellSubName='Rank 1',sets={default=true,friend=true}}
}, db={GetCurrentProfile=function() return 'test' end}}
function Clique:ProjectIsForever() return true end
function Clique:GetCapturedKey(key) if key=='LSHIFT' then return nil end return key end
function Clique:AddBinding(bind) table.insert(self.bindings,bind) end
function Clique:FireMessage() self.changeCount=(self.changeCount or 0)+1 end
function Clique:GetBindingActionText(t,b) return t end
function Clique:GetBindingKeyComboText(b) return b.key end
function Clique:ShowBindingConfig() self.editorOpened=true end
function Clique:Printf() end
EUI_ClassicSpellbook=NewFrame('EUI_ClassicSpellbook',UIParent)
EUI_ClassicSpellbook.spells={NewFrame(nil,EUI_ClassicSpellbook),NewFrame(nil,EUI_ClassicSpellbook)}
EUI_ClassicSpellbook.spells[1].spellID=774
EUI_ClassicSpellbook.spells[2].spellID=5185
EUI_ClassicSpellbook.spells[1].passive=false
EUI_ClassicSpellbook.spells[2].passive=false
EUI_ClassicSpellbook.tabs={NewFrame(nil,EUI_ClassicSpellbook)}
''')
shared = lua.table()
lua.execute('pendingTimers={}; C_Timer.After=function(_, fn) table.insert(pendingTimers,fn) end')
source = (Path(__file__).resolve().parent.parent / 'Companion.lua').read_text()
loader = lua.execute('return function(...)\n' + source + '\nend')
loader('CliqueSpellbookCompanion', shared)
lua.execute(r'''
local ui=assert(CliqueSpellbookCompanion.ui)
assert(ui.holder:IsShown(), 'List should open with spellbook')
ui.refresh(true)
local function contains(text)
 for _,f in ipairs(frames) do if f.textValue==text then return true end end
 return false
end
assert(contains('Rejuvenation [MAX]'), 'Rank-free spell missing from list')
assert(contains('Healing Touch (Rank 1)'), 'Specific rank missing from list')
local capture
for _,f in ipairs(frames) do
 if rawget(f,'original')==EUI_ClassicSpellbook.spells[1] then capture=f end
end
assert(capture and not capture:IsShown(), 'Viewing must not capture spell clicks')
ui.tab.scripts.OnClick()
assert(capture:IsShown(), 'Hand tab should enable binding')
capture.hovered=false
capture.scripts.OnKeyDown(capture,'Q')
assert(Clique.changeCount==nil, 'An unhovered spell must not consume a key')
capture.hovered=true
capture.scripts.OnKeyDown(capture,'Q')
assert(#Clique.bindings==2, 'Rebinding should not duplicate the default binding')
assert(Clique.bindings[1].spell=='Rejuvenation' and Clique.bindings[1].spellSubName==nil)
assert(Clique.bindings[2].spellSubName=='Rank 1', 'Specialized binding was changed')
ui.highest:SetChecked(false)
capture.scripts.OnClick(capture,'BUTTON4')
assert(#Clique.bindings==3 and Clique.bindings[3].spellSubName=='Rank 1', 'Explicit downrank failed')
assert(contains('Rejuvenation (Rank 1)'), 'List failed to refresh after mouse binding')
ui.holder:Hide()
ui.listButton.scripts.OnClick()
assert(ui.holder:IsShown() and not capture:IsShown(), 'Bindings button should only show the list')
Clique.bindings={{type='spell',spell='Healing Touch',key='E',sets={default=true}}}
ui.refresh(false)
local visibleRows=0
for _,f in ipairs(frames) do if rawget(f,'entry') and f:IsShown() then visibleRows=visibleRows+1; assert(f.entry.key=='E') end end
assert(visibleRows==1, 'Profile change left stale rows visible')
''')
print('Passed: list display, binding mode separation, keyboard hover, highest ranks, explicit ranks, scope preservation, live refresh, and profile changes.')

lua.execute(r'''
local menu = CliqueSpellbookCompanion.bindingMenu
local count = 0
local refresh = function(force) assert(force); count = count + 1 end
local b = {type='spell', spell='Heal', key='Q', sets={default=true, friend=true, combat=true, spec2=true, special=true}}
Clique.bindings = {b}
assert(menu:SetChoice(Clique,b,'where','anyunit',refresh))
assert(b.sets.hovercast and not b.sets.default and b.sets.friend and b.sets.combat and b.sets.spec2 and b.sets.special)
assert(menu:SetChoice(Clique,b,'units','enemy',refresh))
assert(b.sets.enemy and not b.sets.friend and b.sets.hovercast and b.sets.combat and b.sets.spec2)
assert(menu:SetChoice(Clique,b,'when','ooc',refresh))
assert(b.sets.ooc and not b.sets.combat and b.sets.enemy and b.sets.spec2)
assert(menu:SetChoice(Clique,b,'where','anywhere',refresh))
assert(b.sets.global and not b.sets.hovercast and not b.sets.enemy and b.sets.ooc and b.sets.spec2)
assert(not menu:SetChoice(Clique,b,'units','friend',refresh))
assert(not menu:SetChoice(Clique,b,'when','bad',refresh))
assert(menu:SetChoice(Clique,b,'where','disabled',refresh) and not next(b.sets))
assert(not menu:SetChoice(Clique,b,'when','combat',refresh))
assert(menu:SetChoice(Clique,b,'where','frames',refresh) and b.sets.default)
assert(CliqueSpellbookCompanionDB.menuBackups.test.bindings[1].sets.friend)

-- Delete by identity, including two otherwise-identical action/key bindings.
local twin = CopyTable(b)
twin.sets.friend=true
Clique.bindings={b,twin}
assert(menu:Delete(Clique,twin,refresh))
assert(#Clique.bindings==1 and Clique.bindings[1]==b)
local previous = Clique.changeCount
assert(not menu:Delete(Clique,twin,refresh))
assert(not menu:SetChoice(Clique,twin,'where','anywhere',refresh))
assert(Clique.changeCount==previous)

-- A menu opened before a profile switch cannot mutate the old binding.
Clique.bindings={CopyTable(b)}
assert(not menu:SetChoice(Clique,b,'where','disabled',refresh))
assert(b.sets.default)
Clique.bindings={b}
function InCombatLockdown() return true end
assert(not menu:SetChoice(Clique,b,'where','disabled',refresh))
assert(not menu:Delete(Clique,b,refresh))
assert(not menu:Edit(Clique,b,function() error('hid in combat') end))
function InCombatLockdown() return false end

-- Exercise the real context-menu callback tree: arrows, radios, selected values.
local function description(label)
 local d={label=label, children={}}
 function d:CreateTitle(text) self.title=text end
 function d:CreateDivider() self.divider=true end
 function d:CreateButton(text, callback)
  local child=description(text); child.callback=callback
  table.insert(self.children,child); return child
 end
 function d:CreateRadio(text, selected, callback)
  local child=self:CreateButton(text,callback); child.selected=selected; return child
 end
 function d:SetEnabled(enabled) self.enabled=enabled end
 return d
end
local root
MenuUtil={CreateContextMenu=function(owner, generator) root=description('root'); generator(owner,root) end}
menu:Show({},Clique,b,refresh,function() end)
assert(#root.children==5)
assert(root.children[1].label=='Edit binding...' and root.children[2].label=='Delete binding')
assert(#root.children[3].children==4 and #root.children[4].children==3 and #root.children[5].children==3)
assert(root.children[3].children[1].selected())
assert(not root.children[3].children[2].selected())
root.children[3].children[2].callback()
assert(b.sets.hovercast)
root.children[4].children[2].callback()
assert(b.sets.friend)
root.children[5].children[3].callback()
assert(b.sets.combat)
menu:SetChoice(Clique,b,'where','anywhere',refresh)
menu:Show({},Clique,b,refresh,function() end)
assert(not root.children[4].enabled and root.children[5].enabled)
menu:SetChoice(Clique,b,'where','disabled',refresh)
menu:Show({},Clique,b,refresh,function() end)
assert(root.children[3].enabled and not root.children[4].enabled and not root.children[5].enabled)

local hidden, edited
function Clique:GetBindingConfig()
 return {SwitchToEditPage=function(_,binding,isNew) assert(not isNew); edited=binding end}
end
assert(menu:Edit(Clique,b,function() hidden=true end))
assert(hidden and edited==b and Clique.editorOpened)

-- Actual row right-click wiring reaches the menu for that exact binding.
CliqueSpellbookCompanion.ui.refresh(true)
local found
for _,f in ipairs(frames) do
 if rawget(f,'entry') and f.entry.bind==b and f:IsShown() then
  found=true; f.scripts.OnClick(f); assert(#root.children==5)
 end
end
assert(found)
''')
print('Passed: context-menu tree and row wiring, radio choices, restriction preservation, exact deletion, stale-profile guards, combat guards, disabled/global rules, backup, and editor routing.')
lua.execute(r'''
local c = CliqueSpellbookCompanion
local db = CliqueSpellbookCompanionDB
local events
for _,f in ipairs(frames) do
 if f.scripts.OnEvent and not rawget(f,'original') then events=f; break end
end
assert(events)
local function flush()
 local pending=pendingTimers; pendingTimers={}
 for _,fn in ipairs(pending) do fn() end
end
assert(not c.whatsNewFrame, 'Automatic popup must wait until entering the world')
db.lastSeenVersion=c.version -- Old premature acknowledgement must not suppress the fixed notice.
events.scripts.OnEvent(events,'PLAYER_ENTERING_WORLD')
assert(not c.whatsNewFrame and #pendingTimers==1, 'Notice must be delayed until login settles')
events.scripts.OnEvent(events,'PLAYER_REGEN_ENABLED')
assert(#pendingTimers==1, 'Repeated events must not queue duplicate notices')
flush()
local popup = assert(c.whatsNewFrame)
assert(popup:IsShown(), 'New release should show its update notice')
popup:Hide()
assert(not db.acknowledgedNewsVersion, 'Incidental hiding or Escape must not mark the notice read')
assert(c:ShowWhatsNew(false))
c.whatsNewDismiss.scripts.OnClick()
assert(db.acknowledgedNewsVersion==c.version and not popup:IsShown())
assert(not c:ShowWhatsNew(false), 'Same release must not repeat')
c.version='1.3.0-test'
assert(c:ShowWhatsNew(false), 'Next release should show')
c.whatsNewSuppress:SetChecked(true)
c.whatsNewSuppress.scripts.OnClick(c.whatsNewSuppress)
assert(db.suppressUpdatePopups)
c.whatsNewDismiss.scripts.OnClick()
c.version='1.4.0-test'
assert(not c:ShowWhatsNew(false) and not popup:IsShown(), 'Opt-out must apply to future versions')
SlashCmdList.CLIQUESPELLBOOKCOMPANION('news')
assert(popup:IsShown() and c.whatsNewSuppress:GetChecked(), 'Manual command must bypass opt-out')
c.whatsNewSuppress:SetChecked(false)
c.whatsNewSuppress.scripts.OnClick(c.whatsNewSuppress)
c.whatsNewDismiss.scripts.OnClick()
c.version='1.5.0-test'
assert(c:ShowWhatsNew(false), 'Unchecking must restore future notices')
function InCombatLockdown() return true end
events.scripts.OnEvent(events,'PLAYER_REGEN_DISABLED')
assert(not popup:IsShown() and db.acknowledgedNewsVersion~='1.5.0-test', 'Combat must not acknowledge the notice')
assert(not c:ShowWhatsNew(true), 'Manual opening is blocked during combat')
function InCombatLockdown() return false end
events.scripts.OnEvent(events,'PLAYER_REGEN_ENABLED')
flush()
assert(popup:IsShown(), 'Deferred notice must return after combat')
c.whatsNewDismiss.scripts.OnClick()
c.ui.news.scripts.OnClick()
assert(popup:IsShown(), 'Panel button must reopen the notice')
''')
print('Passed: first-update notice, dismissal, repeat suppression, next-version notice, persistent opt-out, manual reopening, opt-in restoration, and combat deferral.')
