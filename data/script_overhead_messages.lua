-- Overhead message queue system.
-- Provides a queued notification display so messages don't stomp each other.

local queuedOverheadNotifs = {}
overheadMessagesEnabled = true

function overheadMessageQueue(head, description, displayTime, override)
    --put data into a table since LUA dont got no structs (GOOD LANGUAGE VITTU!)
    override = override or false

    if override == true and #queuedOverheadNotifs > 0 then
        queuedOverheadNotifs[1].time = 0
    end

    sneed = {
    topText = head,
    bottomText = description,
    time = displayTime,
    }
    table.insert(queuedOverheadNotifs, sneed)
end

function overheadMessageDisplay(dt)
    if overheadMessagesEnabled then

        if queuedOverheadNotifs[1] ~= nil then
            queuedOverheadNotifs[1]["time"] = queuedOverheadNotifs[1]["time"] - dt
            ac.setSystemMessage(queuedOverheadNotifs[1]["topText"], queuedOverheadNotifs[1]["bottomText"])
            if queuedOverheadNotifs[1]["time"] < 0 then
                table.remove(queuedOverheadNotifs, 1)
            end
        end
    end
end
