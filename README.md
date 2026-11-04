# Tour Narrator

Tour Narrator lets you write an RP script (a tour, a story, a presentation) and send it to chat one line at a time, with a click, a keybind or a macro. You write the script once, then deliver it at your own pace without copy-pasting or retyping.

## Installation

1. Unzip the `TourNarrator` folder into `World of Warcraft/_retail_/Interface/AddOns/`.
2. Make sure the folder looks like this:

   ```
   AddOns/
   └── TourNarrator/
       ├── TourNarrator.toc
       ├── TourNarrator.lua
       ├── Bindings.xml
       └── Media/
           └── TN_Logo.tga
   ```

3. Restart the game. A full restart is needed the first time so the keybinds are picked up.

## Updating

Your scripts are stored separately from the addon files, so updating the addon doesn't touch them. To update safely:

1. Type `/reload`, then quit the game.
2. Replace the files inside `Interface/AddOns/TourNarrator/` with the new ones. The folder must keep the name `TourNarrator`.
3. Start the game.

**Warning:** there are two different files called `TourNarrator.lua`. The addon file lives in `Interface/AddOns/TourNarrator/`. Your saved scripts live in `WTF/Account/<account name>/SavedVariables/`. Never replace or delete the one in `WTF`, or your scripts will be lost. It's a good idea to keep a copy of your scripts somewhere safe (copy the text out of the editor) before updating.

## Getting started

- **Left-click** the minimap button to open the **Presenter**.
- **Right-click** it (or type `/tn`) to open the **Script Editor**.

Write your script in the editor, one chat line per line of text. Blank lines are ignored. Everything saves automatically. Click the **?** button in the editor's title bar for a quick guide at any time, and hover over the other buttons to see what they do.

To import a script you've written elsewhere, click anywhere in the editor's text area and paste it with Ctrl+V. You can click the empty space below the text to start typing at the end. Press Esc to leave the editor, which also lets your keybinds work again (they are ignored while you are typing in the box).

## Chat types

Start a line with a prefix to change how it is sent. The chat type stays active for every following line until you use another prefix, so you only need to mark the lines where it changes.

| Prefix | Sent as |
| --- | --- |
| `/s` or `/say` | Say (the default) |
| `/e`, `/emote` or `/me` | Emote |
| `/y` or `/yell` | Yell |
| `/p` or `/party` | Party |
| `/ra` or `/raid` | Raid |
| `/g` or `/guild` | Guild |

Example:

```
/s Welcome, everyone, to the Grand Tour of Stormwind!
/e gestures towards the cathedral.
/s Over there you can see the Cathedral of Light.
/s Shall we move on?
```

The first line is sent as Say, the next two as Emote (the second one carries on as an emote), and the last as Say again.

## Emote commands

Standard emotes such as `/bow`, `/sit`, `/laugh` and `/dance` work too. Put each one on its own line and it is performed (animation, sound and chat text, exactly as if you had typed it) when you send that line. In the Presenter and status line these show as `[ACTION]` in blue.

```
/y Welcome to the Trade District!
/wave
/e gestures towards the market stalls.
/bow Thrall
/s Please, follow me.
```

- Every emote the game knows about is supported, including its short forms (for example `/lol` as well as `/laugh`).
- An emote line doesn't change the chat type. In the example above, the last line is still sent as an emote, because that was the chat type before it.
- Emotes are aimed at your current target, as usual. To aim one at someone else, add a name (`/bow Thrall`). To aim it at nobody, add `none` (`/bow none`).
- Anything after an emote command is treated as its target, not as text to say. To speak, use a separate line.
- To write your own emote text, use `/e` (see above). That is sent to chat, unlike the standard emotes.
- Other slash commands, such as `/roll`, are not run. They are sent as plain text.
- WoW limits how quickly emotes can be performed (about four per second), so an emote line pressed in very quick succession with another may be ignored.
- If your character can't use an emote (for example, a faction-only one), you'll see a short message in chat.

## Comments and stage directions

A line that starts with `##` is a comment. It is never sent to chat, and it doesn't count as a line. Use comments for notes to yourself, such as where to stand or move to.

```
## Stand at the fountain
/s Welcome to the Trade District!
/wave
## Walk to the bank steps
/s Over here is the bank.
```

The Presenter shows the most recent comment above the queued line as a green **DIRECTION:** line. It stays on screen until the next comment replaces it. In the example, you would see "Stand at the fountain" for the first two lines, then "Walk to the bank steps" for the last. When the script is finished, the final comment stays on screen.

- Comments don't change the chat type, and a comment is never treated as a prefix or emote. `## /e hello` is just a note.
- A line with only `##` is ignored.
- If the Presenter is hidden (for example, when using only keybinds), each new direction is printed in your chat window instead.

## The Presenter

The Presenter shows the next queued line in full, with the current stage direction above it. Along the bottom are three buttons, with a small **Restart** button at the top:

- **Send**: sends the queued line and moves on to the next.
- **Skip**: moves past the queued line without sending it.
- **Back**: steps back one line.
- **Restart** (top right): goes back to the first line of the script. Your script text is not changed.

## Resizing the windows

Both the Script Editor and the Presenter can be resized by dragging the handle in their bottom-right corner. Make the Presenter bigger if a long line or direction doesn't fit. Resizing only changes the amount of room for text: in the Editor the script box grows or shrinks, and in the Presenter the line preview does. Buttons and text keep their normal size. Window sizes are remembered between sessions.

## Multiple scripts

You can keep several scripts, for example a full tour and a shorter version.

- Use the `<` and `>` buttons in the Presenter or the Editor to switch between scripts.
- In the Editor, use **New**, **Rename** and **Delete** to manage them.
- Switching scripts always starts from line 1.

## Keybinds

Open **Options > Keybindings > AddOns > Tour Narrator** to bind keys for Send Next Line, Skip Line, Back One Line, Restart Script and Toggle Presenter.

## Slash commands

| Command | What it does |
| --- | --- |
| `/tn` | Open or close the Script Editor |
| `/tnp` | Open or close the Presenter |
| `/tn next` (or `/tnnext`) | Send the next line |
| `/tn skip` (or `/tnskip`) | Skip the next line |
| `/tn back` (or `/tnback`) | Go back one line |
| `/tn restart` (or `/tnrestart`) | Go back to line 1 (`/tn reset` also works) |
| `/tn scripts` | List your scripts |
| `/tn script <name or number>` | Switch to a script |
| `/tn nextscript` / `/tn prevscript` | Cycle through scripts |
| `/tn help` | Open the help window |

These work in macros too, for example `/tn script Short Tour`.

## Long lines

WoW cuts off chat messages over 250 characters. Tour Narrator warns you in red in the Editor (and in the Presenter when the queued line is too long). A long line is still sent, but it is cut short and ends with `...`. Split it into two lines to send it in full.

## Good to know

- **Group chats** (Party, Raid, Guild) only work if you are in that kind of group. Otherwise WoW shows its usual "not in a group" message and the line is not sent, but the script still moves on to the next line.
- **Say and Yell outdoors** only work when sent by a real key press or click. Keybinds, macros and the Presenter buttons all count, so there is nothing to do, but it also means a script can't be sent automatically on a timer.
- If the minimap button shows a plain green square, the logo file is missing. Check that `Media/TN_Logo.tga` is in the folder shown above.

## Reporting a problem

Please turn on error messages first by typing `/console scriptErrors 1`, then repeat what you were doing. If an error pops up, copy the full text and send it along with a description of what you clicked. Say which script you were using and whether it had any prefix lines or very long lines.
