local O, P = OneCraft, OneCraft.Equipment
local W = WINDOW_MANAGER
local function setName(id)
    local entry = P.Engine.Sets()[id]
    return id == 0 and P.words.none or entry and entry[1] or "?"
end

local function label(parent, text, x, y, width, font)
    local c = W:CreateControl(nil, parent, CT_LABEL)
    c:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
    c:SetDimensions(width, 32)
    c:SetFont(font or "ZoFontGame")
    c:SetText(text)
    return c
end

local function button(parent, text, x, y, width, callback)
    local c = W:CreateControlFromVirtual(nil, parent, "ZO_DefaultButton")
    c:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y)
    c:SetDimensions(width, 32)
    c:SetText(text)
    c:SetHandler("OnClicked", callback)
    return c
end

local function hint(control, getText, above)
    control:SetMouseEnabled(true)
    control:SetHandler("OnMouseEnter", function(c)
        if above then InitializeTooltip(InformationTooltip, c, BOTTOM, 0, -8, TOP)
        else InitializeTooltip(InformationTooltip, c, RIGHT) end
        SetTooltipText(InformationTooltip, getText())
    end)
    control:SetHandler("OnMouseExit", function() ClearTooltip(InformationTooltip) end)
end

function P.ItemLink(item)
    if not item or not P.ValidItem(item) then return nil end
    local kind = P.types[item.type]
    local ids = item.enchant and O.Enchanting.RecipeEngine.RuneIds(P.GlyphSelection(item)) or {}
    return P.client:getItemLinkFromParticulars(kind.pattern, item.cp, item.level, item.style,
        item.trait + 1, kind.station, item.set, item.quality, ids[1], ids[2], ids[3])
end

local function clearItemTooltip()
    ClearTooltip(ItemTooltip)
end

local function showItemTooltip(control, item)
    local link = P.ItemLink(item)
    if link then
        InitializeTooltip(ItemTooltip, control, LEFT, 8, 0, RIGHT)
        ItemTooltip:SetLink(link)
    end
end

