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
source = (Path(__file__).resolve().parent.parent / 'Companion.lua').read_text()
loader = lua.execute('return function(...)\n' + source + '\nend')
loader('CliqueSpellbookCompanion', lua.table())
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
