# Companion pages

Forever Forge stays class-free. A class pack is a separate addon that adds one page to this menu and stores its settings in Forever Forge's saved variables.

## Register a page

The pack's TOC must load Forever Forge first:

```
## Dependencies: ForeverForge
```

If Forever Forge is not there, return. Do not call into it.

```lua
if not ForeverForge or type(ForeverForge.RegisterPage) ~= "function" then
  return
end

ForeverForge:RegisterPage({
  id = "Druid",
  title = "Druid",
  order = 100,
  description = "Druid tools.",
  builder = function(page, parent)
    local cfg = ForeverForge:GetPageConfig(page.id)
    -- Anchor controls to parent. If the page is tall, call parent:SetHeight(n).
    -- Mutate cfg. Do not replace it.
  end,
})
```

`id` uses letters, numbers, and underscores. It must not match a built-in tool id or another page id.

`title` is the menu label and the settings title.

`order` is a number. Pages are drawn after the built-in tools, lowest order first. The same order uses the title, then the id. A missing order is 0. Built-in tools keep their own order.

`description` is the line under the title. It can be omitted.

`builder` is called once, with the page and a frame inside the Forever Forge menu, under the Back button. The page uses the same window, fonts, and Back button as a tool's Configure screen. A companion page has no on/off switch. The builder draws the settings, including any checkbox.

`GetPageConfig(id)` returns the saved table at `ForeverForgeDB.pages[id]`. Change fields on that table. The table is created the first time you ask for it.

`RegisterPage` returns the page, or nil if the id, title, or builder is missing or the id is already used. A problem is printed in chat.

## If Forever Forge is missing

Check `ForeverForge` before calling `RegisterPage` or `GetPageConfig`. A pack that loads on its own should do nothing and raise no error.

## Druid tools

Druid tools ship inside Forever Forge. On login the code checks the player class and registers the Druid page only for a Druid. Other classes stay on that one-time check. The page has a movable Cat Bar and a movable Bear Bar. Each shows debuffs you cast, with the time left drawn by the game, then that form's resource and mana. Cat uses energy and combo points. Bear uses rage.