function P.ShowSetTooltip(control, id)
    clearItemTooltip()
    ClearTooltip(InformationTooltip)
    if id == 0 then return end
    local item = P.Copy(P.draft)
    item.type, item.set, item.trait, item.enchant = "Chest" .. ARMORTYPE_HEAVY, id, 0, false
    local link = P.ItemLink(item)
    if link then showItemTooltip(control, item); return end
    -- Native set bonuses remain available even for newly added item ID ranges.
    local _, _, count = GetItemSetInfo(id)
    local lines = {setName(id)}
    for i = 1, count do
        local _, description = GetItemSetBonusInfo(id, i)
        lines[#lines + 1] = description
    end
    InitializeTooltip(InformationTooltip, control, LEFT, 8, 0, RIGHT)
    SetTooltipText(InformationTooltip, table.concat(lines, "\n\n"))
end

local function report(ok, reason)
    P.status = ok and nil or reason
    P.RefreshUI()
end

function P.Select(key)
    key = P.OccupiedSlot(key)
    if P.draft then P.saved.last = P.Copy(P.draft) end
    P.selected, P.draft = key, P.Copy(P.saved.items[key] or P.DefaultItem(key))
    P.status = nil
    P.RefreshUI()
end

function P.FieldEntries(field)
    local entries, item = {}, P.draft
    local function add(value, name) entries[#entries + 1] = {value = value, name = name} end
    if field == "type" then
        for _, kind in ipairs(P.TypesForSlot(P.selected)) do add(kind.key, kind.name) end
    elseif field == "set" then
        add(0, P.words.none)
        local sets = {}
        for id, data in pairs(P.Engine.Sets()) do
            if id ~= 0 then sets[#sets + 1] = {value = id, name = data[1]} end
        end
        table.sort(sets, function(a, b) return a.name < b.name end)
        for _, entry in ipairs(sets) do entries[#entries + 1] = entry end
    elseif field == "quality" then
        for i = 1, 5 do add(i, GetString("SI_ITEMQUALITY", i)) end
    elseif field == "style" then
        if P.types[item.type].category == "jewelry" then
            add(item.style, P.Text("Не требуется", "Not required"))
        else
            for i = 1, GetNumValidItemStyles() do
                local id = GetValidItemStyleId(i)
                if id > 0 then add(id, GetItemStyleName(id)) end
            end
        end
    elseif field == "level" then
        add("L1", "1")
        for level = 4, 50, 2 do add("L" .. level, tostring(level)) end
        for level = 10, 160, 10 do add("C" .. level, "CP " .. level) end
    elseif field == "enchant" then
        add(false, P.words.noEnchant)
        for _, effect in ipairs(O.Enchanting.effectList) do
            if effect.equipment == P.types[item.type].category then
                add(effect.key, O.Enchanting.RecipeEngine.EffectName(effect))
            end
        end
    elseif field == "trait" then
        add(0, GetString("SI_ITEMTRAITTYPE", 0))
        local kind = P.types[item.type]
        local filter = kind.category == "weapon" and SMITHING_FILTER_TYPE_WEAPONS or
            kind.category == "jewelry" and SMITHING_FILTER_TYPE_JEWELRY or SMITHING_FILTER_TYPE_ARMOR
        for i = 1, GetNumSmithingTraitItems() do
            local trait = GetSmithingTraitItemInfo(i)
            if trait and trait ~= 0 and ZO_CraftingUtils_GetSmithingFilterFromTrait(trait) == filter then
                add(trait, GetString("SI_ITEMTRAITTYPE", trait))
            end
        end
    end
    return entries
end

function P.ChooseField(field, value)
    if P.rebuilding then return end
    if field == "level" then
        P.draft.cp, P.draft.level = value:sub(1, 1) == "C", tonumber(value:sub(2))
    elseif field == "type" then
        local previous = P.types[P.draft.type]
        P.draft.type = value
        -- Traits from a different equipment family cannot be carried over.
        if previous.category ~= P.types[value].category then P.draft.trait, P.draft.enchant = 0, false end
    else P.draft[field] = value end
    P.saved.last = P.Copy(P.draft)
    P.RefreshUI()
end

function P.RefreshUI()
    if not P.visible then return end
    P.rebuilding = true
    for _, key in ipairs(P.slotOrder) do
        local control, item = P.controls[key], P.SlotItem(key)
        local link = P.ItemLink(item)
        control.icon:SetTexture(link and GetItemLinkIcon(link) or control.emptyIcon)
        control.icon:SetAlpha(item and 1 or 0.4)
        control.selected:SetHidden(P.selected ~= P.OccupiedSlot(key))
        if item then
            local r, g, b = GetInterfaceColor(INTERFACE_COLOR_TYPE_ITEM_QUALITY_COLORS, item.quality)
            control.border:SetColor(r, g, b, 1)
        else control.border:SetColor(0.5, 0.5, 0.5, 0.6) end
    end
    for _, field in ipairs(P.fields) do
        local combo = P.combos[field]
        combo:ClearItems()
        local selectedValue = field == "level" and ((P.draft.cp and "C" or "L") .. P.draft.level) or P.draft[field]
        for _, data in ipairs(P.FieldEntries(field)) do
            local value = data.value
            local entry = combo:CreateItemEntry(data.name, function() P.ChooseField(field, value) end)
            if field == "set" then
                entry.onEnter = function(c) P.ShowSetTooltip(c, value) end
                entry.onExit = function() clearItemTooltip(); ClearTooltip(InformationTooltip) end
            end
            combo:AddItem(entry, ZO_COMBOBOX_SUPPRESS_UPDATE)
            if value == selectedValue then combo:SetSelectedItem(data.name) end
        end
        combo:UpdateItems()
    end
    P.materialRows = P.materialRows or {}
    local materials = P.Materials()
    for i, data in ipairs(materials) do
        local row = P.materialRows[i]
        if not row then
            row = label(P.materialChild, "", 0, (i - 1) * 38, 320, "ZoFontGameSmall")
            hint(row, function() return row.link end)
            P.materialRows[i] = row
        end
        row.link = data.link
        row:SetText(string.format("|t24:24:%s|t %s   %d / %d", data.icon, data.name, data.need, data.have))
        row:SetColor(data.have < data.need and 1 or 0.85, data.have < data.need and 0.22 or 0.85,
            data.have < data.need and 0.22 or 0.85, 1)
        row:SetHidden(false)
    end
    for i = #materials + 1, #P.materialRows do P.materialRows[i]:SetHidden(true) end
    P.materialChild:SetHeight(math.max(1, #materials * 38))
    local batch = P.saved.batch
    P.queueLabel:SetText(batch and string.format(P.words.queued, batch.completed, batch.total) or "")
    P.statusLabel:SetText(P.status or (P.HasQueue() and P.words.waiting or ""))
    P.submitButton:SetEnabled(not P.HasQueue() and not ZO_CraftingUtils_IsPerformingCraftProcess())
    P.cancelButton:SetEnabled(P.HasQueue() and not ZO_CraftingUtils_IsPerformingCraftProcess())
    P.clearButton:SetEnabled(not P.client.active and not ZO_CraftingUtils_IsPerformingCraftProcess())
    P.clearButton:SetEnabled(not P.client.active and not ZO_CraftingUtils_IsPerformingCraftProcess())
    P.rebuilding = false
end

local function createSlot(key, parent, native, x, y)
    -- Reuse the native slot art and exact native anchors, with planner-only
    -- handlers. Never bind these controls to BAG_WORN or native item movement.
    local c = W:CreateControlFromVirtual("OneCraftEquipmentSlot" .. key, parent,
        P.slots[key].weapon and "ZO_InventoryWeaponSlot" or "ZO_InventoryEquippedSlot")
    c.oneCraftSlot = key
    c:ClearAnchors()
    if native then c:SetAnchor(TOPLEFT, native, TOPLEFT, 0, 0)
    else c:SetAnchor(TOPLEFT, parent, TOPLEFT, x, y) end
    c:SetDimensions(44, 44)
    c.icon = c:GetNamedChild("Icon")
    c.emptyIcon = native and ZO_Character_GetEmptyEquipSlotTexture(P.slotIds[key]) or O.noneTexture
    c.border = W:CreateControl(nil, c, CT_TEXTURE)
    c.border:SetAnchorFill()
    c.border:SetTexture("EsoUI/Art/ActionBar/abilityFrame64_up.dds")
    c.selected = W:CreateControl(nil, c, CT_TEXTURE)
    c.selected:SetAnchorFill()
    c.selected:SetTexture("EsoUI/Art/ActionBar/actionBar_mouseOver.dds")
    c.selected:SetColor(1, 0.8, 0.25, 1)
    c:SetHandler("OnMouseDown", function(_, mouseButton)
        if mouseButton == MOUSE_BUTTON_INDEX_LEFT then P.pressed = key end
    end)
    c:SetHandler("OnDragStart", function()
        clearItemTooltip()
        if P.SlotItem(key) then P.dragging = P.OccupiedSlot(key) end
    end)
    c:SetHandler("OnDragStop", function() end)
    c:SetHandler("OnReceiveDrag", function() end)
    c:SetHandler("OnClicked", nil)
    c:SetHandler("OnMouseUp", function(_, mouseButton, inside)
        if mouseButton ~= MOUSE_BUTTON_INDEX_LEFT or not inside then return end
        clearItemTooltip()
        local source = P.dragging or P.pressed
        P.dragging, P.pressed = nil, nil
        if source and source ~= key then
            local ok, reason = P.Move(source, key)
            if ok then P.Select(key) else report(ok, reason) end
        else P.Select(key) end
    end)
    c:SetMouseEnabled(true)
    c:SetHandler("OnMouseEnter", function()
        clearItemTooltip()
        showItemTooltip(c, P.SlotItem(key))
    end)
    c:SetHandler("OnMouseExit", clearItemTooltip)
    P.controls[key] = c
end

function P.Show()
    if not P.stationOpen or IsInGamepadPreferredMode() then return end
    P.visible = true
    P.root:SetHidden(false)
    P.root:BringWindowToTop()
    P.silhouette:SetTexture(GetUnitSilhouetteTexture("player"))
    P.Select(P.selected or "Chest")
end

function P.Hide()
    P.visible, P.dragging, P.pressed = false, nil, nil
    if P.root then P.root:SetHidden(true) end
    ClearTooltip(InformationTooltip)
    clearItemTooltip()
end

function P.CreateUI()
    local launcher = W:CreateTopLevelWindow("OneCraftEquipmentLauncher")
    launcher:SetDimensions(51, 51)
    launcher:SetDrawTier(DT_HIGH)
    P.stationButton = W:CreateControl("OneCraftEquipmentLauncherButton", launcher, CT_BUTTON)
    P.stationButton:SetAnchorFill()
    local texture = "EsoUI/Art/Crafting/smithing_tabIcon_creation_"
    P.stationButton:SetNormalTexture(texture .. "up.dds")
    P.stationButton:SetPressedTexture(texture .. "down.dds")
    P.stationButton:SetMouseOverTexture(texture .. "over.dds")
    P.stationButton:SetHandler("OnClicked", P.Show)
    hint(P.stationButton, function() return "OneCraft — " .. P.words.title end, true)
    P.stationButton:SetHidden(true)
    local advisor = CRAFT_ADVISOR_WINDOW
    local function positionLauncher()
        local equip = ZO_MenuBar_GetButtonControl(advisor.tabBar, SI_CHARACTER_EQUIP_TITLE)
        if not equip then return end
        -- The native bar lays out right to left. Reserve one icon between tabs.
        if not P.launcherPadding then
            P.launcherPadding = (advisor.equipmentData.previousButtonExtraPadding or 0) - 66
        end
        advisor.equipmentData.previousButtonExtraPadding = P.launcherPadding
        ZO_MenuBar_UpdateButtons(advisor.tabBar)
        launcher:ClearAnchors()
        launcher:SetAnchor(LEFT, equip, RIGHT, 15, 0)
    end
    ZO_PostHook(advisor, "OnShowing", positionLauncher)
    positionLauncher()
    local root = W:CreateTopLevelWindow("OneCraftEquipmentPlanner")
    P.root = root
    root:SetAnchorFill(GuiRoot)
    root:SetDrawTier(DT_HIGH)
    root:SetMouseEnabled(true)
    root:SetHidden(true)
    local backdrop = W:CreateControlFromVirtual("OneCraftEquipmentPlannerBackdrop", root, "ZO_DefaultBackdrop")
    backdrop:SetAnchorFill()
    backdrop:SetCenterColor(0.02, 0.02, 0.025, 0.97)
    local origin = W:CreateControl(nil, root, CT_CONTROL)
    -- All doll parts remain at exactly the keyboard character sheet positions.
    origin:SetAnchor(TOPLEFT, ZO_Character, TOPLEFT, 0, 0)
    origin:SetDimensions(1050, 680)
    label(origin, "OneCraft — " .. P.words.title, 10, 35, 780, "ZoFontWinH2")
    button(origin, P.words.close, 890, 35, 150, P.Hide)
    P.silhouette = W:CreateControl(nil, root, CT_TEXTURE)
    P.silhouette:SetAnchor(TOPLEFT, ZO_CharacterPaperDoll, TOPLEFT, 0, 0)
    P.silhouette:SetDimensions(64, 256)
    P.controls = {}
    for _, key in ipairs(P.slotOrder) do
        if not P.slots[key].extra then createSlot(key, root, _G["ZO_CharacterEquipmentSlots" .. key]) end
    end
    label(origin, GetString("SI_EQUIPSLOTVISUALCATEGORY", EQUIP_SLOT_VISUAL_CATEGORY_ACCESSORIES), 10, 314, 220, "ZoFontHeader")
    label(origin, GetString("SI_EQUIPSLOTVISUALCATEGORY", EQUIP_SLOT_VISUAL_CATEGORY_WEAPONS), 10, 400, 220, "ZoFontHeader")
    label(origin, P.words.extras, 10, 535, 650, "ZoFontWinH3")
    local extras = W:CreateControl(nil, origin, CT_CONTROL)
    extras:SetAnchor(TOPLEFT, origin, TOPLEFT, 10, 580)
    extras:SetDimensions(650, 50)
    for i = 1, P.extraCount do createSlot("extra" .. i, extras, nil, (i - 1) * 64, 0) end
    label(origin, P.words.move, 10, 638, 660, "ZoFontGameSmall")
    P.fields, P.combos = {"set", "type", "level", "style", "trait", "enchant", "quality"}, {}
    local editor = W:CreateControl(nil, origin, CT_CONTROL)
    editor:SetAnchor(TOPLEFT, origin, TOPLEFT, 250, 92)
    editor:SetDimensions(410, 435)
    for i, field in ipairs(P.fields) do
        label(editor, P.words[field], 0, (i - 1) * 52, 130, "ZoFontGameSmall")
        local control = W:CreateControlFromVirtual("OneCraftEquipmentField" .. field, editor, "ZO_ComboBox")
        control:SetAnchor(TOPLEFT, editor, TOPLEFT, 130, (i - 1) * 52)
        control:SetDimensions(275, 32)
        local combo = ZO_ComboBox_ObjectFromContainer(control)
        combo:SetSortsItems(false)
        P.combos[field] = combo
        if field == "set" then
            hint(control, function() return setName(P.draft.set) end)
            control:SetHandler("OnMouseEnter", function(c) P.ShowSetTooltip(c, P.draft.set) end)
            control:SetHandler("OnMouseExit", function() clearItemTooltip(); ClearTooltip(InformationTooltip) end)
        end
    end
    label(editor, P.words.sameSet, 0, 363, 410, "ZoFontGameSmall")
    button(editor, P.words.apply, 0, 399, 250, function() report(P.Apply(P.selected, P.draft)) end)
    button(editor, P.words.remove, 260, 399, 145, function()
        P.saved.items[P.selected] = nil
        P.Select(P.selected)
    end)
    label(origin, P.words.materials, 700, 94, 340, "ZoFontWinH3")
    local scroll = W:CreateControlFromVirtual("OneCraftEquipmentMaterials", origin, "ZO_ScrollContainer")
    scroll:SetAnchor(TOPLEFT, origin, TOPLEFT, 700, 134)
    scroll:SetDimensions(340, 335)
    P.materialChild = scroll:GetNamedChild("ScrollChild")
    P.materialChild:SetWidth(320)
    P.queueLabel = label(origin, "", 700, 482, 340, "ZoFontWinH3")
    P.submitButton = button(origin, P.words.submit, 700, 526, 340, function() report(P.Submit()) end)
    P.cancelButton = button(origin, P.words.cancel, 700, 569, 340, function() report(P.Cancel()) end)
    P.clearButton = button(origin, P.words.clear, 700, 612, 340, function() report(P.ClearAll()) end)
    P.statusLabel = label(origin, "", 700, 652, 340, "ZoFontGameSmall")
    P.statusLabel:SetHeight(85)
    EVENT_MANAGER:RegisterForEvent("OneCraftEquipmentDrop", EVENT_GLOBAL_MOUSE_UP, function(_, mouseButton)
        if mouseButton ~= MOUSE_BUTTON_INDEX_LEFT or not P.visible then return end
        local source = P.dragging
        P.dragging, P.pressed = nil, nil
        if not source then return end
        local target = W:GetMouseOverControl()
        while target and not target.oneCraftSlot do target = target:GetParent() end
        if target and target.oneCraftSlot ~= source then
            local ok, reason = P.Move(source, target.oneCraftSlot)
            if ok then P.Select(target.oneCraftSlot) else report(ok, reason) end
        end
    end)
end
