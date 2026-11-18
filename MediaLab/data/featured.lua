local _, ML = ...

-- Hand-picked starting points. Each list adds a "Common" filter to its tab;
-- names missing from the running client are simply not tagged.
ML.Common = {
    control = {
        "BackdropTemplate", "UIPanelButtonTemplate", "UIPanelDynamicResizeButtonTemplate",
        "SharedButtonSmallTemplate", "MagicButtonTemplate", "UIGoldBorderButtonTemplate",
        "UIPanelCloseButton", "UIPanelCloseButtonDefaultAnchors", "UIPanelSquareButton",
        "PanelTabButtonTemplate", "PanelResizeButtonTemplate", "UIMenuButtonStretchTemplate",
        "UICheckButtonTemplate", "UIRadioButtonTemplate", "SettingsCheckboxTemplate",
        "InputBoxTemplate", "SearchBoxTemplate", "LargeInputBoxTemplate",
        "UISliderTemplate", "MinimalSliderTemplate", "OptionsSliderTemplate",
        "UIPanelScrollFrameTemplate", "ScrollFrameTemplate", "WowScrollBoxList", "MinimalScrollBar",
        "WowStyle1DropdownTemplate", "WowStyle2DropdownTemplate",
        "ButtonFrameTemplate", "BasicFrameTemplate", "BasicFrameTemplateWithInset",
        "PortraitFrameTemplate", "DefaultPanelTemplate", "DefaultPanelFlatTemplate",
        "InsetFrameTemplate", "DialogBorderTemplate", "DialogBorderDarkTemplate",
        "TranslucentFrameTemplate", "TooltipBorderedFrameTemplate", "GlowBoxTemplate",
    },
    sound = {
        "IG_MAINMENU_OPEN", "IG_MAINMENU_CLOSE", "IG_MAINMENU_OPTION_CHECKBOX_ON",
        "IG_MAINMENU_OPTION_CHECKBOX_OFF", "IG_CHARACTER_INFO_TAB", "IG_SPELLBOOK_OPEN",
        "IG_QUEST_LOG_OPEN", "IG_QUEST_LOG_CLOSE", "IG_BACKPACK_OPEN", "IG_BACKPACK_CLOSE",
        "U_CHAT_SCROLL_BUTTON", "LOOT_WINDOW_COIN_SOUND", "MONEY_FRAME_OPEN",
        "READY_CHECK", "RAID_WARNING", "TELL_MESSAGE", "ALARM_CLOCK_WARNING_3",
        "UI_EPICLOOT_TOAST", "UI_LEGENDARY_LOOT_TOAST", "AUCTION_WINDOW_OPEN", "AUCTION_WINDOW_CLOSE",
    },
    font = {
        "GameFontNormal", "GameFontNormalSmall", "GameFontNormalLarge", "GameFontNormalHuge",
        "GameFontHighlight", "GameFontHighlightSmall", "GameFontHighlightLarge",
        "GameFontDisable", "GameFontGreen", "GameFontRed", "GameFontWhite",
        "SystemFont_Small", "SystemFont_Med1", "SystemFont_Large", "SystemFont_Huge1",
        "NumberFontNormal", "NumberFontNormalLarge", "QuestFont", "QuestTitleFont",
        "ChatFontNormal", "Tooltip_Med", "Fancy16Font", "Fancy24Font",
    },
}
